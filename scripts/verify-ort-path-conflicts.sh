#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-ort-paths.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

strategy_repo="$lab_dir/strategy"
path_repo="$lab_dir/path-conflicts"

git init --quiet --initial-branch=main "$strategy_repo"
git -C "$strategy_repo" config user.name "Ort Strategy Lab"
git -C "$strategy_repo" config user.email "ort-strategy@example.invalid"
printf 'mode=base\n' > "$strategy_repo/config.txt"
git -C "$strategy_repo" add config.txt
git -C "$strategy_repo" commit --quiet -m "build: add strategy base"
base_oid="$(git -C "$strategy_repo" rev-parse HEAD)"

git -C "$strategy_repo" switch --quiet -c topic
printf 'mode=topic\n' > "$strategy_repo/config.txt"
printf 'topic only\n' > "$strategy_repo/topic.txt"
git -C "$strategy_repo" add config.txt topic.txt
git -C "$strategy_repo" commit --quiet -m "feat: add topic changes"
topic_oid="$(git -C "$strategy_repo" rev-parse HEAD)"

git -C "$strategy_repo" switch --quiet main
printf 'mode=main\n' > "$strategy_repo/config.txt"
printf 'main only\n' > "$strategy_repo/main.txt"
git -C "$strategy_repo" add config.txt main.txt
git -C "$strategy_repo" commit --quiet -m "fix: add main changes"
main_oid="$(git -C "$strategy_repo" rev-parse HEAD)"
main_tree="$(git -C "$strategy_repo" rev-parse 'HEAD^{tree}')"

git -C "$strategy_repo" switch --quiet -c integration/x-ours "$main_oid"
git -C "$strategy_repo" merge --quiet --no-edit -X ours "$topic_oid" \
  >"$lab_dir/x-ours.out" 2>"$lab_dir/x-ours.err"
x_ours_oid="$(git -C "$strategy_repo" rev-parse HEAD)"
test "$(git -C "$strategy_repo" show HEAD:config.txt)" = "mode=main"
test "$(git -C "$strategy_repo" show HEAD:main.txt)" = "main only"
test "$(git -C "$strategy_repo" show HEAD:topic.txt)" = "topic only"
test "$(git -C "$strategy_repo" show -s --format=%P HEAD | awk '{print NF}')" = "2"
git -C "$strategy_repo" merge-base --is-ancestor "$topic_oid" "$x_ours_oid"

git -C "$strategy_repo" switch --quiet -c integration/strategy-ours "$main_oid"
git -C "$strategy_repo" merge --quiet --no-edit -s ours "$topic_oid"
strategy_ours_oid="$(git -C "$strategy_repo" rev-parse HEAD)"
test "$(git -C "$strategy_repo" rev-parse 'HEAD^{tree}')" = "$main_tree"
test "$(git -C "$strategy_repo" show HEAD:config.txt)" = "mode=main"
test "$(git -C "$strategy_repo" show HEAD:main.txt)" = "main only"
if git -C "$strategy_repo" cat-file -e 'HEAD:topic.txt' 2>/dev/null; then
  printf 'The ours strategy must not include the incoming-only path.\n' >&2
  exit 1
fi
test "$(git -C "$strategy_repo" show -s --format=%P HEAD | awk '{print NF}')" = "2"
git -C "$strategy_repo" merge-base --is-ancestor "$topic_oid" "$strategy_ours_oid"

git -C "$strategy_repo" switch --quiet -c integration/auto-merge "$main_oid"
if git -C "$strategy_repo" merge --quiet "$topic_oid" \
  >"$lab_dir/content-conflict.out" 2>"$lab_dir/content-conflict.err"; then
  printf 'Expected a content conflict for AUTO_MERGE.\n' >&2
  exit 1
fi
test "$(git -C "$strategy_repo" cat-file -t AUTO_MERGE)" = "tree"
auto_merge_tree="$(git -C "$strategy_repo" rev-parse 'AUTO_MERGE^{tree}')"
test -n "$auto_merge_tree"
git -C "$strategy_repo" diff --quiet AUTO_MERGE
printf 'manual investigation\n' >> "$strategy_repo/config.txt"
if git -C "$strategy_repo" diff --quiet AUTO_MERGE; then
  printf 'Expected manual edits to differ from AUTO_MERGE.\n' >&2
  exit 1
fi
git -C "$strategy_repo" merge --abort
test "$(git -C "$strategy_repo" rev-parse HEAD)" = "$main_oid"
test -z "$(git -C "$strategy_repo" status --short)"

git init --quiet --initial-branch=main "$path_repo"
git -C "$path_repo" config user.name "Path Conflict Lab"
git -C "$path_repo" config user.email "path-conflict@example.invalid"
printf 'legacy base\n' > "$path_repo/legacy.txt"
printf 'root\n' > "$path_repo/README.md"
git -C "$path_repo" add legacy.txt README.md
git -C "$path_repo" commit --quiet -m "build: add path base"

git -C "$path_repo" switch --quiet -c topic
printf 'legacy updated by topic\n' > "$path_repo/legacy.txt"
printf 'topic collision\n' > "$path_repo/collision.txt"
git -C "$path_repo" add legacy.txt collision.txt
git -C "$path_repo" commit --quiet -m "feat: update legacy and add collision"
path_topic="$(git -C "$path_repo" rev-parse HEAD)"

git -C "$path_repo" switch --quiet main
git -C "$path_repo" rm --quiet legacy.txt
printf 'main collision\n' > "$path_repo/collision.txt"
git -C "$path_repo" add collision.txt
git -C "$path_repo" commit --quiet -m "refactor: delete legacy and add collision"
path_main="$(git -C "$path_repo" rev-parse HEAD)"
if git -C "$path_repo" merge --quiet topic \
  >"$lab_dir/path-conflict.out" 2>"$lab_dir/path-conflict.err"; then
  printf 'Expected add/add and modify/delete conflicts.\n' >&2
  exit 1
fi
test "$(git -C "$path_repo" rev-parse HEAD)" = "$path_main"
test "$(git -C "$path_repo" rev-parse MERGE_HEAD)" = "$path_topic"
test "$(git -C "$path_repo" status --porcelain=v1 -- collision.txt)" = "AA collision.txt"
test "$(git -C "$path_repo" status --porcelain=v1 -- legacy.txt)" = "DU legacy.txt"
test "$(git -C "$path_repo" ls-files -u -- collision.txt | awk '{print $3}' | tr '\n' ' ')" = "2 3 "
test "$(git -C "$path_repo" ls-files -u -- legacy.txt | awk '{print $3}' | tr '\n' ' ')" = "1 3 "
test "$(git -C "$path_repo" show :2:collision.txt)" = "main collision"
test "$(git -C "$path_repo" show :3:collision.txt)" = "topic collision"
test "$(git -C "$path_repo" show :1:legacy.txt)" = "legacy base"
test "$(git -C "$path_repo" show :3:legacy.txt)" = "legacy updated by topic"
git -C "$path_repo" merge --abort
test "$(git -C "$path_repo" rev-parse HEAD)" = "$path_main"
test -z "$(git -C "$path_repo" status --short)"

git -C "$strategy_repo" fsck --full --strict >/dev/null
git -C "$path_repo" fsck --full --strict >/dev/null

printf 'Ort options, ours strategy, AUTO_MERGE, add/add, and modify/delete stages passed.\n'
