#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-clone-state.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

source_repo="$lab_dir/source"
server="$lab_dir/server.git"
normal="$lab_dir/normal"
no_checkout="$lab_dir/no-checkout"
bare_clone="$lab_dir/bare.git"
mirror_clone="$lab_dir/mirror.git"
empty_server="$lab_dir/empty.git"
empty_clone="$lab_dir/empty-clone"

git init --quiet --initial-branch=main "$source_repo"
git -C "$source_repo" config user.name "Clone State Lab"
git -C "$source_repo" config user.email "clone-state@example.invalid"
git -C "$source_repo" config clone.privateSetting "must-not-transfer"
mkdir -p "$source_repo/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$source_repo/.git/hooks/pre-commit"
chmod +x "$source_repo/.git/hooks/pre-commit"
printf 'tracked payload\n' > "$source_repo/tracked.txt"
printf 'untracked payload\n' > "$source_repo/untracked.txt"
git -C "$source_repo" add tracked.txt
git -C "$source_repo" commit --quiet --no-verify -m "build: create clone source"
main_oid="$(git -C "$source_repo" rev-parse HEAD)"
main_tree="$(git -C "$source_repo" rev-parse 'HEAD^{tree}')"
git -C "$source_repo" switch --quiet -c topic
printf 'topic payload\n' > "$source_repo/topic.txt"
git -C "$source_repo" add topic.txt
git -C "$source_repo" commit --quiet --no-verify -m "feat: add topic"
topic_oid="$(git -C "$source_repo" rev-parse HEAD)"
git -C "$source_repo" switch --quiet main
git -C "$source_repo" tag -a v1.0.0 -m "Clone state release" "$main_oid"

git clone --quiet --bare "$source_repo" "$server"
git --git-dir="$server" symbolic-ref HEAD refs/heads/main
server_url="file://$server"

git clone --quiet "$server_url" "$normal"
test "$(git -C "$normal" remote get-url origin)" = "$server_url"
test "$(git -C "$normal" config --get-all remote.origin.fetch)" = "+refs/heads/*:refs/remotes/origin/*"
test "$(git -C "$normal" symbolic-ref HEAD)" = "refs/heads/main"
test "$(git -C "$normal" symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main"
test "$(git -C "$normal" rev-parse HEAD)" = "$main_oid"
test "$(git -C "$normal" rev-parse refs/remotes/origin/main)" = "$main_oid"
test "$(git -C "$normal" rev-parse '@{upstream}')" = "$main_oid"
test "$(git -C "$normal" write-tree)" = "$main_tree"
test "$(cat "$normal/tracked.txt")" = "tracked payload"
test ! -e "$normal/untracked.txt"
if git -C "$normal" config --get clone.privateSetting >/dev/null 2>&1; then
  printf 'Source local config must not transfer into a normal clone.\n' >&2
  exit 1
fi
test ! -e "$normal/.git/hooks/pre-commit"
test -z "$(git -C "$normal" status --short)"

git clone --quiet --no-checkout "$server_url" "$no_checkout"
test "$(git -C "$no_checkout" rev-parse HEAD)" = "$main_oid"
test -z "$(git -C "$no_checkout" ls-files --stage)"
test ! -e "$no_checkout/tracked.txt"
test "$(git -C "$no_checkout" status --porcelain=v1 -- tracked.txt)" = "D  tracked.txt"

git clone --quiet --bare "$server_url" "$bare_clone"
test "$(git --git-dir="$bare_clone" rev-parse --is-bare-repository)" = "true"
test "$(git --git-dir="$bare_clone" rev-parse refs/heads/main)" = "$main_oid"
test "$(git --git-dir="$bare_clone" rev-parse refs/heads/topic)" = "$topic_oid"
if git --git-dir="$bare_clone" show-ref --verify --quiet refs/remotes/origin/main; then
  printf 'Bare clone must copy source heads directly, not create origin/main.\n' >&2
  exit 1
fi

git clone --quiet --mirror "$server_url" "$mirror_clone"
test "$(git --git-dir="$mirror_clone" rev-parse --is-bare-repository)" = "true"
test "$(git --git-dir="$mirror_clone" config --get remote.origin.mirror)" = "true"
test "$(git --git-dir="$mirror_clone" config --get-all remote.origin.fetch)" = "+refs/*:refs/*"
test "$(git --git-dir="$mirror_clone" rev-parse refs/heads/main)" = "$main_oid"
test "$(git --git-dir="$mirror_clone" rev-parse 'refs/tags/v1.0.0^{}')" = "$main_oid"

git init --quiet --bare "$empty_server"
git --git-dir="$empty_server" symbolic-ref HEAD refs/heads/trunk
git clone "$empty_server" "$empty_clone" \
  >"$lab_dir/empty-clone.out" 2>"$lab_dir/empty-clone.err"
test "$(git -C "$empty_clone" symbolic-ref HEAD)" = "refs/heads/trunk"
if git -C "$empty_clone" rev-parse --verify 'HEAD^{commit}' >/dev/null 2>&1; then
  printf 'Empty clone must have an unborn HEAD.\n' >&2
  exit 1
fi
test "$(git -C "$empty_clone" remote get-url origin)" = "$empty_server"

git --git-dir="$server" fsck --full --strict >/dev/null
git -C "$normal" fsck --full --strict >/dev/null
git --git-dir="$bare_clone" fsck --full --strict >/dev/null
git --git-dir="$mirror_clone" fsck --full --strict >/dev/null

printf 'Normal, no-checkout, bare, mirror, empty clone, and non-transferred local state passed.\n'
