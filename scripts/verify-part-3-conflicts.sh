#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part3-conflict.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

git -C "$lab_dir" init --quiet --initial-branch=main
git -C "$lab_dir" config user.name "Git Blue Book Test"
git -C "$lab_dir" config user.email "git-blue-book@example.invalid"

printf '# Git Practice Lab\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: initialize lab"

git -C "$lab_dir" switch --quiet -c feature/navigation
printf '# Navigation\n' > "$lab_dir/NAVIGATION.md"
git -C "$lab_dir" add NAVIGATION.md
git -C "$lab_dir" commit --quiet -m "docs: add navigation guide"

git -C "$lab_dir" switch --quiet main
printf '\nVersion notes live here.\n' >> "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: add version note"
git -C "$lab_dir" merge --quiet --no-edit feature/navigation
test "$(git -C "$lab_dir" show -s --format=%P HEAD | wc -w | tr -d ' ')" = "2"
git -C "$lab_dir" branch -d feature/navigation >/dev/null

git -C "$lab_dir" switch --quiet -c feature/title
sed -i.bak '1s/.*/# Git Quick Start Lab/' "$lab_dir/README.md"
rm "$lab_dir/README.md.bak"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: rename guide for quick start"

git -C "$lab_dir" switch --quiet main
sed -i.bak '1s/.*/# Git Practice Handbook/' "$lab_dir/README.md"
rm "$lab_dir/README.md.bak"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: rename guide as handbook"

if git -C "$lab_dir" merge --quiet feature/title >/dev/null 2>&1; then
  printf 'Expected a merge conflict, but merge succeeded.\n' >&2
  exit 1
fi
test "$(git -C "$lab_dir" status --short README.md)" = "UU README.md"
git -C "$lab_dir" merge --abort
test -z "$(git -C "$lab_dir" status --short)"

if git -C "$lab_dir" merge --quiet feature/title >/dev/null 2>&1; then
  printf 'Expected the second merge conflict, but merge succeeded.\n' >&2
  exit 1
fi
sed -i.bak '1,5c\
# Git Quick Start Practice' "$lab_dir/README.md"
rm "$lab_dir/README.md.bak"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "merge: reconcile guide title"

test -z "$(git -C "$lab_dir" status --short)"
if git -C "$lab_dir" grep -n -e '<<<<<<<' -e '>>>>>>>' >/dev/null; then
  printf 'Conflict markers remain after resolution.\n' >&2
  exit 1
fi

git -C "$lab_dir" tag -a v0.1.0 -m "First Git workflow lab release"
test "$(git -C "$lab_dir" cat-file -t v0.1.0)" = "tag"
test "$(git -C "$lab_dir" rev-list -n 1 v0.1.0)" = "$(git -C "$lab_dir" rev-parse HEAD)"

printf 'Part 3 divergence, conflict, abort, resolution, and tag experiments passed.\n'
