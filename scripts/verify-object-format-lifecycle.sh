#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-object-format.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

sha1_repo="$lab_dir/sha1"
sha256_repo="$lab_dir/sha256"

digest_sha1() {
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum | awk '{print $1}'
  else
    shasum -a 1 | awk '{print $1}'
  fi
}

digest_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

git init --quiet --initial-branch=main --object-format=sha1 "$sha1_repo"
if ! git init --quiet --initial-branch=main --object-format=sha256 "$sha256_repo"; then
  printf 'This Git build does not support SHA-256 repositories.\n' >&2
  exit 1
fi

for repo in "$sha1_repo" "$sha256_repo"; do
  git -C "$repo" config user.name "Object Format Lab"
  git -C "$repo" config user.email "object-format@example.invalid"
  printf 'same payload\n' > "$repo/payload.txt"
done

test "$(git -C "$sha1_repo" rev-parse --show-object-format)" = "sha1"
test "$(git -C "$sha256_repo" rev-parse --show-object-format)" = "sha256"

sha1_blob="$(git -C "$sha1_repo" hash-object -w payload.txt)"
sha256_blob="$(git -C "$sha256_repo" hash-object -w payload.txt)"
test "${#sha1_blob}" = "40"
test "${#sha256_blob}" = "64"
test "$sha1_blob" != "$sha256_blob"

payload_size="$(wc -c < "$sha1_repo/payload.txt" | tr -d '[:space:]')"
expected_sha1="$({ printf 'blob %s\0' "$payload_size"; cat "$sha1_repo/payload.txt"; } | digest_sha1)"
expected_sha256="$({ printf 'blob %s\0' "$payload_size"; cat "$sha1_repo/payload.txt"; } | digest_sha256)"
test "$sha1_blob" = "$expected_sha1"
test "$sha256_blob" = "$expected_sha256"

git -C "$sha1_repo" cat-file blob "$sha1_blob" > "$lab_dir/sha1.payload"
git -C "$sha256_repo" cat-file blob "$sha256_blob" > "$lab_dir/sha256.payload"
cmp "$lab_dir/sha1.payload" "$lab_dir/sha256.payload"

git -C "$sha1_repo" add payload.txt
git -C "$sha1_repo" commit --quiet -m "docs: add payload"
commit_before="$(git -C "$sha1_repo" rev-parse HEAD)"
tree_before="$(git -C "$sha1_repo" rev-parse 'HEAD^{tree}')"
blob_before="$(git -C "$sha1_repo" rev-parse 'HEAD:payload.txt')"

git -C "$sha1_repo" repack -ad
test "$(git -C "$sha1_repo" rev-parse HEAD)" = "$commit_before"
test "$(git -C "$sha1_repo" rev-parse 'HEAD^{tree}')" = "$tree_before"
test "$(git -C "$sha1_repo" rev-parse 'HEAD:payload.txt')" = "$blob_before"
test "$(git -C "$sha1_repo" cat-file -t "$commit_before")" = "commit"
test "$(git -C "$sha1_repo" cat-file -t "$tree_before")" = "tree"
test "$(git -C "$sha1_repo" cat-file -t "$blob_before")" = "blob"

printf 'unreachable payload\n' > "$lab_dir/unreachable.txt"
unreachable_blob="$(git -C "$sha1_repo" hash-object -w "$lab_dir/unreachable.txt")"
test "$(git -C "$sha1_repo" cat-file -t "$unreachable_blob")" = "blob"
git -C "$sha1_repo" fsck --no-reflogs --unreachable 2>&1 |
  grep -F "unreachable blob $unreachable_blob" >/dev/null

git -C "$sha1_repo" prune --expire=now
if git -C "$sha1_repo" cat-file -e "$unreachable_blob" 2>/dev/null; then
  printf 'Expected the unreachable experimental blob to be pruned.\n' >&2
  exit 1
fi

test "$(git -C "$sha1_repo" rev-parse HEAD)" = "$commit_before"
git -C "$sha1_repo" fsck --full --strict >/dev/null
test -z "$(git -C "$sha1_repo" status --short)"

printf 'Object formats, repack identity, unreachable detection, and prune boundary passed.\n'
