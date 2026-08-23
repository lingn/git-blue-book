#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-incident-release.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS GIT_CONFIG_COUNT SSH_ASKPASS

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'A SHA-256 command is required for the incident experiment.\n' >&2
    return 1
  fi
}

repo="$lab_dir/repository"
mkdir -p "$repo/service" "$repo/scripts"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Incident Lab"
git -C "$repo" config user.email "incident@example.invalid"

printf 'dedupe\n' > "$repo/service/mode.txt"
git -C "$repo" add service/mode.txt
git -C "$repo" commit --quiet -m "service: establish idempotent behavior"
known_good_commit="$(git -C "$repo" rev-parse HEAD)"

printf 'duplicate\n' > "$repo/service/mode.txt"
git -C "$repo" add service/mode.txt
git -C "$repo" commit --quiet -m "sdk: regress task idempotency"
known_bad_commit="$(git -C "$repo" rev-parse HEAD)"

printf 'incident fixture documentation\n' > "$repo/INCIDENT.md"
git -C "$repo" add INCIDENT.md
git -C "$repo" commit --quiet -m "docs: record incident context"
main_before_fix="$(git -C "$repo" rev-parse HEAD)"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'test "$(cat service/mode.txt)" = dedupe' \
  > "$repo/scripts/reproduce-incident.sh"
chmod +x "$repo/scripts/reproduce-incident.sh"

git -C "$repo" bisect start
git -C "$repo" bisect bad "$main_before_fix"
git -C "$repo" bisect good "$known_good_commit"
git -C "$repo" bisect run ./scripts/reproduce-incident.sh >/dev/null
first_bad_commit="$(git -C "$repo" rev-parse HEAD)"
test "$first_bad_commit" = "$known_bad_commit"
git -C "$repo" bisect log > "$lab_dir/bisect.log"
git -C "$repo" bisect reset >/dev/null
test "$(git -C "$repo" rev-parse HEAD)" = "$main_before_fix"
grep -Fq "git bisect bad $main_before_fix" "$lab_dir/bisect.log"
grep -Fq "git bisect good $known_good_commit" "$lab_dir/bisect.log"

git -C "$repo" switch --quiet --create fix/incident "$known_bad_commit"
printf 'dedupe\n' > "$repo/service/mode.txt"
printf 'idempotency regression test\n' > "$repo/service/regression.test"
git -C "$repo" add service/mode.txt service/regression.test
git -C "$repo" commit --quiet -m "fix: make task execution idempotent"
fix_source_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet --create release/1.x "$known_bad_commit"
printf 'maintenance release line\n' > "$repo/RELEASE.md"
git -C "$repo" add RELEASE.md
git -C "$repo" commit --quiet -m "release: prepare maintenance line"
git -C "$repo" cherry-pick --quiet "$fix_source_commit"
fix_target_commit="$(git -C "$repo" rev-parse HEAD)"
test "$fix_source_commit" != "$fix_target_commit"
test "$(git -C "$repo" show "$fix_target_commit:service/mode.txt")" = dedupe

incident_id="INC-2026-0823-001"
release_tag="v1.2.1"
git -C "$repo" tag -a "$release_tag" "$fix_target_commit" \
  -m "Release $release_tag for $incident_id"
tag_object="$(git -C "$repo" rev-parse "$release_tag^{tag}")"
tag_target="$(git -C "$repo" rev-parse "$release_tag^{}")"
test "$tag_target" = "$fix_target_commit"
test "$(git -C "$repo" cat-file -t "$release_tag")" = tag

mkdir -p "$lab_dir/build" "$lab_dir/deployment/manager" \
  "$lab_dir/deployment/worker" "$lab_dir/evidence"
git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=application/ "$fix_target_commit" > "$lab_dir/build/application.tar"
artifact_digest="$(sha256_file "$lab_dir/build/application.tar")"
manifest="$lab_dir/build/build.manifest"
printf '%s\n' \
  "incident_id=$incident_id" \
  "first_bad_commit=$first_bad_commit" \
  "fix_source_commit=$fix_source_commit" \
  "source_commit=$fix_target_commit" \
  "tag_object=$tag_object" \
  "release_tag=$release_tag" \
  "artifact_digest=$artifact_digest" \
  'configuration_version=config-v3' \
  'database_schema=schema-v2-expand' \
  > "$manifest"
manifest_digest="$(sha256_file "$manifest")"

printf '%s\n' \
  "incident_id=$incident_id" \
  'state=evidence_frozen' \
  "runtime_artifact_digest=$artifact_digest" \
  'configuration_version=config-v2' \
  'database_schema=schema-v2-expand' \
  'queue_state=paused' \
  'duplicate_count=4' \
  "evidence_manifest_digest=$manifest_digest" \
  > "$lab_dir/evidence/incident.env"
grep -Fqx 'state=evidence_frozen' "$lab_dir/evidence/incident.env"
grep -Fqx 'queue_state=paused' "$lab_dir/evidence/incident.env"

printf '%s\n' \
  "incident_id=$incident_id" \
  'state=mitigated' \
  "runtime_artifact_digest=$artifact_digest" \
  'configuration_version=config-v2' \
  'database_schema=schema-v2-expand' \
  'queue_state=paused' \
  'duplicate_count=0-new-tasks' \
  "evidence_manifest_digest=$manifest_digest" \
  > "$lab_dir/evidence/mitigation.env"
grep -Fqx 'state=mitigated' "$lab_dir/evidence/mitigation.env"

for component in manager worker; do
  cp "$lab_dir/build/application.tar" \
    "$lab_dir/deployment/$component/application.tar"
  printf '%s\n' \
    "component=$component" \
    "incident_id=$incident_id" \
    "artifact_digest=$artifact_digest" \
    "source_commit=$fix_target_commit" \
    'configuration_version=config-v3' \
    'database_schema=schema-v2-expand' \
    'old_instances_fenced=true' \
    'health=pass' \
    'duplicate_count=0' \
    > "$lab_dir/deployment/$component/observation.env"
  test "$(sha256_file "$lab_dir/deployment/$component/application.tar")" = \
    "$artifact_digest"
  grep -Fqx 'old_instances_fenced=true' \
    "$lab_dir/deployment/$component/observation.env"
done

printf '%s\n' \
  "incident_id=$incident_id" \
  'state=rollout_observing' \
  "release_tag=$release_tag" \
  "artifact_digest=$artifact_digest" \
  'components=manager,worker' \
  'queue_state=draining' \
  'duplicate_count=0' \
  'database_validation=pass' \
  "build_manifest_digest=$manifest_digest" \
  > "$lab_dir/deployment/deployment.env"
grep -Fqx 'state=rollout_observing' "$lab_dir/deployment/deployment.env"
grep -Fqx 'database_validation=pass' "$lab_dir/deployment/deployment.env"

printf '%s\n' \
  "incident_id=$incident_id" \
  'state=resolved' \
  "release_tag=$release_tag" \
  "artifact_digest=$artifact_digest" \
  'queue_state=empty' \
  'duplicate_count=0' \
  'database_validation=pass' \
  'old_instances_fenced=true' \
  "build_manifest_digest=$manifest_digest" \
  > "$lab_dir/evidence/resolved.env"
grep -Fqx 'state=resolved' "$lab_dir/evidence/resolved.env"
grep -Fqx 'queue_state=empty' "$lab_dir/evidence/resolved.env"

git -C "$repo" switch --quiet main
printf 'main continues after incident release\n' > "$repo/POST-INCIDENT.md"
git -C "$repo" add POST-INCIDENT.md
git -C "$repo" commit --quiet -m "docs: add post-incident follow-up"
new_main="$(git -C "$repo" rev-parse HEAD)"
test "$new_main" != "$fix_target_commit"
test "$(sha256_file "$lab_dir/deployment/manager/application.tar")" = \
  "$artifact_digest"
test "$(sha256_file "$lab_dir/deployment/worker/application.tar")" = \
  "$artifact_digest"
grep -Fqx 'state=resolved' "$lab_dir/evidence/resolved.env"

printf '%s\n' \
  "incident_id=$incident_id" \
  'state=closed' \
  'root_cause=first_bad_commit_and_shared_sdk' \
  "fix_source_commit=$fix_source_commit" \
  "fix_target_commit=$fix_target_commit" \
  "artifact_digest=$artifact_digest" \
  'mitigation=queue_paused_and_old_tasks_fenced' \
  'validation=instances_metrics_database_and_queue' \
  "evidence_manifest_digest=$manifest_digest" \
  > "$lab_dir/evidence/closure.env"
grep -Fqx 'state=closed' "$lab_dir/evidence/closure.env"
grep -Fqx "fix_source_commit=$fix_source_commit" "$lab_dir/evidence/closure.env"
grep -Fqx "fix_target_commit=$fix_target_commit" "$lab_dir/evidence/closure.env"

printf 'Incident evidence freeze, first-bad isolation, cherry-picked hotfix, dual-service promotion, and closure checks passed.\n'
