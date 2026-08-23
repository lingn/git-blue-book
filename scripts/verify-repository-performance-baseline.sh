#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-performance.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Performance Fixture Author'
git -C "$repo" config user.email 'performance@example.invalid'
git -C "$repo" config maintenance.auto false
git -C "$repo" config gc.auto 0

write_commit_batch() {
  start="$1"
  end="$2"
  i="$start"
  while test "$i" -le "$end"; do
    module=$((i % 6))
    mkdir -p "$repo/modules/module-$module"
    printf 'revision=%s\nmodule=%s\n' "$i" "$module" \
      > "$repo/modules/module-$module/entry-$i.txt"
    git -C "$repo" add "modules/module-$module/entry-$i.txt"
    git -C "$repo" commit --quiet -m "fixture: add revision $i"
    i=$((i + 1))
  done
}

write_commit_batch 1 18
git -C "$repo" repack -d --quiet
write_commit_batch 19 36
git -C "$repo" repack -d --quiet

git -C "$repo" branch archive/first-batch HEAD~18
git -C "$repo" branch release/stable HEAD~6
git -C "$repo" tag -a -m 'Performance fixture baseline' fixture-v1 HEAD~12

pack_dir="$repo/.git/objects/pack"
pack_count_before="$(find "$pack_dir" -type f -name '*.pack' | wc -l | tr -d ' ')"
test "$pack_count_before" -ge 2

commit_count="$(git -C "$repo" rev-list --count --all)"
ref_count="$(git -C "$repo" for-each-ref --format='%(refname)' | wc -l | tr -d ' ')"
tracked_path_count="$(git -C "$repo" ls-files -z | tr -cd '\000' | wc -c | tr -d ' ')"
index_path="$(git -C "$repo" rev-parse --git-path index)"
index_bytes="$(wc -c < "$repo/$index_path" | tr -d ' ')"

test "$commit_count" = '36'
test "$ref_count" = '4'
test "$tracked_path_count" = '36'
test "$index_bytes" -gt 0

object_metrics="$lab_root/object-metrics"
git -C "$repo" count-objects -v > "$object_metrics"
grep -q '^count: ' "$object_metrics"
grep -q '^in-pack: ' "$object_metrics"
grep -q '^packs: ' "$object_metrics"
test "$(awk '/^packs: / {print $2}' "$object_metrics")" -ge 2

trace_event="$lab_root/status-trace.json"
GIT_TRACE2_EVENT="$trace_event" git -C "$repo" status --short >/dev/null
test -s "$trace_event"
grep -q '"event":"version"' "$trace_event"
grep -q '"event":"exit"' "$trace_event"

refs_before="$(git -C "$repo" show-ref | sort)"
head_before="$(git -C "$repo" rev-parse HEAD)"
tree_before="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
history_before="$(git -C "$repo" rev-list --all | sort)"
status_before="$(git -C "$repo" status --porcelain=v1)"
test -z "$status_before"

git -C "$repo" commit-graph write --reachable --changed-paths
git -C "$repo" commit-graph verify
test -f "$repo/.git/objects/info/commit-graph"

git -C "$repo" multi-pack-index write --bitmap
git -C "$repo" multi-pack-index verify
test -f "$pack_dir/multi-pack-index"

test "$(git -C "$repo" rev-list --all | sort)" = "$history_before"
test "$(git -C "$repo" -c core.commitGraph=false rev-list --all | sort)" = \
  "$history_before"
git -C "$repo" -c core.multiPackIndex=false cat-file -e 'HEAD^{commit}'

git -C "$repo" maintenance run --task=commit-graph
git -C "$repo" maintenance run --task=incremental-repack
git -C "$repo" commit-graph verify
git -C "$repo" multi-pack-index verify
git -C "$repo" fsck --full --no-progress >/dev/null

test "$(git -C "$repo" show-ref | sort)" = "$refs_before"
test "$(git -C "$repo" rev-parse HEAD)" = "$head_before"
test "$(git -C "$repo" rev-parse 'HEAD^{tree}')" = "$tree_before"
test "$(git -C "$repo" rev-list --all | sort)" = "$history_before"
test -z "$(git -C "$repo" status --porcelain=v1)"

printf 'Scale metrics, Trace2, commit-graph, MIDX bitmap, and explicit maintenance passed.\n'
