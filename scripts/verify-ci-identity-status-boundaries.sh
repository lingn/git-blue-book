#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-ci-identities.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
export GIT_PAGER=cat
export LC_ALL=C
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
reporters="$lab_root/trusted-reporters.tsv"
statuses_old="$lab_root/statuses-old.tsv"
statuses_wrong="$lab_root/statuses-wrong.tsv"
statuses_good="$lab_root/statuses-good.tsv"
reporters_revoked="$lab_root/trusted-reporters-revoked.tsv"

git -C "$lab_root" init --quiet --initial-branch=main repository
git -C "$repo" config user.name 'CI Identity Fixture'
git -C "$repo" config user.email 'ci-identity@example.invalid'
mkdir -p "$repo/service" "$repo/.ci"
printf 'version=1\n' > "$repo/service/app.txt"
printf 'pipeline=trusted-v1\n' > "$repo/.ci/workflow.yml"
git -C "$repo" add .
GIT_AUTHOR_DATE='2026-09-14T03:00:00+00:00' GIT_COMMITTER_DATE='2026-09-14T03:00:00+00:00' git -C "$repo" commit --quiet -m 'fixture: establish CI identity baseline'
base_commit="$(git -C "$repo" rev-parse HEAD)"

{
  printf 'check_id\tprincipal\tstatus\tpipeline_version\n'
  printf 'integration-v2\tci-service\tactive\tpipeline-v2\n'
} > "$reporters"

evaluate_status() {
  local candidate="$1" target="$2" check_id="$3" reporter="$4"
  local pipeline_version="$5" statuses_path="$6" reporters_path="$7"

  if ! git -C "$repo" cat-file -e "$candidate^{commit}"; then
    printf 'inconclusive reason=candidate-missing candidate=%s\n' "$candidate"
    return 3
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$target" "$candidate"; then
    printf 'deny reason=stale-candidate target=%s candidate=%s\n' "$target" "$candidate"
    return 2
  fi

  reporter_status=""
  trusted_pipeline=""
  reporter_matches=0
  while IFS=$'\t' read -r configured_check configured_reporter status configured_pipeline; do
    test "$configured_check" = check_id && continue
    if test "$configured_check" = "$check_id" && test "$configured_reporter" = "$reporter"; then
      reporter_matches=$((reporter_matches + 1))
      reporter_status="$status"
      trusted_pipeline="$configured_pipeline"
    fi
  done < "$reporters_path"
  if test "$reporter_matches" -ne 1 || test "$reporter_status" != active; then
    printf 'inconclusive reason=reporter-not-trusted check=%s reporter=%s\n' "$check_id" "$reporter"
    return 3
  fi
  if test "$pipeline_version" != "$trusted_pipeline"; then
    printf 'deny reason=pipeline-mismatch expected=%s got=%s\n' "$trusted_pipeline" "$pipeline_version"
    return 2
  fi

  if awk -F '\t' -v candidate="$candidate" -v check_id="$check_id" -v reporter="$reporter" -v pipeline="$pipeline_version" 'NR > 1 && $1 == candidate && $2 == check_id && $3 == reporter && $4 == pipeline && $5 == "success" { found = 1 } END { exit(found ? 0 : 1) }' "$statuses_path"; then
    printf 'allow candidate=%s check=%s reporter=%s\n' "$candidate" "$check_id" "$reporter"
    return 0
  fi

  if awk -F '\t' -v candidate="$candidate" -v check_id="$check_id" -v reporter="$reporter" 'NR > 1 && $1 == candidate && $2 == check_id && $3 != reporter { found = 1 } END { exit(found ? 0 : 1) }' "$statuses_path"; then
    printf 'deny reason=untrusted-reporter check=%s reporter=%s\n' "$check_id" "$reporter"
    return 2
  fi
  if awk -F '\t' -v candidate="$candidate" -v check_id="$check_id" -v reporter="$reporter" 'NR > 1 && $1 != candidate && $2 == check_id && $3 == reporter { found = 1 } END { exit(found ? 0 : 1) }' "$statuses_path"; then
    printf 'deny reason=stale-status check=%s reporter=%s candidate=%s\n' "$check_id" "$reporter" "$candidate"
    return 2
  fi
  if awk -F '\t' -v check_id="$check_id" -v reporter="$reporter" 'NR > 1 && $2 == check_id && $3 == reporter { found = 1 } END { exit(found ? 0 : 1) }' "$statuses_path"; then
    printf 'deny reason=status-not-success check=%s reporter=%s\n' "$check_id" "$reporter"
    return 2
  fi

  printf 'deny reason=status-missing check=%s reporter=%s candidate=%s\n' "$check_id" "$reporter" "$candidate"
  return 2
}

printf 'version=2\n' > "$repo/service/app.txt"
printf 'reporter=untrusted-candidate\n' > "$repo/.ci/trusted-reporters.tsv"
git -C "$repo" add service/app.txt .ci/trusted-reporters.tsv
GIT_AUTHOR_DATE='2026-09-14T03:05:00+00:00' GIT_COMMITTER_DATE='2026-09-14T03:05:00+00:00' git -C "$repo" commit --quiet -m 'feat: candidate changes service and CI metadata'
candidate_commit="$(git -C "$repo" rev-parse HEAD)"

{
  printf 'candidate\tcheck_id\treporter\tpipeline_version\tconclusion\tevidence\n'
  printf '%s\tintegration-v2\tother-app\tpipeline-v2\tsuccess\tlog-old\n' "$candidate_commit"
} > "$statuses_wrong"
wrong_reporter_status=0
evaluate_status "$candidate_commit" "$base_commit" integration-v2 ci-service pipeline-v2 "$statuses_wrong" "$reporters" > "$lab_root/wrong-reporter.txt" || wrong_reporter_status=$?
test "$wrong_reporter_status" -eq 2
grep -F 'deny reason=untrusted-reporter' "$lab_root/wrong-reporter.txt" >/dev/null

{
  printf 'candidate\tcheck_id\treporter\tpipeline_version\tconclusion\tevidence\n'
  printf '%s\tintegration-v2\tci-service\tpipeline-v2\tsuccess\tlog-old\n' "$base_commit"
} > "$statuses_old"
old_status=0
evaluate_status "$candidate_commit" "$base_commit" integration-v2 ci-service pipeline-v2 "$statuses_old" "$reporters" > "$lab_root/old-candidate.txt" || old_status=$?
test "$old_status" -eq 2
grep -F 'deny reason=stale-status' "$lab_root/old-candidate.txt" >/dev/null

{
  printf 'candidate\tcheck_id\treporter\tpipeline_version\tconclusion\tevidence\n'
  printf '%s\tintegration-v2\tci-service\tpipeline-v2\tsuccess\tlog-current\n' "$candidate_commit"
} > "$statuses_good"
evaluate_status "$candidate_commit" "$base_commit" integration-v2 ci-service pipeline-v2 "$statuses_good" "$reporters" > "$lab_root/current-status.txt"
grep -F "allow candidate=$candidate_commit check=integration-v2 reporter=ci-service" "$lab_root/current-status.txt" >/dev/null

pipeline_status=0
evaluate_status "$candidate_commit" "$base_commit" integration-v2 ci-service pipeline-v1 "$statuses_good" "$reporters" > "$lab_root/pipeline-mismatch.txt" || pipeline_status=$?
test "$pipeline_status" -eq 2
grep -F 'deny reason=pipeline-mismatch expected=pipeline-v2 got=pipeline-v1' "$lab_root/pipeline-mismatch.txt" >/dev/null

awk -F '\t' 'NR == 1 { print; next } { $3 = "revoked"; print }' OFS='\t' "$reporters" > "$reporters_revoked"
revoked_status=0
evaluate_status "$candidate_commit" "$base_commit" integration-v2 ci-service pipeline-v2 "$statuses_good" "$reporters_revoked" > "$lab_root/revoked-reporter.txt" || revoked_status=$?
test "$revoked_status" -eq 3
grep -F 'inconclusive reason=reporter-not-trusted' "$lab_root/revoked-reporter.txt" >/dev/null

printf 'Candidate binding, reporter identity, pipeline version, stale status, and revocation boundaries passed.\n'
