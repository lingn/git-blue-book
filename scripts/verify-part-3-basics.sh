#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part3.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

git -C "$lab_dir" init --quiet --initial-branch=main
git -C "$lab_dir" config user.name "Git Blue Book Test"
git -C "$lab_dir" config user.email "git-blue-book@example.invalid"

printf '# Branch Lab\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: initialize branch lab"
root_commit="$(git -C "$lab_dir" rev-parse HEAD)"
test "$(git -C "$lab_dir" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = "1"
test "$(git -C "$lab_dir" rev-parse HEAD^{tree})" = "$(git -C "$lab_dir" show -s --format=%T HEAD)"

git -C "$lab_dir" branch feature/quick-start
test "$(git -C "$lab_dir" branch --show-current)" = "main"
test "$(git -C "$lab_dir" rev-parse refs/heads/feature/quick-start)" = "$root_commit"
git -C "$lab_dir" switch --quiet feature/quick-start
test "$(git -C "$lab_dir" branch --show-current)" = "feature/quick-start"
test "$(git -C "$lab_dir" symbolic-ref --short HEAD)" = "feature/quick-start"

printf '# Quick Start\n\n先查看状态，再选择内容并提交。\n' > "$lab_dir/QUICKSTART.md"
git -C "$lab_dir" add QUICKSTART.md
git -C "$lab_dir" commit --quiet -m "docs: add quick start guide"
feature_tip="$(git -C "$lab_dir" rev-parse HEAD)"
if git -C "$lab_dir" merge-base --is-ancestor "$feature_tip" "$root_commit"; then
  printf 'Expected the feature tip not to be an ancestor of the root commit.\n' >&2
  exit 1
fi

git -C "$lab_dir" switch --quiet --detach "$root_commit"
test -z "$(git -C "$lab_dir" branch --show-current)"
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$root_commit"
if git -C "$lab_dir" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  printf 'Expected detached HEAD to have no symbolic branch.\n' >&2
  exit 1
fi
git -C "$lab_dir" switch --quiet main

git -C "$lab_dir" merge --quiet feature/quick-start
test "$(git -C "$lab_dir" rev-parse main)" = "$(git -C "$lab_dir" rev-parse feature/quick-start)"
test "$(git -C "$lab_dir" rev-list --parents -n 1 main | wc -w | tr -d ' ')" = "2"
test -z "$(git -C "$lab_dir" status --short)"

git -C "$lab_dir" branch -d feature/quick-start >/dev/null
printf 'Part 3 branch and fast-forward experiment passed.\n'
