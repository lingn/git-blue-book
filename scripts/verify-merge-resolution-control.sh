#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-merge-control.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

repo="$lab_dir/repo"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name "Merge Control Lab"
git -C "$repo" config user.email "merge-control@example.invalid"
printf 'mode=base\n' > "$repo/config.txt"
printf 'local base\n' > "$repo/local.txt"
git -C "$repo" add config.txt local.txt
git -C "$repo" commit --quiet -m "build: add merge control base"

git -C "$repo" switch --quiet -c topic
printf 'mode=topic\n' > "$repo/config.txt"
git -C "$repo" add config.txt
git -C "$repo" commit --quiet -m "feat: use topic mode"
topic_oid="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet main
printf 'mode=main\n' > "$repo/config.txt"
git -C "$repo" add config.txt
git -C "$repo" commit --quiet -m "fix: use main mode"
main_oid="$(git -C "$repo" rev-parse HEAD)"
main_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"

printf 'local uncommitted change\n' > "$repo/local.txt"
local_change_oid="$(git -C "$repo" hash-object -- local.txt)"
if git -C "$repo" merge --autostash --quiet topic \
  >"$lab_dir/autostash-merge.out" 2>"$lab_dir/autostash-merge.err"; then
  printf 'Expected autostash merge to stop on a content conflict.\n' >&2
  exit 1
fi
test "$(git -C "$repo" rev-parse HEAD)" = "$main_oid"
test "$(git -C "$repo" rev-parse MERGE_HEAD)" = "$topic_oid"
git -C "$repo" rev-parse --verify MERGE_AUTOSTASH >/dev/null
test "$(cat "$repo/local.txt")" = "local base"
git -C "$repo" merge --abort \
  >"$lab_dir/autostash-abort.out" 2>"$lab_dir/autostash-abort.err"
test "$(git -C "$repo" rev-parse HEAD)" = "$main_oid"
test "$(git -C "$repo" write-tree)" = "$main_tree"
test "$(git -C "$repo" hash-object -- local.txt)" = "$local_change_oid"
test "$(git -C "$repo" status --porcelain=v1 -- local.txt)" = " M local.txt"
if git -C "$repo" rev-parse --verify MERGE_HEAD >/dev/null 2>&1; then
  printf 'Abort must remove MERGE_HEAD.\n' >&2
  exit 1
fi
if git -C "$repo" rev-parse --verify MERGE_AUTOSTASH >/dev/null 2>&1; then
  printf 'Abort must consume MERGE_AUTOSTASH after restoring the local change.\n' >&2
  exit 1
fi
git -C "$repo" restore --worktree -- local.txt
test -z "$(git -C "$repo" status --short)"

if git -C "$repo" merge --quiet topic \
  >"$lab_dir/quit-merge.out" 2>"$lab_dir/quit-merge.err"; then
  printf 'Expected the quit scenario to conflict.\n' >&2
  exit 1
fi
stages_before_quit="$(git -C "$repo" ls-files -u -- config.txt)"
worktree_before_quit="$(git -C "$repo" hash-object -- config.txt)"
git -C "$repo" merge --quit
if git -C "$repo" rev-parse --verify MERGE_HEAD >/dev/null 2>&1; then
  printf 'Quit must remove MERGE_HEAD.\n' >&2
  exit 1
fi
test "$(git -C "$repo" ls-files -u -- config.txt)" = "$stages_before_quit"
test "$(git -C "$repo" hash-object -- config.txt)" = "$worktree_before_quit"
if git -C "$repo" merge --abort \
  >"$lab_dir/abort-after-quit.out" 2>"$lab_dir/abort-after-quit.err"; then
  printf 'Abort must not succeed after quit removed the merge state.\n' >&2
  exit 1
fi
test -s "$lab_dir/abort-after-quit.err"
git -C "$repo" reset --quiet --hard "$main_oid"
test -z "$(git -C "$repo" status --short)"

if git -C "$repo" merge --quiet topic \
  >"$lab_dir/continue-merge.out" 2>"$lab_dir/continue-merge.err"; then
  printf 'Expected the continue scenario to conflict.\n' >&2
  exit 1
fi
printf 'mode=combined\n' > "$repo/config.txt"
git -C "$repo" add config.txt
test -z "$(git -C "$repo" ls-files -u -- config.txt)"
resolved_tree="$(git -C "$repo" write-tree)"

printf '#!/bin/sh\nprintf "synthetic pre-commit rejection\\n" >&2\nexit 1\n' \
  > "$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
if GIT_EDITOR=true git -C "$repo" merge --continue \
  >"$lab_dir/continue-rejected.out" 2>"$lab_dir/continue-rejected.err"; then
  printf 'Expected the synthetic pre-commit hook to reject merge --continue.\n' >&2
  exit 1
fi
grep -F 'synthetic pre-commit rejection' "$lab_dir/continue-rejected.err" >/dev/null
test "$(git -C "$repo" rev-parse HEAD)" = "$main_oid"
test "$(git -C "$repo" rev-parse MERGE_HEAD)" = "$topic_oid"
test "$(git -C "$repo" write-tree)" = "$resolved_tree"

rm -- "$repo/.git/hooks/pre-commit"
GIT_EDITOR=true git -C "$repo" merge --continue \
  >"$lab_dir/continue-success.out" 2>"$lab_dir/continue-success.err"
merge_oid="$(git -C "$repo" rev-parse HEAD)"
parents="$(git -C "$repo" show -s --format=%P "$merge_oid")"
test "$(printf '%s\n' "$parents" | awk '{print $1}')" = "$main_oid"
test "$(printf '%s\n' "$parents" | awk '{print $2}')" = "$topic_oid"
test "$(git -C "$repo" rev-parse 'HEAD^{tree}')" = "$resolved_tree"
test "$(git -C "$repo" show HEAD:config.txt)" = "mode=combined"
test -z "$(git -C "$repo" status --short)"
if git -C "$repo" rev-parse --verify MERGE_HEAD >/dev/null 2>&1; then
  printf 'Completed merge must not retain MERGE_HEAD.\n' >&2
  exit 1
fi

git -C "$repo" fsck --full --strict >/dev/null
printf 'Autostash abort, merge quit, hook rejection, continue retry, and final merge verification passed.\n'
