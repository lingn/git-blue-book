#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part2.XXXXXX")"
lab_real="$(cd "$lab_dir" && pwd -P)"
combined_diff="$lab_dir-combined.diff"
attributes_output="$lab_dir-attributes.txt"
worktree_attributes="$lab_dir-worktree-attributes.txt"
index_attributes="$lab_dir-index-attributes.txt"
global_config="$lab_dir-global-config"
conditional_identity="$lab_dir-work-identity.inc"
hook_marker="$lab_dir-hook-marker"
identity_sources="$lab_dir-identity-sources.txt"
history_output="$lab_dir-history.txt"
scope_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-scope.XXXXXX")"
trap 'rm -rf "$lab_dir" "$scope_dir" "$combined_diff" "$attributes_output" "$worktree_attributes" "$index_attributes" "$global_config" "$conditional_identity" "$hook_marker" "$identity_sources"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$global_config"
printf '[includeIf "gitdir:%s/.git"]\n\tpath = %s\n' "$lab_real" "$conditional_identity" > "$global_config"
printf '[user]\n\tname = Included Work Identity\n\temail = included@example.invalid\n' > "$conditional_identity"

if git -C "$lab_dir" rev-parse --show-toplevel >/dev/null 2>&1; then
  printf 'Expected repository discovery to fail before git init.\n' >&2
  exit 1
fi
git -C "$lab_dir" init --quiet --initial-branch=main
test "$(git -C "$lab_dir" rev-parse --show-toplevel)" = "$lab_real"
test "$(git -C "$lab_dir" rev-parse --is-inside-work-tree)" = "true"
test "$(git -C "$lab_dir" symbolic-ref --short HEAD)" = "main"
test "$(git -C "$lab_dir" config user.name)" = "Included Work Identity"
git -C "$lab_dir" var GIT_AUTHOR_IDENT | grep -F 'Included Work Identity <included@example.invalid>' >/dev/null
git -C "$lab_dir" config user.name "Git Blue Book Test"
git -C "$lab_dir" config user.email "git-blue-book@example.invalid"
test "$(git -C "$lab_dir" config --local user.name)" = "Git Blue Book Test"
git -C "$lab_dir" config --show-origin --show-scope --get-regexp '^user\.' > "$identity_sources"
grep -F 'local' "$identity_sources" >/dev/null

mkdir -p "$scope_dir/subdir"
git -C "$scope_dir" init --quiet --initial-branch=main
git -C "$scope_dir" config user.name "Scope Fixture"
git -C "$scope_dir" config user.email "scope@example.invalid"
printf 'scope baseline\n' > "$scope_dir/base.txt"
git -C "$scope_dir" add -- base.txt
git -C "$scope_dir" commit --quiet -m "test: create scope fixture"
printf 'child only\n' > "$scope_dir/subdir/child.txt"
printf 'sibling only\n' > "$scope_dir/sibling.txt"
(cd "$scope_dir/subdir" && git add .)
git -C "$scope_dir" diff --cached --name-only > "$scope_dir/staged-names.txt"
grep -Fx 'subdir/child.txt' "$scope_dir/staged-names.txt" >/dev/null
if grep -Fx 'sibling.txt' "$scope_dir/staged-names.txt" >/dev/null; then
  printf 'git add . from a subdirectory staged a sibling path.\n' >&2
  exit 1
fi
git -C "$scope_dir" restore --staged -- subdir/child.txt
git -C "$scope_dir" status --short --untracked-files=all > "$scope_dir/scope-status.txt"
grep -F '?? subdir/child.txt' "$scope_dir/scope-status.txt" >/dev/null
grep -F '?? sibling.txt' "$scope_dir/scope-status.txt" >/dev/null

printf '# Git First Lab\n\n这是我的第一个 Git 练习仓库。\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: add project introduction"

printf '\n这个仓库用于练习 Git 的基本工作流。\n' >> "$lab_dir/README.md"
test -n "$(git -C "$lab_dir" diff -- README.md)"
test -z "$(git -C "$lab_dir" diff --staged -- README.md)"
git -C "$lab_dir" add README.md
test -z "$(git -C "$lab_dir" diff -- README.md)"
test -n "$(git -C "$lab_dir" diff --staged -- README.md)"

printf '暂存之后的第二处修改。\n' >> "$lab_dir/README.md"
test "$(git -C "$lab_dir" status --short)" = "MM README.md"
test -n "$(git -C "$lab_dir" diff -- README.md)"
test -n "$(git -C "$lab_dir" diff --staged -- README.md)"
git -C "$lab_dir" diff HEAD -- README.md > "$combined_diff"
grep -F '这个仓库用于练习 Git 的基本工作流。' "$combined_diff" >/dev/null
grep -F '暂存之后的第二处修改。' "$combined_diff" >/dev/null

git -C "$lab_dir" restore --staged -- README.md
test "$(git -C "$lab_dir" status --short)" = " M README.md"
test -z "$(git -C "$lab_dir" diff --staged -- README.md)"
grep -F '暂存之后的第二处修改。' "$lab_dir/README.md" >/dev/null

git -C "$lab_dir" add README.md
git -C "$lab_dir" commit --quiet -m "docs: explain repository purpose"

printf 'hook fixture\n' > "$lab_dir/hook.txt"
git -C "$lab_dir" add hook.txt
printf '#!/usr/bin/env bash\nprintf "hook ran\\n" > "%s"\nexit 1\n' "$hook_marker" > "$lab_dir/.git/hooks/pre-commit"
chmod +x "$lab_dir/.git/hooks/pre-commit"
head_before_hook="$(git -C "$lab_dir" rev-parse HEAD)"
if git -C "$lab_dir" commit --quiet -m "test: rejected by local hook"; then
  printf 'Expected the local pre-commit hook to reject the commit.\n' >&2
  exit 1
fi
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$head_before_hook"
test -n "$(git -C "$lab_dir" diff --staged -- hook.txt)"
test -s "$hook_marker"
rm "$lab_dir/.git/hooks/pre-commit"
git -C "$lab_dir" commit --quiet -m "test: recover after hook rejection"

head_before_empty="$(git -C "$lab_dir" rev-parse HEAD)"
if git -C "$lab_dir" commit --quiet -m "test: reject empty commit"; then
  printf 'Expected a no-op commit to be rejected without --allow-empty.\n' >&2
  exit 1
fi
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$head_before_empty"
git -C "$lab_dir" commit --quiet --allow-empty -m "ci: record lab marker"

printf '*.log\nbuild/\n.DS_Store\nnotes.txt\n' > "$lab_dir/.gitignore"
printf 'local debug output\n' > "$lab_dir/debug.log"
git -C "$lab_dir" check-ignore --quiet debug.log
git -C "$lab_dir" add .gitignore
git -C "$lab_dir" commit --quiet -m "chore: ignore local generated files"

printf 'tracked log entry\n' > "$lab_dir/tracked.log"
git -C "$lab_dir" add --force -- tracked.log
git -C "$lab_dir" commit --quiet -m "test: track a log fixture"
printf 'tracked change remains visible\n' >> "$lab_dir/tracked.log"
grep -F ' M tracked.log' <(git -C "$lab_dir" status --short) >/dev/null
git -C "$lab_dir" restore --worktree -- tracked.log
test -z "$(git -C "$lab_dir" status --short)"

printf '*.md text eol=lf\n*.txt text eol=lf\n*.generated filter=lab\n' > "$lab_dir/.gitattributes"
git -C "$lab_dir" add .gitattributes
git -C "$lab_dir" commit --quiet -m "chore: define text attributes"
git -C "$lab_dir" check-attr text eol -- README.md > "$attributes_output"
grep -F 'README.md: text: set' "$attributes_output" >/dev/null
grep -F 'README.md: eol: lf' "$attributes_output" >/dev/null

printf '*.md text eol=crlf\n*.txt text eol=lf\n*.generated filter=lab\n' > "$lab_dir/.gitattributes"
git -C "$lab_dir" check-attr text eol -- README.md > "$worktree_attributes"
git -C "$lab_dir" check-attr --cached text eol -- README.md > "$index_attributes"
grep -F 'README.md: eol: crlf' "$worktree_attributes" >/dev/null
grep -F 'README.md: eol: lf' "$index_attributes" >/dev/null
git -C "$lab_dir" restore --worktree -- .gitattributes

printf '# Contributing\n\n提交前请检查差异并运行项目测试。\n' > "$lab_dir/CONTRIBUTING.md"
printf '\n贡献说明请查看 CONTRIBUTING.md。\n' >> "$lab_dir/README.md"
printf '个人草稿：后续考虑增加分支练习。\n' > "$lab_dir/notes.txt"

git -C "$lab_dir" add -- README.md CONTRIBUTING.md
git -C "$lab_dir" diff --staged --check
git -C "$lab_dir" commit --quiet -m "docs: add contribution guide"

test -z "$(git -C "$lab_dir" status --short)"
test "$(git -C "$lab_dir" rev-list --count main)" = "8"
test "$(git -C "$lab_dir" log -1 --format=%s)" = "docs: add contribution guide"
test -n "$(git -C "$lab_dir" show --stat --oneline HEAD)"
git -C "$lab_dir" log --format='%H %s' --all > "$history_output"
test "$(wc -l < "$history_output" | tr -d ' ')" = "8"
test "$(git -C "$lab_dir" log --format=%s HEAD~1..HEAD)" = "docs: add contribution guide"
test -z "$(git -C "$lab_dir" log --all --oneline -- notes.txt)"
test -n "$(git -C "$lab_dir" log --all --oneline -- .gitignore)"
git -C "$lab_dir" diff --check

printf 'Part 2 identity scope, worktree/index/HEAD state matrix, commit failures, ignore rules, attributes, and recovery experiment passed.\n'
