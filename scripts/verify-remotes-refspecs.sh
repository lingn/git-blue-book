#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-remotes-refspecs.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

seed="$lab_dir/seed"
fetch_server="$lab_dir/fetch.git"
push_server="$lab_dir/push.git"
client="$lab_dir/client"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "Refspec Seed"
git -C "$seed" config user.email "refspec-seed@example.invalid"
printf 'main\n' > "$seed/main.txt"
git -C "$seed" add main.txt
git -C "$seed" commit --quiet -m "build: create refspec seed"
main_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" switch --quiet -c release/1.x
printf 'release\n' > "$seed/release.txt"
git -C "$seed" add release.txt
git -C "$seed" commit --quiet -m "release: add maintenance"
release_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" switch --quiet -c wip/private main
printf 'private\n' > "$seed/private.txt"
git -C "$seed" add private.txt
git -C "$seed" commit --quiet -m "test: add excluded work"
wip_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" switch --quiet main

git clone --quiet --bare "$seed" "$fetch_server"
git clone --quiet --bare "$seed" "$push_server"
fetch_url="file://$fetch_server"
push_url="file://$push_server"

git init --quiet --initial-branch=main "$client"
git -C "$client" remote add origin "$fetch_url"
test "$(git -C "$client" remote get-url origin)" = "$fetch_url"
test -z "$(git -C "$client" for-each-ref refs/remotes/origin/)"
git -C "$client" remote set-url --push origin "$push_url"
test "$(git -C "$client" remote get-url --push origin)" = "$push_url"
test "$(git -C "$client" remote get-url origin)" = "$fetch_url"

git -C "$client" config --unset-all remote.origin.fetch
git -C "$client" config --add remote.origin.fetch \
  '+refs/heads/*:refs/remotes/origin/*'
git -C "$client" config --add remote.origin.fetch '^refs/heads/wip/*'
git -C "$client" fetch --quiet origin
test "$(git -C "$client" rev-parse refs/remotes/origin/main)" = "$main_oid"
test "$(git -C "$client" rev-parse refs/remotes/origin/release/1.x)" = "$release_oid"
if git -C "$client" show-ref --verify --quiet refs/remotes/origin/wip/private; then
  printf 'Negative refspec must exclude origin/wip/private.\n' >&2
  exit 1
fi
if git -C "$client" cat-file -e "$wip_oid" 2>/dev/null; then
  printf 'The excluded branch-only object must not be fetched.\n' >&2
  exit 1
fi

git -C "$client" config user.name "Refspec Client"
git -C "$client" config user.email "refspec-client@example.invalid"
git -C "$client" switch --quiet -c local-main refs/remotes/origin/main
printf 'review\n' > "$client/review.txt"
git -C "$client" add review.txt
git -C "$client" commit --quiet -m "docs: add review branch"
review_oid="$(git -C "$client" rev-parse HEAD)"
git -C "$client" push --quiet origin \
  HEAD:refs/heads/review/refspec
test "$(git --git-dir="$push_server" rev-parse refs/heads/review/refspec)" = "$review_oid"
if git --git-dir="$fetch_server" show-ref --verify --quiet refs/heads/review/refspec; then
  printf 'PushURL must isolate writes from the fetch server.\n' >&2
  exit 1
fi

git -C "$client" remote rename origin upstream \
  >"$lab_dir/remote-rename.out" 2>"$lab_dir/remote-rename.err"
test "$(git -C "$client" remote)" = "upstream"
test "$(git -C "$client" remote get-url upstream)" = "$fetch_url"
test "$(git -C "$client" remote get-url --push upstream)" = "$push_url"
test "$(git -C "$client" rev-parse refs/remotes/upstream/main)" = "$main_oid"
test "$(git -C "$client" config --get branch.local-main.remote)" = "upstream"
test "$(git -C "$client" config --get branch.local-main.merge)" = "refs/heads/main"
if git -C "$client" show-ref --verify --quiet refs/remotes/origin/main; then
  printf 'Remote rename must move the tracking namespace.\n' >&2
  exit 1
fi
test -s "$lab_dir/remote-rename.err"

local_main_oid="$(git -C "$client" rev-parse refs/heads/local-main)"
git -C "$client" remote remove upstream
test -z "$(git -C "$client" remote)"
if git -C "$client" for-each-ref refs/remotes/upstream/ | grep -q .; then
  printf 'Remote remove must delete associated tracking refs.\n' >&2
  exit 1
fi
test "$(git -C "$client" rev-parse refs/heads/local-main)" = "$local_main_oid"
test "$(git --git-dir="$fetch_server" rev-parse refs/heads/main)" = "$main_oid"
test "$(git --git-dir="$push_server" rev-parse refs/heads/review/refspec)" = "$review_oid"

git --git-dir="$fetch_server" fsck --full --strict >/dev/null
git --git-dir="$push_server" fsck --full --strict >/dev/null
git -C "$client" fsck --full --strict >/dev/null
test -z "$(git -C "$client" status --short)"

printf 'Remote URLs, pushURL isolation, positive/negative refspecs, rename, and remove boundaries passed.\n'
