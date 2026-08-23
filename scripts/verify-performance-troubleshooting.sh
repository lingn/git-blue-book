#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d /tmp/git-blue-book-performance-troubleshooting.XXXXXX)"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Performance Troubleshooting Fixture'
git -C "$repo" config user.email 'performance-troubleshooting@example.invalid'
git -C "$repo" config maintenance.auto false
git -C "$repo" config gc.auto 0

write_batch() {
  start="$1"
  end="$2"
  i="$start"
  while test "$i" -le "$end"; do
    module=$((i % 5))
    mkdir -p "$repo/modules/module-$module"
    printf 'revision=%s\nmodule=%s\n' "$i" "$module" \
      > "$repo/modules/module-$module/entry-$i.txt"
    git -C "$repo" add "modules/module-$module/entry-$i.txt"
    git -C "$repo" commit --quiet -m "fixture: add revision $i"
    i=$((i + 1))
  done
}

classify_capacity() {
  snapshots_path="$1"
  budgets_path="$2"
  repository_id="$3"

  awk -F '\t' -v target="$repository_id" '
    NR == FNR {
      if (FNR == 1) {
        next
      }
      if ($2 != target) {
        next
      }
      snapshot_count++
      timestamp = $1 + 0
      if (!have_current || timestamp > current_time) {
        previous_time = current_time
        previous_object = current_object
        previous_refs = current_refs
        previous_lfs = current_lfs
        previous_artifact = current_artifact
        current_time = timestamp
        current_source = $3
        current_object = $4 + 0
        current_refs = $5 + 0
        current_lfs = $6 + 0
        current_artifact = $7 + 0
        current_fsck = $8
        current_backup = $9
        have_current = 1
      }
      next
    }

    FNR == 1 {
      next
    }

    $1 == target {
      budget_matches++
      object_limit = $2 + 0
      refs_limit = $3 + 0
      lfs_limit = $4 + 0
      artifact_limit = $5 + 0
      warn_days = $6 + 0
    }

    function warns(previous, current, limit, elapsed_days, growth, headroom) {
      if (elapsed_days <= 0) {
        return 0
      }
      growth = (current - previous) / elapsed_days
      if (growth <= 0) {
        return 0
      }
      headroom = (limit - current) / growth
      return headroom < warn_days
    }

    END {
      if (budget_matches != 1 || snapshot_count < 2 ||
          !have_current || previous_time == "" ||
          current_time <= previous_time) {
        print "inconclusive"
        exit 30
      }
      if (current_source != "available" ||
          current_fsck == "unknown" || current_backup == "unknown") {
        print "inconclusive"
        exit 30
      }
      if (current_fsck != "pass" || current_backup != "verified" ||
          current_object > object_limit || current_refs > refs_limit ||
          current_lfs > lfs_limit || current_artifact > artifact_limit) {
        print "fail"
        exit 20
      }
      elapsed_days = (current_time - previous_time) / 86400
      if (warns(previous_object, current_object, object_limit, elapsed_days) ||
          warns(previous_refs, current_refs, refs_limit, elapsed_days) ||
          warns(previous_lfs, current_lfs, lfs_limit, elapsed_days) ||
          warns(previous_artifact, current_artifact, artifact_limit, elapsed_days)) {
        print "warn"
        exit 10
      }
      print "pass"
      exit 0
    }
  ' "$snapshots_path" "$budgets_path"
}

write_batch 1 12
git -C "$repo" repack -d --quiet
write_batch 13 24
git -C "$repo" repack -d --quiet
write_batch 25 36

pack_dir="$repo/.git/objects/pack"
pack_count="$(find "$pack_dir" -type f -name '*.pack' | wc -l | tr -d ' ')"
test "$pack_count" -ge 2

git -C "$repo" branch archive/first-batch HEAD~24
git -C "$repo" branch release/stable HEAD~6
git -C "$repo" tag -a -m 'Performance troubleshooting fixture' fixture-v1 HEAD~12

refs_before="$(git -C "$repo" show-ref | LC_ALL=C sort)"
head_before="$(git -C "$repo" rev-parse HEAD)"
tree_before="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
history_before="$(git -C "$repo" rev-list --all | LC_ALL=C sort)"
objects_before="$(git -C "$repo" rev-list --objects --all | LC_ALL=C sort)"
status_before="$(git -C "$repo" status --porcelain=v1)"
test -z "$status_before"

commit_count="$(git -C "$repo" rev-list --count --all)"
ref_count="$(git -C "$repo" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')"
tracked_path_count="$(git -C "$repo" ls-files -z | tr -cd '\0' | wc -c | tr -d ' ')"
index_path="$(git -C "$repo" rev-parse --git-path index)"
index_bytes="$(wc -c < "$repo/$index_path" | tr -d ' ')"
test "$commit_count" = 36
test "$ref_count" = 4
test "$tracked_path_count" = 36
test "$index_bytes" -gt 0

object_metrics="$lab_root/object-metrics.txt"
git -C "$repo" count-objects -v > "$object_metrics"
grep -q '^count: ' "$object_metrics"
grep -q '^in-pack: ' "$object_metrics"
grep -q '^packs: ' "$object_metrics"
test "$(awk '/^packs: / {print $2}' "$object_metrics")" -ge 2

trace_event="$lab_root/status-trace.json"
GIT_OPTIONAL_LOCKS=0 GIT_TRACE2_EVENT="$trace_event" \
  git -C "$repo" status --short >/dev/null
test -s "$trace_event"
grep -q '"event":"version"' "$trace_event"
grep -q '"event":"exit"' "$trace_event"

object_kib="$(awk '/^size: / {print $2}' "$object_metrics")"
pack_kib="$(awk '/^size-pack: / {print $2}' "$object_metrics")"
object_bytes=$(((object_kib + pack_kib) * 1024))
test "$object_bytes" -gt 0

snapshots="$lab_root/capacity-snapshots.tsv"
budgets="$lab_root/capacity-budgets.tsv"
first_time=2000000000
second_time=$((first_time + 86400))
{
  printf 'timestamp\trepository_id\tsource_status\tobject_bytes\trefs\tlfs_bytes\tartifact_bytes\tfsck_status\tbackup_status\n'
  printf '%s\tfixture-pass\tavailable\t%s\t%s\t0\t0\tpass\tverified\n' \
    "$first_time" "$object_bytes" "$ref_count"
  printf '%s\tfixture-pass\tavailable\t%s\t%s\t0\t0\tpass\tverified\n' \
    "$second_time" "$object_bytes" "$ref_count"
  printf '%s\tfixture-warn\tavailable\t400\t2\t0\t0\tpass\tverified\n' "$first_time"
  printf '%s\tfixture-warn\tavailable\t700\t2\t0\t0\tpass\tverified\n' "$second_time"
  printf '%s\tfixture-fail\tavailable\t400\t2\t900\t0\tpass\tverified\n' "$first_time"
  printf '%s\tfixture-fail\tavailable\t400\t2\t1100\t0\tpass\tverified\n' "$second_time"
  printf '%s\tfixture-hidden\tunavailable\t0\t0\t0\t0\tunknown\tunknown\n' "$first_time"
  printf '%s\tfixture-hidden\tunavailable\t0\t0\t0\t0\tunknown\tunknown\n' "$second_time"
} > "$snapshots"
{
  printf 'repository_id\tobject_limit\trefs_limit\tlfs_limit\tartifact_limit\twarn_headroom_days\n'
  printf 'fixture-pass\t%s\t%s\t100\t100\t30\n' \
    "$((object_bytes * 10 + 1024))" "$((ref_count + 100))"
  printf 'fixture-warn\t1000\t100\t1000\t100\t30\n'
  printf 'fixture-fail\t1000\t100\t1000\t100\t30\n'
  printf 'fixture-hidden\t1000\t100\t1000\t100\t30\n'
} > "$budgets"

classify_capacity "$snapshots" "$budgets" fixture-pass \
  > "$lab_root/pass.classification"
grep -Fx pass "$lab_root/pass.classification" >/dev/null

warn_status=0
classify_capacity "$snapshots" "$budgets" fixture-warn \
  > "$lab_root/warn.classification" || warn_status=$?
test "$warn_status" -eq 10
grep -Fx warn "$lab_root/warn.classification" >/dev/null

fail_status=0
classify_capacity "$snapshots" "$budgets" fixture-fail \
  > "$lab_root/fail.classification" || fail_status=$?
test "$fail_status" -eq 20
grep -Fx fail "$lab_root/fail.classification" >/dev/null

hidden_status=0
classify_capacity "$snapshots" "$budgets" fixture-hidden \
  > "$lab_root/hidden.classification" || hidden_status=$?
test "$hidden_status" -eq 30
grep -Fx inconclusive "$lab_root/hidden.classification" >/dev/null

git -C "$repo" commit-graph write --reachable --changed-paths
git -C "$repo" commit-graph verify
test -f "$repo/.git/objects/info/commit-graph"

git -C "$repo" multi-pack-index write --bitmap
git -C "$repo" multi-pack-index verify
test -f "$pack_dir/multi-pack-index"

git -C "$repo" maintenance run --task=commit-graph
git -C "$repo" maintenance run --task=incremental-repack
git -C "$repo" commit-graph verify
git -C "$repo" multi-pack-index verify
git -C "$repo" fsck --full --no-progress >/dev/null

test "$(git -C "$repo" show-ref | LC_ALL=C sort)" = "$refs_before"
test "$(git -C "$repo" rev-parse HEAD)" = "$head_before"
test "$(git -C "$repo" rev-parse 'HEAD^{tree}')" = "$tree_before"
test "$(git -C "$repo" rev-list --all | LC_ALL=C sort)" = "$history_before"
test "$(git -C "$repo" rev-list --objects --all | LC_ALL=C sort)" = "$objects_before"
test -z "$(git -C "$repo" status --porcelain=v1)"

printf 'Performance evidence, capacity states, auxiliary indexes, maintenance, and invariants passed.\n'
