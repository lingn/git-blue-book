#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-branch-switch.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

seed="$lab_dir/seed"
server="$lab_dir/server.git"
client="$lab_dir/client"
linked="$lab_dir/linked"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "Branch Switch Lab"
git -C "$seed" config user.email "branch-switch@example.invalid"
printf 'base config\n' > "$seed/config.txt"
printf 'portable base\n' > "$seed/portable.txt"
git -C "$seed" add config.txt portable.txt
git -C "$seed" commit --quiet -m "build: create branch baseline"
base_oid="$(git -C "$seed" rev-parse HEAD)"
base_tree="$(git -C "$seed" rev-parse 'HEAD^{tree}')"

git -C "$seed" branch feature/switch "$base_oid"
test "$(git -C "$seed" branch --show-current)" = "main"
test "$(git -C "$seed" rev-parse HEAD)" = "$base_oid"
test "$(git -C "$seed" write-tree)" = "$base_tree"
if git -C "$seed" check-ref-format --branch 'bad..branch' >/dev/null 2>&1; then
  printf 'Expected an invalid branch name to be rejected.\n' >&2
  exit 1
fi

git -C "$seed" switch --quiet feature/switch
printf 'feature config\n' > "$seed/config.txt"
printf 'feature tracked path\n' > "$seed/target.txt"
git -C "$seed" add config.txt target.txt
git -C "$seed" commit --quiet -m "feat: change target branch"
feature_oid="$(git -C "$seed" rev-parse HEAD)"
test "$feature_oid" != "$base_oid"
test "$(git -C "$seed" rev-parse refs/heads/main)" = "$base_oid"

git -C "$seed" switch --quiet main
printf 'portable local change\n' > "$seed/portable.txt"
git -C "$seed" switch --quiet feature/switch
test "$(git -C "$seed" branch --show-current)" = "feature/switch"
test "$(cat "$seed/portable.txt")" = "portable local change"
test "$(git -C "$seed" status --porcelain=v1 -- portable.txt)" = " M portable.txt"
git -C "$seed" restore --worktree -- portable.txt
git -C "$seed" switch --quiet main

printf 'local config not committed\n' > "$seed/config.txt"
head_before_rejection="$(git -C "$seed" rev-parse HEAD)"
index_before_rejection="$(git -C "$seed" write-tree)"
worktree_before_rejection="$(git -C "$seed" hash-object -- config.txt)"
if git -C "$seed" switch feature/switch \
  >"$lab_dir/tracked-switch.out" 2>"$lab_dir/tracked-switch.err"; then
  printf 'Expected tracked overwrite protection to reject the switch.\n' >&2
  exit 1
fi
test -s "$lab_dir/tracked-switch.err"
test "$(git -C "$seed" rev-parse HEAD)" = "$head_before_rejection"
test "$(git -C "$seed" write-tree)" = "$index_before_rejection"
test "$(git -C "$seed" hash-object -- config.txt)" = "$worktree_before_rejection"
git -C "$seed" restore --worktree -- config.txt

printf 'untracked obstruction\n' > "$seed/target.txt"
if git -C "$seed" switch feature/switch \
  >"$lab_dir/untracked-switch.out" 2>"$lab_dir/untracked-switch.err"; then
  printf 'Expected untracked overwrite protection to reject the switch.\n' >&2
  exit 1
fi
test -s "$lab_dir/untracked-switch.err"
test "$(git -C "$seed" branch --show-current)" = "main"
test "$(cat "$seed/target.txt")" = "untracked obstruction"
rm -- "$seed/target.txt"

git -C "$seed" switch --quiet --detach "$base_oid"
test -z "$(git -C "$seed" branch --show-current)"
printf 'detached work\n' > "$seed/detached.txt"
git -C "$seed" add detached.txt
git -C "$seed" commit --quiet -m "test: create detached work"
detached_oid="$(git -C "$seed" rev-parse HEAD)"
test "$(git -C "$seed" rev-parse refs/heads/main)" = "$base_oid"
test "$(git -C "$seed" rev-parse refs/heads/feature/switch)" = "$feature_oid"
git -C "$seed" branch recovery/detached "$detached_oid"
git -C "$seed" switch --quiet main
test "$(git -C "$seed" rev-parse refs/heads/recovery/detached)" = "$detached_oid"
git -C "$seed" cat-file -e "$detached_oid^{commit}"

git clone --quiet --bare "$seed" "$server"
git clone --quiet "$server" "$client"
git -C "$client" config user.name "Branch Client"
git -C "$client" config user.email "branch-client@example.invalid"
git -C "$client" switch --quiet --create topic --track origin/feature/switch
test "$(git -C "$client" rev-parse HEAD)" = "$feature_oid"
test "$(git -C "$client" rev-parse '@{upstream}')" = "$feature_oid"
test "$(git -C "$client" config --get branch.topic.remote)" = "origin"
test "$(git -C "$client" config --get branch.topic.merge)" = "refs/heads/feature/switch"

if git -C "$client" worktree add --quiet "$linked" topic \
  >"$lab_dir/occupied-add.out" 2>"$lab_dir/occupied-add.err"; then
  printf 'Expected worktree add to reject an already checked out branch.\n' >&2
  exit 1
fi
test -s "$lab_dir/occupied-add.err"
test ! -e "$linked"

git -C "$client" worktree add --quiet -b linked/topic "$linked" "$feature_oid"
test "$(git -C "$linked" branch --show-current)" = "linked/topic"
test "$(git -C "$linked" rev-parse HEAD)" = "$feature_oid"
test "$(git -C "$client" rev-parse refs/heads/linked/topic)" = "$feature_oid"
if git -C "$client" switch linked/topic \
  >"$lab_dir/occupied-switch.out" 2>"$lab_dir/occupied-switch.err"; then
  printf 'Expected switch to reject a branch checked out in another worktree.\n' >&2
  exit 1
fi
test -s "$lab_dir/occupied-switch.err"
test "$(git -C "$client" branch --show-current)" = "topic"
test -z "$(git -C "$client" status --short)"
test -z "$(git -C "$linked" status --short)"

git -C "$seed" fsck --full --strict >/dev/null
git --git-dir="$server" fsck --full --strict >/dev/null
git -C "$client" fsck --full --strict >/dev/null

printf 'Branch states, switch protection, upstreams, detached recovery, and worktree occupancy passed.\n'
