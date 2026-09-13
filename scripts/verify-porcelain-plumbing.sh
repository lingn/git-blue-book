#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-plumbing.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

repo="$lab_dir/repo"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name "Plumbing Lab"
git -C "$repo" config user.email "plumbing@example.invalid"

printf 'hello from plumbing\n' > "$repo/payload.txt"
blob_oid="$(git -C "$repo" hash-object -w -- payload.txt)"
test "$(git -C "$repo" cat-file -t "$blob_oid")" = "blob"
test "$(git -C "$repo" cat-file -s "$blob_oid")" = "20"
test -z "$(git -C "$repo" ls-files --stage)"
if git -C "$repo" show-ref --verify --quiet refs/heads/main; then
  printf 'Plumbing object writes must not create the unborn branch.\n' >&2
  exit 1
fi

tree_oid="$(
  printf '100644 blob %s\tREADME.md\n' "$blob_oid" |
    git -C "$repo" mktree
)"
test "$(git -C "$repo" cat-file -t "$tree_oid")" = "tree"
test "$(git -C "$repo" ls-tree "$tree_oid" | awk '{print $1}')" = "100644"
test "$(git -C "$repo" ls-tree "$tree_oid" | awk '{print $3}')" = "$blob_oid"
test "$(git -C "$repo" ls-tree "$tree_oid" | cut -f2-)" = "README.md"

root_commit="$(printf 'plumbing root\n' | git -C "$repo" commit-tree "$tree_oid")"
test "$(git -C "$repo" cat-file -t "$root_commit")" = "commit"
test "$(git -C "$repo" rev-parse "$root_commit^{tree}")" = "$tree_oid"
test "$(git -C "$repo" rev-list --parents --max-count=1 "$root_commit" | wc -w | tr -d '[:space:]')" = "1"
if git -C "$repo" rev-list --all | grep -Fx "$root_commit" >/dev/null; then
  printf 'An unreferenced commit unexpectedly appeared in --all.\n' >&2
  exit 1
fi

git -C "$repo" update-ref -m "import: publish verified root" \
  refs/heads/main "$root_commit" ""
test "$(git -C "$repo" rev-parse 'refs/heads/main^{commit}')" = "$root_commit"
git -C "$repo" rev-list --all | grep -Fx "$root_commit" >/dev/null
test "$(git -C "$repo" status --porcelain=v1 -- README.md)" = "D  README.md"
test -z "$(git -C "$repo" ls-files --stage)"

git -C "$repo" reset --quiet --hard HEAD
test "$(git -C "$repo" show :README.md)" = "hello from plumbing"
test "$(git -C "$repo" ls-files --stage -- README.md | awk '{print $2}')" = "$blob_oid"
test "$(git -C "$repo" status --porcelain=v1 -- README.md)" = ""
test "$(git -C "$repo" status --porcelain=v1 -- payload.txt)" = "?? payload.txt"

printf 'porcelain successor\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit --quiet -m "docs: add porcelain successor"
successor="$(git -C "$repo" rev-parse HEAD)"
successor_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
test "$(git -C "$repo" rev-parse HEAD^)" = "$root_commit"
test "$successor" != "$root_commit"
test "$successor_tree" != "$tree_oid"
test "$(git -C "$repo" write-tree)" = "$successor_tree"
test "$(git -C "$repo" ls-files --stage -- README.md | awk '{print $3}')" = "0"

missing_oid="0000000000000000000000000000000000000001"
if printf '100644 blob %s\tmissing.txt\n' "$missing_oid" |
  git -C "$repo" mktree >"$lab_dir/missing-tree.out" 2>"$lab_dir/missing-tree.err"; then
  printf 'Expected mktree to reject an unavailable object.\n' >&2
  exit 1
fi
test -s "$lab_dir/missing-tree.err"

printf '%s\n%s\nmissing-name\n' "$successor" "$successor_tree" |
  git -C "$repo" cat-file \
    --batch-check='%(objectname) %(objecttype) %(objectsize)' \
    > "$lab_dir/batch-check.txt"
test "$(sed -n '1p' "$lab_dir/batch-check.txt" | awk '{print $1" "$2}')" = "$successor commit"
test "$(sed -n '2p' "$lab_dir/batch-check.txt" | awk '{print $1" "$2}')" = "$successor_tree tree"
test "$(sed -n '3p' "$lab_dir/batch-check.txt")" = "missing-name missing"

if git -C "$repo" update-ref -m "import: stale overwrite" \
  refs/heads/main "$root_commit" "$root_commit" \
  2>"$lab_dir/stale-update.err"; then
  printf 'Expected stale expected-old update to fail.\n' >&2
  exit 1
fi
test -s "$lab_dir/stale-update.err"
test "$(git -C "$repo" rev-parse refs/heads/main)" = "$successor"

git -C "$repo" fsck --full --strict >/dev/null
test "$(git -C "$repo" status --porcelain=v1 -- README.md)" = ""
test "$(git -C "$repo" status --porcelain=v1 -- payload.txt)" = "?? payload.txt"

printf 'Porcelain orchestration, plumbing object construction, batch reads, and conditional refs passed.\n'
