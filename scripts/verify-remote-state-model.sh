#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-remote-state.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

seed="$lab_dir/seed"
server="$lab_dir/server.git"
alice="$lab_dir/alice"
bob="$lab_dir/bob"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "Remote State Seed"
git -C "$seed" config user.email "remote-state@example.invalid"
printf 'state one\n' > "$seed/state.txt"
git -C "$seed" add state.txt
git -C "$seed" commit --quiet -m "build: create remote baseline"
baseline_oid="$(git -C "$seed" rev-parse HEAD)"

git clone --quiet --bare "$seed" "$server"
git --git-dir="$server" symbolic-ref HEAD refs/heads/main
server_url="file://$server"
git clone --quiet "$server_url" "$alice"
git clone --quiet "$server_url" "$bob"
git -C "$alice" config user.name "Alice"
git -C "$alice" config user.email "alice@example.invalid"
git -C "$bob" config user.name "Bob"
git -C "$bob" config user.email "bob@example.invalid"

test "$(git -C "$bob" rev-parse refs/heads/main)" = "$baseline_oid"
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$baseline_oid"
test "$(git -C "$bob" rev-parse '@{upstream}')" = "$baseline_oid"
test "$(git -C "$bob" config --get branch.main.remote)" = "origin"
test "$(git -C "$bob" config --get branch.main.merge)" = "refs/heads/main"
test "$(git -C "$bob" symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main"

printf 'state two\n' > "$alice/state.txt"
git -C "$alice" add state.txt
git -C "$alice" commit --quiet -m "feat: advance server state"
server_new_oid="$(git -C "$alice" rev-parse HEAD)"
git -C "$alice" push --quiet origin refs/heads/main:refs/heads/main
test "$(git --git-dir="$server" rev-parse refs/heads/main)" = "$server_new_oid"
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$baseline_oid"
test "$(git -C "$bob" rev-parse refs/heads/main)" = "$baseline_oid"

bob_tracking_before="$(git -C "$bob" rev-parse refs/remotes/origin/main)"
bob_main_before="$(git -C "$bob" rev-parse refs/heads/main)"
fetch_head_path="$(git -C "$bob" rev-parse --path-format=absolute --git-path FETCH_HEAD)"
test ! -e "$fetch_head_path"
remote_main_line="$(git -C "$bob" ls-remote origin refs/heads/main)"
test "$(printf '%s\n' "$remote_main_line" | awk '{print $1}')" = "$server_new_oid"
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$bob_tracking_before"
test "$(git -C "$bob" rev-parse refs/heads/main)" = "$bob_main_before"
test ! -e "$fetch_head_path"

git -C "$bob" fetch --quiet origin
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$server_new_oid"
test "$(git -C "$bob" rev-parse refs/heads/main)" = "$baseline_oid"
test "$(git -C "$bob" rev-list --left-right --count main...origin/main)" = $'0\t1'
grep -F "$server_new_oid" "$fetch_head_path" >/dev/null
test "$(git -C "$bob" rev-parse '@{upstream}')" = "$server_new_oid"

git --git-dir="$server" update-ref refs/heads/stable "$server_new_oid"
git --git-dir="$server" symbolic-ref HEAD refs/heads/stable
test "$(git -C "$bob" symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main"
symref_response="$(git -C "$bob" ls-remote --symref origin HEAD)"
printf '%s\n' "$symref_response" | grep -F $'ref: refs/heads/stable\tHEAD' >/dev/null
test "$(git -C "$bob" symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main"
if git -C "$bob" show-ref --verify --quiet refs/remotes/origin/stable; then
  printf 'ls-remote must not create origin/stable.\n' >&2
  exit 1
fi
git -C "$bob" fetch --quiet origin
test "$(git -C "$bob" rev-parse refs/remotes/origin/stable)" = "$server_new_oid"
git -C "$bob" remote set-head origin --auto >/dev/null
test "$(git -C "$bob" symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/stable"
test "$(git -C "$bob" rev-parse refs/heads/main)" = "$baseline_oid"

git -C "$seed" fsck --full --strict >/dev/null
git --git-dir="$server" fsck --full --strict >/dev/null
git -C "$alice" fsck --full --strict >/dev/null
git -C "$bob" fsck --full --strict >/dev/null
test -z "$(git -C "$alice" status --short)"
test -z "$(git -C "$bob" status --short)"

printf 'Server refs, ls-remote observations, tracking refs, upstreams, FETCH_HEAD, and local branches passed.\n'
