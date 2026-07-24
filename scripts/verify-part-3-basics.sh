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

git -C "$lab_dir" branch feature/quick-start
test "$(git -C "$lab_dir" branch --show-current)" = "main"
git -C "$lab_dir" switch --quiet feature/quick-start
test "$(git -C "$lab_dir" branch --show-current)" = "feature/quick-start"

printf '# Quick Start\n\n先查看状态，再选择内容并提交。\n' > "$lab_dir/QUICKSTART.md"
git -C "$lab_dir" add QUICKSTART.md
git -C "$lab_dir" commit --quiet -m "docs: add quick start guide"

git -C "$lab_dir" switch --quiet main
git -C "$lab_dir" merge --quiet feature/quick-start
test "$(git -C "$lab_dir" rev-parse main)" = "$(git -C "$lab_dir" rev-parse feature/quick-start)"
test -z "$(git -C "$lab_dir" status --short)"

git -C "$lab_dir" branch -d feature/quick-start >/dev/null
printf 'Part 3 branch and fast-forward experiment passed.\n'
