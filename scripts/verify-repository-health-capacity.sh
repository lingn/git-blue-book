#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-health-capacity.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

classify_capacity() {
  local snapshots_path="$1"
  local budgets_path="$2"
  local repository_id="$3"

  awk -F '\t' -v repository_id="$repository_id" '
    FILENAME == ARGV[1] {
      if (FNR == 1) {
        if ($0 != "timestamp\trepository_id\tsource_status\tobject_bytes\trefs\tlfs_bytes\tartifact_bytes\tfsck_status\tbackup_status") {
          schema_error = 1
        }
        next
      }
      if ($2 != repository_id) {
        next
      }
      snapshot_count++
      if ($1 + 0 > current_time + 0) {
        previous_time = current_time
        previous_object = current_object
        previous_refs = current_refs
        previous_lfs = current_lfs
        previous_artifact = current_artifact

        current_time = $1 + 0
        current_source = $3
        current_object = $4 + 0
        current_refs = $5 + 0
        current_lfs = $6 + 0
        current_artifact = $7 + 0
        current_fsck = $8
        current_backup = $9
      }
      next
    }

    FILENAME == ARGV[2] {
      if (FNR == 1) {
        if ($0 != "repository_id\tobject_limit\trefs_limit\tlfs_limit\tartifact_limit\twarn_headroom_days") {
          schema_error = 1
        }
        next
      }
      if ($1 == repository_id) {
        budget_matches++
        object_limit = $2 + 0
        refs_limit = $3 + 0
        lfs_limit = $4 + 0
        artifact_limit = $5 + 0
        warn_days = $6 + 0
      }
      next
    }

    function dimension_warn(previous, current, limit, days, growth, headroom) {
      growth = (current - previous) / days
      if (growth <= 0) {
        return 0
      }
      headroom = (limit - current) / growth
      return headroom < warn_days
    }

    END {
      if (schema_error) {
        print "schema-error"
        exit 40
      }
      if (budget_matches != 1 || snapshot_count < 2 ||
          previous_time == "" || current_time <= previous_time) {
        print "inconclusive"
        exit 30
      }
      if (current_source != "available") {
        print "inconclusive"
        exit 30
      }
      if (current_fsck == "unknown" || current_backup == "unknown") {
        print "inconclusive"
        exit 30
      }
      if (current_fsck != "pass" || current_backup != "verified") {
        print "fail"
        exit 20
      }
      if (current_object > object_limit || current_refs > refs_limit ||
          current_lfs > lfs_limit || current_artifact > artifact_limit) {
        print "fail"
        exit 20
      }

      elapsed_days = (current_time - previous_time) / 86400
      if (dimension_warn(previous_object, current_object,
                         object_limit, elapsed_days) ||
          dimension_warn(previous_refs, current_refs,
                         refs_limit, elapsed_days) ||
          dimension_warn(previous_lfs, current_lfs,
                         lfs_limit, elapsed_days) ||
          dimension_warn(previous_artifact, current_artifact,
                         artifact_limit, elapsed_days)) {
        print "warn"
        exit 10
      }

      print "pass"
      exit 0
    }
  ' "$snapshots_path" "$budgets_path"
}

run_maintenance() {
  local repository_path="$1"
  local task_name="$2"
  local lock_path="$3"
  local scratch_available="$4"
  local scratch_required="$5"
  local backup_state="$6"
  local incident_state="$7"
  local event_log="$8"
  local command_status

  test "$incident_state" = clear || return 21
  test "$backup_state" = verified || return 22
  test "$scratch_available" -ge "$scratch_required" || return 23
  mkdir "$lock_path" 2>/dev/null || return 24

  printf 'START\ttask=%s\n' "$task_name" >> "$event_log"
  set +e
  git -C "$repository_path" maintenance run --task="$task_name" \
    > "$lab_root/maintenance-$task_name.stdout" \
    2> "$lab_root/maintenance-$task_name.stderr"
  command_status="$?"
  set -e

  if test "$command_status" -ne 0; then
    printf 'FAILED\ttask=%s\texit=%s\n' \
      "$task_name" "$command_status" >> "$event_log"
    rmdir "$lock_path"
    return 25
  fi

  printf 'VALIDATING\ttask=%s\n' "$task_name" >> "$event_log"
  if test "$task_name" = commit-graph; then
    git -C "$repository_path" commit-graph verify \
      > "$lab_root/commit-graph.verify" 2>&1
  fi
  rmdir "$lock_path"
  printf 'COMPLETE\ttask=%s\n' "$task_name" >> "$event_log"
}

repo="$lab_root/repository"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Health Capacity Fixture'
git -C "$repo" config user.email 'health-capacity@example.invalid'

for version in 1 2 3 4
do
  printf 'version=%s\n' "$version" > "$repo/service.conf"
  printf 'payload-%s-%040d\n' "$version" "$version" \
    > "$repo/payload-$version.txt"
  git -C "$repo" add service.conf "payload-$version.txt"
  GIT_AUTHOR_DATE="2026-08-21T05:0${version}:00+00:00" \
  GIT_COMMITTER_DATE="2026-08-21T05:0${version}:00+00:00" \
    git -C "$repo" commit --quiet -m "fixture: health snapshot $version"
done
git -C "$repo" tag -a health-v1 -m 'fixture: health checkpoint'

count_objects="$lab_root/count-objects.txt"
git -C "$repo" count-objects -v > "$count_objects"
loose_kib="$(awk '$1 == "size:" { print $2 }' "$count_objects")"
packed_kib="$(awk '$1 == "size-pack:" { print $2 }' "$count_objects")"
actual_object_bytes=$(((loose_kib + packed_kib) * 1024))
actual_refs="$(git -C "$repo" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')"
actual_commits="$(git -C "$repo" rev-list --count --all)"
object_format="$(git -C "$repo" rev-parse --show-object-format)"
ref_format="$(git -C "$repo" rev-parse --show-ref-format)"
git -C "$repo" fsck --full --strict --no-progress \
  > "$lab_root/initial.fsck" 2>&1

test "$actual_object_bytes" -gt 0
test "$actual_refs" -ge 2
test "$actual_commits" -eq 4
test -n "$object_format"
test -n "$ref_format"

actual_metrics="$lab_root/actual-git-metrics.tsv"
{
  printf 'repository_id\tobject_format\tref_format\tobject_bytes\trefs\treachable_commits\tfsck_status\n'
  printf 'repository-fixture\t%s\t%s\t%s\t%s\t%s\tpass\n' \
    "$object_format" "$ref_format" "$actual_object_bytes" \
    "$actual_refs" "$actual_commits"
} > "$actual_metrics"

snapshots="$lab_root/health-snapshots.tsv"
budgets="$lab_root/capacity-budgets.tsv"
first_time=2000000000
second_time=$((first_time + 86400))
actual_limit=$((actual_object_bytes * 10 + 1024))
actual_refs_limit=$((actual_refs + 100))

{
  printf 'timestamp\trepository_id\tsource_status\tobject_bytes\trefs\tlfs_bytes\tartifact_bytes\tfsck_status\tbackup_status\n'
  printf '%s\trepository-fixture\tavailable\t%s\t%s\t0\t0\tpass\tverified\n' \
    "$first_time" "$actual_object_bytes" "$actual_refs"
  printf '%s\trepository-fixture\tavailable\t%s\t%s\t0\t0\tpass\tverified\n' \
    "$second_time" "$actual_object_bytes" "$actual_refs"
  printf '%s\trepository-payments\tavailable\t400\t2\t700\t100\tpass\tverified\n' "$first_time"
  printf '%s\trepository-payments\tavailable\t500\t3\t950\t120\tpass\tverified\n' "$second_time"
  printf '%s\trepository-docs\tavailable\t400\t10\t0\t100\tpass\tverified\n' "$first_time"
  printf '%s\trepository-docs\tavailable\t700\t11\t0\t120\tpass\tverified\n' "$second_time"
  printf '%s\trepository-stable\tavailable\t100\t1\t0\t0\tpass\tverified\n' "$first_time"
  printf '%s\trepository-stable\tavailable\t100\t1\t0\t0\tpass\tverified\n' "$second_time"
  printf '%s\trepository-hidden\tunavailable\t0\t0\t0\t0\tunknown\tunknown\n' "$first_time"
  printf '%s\trepository-hidden\tunavailable\t0\t0\t0\t0\tunknown\tunknown\n' "$second_time"
  printf '%s\trepository-corrupt\tavailable\t10\t1\t0\t0\tpass\tverified\n' "$first_time"
  printf '%s\trepository-corrupt\tavailable\t11\t1\t0\t0\tfail\tverified\n' "$second_time"
} > "$snapshots"

{
  printf 'repository_id\tobject_limit\trefs_limit\tlfs_limit\tartifact_limit\twarn_headroom_days\n'
  printf 'repository-fixture\t%s\t%s\t100\t100\t30\n' \
    "$actual_limit" "$actual_refs_limit"
  printf 'repository-payments\t1000\t100\t900\t500\t30\n'
  printf 'repository-docs\t1000\t100\t100\t1000\t30\n'
  printf 'repository-stable\t1000\t100\t100\t100\t30\n'
  printf 'repository-hidden\t1000\t100\t100\t100\t30\n'
  printf 'repository-corrupt\t1000\t100\t100\t100\t30\n'
} > "$budgets"

classify_capacity "$snapshots" "$budgets" repository-fixture \
  > "$lab_root/fixture.classification"
grep -Fx pass "$lab_root/fixture.classification" >/dev/null

payments_status=0
classify_capacity "$snapshots" "$budgets" repository-payments \
  > "$lab_root/payments.classification" || payments_status=$?
if test "$payments_status" -ne 20; then
  printf 'Expected hard LFS limit breach to return fail status 20, got %s.\n' \
    "$payments_status" >&2
  exit 1
fi
grep -Fx fail "$lab_root/payments.classification" >/dev/null

docs_status=0
classify_capacity "$snapshots" "$budgets" repository-docs \
  > "$lab_root/docs.classification" || docs_status=$?
if test "$docs_status" -ne 10; then
  printf 'Expected short object headroom to return warn status 10, got %s.\n' \
    "$docs_status" >&2
  exit 1
fi
grep -Fx warn "$lab_root/docs.classification" >/dev/null

classify_capacity "$snapshots" "$budgets" repository-stable \
  > "$lab_root/stable.classification"
grep -Fx pass "$lab_root/stable.classification" >/dev/null

hidden_status=0
classify_capacity "$snapshots" "$budgets" repository-hidden \
  > "$lab_root/hidden.classification" || hidden_status=$?
if test "$hidden_status" -ne 30; then
  printf 'Expected unavailable source to return inconclusive status 30, got %s.\n' \
    "$hidden_status" >&2
  exit 1
fi
grep -Fx inconclusive "$lab_root/hidden.classification" >/dev/null

corrupt_status=0
classify_capacity "$snapshots" "$budgets" repository-corrupt \
  > "$lab_root/corrupt.classification" || corrupt_status=$?
if test "$corrupt_status" -ne 20; then
  printf 'Expected integrity failure to return fail status 20, got %s.\n' \
    "$corrupt_status" >&2
  exit 1
fi
grep -Fx fail "$lab_root/corrupt.classification" >/dev/null

refs_before="$lab_root/refs-before.txt"
objects_before="$lab_root/objects-before.txt"
git -C "$repo" show-ref | LC_ALL=C sort > "$refs_before"
git -C "$repo" rev-list --objects --all | LC_ALL=C sort > "$objects_before"
tree_before="$(git -C "$repo" rev-parse HEAD^{tree})"

lock_path="$lab_root/maintenance.lock"
maintenance_log="$lab_root/maintenance-events.tsv"
: > "$maintenance_log"
required_scratch=$((actual_object_bytes * 2 + 1024))
available_scratch=$((required_scratch * 2))

incident_status=0
run_maintenance "$repo" commit-graph "$lock_path" \
  "$available_scratch" "$required_scratch" verified active \
  "$maintenance_log" || incident_status=$?
test "$incident_status" -eq 21
test ! -e "$lock_path"

backup_status=0
run_maintenance "$repo" commit-graph "$lock_path" \
  "$available_scratch" "$required_scratch" stale clear \
  "$maintenance_log" || backup_status=$?
test "$backup_status" -eq 22
test ! -e "$lock_path"

scratch_status=0
run_maintenance "$repo" commit-graph "$lock_path" \
  "$((required_scratch - 1))" "$required_scratch" verified clear \
  "$maintenance_log" || scratch_status=$?
test "$scratch_status" -eq 23
test ! -e "$lock_path"

mkdir "$lock_path"
lock_status=0
run_maintenance "$repo" commit-graph "$lock_path" \
  "$available_scratch" "$required_scratch" verified clear \
  "$maintenance_log" || lock_status=$?
test "$lock_status" -eq 24
rmdir "$lock_path"

failed_task_status=0
run_maintenance "$repo" fixture-invalid "$lock_path" \
  "$available_scratch" "$required_scratch" verified clear \
  "$maintenance_log" || failed_task_status=$?
test "$failed_task_status" -eq 25
test ! -e "$lock_path"
grep -F $'FAILED\ttask=fixture-invalid' "$maintenance_log" >/dev/null

run_maintenance "$repo" commit-graph "$lock_path" \
  "$available_scratch" "$required_scratch" verified clear \
  "$maintenance_log"
test ! -e "$lock_path"
grep -F $'START\ttask=commit-graph' "$maintenance_log" >/dev/null
grep -F $'VALIDATING\ttask=commit-graph' "$maintenance_log" >/dev/null
grep -F $'COMPLETE\ttask=commit-graph' "$maintenance_log" >/dev/null

refs_after="$lab_root/refs-after.txt"
objects_after="$lab_root/objects-after.txt"
git -C "$repo" show-ref | LC_ALL=C sort > "$refs_after"
git -C "$repo" rev-list --objects --all | LC_ALL=C sort > "$objects_after"
cmp "$refs_before" "$refs_after"
cmp "$objects_before" "$objects_after"
test "$(git -C "$repo" rev-parse HEAD^{tree})" = "$tree_before"
git -C "$repo" fsck --full --strict --no-progress \
  > "$lab_root/final.fsck" 2>&1

printf 'Repository health pass/warn/fail/inconclusive, layered capacity, maintenance gates, lock recovery, and invariants passed.\n'
