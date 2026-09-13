#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-tags.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

repo="$lab_dir/repo"
server="$lab_dir/server.git"

git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name "Tag Lab"
git -C "$repo" config user.email "tag-lab@example.invalid"
printf 'version one\n' > "$repo/version.txt"
git -C "$repo" add version.txt
git -C "$repo" commit --quiet -m "release: create first candidate"
first_oid="$(git -C "$repo" rev-parse HEAD)"
printf 'version two\n' > "$repo/version.txt"
git -C "$repo" add version.txt
git -C "$repo" commit --quiet -m "release: create second candidate"
second_oid="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" tag build-check "$first_oid"
git -C "$repo" tag -a v2.0.0 "$second_oid" -m "Release 2.0.0"
annotated_object="$(git -C "$repo" rev-parse 'refs/tags/v2.0.0^{tag}')"
test "$(git -C "$repo" cat-file -t refs/tags/build-check)" = "commit"
test "$(git -C "$repo" cat-file -t refs/tags/v2.0.0)" = "tag"
test "$(git -C "$repo" rev-parse 'refs/tags/build-check^{commit}')" = "$first_oid"
test "$(git -C "$repo" rev-parse 'refs/tags/v2.0.0^{}')" = "$second_oid"
test "$(git -C "$repo" cat-file tag "$annotated_object" | sed -n '1s/^object //p')" = "$second_oid"
git -C "$repo" cat-file tag "$annotated_object" | grep -F 'tag v2.0.0' >/dev/null

git -C "$repo" branch release "$first_oid"
git -C "$repo" tag release "$second_oid"
test "$(git -C "$repo" rev-parse refs/heads/release)" = "$first_oid"
test "$(git -C "$repo" rev-parse refs/tags/release)" = "$second_oid"

git init --quiet --bare "$server"
git --git-dir="$server" symbolic-ref HEAD refs/heads/main
git -C "$repo" remote add origin "file://$server"
git -C "$repo" push --quiet origin refs/heads/main:refs/heads/main
git -C "$repo" push --quiet origin \
  refs/tags/build-check:refs/tags/build-check \
  refs/tags/v2.0.0:refs/tags/v2.0.0
test "$(git --git-dir="$server" rev-parse refs/tags/build-check)" = "$first_oid"
test "$(git --git-dir="$server" rev-parse refs/tags/v2.0.0)" = "$annotated_object"
test "$(git --git-dir="$server" rev-parse 'refs/tags/v2.0.0^{}')" = "$second_oid"

git -C "$repo" tag -f -a v2.0.0 "$first_oid" -m "Incorrect replacement" >/dev/null
moved_object="$(git -C "$repo" rev-parse refs/tags/v2.0.0)"
test "$moved_object" != "$annotated_object"
if git -C "$repo" push --quiet origin \
  refs/tags/v2.0.0:refs/tags/v2.0.0 \
  >"$lab_dir/rejected-tag.out" 2>"$lab_dir/rejected-tag.err"; then
  printf 'Expected remote tag replacement to be rejected.\n' >&2
  exit 1
fi
test -s "$lab_dir/rejected-tag.err"
test "$(git --git-dir="$server" rev-parse refs/tags/v2.0.0)" = "$annotated_object"
git -C "$repo" update-ref refs/tags/v2.0.0 "$annotated_object" "$moved_object"
test "$(git -C "$repo" rev-parse refs/tags/v2.0.0)" = "$annotated_object"

git -C "$repo" tag temporary-checkpoint "$first_oid"
git -C "$repo" push --quiet origin \
  refs/tags/temporary-checkpoint:refs/tags/temporary-checkpoint
test "$(git --git-dir="$server" rev-parse refs/tags/temporary-checkpoint)" = "$first_oid"
git -C "$repo" push --quiet origin :refs/tags/temporary-checkpoint
if git --git-dir="$server" show-ref --verify --quiet refs/tags/temporary-checkpoint; then
  printf 'Expected the temporary remote tag to be deleted.\n' >&2
  exit 1
fi
test "$(git --git-dir="$server" rev-parse refs/heads/main)" = "$second_oid"

git -C "$repo" fsck --full --strict >/dev/null
git --git-dir="$server" fsck --full --strict >/dev/null
test -z "$(git -C "$repo" status --short)"
printf 'Lightweight and annotated tags, peeling, explicit push, collision rejection, and deletion passed.\n'
