#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part2.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

git -C "$lab_dir" init --quiet --initial-branch=main
git -C "$lab_dir" config user.name "Git Blue Book Test"
git -C "$lab_dir" config user.email "git-blue-book@example.invalid"

printf '# Git First Lab\n\n这是我的第一个 Git 练习仓库。\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: add project introduction"

printf '\n这个仓库用于练习 Git 的基本工作流。\n' >> "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: explain repository purpose"

printf '*.log\nbuild/\n.DS_Store\nnotes.txt\n' > "$lab_dir/.gitignore"
printf 'local debug output\n' > "$lab_dir/debug.log"
git -C "$lab_dir" check-ignore --quiet debug.log
git -C "$lab_dir" add .gitignore
git -C "$lab_dir" commit --quiet -m "chore: ignore local generated files"

printf '# Contributing\n\n提交前请检查差异并运行项目测试。\n' > "$lab_dir/CONTRIBUTING.md"
printf '\n贡献说明请查看 CONTRIBUTING.md。\n' >> "$lab_dir/README.md"
printf '个人草稿：后续考虑增加分支练习。\n' > "$lab_dir/notes.txt"

git -C "$lab_dir" add README.md CONTRIBUTING.md
git -C "$lab_dir" commit --quiet -m "docs: add contribution guide"

test -z "$(git -C "$lab_dir" status --short)"
test "$(git -C "$lab_dir" rev-list --count main)" = "4"
test "$(git -C "$lab_dir" log -1 --format=%s)" = "docs: add contribution guide"
test -n "$(git -C "$lab_dir" show --stat --oneline HEAD)"

printf 'Part 2 experiment passed in isolated repository.\n'
