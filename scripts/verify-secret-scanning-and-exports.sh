#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-secret-export.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

marker='EXAMPLE-SECRET-SCAN-DO-NOT-USE-9b71c4'
repo="$lab_root/repository"
mkdir -p "$repo"

git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Secret Scan Fixture'
git -C "$repo" config user.email 'secret-scan@example.invalid'

printf 'safe source content\n' > "$repo/source.txt"
mkdir -p "$repo/history" "$repo/private"
printf 'old fixture token=%s\n' "$marker" > "$repo/history/$marker.txt"
printf 'private fixture token=%s\n' "$marker" > "$repo/private/old.env"
git -C "$repo" add source.txt history private
git -C "$repo" commit --quiet -m "fixture: old commit includes $marker"
old_commit="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" branch archive "$old_commit"
git -C "$repo" tag -a release-leaked -m "fixture tag includes $marker" "$old_commit"
git -C "$repo" notes add -m "fixture note includes $marker" "$old_commit"

git -C "$repo" rm --quiet -r -- history private/old.env
mkdir -p "$repo/private"
printf 'current fixture token=%s\n' "$marker" > "$repo/private/current.env"
printf 'private/ export-ignore\n' > "$repo/.gitattributes"
printf 'link target is outside the export root\n' > "$lab_root/outside.txt"
ln -s ../outside.txt "$repo/link-outside"
printf '%02048d\n' 0 > "$repo/large.bin"
git -C "$repo" add .gitattributes private/current.env link-outside large.bin
git -C "$repo" commit --quiet -m 'fixture: current tree has ignored content and unusual objects'
current_commit="$(git -C "$repo" rev-parse HEAD)"

GIT_REFLOG_ACTION="fixture: $marker" \
  git -C "$repo" update-ref refs/heads/reflog-fixture "$current_commit"

mkdir -p "$lab_root/ci-artifact" "$lab_root/lfs-cache"
printf 'CI log accidentally printed %s\n' "$marker" > "$lab_root/ci-artifact/build.log"
printf 'LFS payload fixture %s\n' "$marker" > "$lab_root/lfs-cache/payload.bin"

current_tree_paths="$lab_root/current-tree.paths"
git -C "$repo" ls-tree -r --name-only "$current_commit" > "$current_tree_paths"
if grep -F "$marker" "$current_tree_paths" >/dev/null 2>&1; then
  printf 'Expected the old marker filename to be absent from the current tree.\n' >&2
  exit 1
fi
if ! git -C "$repo" grep -q -F "$marker" "$current_commit" --; then
  printf 'Expected the current ignored file to contain the synthetic marker.\n' >&2
  exit 1
fi

if ! git -C "$repo" log --all --format='%B' | grep -F "$marker" >/dev/null; then
  printf 'Expected the synthetic marker in reachable commit or tag messages.\n' >&2
  exit 1
fi
if ! git -C "$repo" notes show "$old_commit" | grep -F "$marker" >/dev/null; then
  printf 'Expected the synthetic marker in a notes ref.\n' >&2
  exit 1
fi
if ! git -C "$repo" cat-file tag release-leaked | grep -F "$marker" >/dev/null; then
  printf 'Expected the synthetic marker in the annotated tag message.\n' >&2
  exit 1
fi
if ! git -C "$repo" reflog --all | grep -F "$marker" >/dev/null; then
  printf 'Expected the synthetic marker in a reflog message.\n' >&2
  exit 1
fi
if ! grep -F "$marker" "$lab_root/ci-artifact/build.log" "$lab_root/lfs-cache/payload.bin" \
  >/dev/null; then
  printf 'Expected the synthetic marker in external copies.\n' >&2
  exit 1
fi

git -C "$repo" fsck --full --no-progress > "$lab_root/fsck.out" 2>&1
tree_snapshot="$lab_root/tree.snapshot"
git -C "$repo" ls-tree -r -z --full-tree "$current_commit" > "$tree_snapshot"
if ! git -C "$repo" ls-tree -r --full-tree "$current_commit" |
  grep -E '^120000 .*link-outside$' >/dev/null; then
  printf 'Expected a symlink entry in the current tree.\n' >&2
  exit 1
fi
objects_snapshot="$lab_root/objects.snapshot"
git -C "$repo" cat-file --batch-all-objects \
  --batch-check='%(objectname) %(objecttype) %(objectsize)' > "$objects_snapshot"
if ! awk '$2 == "blob" && $3 >= 2048 {found = 1} END {exit(found ? 0 : 1)}' \
  "$objects_snapshot"; then
  printf 'Expected an unusually large blob in the object snapshot.\n' >&2
  exit 1
fi

archive_root="$lab_root/archives"
mkdir "$archive_root"
default_archive="$archive_root/default.tar"
git -C "$repo" archive --format=tar --output="$default_archive" "$current_commit"
tar -tf "$default_archive" > "$archive_root/default.paths"
if grep -F 'private/current.env' "$archive_root/default.paths" >/dev/null; then
  printf 'Expected export-ignore to omit private/current.env.\n' >&2
  exit 1
fi
if ! grep -F 'source.txt' "$archive_root/default.paths" >/dev/null; then
  printf 'Expected source.txt in the default archive.\n' >&2
  exit 1
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$archive_root/default.paths"; then
  printf 'Archive contained an unsafe traversal path.\n' >&2
  exit 1
fi

printf 'source.txt export-ignore\nprivate/ export-ignore\n' > "$repo/.gitattributes"
worktree_archive="$archive_root/worktree-attributes.tar"
git -C "$repo" archive --worktree-attributes \
  --format=tar --output="$worktree_archive" "$current_commit"
tar -tf "$worktree_archive" > "$archive_root/worktree.paths"
if grep -F 'source.txt' "$archive_root/worktree.paths" >/dev/null; then
  printf 'Expected worktree attributes to omit source.txt.\n' >&2
  exit 1
fi
git -C "$repo" restore -- .gitattributes

printf '# no export rule in this temporary worktree\n' > "$repo/.gitattributes"
bad_archive="$archive_root/bad.tar"
git -C "$repo" archive --worktree-attributes \
  --format=tar --output="$bad_archive" "$current_commit"
if ! tar -xOf "$bad_archive" private/current.env | grep -F "$marker" >/dev/null; then
  printf 'Expected the intentionally bad archive to contain the marker.\n' >&2
  exit 1
fi
git -C "$repo" restore -- .gitattributes
clean_archive="$archive_root/clean-regenerated.tar"
git -C "$repo" archive --format=tar --output="$clean_archive" "$current_commit"
if tar -tf "$clean_archive" | grep -F 'private/current.env' >/dev/null; then
  printf 'Expected the regenerated archive to omit private/current.env.\n' >&2
  exit 1
fi
if tar -tf "$clean_archive" | grep -F "$marker" >/dev/null; then
  printf 'Expected the regenerated archive paths to omit the marker.\n' >&2
  exit 1
fi

bundle_path="$lab_root/repository.bundle"
git -C "$repo" bundle create "$bundle_path" --all >/dev/null
git -C "$repo" bundle verify "$bundle_path" >/dev/null 2>&1
bundle_clone="$lab_root/bundle-clone"
git -c init.defaultBranch=main clone --quiet "$bundle_path" "$bundle_clone"
if ! git -C "$bundle_clone" grep -q -F "$marker" "$old_commit" --; then
  printf 'Expected a bundle clone to retain the old reachable history.\n' >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$clean_archive" > "$archive_root/clean.sha256"
else
  sha256sum "$clean_archive" > "$archive_root/clean.sha256"
fi
test -s "$archive_root/default.paths"
test -s "$archive_root/clean.sha256"

printf 'Secret scan scope, fsck limits, export-ignore, archive regeneration, and bundle boundaries passed.\n'
