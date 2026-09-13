#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-merge-shapes.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

ff_repo="$lab_dir/fast-forward"
divergent_repo="$lab_dir/divergent"
conflict_repo="$lab_dir/conflict"

git init --quiet --initial-branch=main "$ff_repo"
git -C "$ff_repo" config user.name "Merge Shapes Lab"
git -C "$ff_repo" config user.email "merge-shapes@example.invalid"
printf 'base\n' > "$ff_repo/base.txt"
git -C "$ff_repo" add base.txt
git -C "$ff_repo" commit --quiet -m "build: create merge base"
ff_base="$(git -C "$ff_repo" rev-parse HEAD)"
git -C "$ff_repo" switch --quiet -c topic
printf 'topic\n' > "$ff_repo/topic.txt"
git -C "$ff_repo" add topic.txt
git -C "$ff_repo" commit --quiet -m "feat: add topic"
ff_topic="$(git -C "$ff_repo" rev-parse HEAD)"
ff_topic_tree="$(git -C "$ff_repo" rev-parse 'HEAD^{tree}')"
git -C "$ff_repo" switch --quiet main

git -C "$ff_repo" merge --quiet --no-commit topic
test "$(git -C "$ff_repo" rev-parse HEAD)" = "$ff_topic"
test "$(git -C "$ff_repo" rev-parse refs/heads/main)" = "$ff_topic"
test "$(git -C "$ff_repo" rev-parse refs/heads/topic)" = "$ff_topic"
test "$(git -C "$ff_repo" rev-parse 'HEAD^{tree}')" = "$ff_topic_tree"
if git -C "$ff_repo" rev-parse --verify MERGE_HEAD >/dev/null 2>&1; then
  printf 'A normal fast-forward must not leave MERGE_HEAD.\n' >&2
  exit 1
fi
test "$(git -C "$ff_repo" show -s --format=%P HEAD | wc -w | tr -d '[:space:]')" = "1"
test -z "$(git -C "$ff_repo" status --short)"

git -C "$ff_repo" switch --quiet -c integration/no-ff "$ff_base"
git -C "$ff_repo" merge --quiet --no-ff --no-commit "$ff_topic" \
  >"$lab_dir/ff-no-commit.out" 2>"$lab_dir/ff-no-commit.err"
test "$(git -C "$ff_repo" rev-parse HEAD)" = "$ff_base"
test "$(git -C "$ff_repo" rev-parse MERGE_HEAD)" = "$ff_topic"
test "$(git -C "$ff_repo" write-tree)" = "$ff_topic_tree"
git -C "$ff_repo" merge --abort
test "$(git -C "$ff_repo" rev-parse HEAD)" = "$ff_base"
test -z "$(git -C "$ff_repo" status --short)"

git init --quiet --initial-branch=main "$divergent_repo"
git -C "$divergent_repo" config user.name "Divergent Merge Lab"
git -C "$divergent_repo" config user.email "divergent@example.invalid"
printf 'base\n' > "$divergent_repo/base.txt"
git -C "$divergent_repo" add base.txt
git -C "$divergent_repo" commit --quiet -m "build: create divergent base"
divergent_base="$(git -C "$divergent_repo" rev-parse HEAD)"
git -C "$divergent_repo" switch --quiet -c topic
printf 'topic\n' > "$divergent_repo/topic.txt"
git -C "$divergent_repo" add topic.txt
git -C "$divergent_repo" commit --quiet -m "feat: add divergent topic"
divergent_topic="$(git -C "$divergent_repo" rev-parse HEAD)"
git -C "$divergent_repo" switch --quiet main
printf 'main\n' > "$divergent_repo/main.txt"
git -C "$divergent_repo" add main.txt
git -C "$divergent_repo" commit --quiet -m "fix: advance main"
divergent_main="$(git -C "$divergent_repo" rev-parse HEAD)"
divergent_main_tree="$(git -C "$divergent_repo" rev-parse 'HEAD^{tree}')"

test "$(git -C "$divergent_repo" merge-base --all "$divergent_main" "$divergent_topic")" = "$divergent_base"
test "$(git -C "$divergent_repo" rev-list --left-right --count "$divergent_main...$divergent_topic")" = $'1\t1'
if git -C "$divergent_repo" merge-base --is-ancestor "$divergent_main" "$divergent_topic"; then
  printf 'Divergent main must not be an ancestor of topic.\n' >&2
  exit 1
fi
if git -C "$divergent_repo" merge-base --is-ancestor "$divergent_topic" "$divergent_main"; then
  printf 'Divergent topic must not be an ancestor of main.\n' >&2
  exit 1
fi

if git -C "$divergent_repo" merge --ff-only topic \
  >"$lab_dir/ff-only.out" 2>"$lab_dir/ff-only.err"; then
  printf 'Expected ff-only to reject divergent histories.\n' >&2
  exit 1
fi
test -s "$lab_dir/ff-only.err"
test "$(git -C "$divergent_repo" rev-parse HEAD)" = "$divergent_main"
test "$(git -C "$divergent_repo" write-tree)" = "$divergent_main_tree"
test -z "$(git -C "$divergent_repo" status --short)"

git -C "$divergent_repo" merge --quiet --no-ff --no-commit topic \
  >"$lab_dir/divergent-no-commit.out" \
  2>"$lab_dir/divergent-no-commit.err"
test "$(git -C "$divergent_repo" rev-parse HEAD)" = "$divergent_main"
test "$(git -C "$divergent_repo" rev-parse MERGE_HEAD)" = "$divergent_topic"
combined_tree="$(git -C "$divergent_repo" write-tree)"
test "$(git -C "$divergent_repo" show "$combined_tree:base.txt")" = "base"
test "$(git -C "$divergent_repo" show "$combined_tree:main.txt")" = "main"
test "$(git -C "$divergent_repo" show "$combined_tree:topic.txt")" = "topic"
git -C "$divergent_repo" merge --abort
test "$(git -C "$divergent_repo" rev-parse HEAD)" = "$divergent_main"
test "$(git -C "$divergent_repo" write-tree)" = "$divergent_main_tree"
test -z "$(git -C "$divergent_repo" status --short)"

git -C "$divergent_repo" merge --quiet --no-ff --no-edit topic
merge_oid="$(git -C "$divergent_repo" rev-parse HEAD)"
parents="$(git -C "$divergent_repo" show -s --format=%P "$merge_oid")"
test "$(printf '%s\n' "$parents" | awk '{print $1}')" = "$divergent_main"
test "$(printf '%s\n' "$parents" | awk '{print $2}')" = "$divergent_topic"
test "$(git -C "$divergent_repo" rev-parse 'HEAD^{tree}')" = "$combined_tree"
git -C "$divergent_repo" merge-base --is-ancestor "$divergent_main" "$merge_oid"
git -C "$divergent_repo" merge-base --is-ancestor "$divergent_topic" "$merge_oid"
test -z "$(git -C "$divergent_repo" status --short)"

git init --quiet --initial-branch=main "$conflict_repo"
git -C "$conflict_repo" config user.name "Conflict Inputs Lab"
git -C "$conflict_repo" config user.email "conflict-inputs@example.invalid"
printf 'mode=base\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "build: add conflict base"
git -C "$conflict_repo" switch --quiet -c topic
printf 'mode=topic\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "feat: use topic mode"
conflict_topic="$(git -C "$conflict_repo" rev-parse HEAD)"
git -C "$conflict_repo" switch --quiet main
printf 'mode=main\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "fix: use main mode"
conflict_main="$(git -C "$conflict_repo" rev-parse HEAD)"
if git -C "$conflict_repo" merge --quiet topic \
  >"$lab_dir/conflict.out" 2>"$lab_dir/conflict.err"; then
  printf 'Expected content/content conflict.\n' >&2
  exit 1
fi
test "$(git -C "$conflict_repo" rev-parse HEAD)" = "$conflict_main"
test "$(git -C "$conflict_repo" rev-parse MERGE_HEAD)" = "$conflict_topic"
test "$(git -C "$conflict_repo" ls-files -u -- config.txt | awk '{print $3}' | tr '\n' ' ')" = "1 2 3 "
test "$(git -C "$conflict_repo" show :1:config.txt)" = "mode=base"
test "$(git -C "$conflict_repo" show :2:config.txt)" = "mode=main"
test "$(git -C "$conflict_repo" show :3:config.txt)" = "mode=topic"
git -C "$conflict_repo" merge --abort
test "$(git -C "$conflict_repo" rev-parse HEAD)" = "$conflict_main"
test -z "$(git -C "$conflict_repo" status --short)"

git -C "$ff_repo" fsck --full --strict >/dev/null
git -C "$divergent_repo" fsck --full --strict >/dev/null
git -C "$conflict_repo" fsck --full --strict >/dev/null

printf 'Merge bases, fast-forwards, ff-only rejection, merge commits, aborts, and conflict inputs passed.\n'
