#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-deploy-rollback.XXXXXX")"
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
    printf 'A SHA-256 command is required for the deployment experiment.\n' >&2
    return 1
  fi
}

repo="$lab_dir/source"
mkdir -p "$repo/service"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Deployment Lab"
git -C "$repo" config user.email "deploy@example.invalid"

printf 'service version 1\n' > "$repo/service/version.txt"
git -C "$repo" add service/version.txt
git -C "$repo" commit --quiet -m "release: known good"
known_good_commit="$(git -C "$repo" rev-parse HEAD)"

printf 'service version 2\n' > "$repo/service/version.txt"
git -C "$repo" add service/version.txt
git -C "$repo" commit --quiet -m "release: canary candidate"
candidate_commit="$(git -C "$repo" rev-parse HEAD)"
test "$known_good_commit" != "$candidate_commit"

mkdir -p "$lab_dir/build" "$lab_dir/environments/prod/instances"
git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=application/ "$known_good_commit" > "$lab_dir/build/known-good.tar"
git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=application/ "$candidate_commit" > "$lab_dir/build/candidate.tar"
known_good_digest="$(sha256_file "$lab_dir/build/known-good.tar")"
candidate_digest="$(sha256_file "$lab_dir/build/candidate.tar")"
test "$known_good_digest" != "$candidate_digest"

manifest="$lab_dir/build/release.manifest"
printf '%s\n' \
  "source_commit=$candidate_commit" \
  "artifact_digest=$candidate_digest" \
  'configuration_version=config-v2' \
  > "$manifest"

deployment="$lab_dir/environments/prod/deployment.env"
printf '%s\n' \
  'deployment_id=deploy-001' \
  'state=requested' \
  "source_commit=$candidate_commit" \
  "artifact_digest=$candidate_digest" \
  'configuration_version=config-v2' \
  'rollout_strategy=canary' \
  > "$deployment"
grep -Fqx 'state=requested' "$deployment"
grep -Fqx "artifact_digest=$candidate_digest" "$deployment"

canary="$lab_dir/environments/prod/instances/canary"
mkdir -p "$canary"
cp "$lab_dir/build/candidate.tar" "$canary/application.tar"
printf '%s\n' \
  "artifact_digest=$candidate_digest" \
  'health=fail' \
  'traffic_percent=10' \
  > "$canary/observation.env"
test "$(sha256_file "$canary/application.tar")" = "$candidate_digest"
grep -Fqx 'health=fail' "$canary/observation.env"

printf '%s\n' \
  'deployment_id=deploy-001' \
  'state=paused' \
  "source_commit=$candidate_commit" \
  "artifact_digest=$candidate_digest" \
  'configuration_version=config-v2' \
  'rollout_strategy=canary' \
  'pause_reason=canary_health_failed' \
  > "$deployment"
grep -Fqx 'state=paused' "$deployment"
if grep -Fq 'traffic_percent=100' "$canary/observation.env"; then
  printf 'failed canary unexpectedly received all traffic.\n' >&2
  exit 1
fi

old_instance="$lab_dir/environments/prod/instances/old"
mkdir -p "$old_instance"
cp "$lab_dir/build/known-good.tar" "$old_instance/application.tar"
printf '%s\n' \
  "artifact_digest=$known_good_digest" \
  'health=pass' \
  'traffic_percent=90' \
  > "$old_instance/observation.env"

cp "$lab_dir/build/known-good.tar" "$canary/application.tar"
printf '%s\n' \
  "artifact_digest=$known_good_digest" \
  'health=pass' \
  'traffic_percent=0' \
  > "$canary/observation.env"
printf '%s\n' \
  'deployment_id=deploy-001' \
  'state=rolled_back' \
  "source_commit=$known_good_commit" \
  "artifact_digest=$known_good_digest" \
  'configuration_version=config-v1' \
  'rollout_strategy=canary' \
  'rollback_reason=canary_health_failed' \
  > "$deployment"
test "$(sha256_file "$canary/application.tar")" = "$known_good_digest"
test "$(sha256_file "$old_instance/application.tar")" = "$known_good_digest"
grep -Fqx 'state=rolled_back' "$deployment"
grep -Fqx 'configuration_version=config-v1' "$deployment"

printf 'configuration_version=config-v2\n' > "$lab_dir/environments/prod/config.env"
printf 'configuration_version=config-v1\n' > "$lab_dir/environments/prod/config.rollback.env"
cp "$lab_dir/environments/prod/config.rollback.env" \
  "$lab_dir/environments/prod/config.env"
grep -Fqx 'configuration_version=config-v1' \
  "$lab_dir/environments/prod/config.env"

printf '%s\n' \
  "task_id=task-001" \
  "started_with_digest=$candidate_digest" \
  'status=blocked_after_rollback' \
  > "$lab_dir/environments/prod/task.env"
grep -Fqx 'status=blocked_after_rollback' \
  "$lab_dir/environments/prod/task.env"

printf 'post-deployment change\n' > "$repo/CHANGELOG.md"
git -C "$repo" add CHANGELOG.md
git -C "$repo" commit --quiet -m "docs: advance main after deployment"
new_main="$(git -C "$repo" rev-parse HEAD)"
test "$new_main" != "$known_good_commit"
test "$new_main" != "$candidate_commit"
test "$(sha256_file "$canary/application.tar")" = "$known_good_digest"
grep -Fqx "artifact_digest=$known_good_digest" "$deployment"

printf 'Deployment state machine, canary stop, rollback verification, and stale-task fencing passed.\n'
