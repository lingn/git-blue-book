#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-rebase.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

rewrite_repo="$lab_root/rewrite"
git -C "$lab_root" init --quiet --initial-branch=main "$rewrite_repo"
git -C "$rewrite_repo" config user.name "Rebase Test"
git -C "$rewrite_repo" config user.email "rebase@example.invalid"

printf 'base\n' > "$rewrite_repo/README.md"
git -C "$rewrite_repo" add README.md
git -C "$rewrite_repo" commit --quiet -m "docs: add base"
rewrite_base="$(git -C "$rewrite_repo" rev-parse HEAD)"

mkdir "$rewrite_repo/src"
printf 'parser v1\n' > "$rewrite_repo/src/parser.txt"
git -C "$rewrite_repo" add src/parser.txt
git -C "$rewrite_repo" commit --quiet -m "feat: add parser draft"

printf 'parser v2\n' > "$rewrite_repo/src/parser.txt"
git -C "$rewrite_repo" add src/parser.txt
git -C "$rewrite_repo" commit --quiet -m "fix: correct parser draft"

mkdir "$rewrite_repo/tests" "$rewrite_repo/docs"
printf 'parser test\n' > "$rewrite_repo/tests/parser.txt"
printf 'parser docs\n' > "$rewrite_repo/docs/parser.md"
git -C "$rewrite_repo" add tests/parser.txt docs/parser.md
git -C "$rewrite_repo" commit --quiet -m "test: add parser test and docs"

original_tip="$(git -C "$rewrite_repo" rev-parse HEAD)"
original_tree="$(git -C "$rewrite_repo" rev-parse 'HEAD^{tree}')"
git -C "$rewrite_repo" branch recovery/before-interactive-rebase "$original_tip"

sequence_editor="$rewrite_repo/.git/sequence-editor.sh"
message_editor="$rewrite_repo/.git/message-editor.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'sed -e '\''1s/^pick /reword /'\'' -e '\''2s/^pick /fixup /'\'' -e '\''3s/^pick /edit /'\'' "$1" > "$1.tmp"' \
  'mv "$1.tmp" "$1"' > "$sequence_editor"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''feat: add corrected parser\n'\'' > "$1"' > "$message_editor"

chmod +x "$sequence_editor" "$message_editor"

if ! GIT_SEQUENCE_EDITOR="$sequence_editor" GIT_EDITOR="$message_editor" \
  git -C "$rewrite_repo" rebase --quiet --interactive "$rewrite_base" \
    > "$lab_root/rewrite-rebase.log" 2>&1; then
  cat "$lab_root/rewrite-rebase.log" >&2
  exit 1
fi

test -d "$rewrite_repo/.git/rebase-merge"
git -C "$rewrite_repo" reset --quiet HEAD^
git -C "$rewrite_repo" add tests/parser.txt
git -C "$rewrite_repo" commit --quiet -m "test: add parser test"
git -C "$rewrite_repo" add docs/parser.md
git -C "$rewrite_repo" commit --quiet -m "docs: explain parser"
GIT_EDITOR=true git -C "$rewrite_repo" rebase --continue >/dev/null

rewritten_tip="$(git -C "$rewrite_repo" rev-parse HEAD)"
test "$rewritten_tip" != "$original_tip"
test "$(git -C "$rewrite_repo" rev-parse 'HEAD^{tree}')" = "$original_tree"
test "$(git -C "$rewrite_repo" rev-list --count "$rewrite_base"..HEAD)" = "3"
test "$(git -C "$rewrite_repo" log -1 --format=%s)" = "docs: explain parser"
test "$(git -C "$rewrite_repo" log -2 --format=%s | tail -1)" = "test: add parser test"
test "$(git -C "$rewrite_repo" log -3 --format=%s | tail -1)" = "feat: add corrected parser"
test "$(cat "$rewrite_repo/src/parser.txt")" = "parser v2"
test -z "$(git -C "$rewrite_repo" status --short)"
test "$(git -C "$rewrite_repo" rev-parse recovery/before-interactive-rebase)" = "$original_tip"
git -C "$rewrite_repo" range-diff \
  "$rewrite_base".."$original_tip" \
  "$rewrite_base".."$rewritten_tip" >/dev/null

conflict_repo="$lab_root/conflict"
git -C "$lab_root" init --quiet --initial-branch=main "$conflict_repo"
git -C "$conflict_repo" config user.name "Conflict Test"
git -C "$conflict_repo" config user.email "conflict@example.invalid"

printf 'value=base\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "config: add base value"
conflict_base="$(git -C "$conflict_repo" rev-parse HEAD)"

printf 'value=main\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "config: update main value"

git -C "$conflict_repo" switch --quiet -c feature/conflict "$conflict_base"
printf 'value=feature\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "config: update feature value"
feature_tip="$(git -C "$conflict_repo" rev-parse HEAD)"
feature_tree="$(git -C "$conflict_repo" rev-parse 'HEAD^{tree}')"

if GIT_SEQUENCE_EDITOR=: GIT_EDITOR=true \
  git -C "$conflict_repo" rebase --quiet --interactive main >/dev/null 2>&1; then
  printf 'Expected interactive rebase conflict did not occur.\n' >&2
  exit 1
fi

test -d "$conflict_repo/.git/rebase-merge"
git -C "$conflict_repo" rebase --show-current-patch > "$lab_root/current.patch"
grep -q 'value=feature' "$lab_root/current.patch"
grep -q '^UU config.txt$' < <(git -C "$conflict_repo" status --short)
git -C "$conflict_repo" rebase --abort
test "$(git -C "$conflict_repo" branch --show-current)" = "feature/conflict"
test "$(git -C "$conflict_repo" rev-parse HEAD)" = "$feature_tip"
test "$(git -C "$conflict_repo" rev-parse 'HEAD^{tree}')" = "$feature_tree"
test "$(cat "$conflict_repo/config.txt")" = "value=feature"
test -z "$(git -C "$conflict_repo" status --short)"

printf 'Interactive rebase rewrite, split, conflict, and abort passed.\n'
