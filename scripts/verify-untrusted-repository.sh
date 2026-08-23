#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-untrusted.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

ownership_repo="$lab_root/ownership-repository"
git init --quiet --initial-branch=main "$ownership_repo"
git -C "$ownership_repo" config safe.directory '*'

if GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$ownership_repo" status --short \
  >/dev/null 2>"$lab_root/ownership-rejection"; then
  printf 'Expected ownership protection to ignore repository-local safe.directory.\n' >&2
  exit 1
fi
grep -q 'safe.directory' "$lab_root/ownership-rejection"

git config --global --add safe.directory "$ownership_repo"
GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$ownership_repo" status --short >/dev/null
git config --global --fixed-value --unset-all safe.directory "$ownership_repo"
if GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$ownership_repo" status --short \
  >/dev/null 2>&1; then
  printf 'Expected the removed ownership exception to stop applying.\n' >&2
  exit 1
fi

bare_repo="$lab_root/embedded.git"
git init --quiet --bare --initial-branch=main "$bare_repo"
git config --global safe.bareRepository explicit
if git -C "$bare_repo" rev-parse --is-bare-repository >/dev/null 2>&1; then
  printf 'Expected implicit bare-repository discovery to be rejected.\n' >&2
  exit 1
fi
test "$(git --git-dir="$bare_repo" rev-parse --is-bare-repository)" = 'true'
git config --global --unset safe.bareRepository

dependency_repo="$lab_root/dependency"
git init --quiet --initial-branch=main "$dependency_repo"
git -C "$dependency_repo" config user.name 'Dependency Author'
git -C "$dependency_repo" config user.email 'dependency@example.invalid'
printf 'trusted dependency fixture\n' > "$dependency_repo/library.txt"
git -C "$dependency_repo" add library.txt
git -C "$dependency_repo" commit --quiet -m 'feat: add dependency fixture'

source_repo="$lab_root/source"
git init --quiet --initial-branch=main "$source_repo"
git -C "$source_repo" config user.name 'Source Author'
git -C "$source_repo" config user.email 'source@example.invalid'
mkdir -p "$source_repo/tools/hooks"
printf '*.lab filter=lab\n' > "$source_repo/.gitattributes"
printf 'stored-content\n' > "$source_repo/data.lab"
printf '%s\n' \
  '#!/bin/sh' \
  ': "${UNTRUSTED_HOOK_MARKER:?}"' \
  'printf "pre-commit hook executed\\n" >> "$UNTRUSTED_HOOK_MARKER"' \
  'exit 23' > "$source_repo/tools/hooks/pre-commit"
chmod +x "$source_repo/tools/hooks/pre-commit"
git -C "$source_repo" add .gitattributes data.lab tools/hooks/pre-commit
git -C "$source_repo" commit --quiet -m 'test: add tracked execution selectors'
git -c protocol.file.allow=always -C "$source_repo" \
  submodule add --quiet "$dependency_repo" vendor/dependency
git -C "$source_repo" commit --quiet -am 'build: record recursive dependency URL'

source_hook_marker="$lab_root/source-hook-marker"
source_filter_marker="$lab_root/source-filter-marker"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "source hook executed\\n" >> "$SOURCE_HOOK_MARKER"' \
  > "$source_repo/.git/hooks/post-checkout"
chmod +x "$source_repo/.git/hooks/post-checkout"
git -C "$source_repo" config filter.lab.smudge \
  "printf 'source filter executed\\n' >> '$source_filter_marker'; cat"

empty_template="$lab_root/empty-template"
mkdir "$empty_template"
clone_repo="$lab_root/clone"
SOURCE_HOOK_MARKER="$source_hook_marker" \
  git clone --quiet --no-recurse-submodules --template="$empty_template" \
  "$source_repo" "$clone_repo"

test ! -e "$source_hook_marker"
test ! -e "$source_filter_marker"
test ! -e "$clone_repo/.git/hooks/post-checkout"
test "$(git -C "$clone_repo" config --get filter.lab.smudge || :)" = ''
test "$(cat "$clone_repo/data.lab")" = 'stored-content'

filter_marker="$lab_root/filter-marker"
filter_helper="$lab_root/smudge-filter"
printf '%s\n' \
  '#!/bin/sh' \
  ': "${UNTRUSTED_FILTER_MARKER:?}"' \
  'printf "smudge filter executed\\n" >> "$UNTRUSTED_FILTER_MARKER"' \
  'cat' > "$filter_helper"
chmod +x "$filter_helper"

git -C "$clone_repo" config filter.lab.smudge "$filter_helper"
git -C "$clone_repo" config filter.lab.required true
rm "$clone_repo/data.lab"
UNTRUSTED_FILTER_MARKER="$filter_marker" \
  git -C "$clone_repo" restore --source=HEAD --worktree -- data.lab
test -s "$filter_marker"
test "$(cat "$clone_repo/data.lab")" = 'stored-content'

failing_filter="$lab_root/failing-filter"
printf '%s\n' \
  '#!/bin/sh' \
  'cat >/dev/null' \
  'exit 17' > "$failing_filter"
chmod +x "$failing_filter"
git -C "$clone_repo" config filter.lab.smudge "$failing_filter"
rm "$clone_repo/data.lab"
if git -C "$clone_repo" restore --source=HEAD --worktree -- data.lab \
  >/dev/null 2>&1; then
  printf 'Expected a required smudge-filter failure to stop restore.\n' >&2
  exit 1
fi
git -C "$clone_repo" config --unset-all filter.lab.smudge
git -C "$clone_repo" config --unset-all filter.lab.required
git -C "$clone_repo" restore --source=HEAD --worktree -- data.lab
test "$(cat "$clone_repo/data.lab")" = 'stored-content'

git -C "$clone_repo" config user.name 'Clone Author'
git -C "$clone_repo" config user.email 'clone@example.invalid'
hook_marker="$lab_root/hook-marker"
printf 'candidate change\n' >> "$clone_repo/data.lab"
git -C "$clone_repo" add data.lab
head_before_hook="$(git -C "$clone_repo" rev-parse HEAD)"
git -C "$clone_repo" config core.hooksPath tools/hooks
if UNTRUSTED_HOOK_MARKER="$hook_marker" \
  git -C "$clone_repo" commit --quiet -m 'test: trigger tracked hook' \
  >/dev/null 2>&1; then
  printf 'Expected the configured tracked pre-commit hook to reject the commit.\n' >&2
  exit 1
fi
test -s "$hook_marker"
test "$(git -C "$clone_repo" rev-parse HEAD)" = "$head_before_hook"
test -n "$(git -C "$clone_repo" diff --cached --name-only)"
git -C "$clone_repo" config --unset core.hooksPath
git -C "$clone_repo" commit --quiet -m 'test: commit after removing hook opt-in'

if git -C "$clone_repo" submodule update --init >/dev/null 2>&1; then
  printf 'Expected recursive file transport to require explicit permission.\n' >&2
  exit 1
fi
git -c protocol.file.allow=always -C "$clone_repo" \
  submodule update --init --quiet
test "$(cat "$clone_repo/vendor/dependency/library.txt")" = \
  'trusted dependency fixture'

printf 'Ownership gates, bare discovery, clone boundaries, filters, hooks, and recursive protocol passed.\n'
