#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-complex-conflicts.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

content_repo="$lab_root/content"
mkdir "$content_repo"
git -C "$content_repo" init --quiet --initial-branch=main
git -C "$content_repo" config user.name "Conflict Author"
git -C "$content_repo" config user.email "conflict@example.invalid"
git -C "$content_repo" config rerere.enabled true
git -C "$content_repo" config rerere.autoupdate false
git -C "$content_repo" config merge.conflictStyle zdiff3

printf 'service settings\nmode=base\nend\n' > "$content_repo/service.conf"
git -C "$content_repo" add service.conf
git -C "$content_repo" commit --quiet -m "build: add base service mode"

git -C "$content_repo" switch --quiet --create feature/mode
printf 'service settings\nmode=feature\nend\n' > "$content_repo/service.conf"
git -C "$content_repo" add service.conf
git -C "$content_repo" commit --quiet -m "feat: use feature mode"
feature_tip="$(git -C "$content_repo" rev-parse HEAD)"

git -C "$content_repo" switch --quiet main
printf 'service settings\nmode=main\nend\n' > "$content_repo/service.conf"
git -C "$content_repo" add service.conf
git -C "$content_repo" commit --quiet -m "ops: use main mode"
main_before_merge="$(git -C "$content_repo" rev-parse HEAD)"

if git -C "$content_repo" merge --quiet feature/mode >/dev/null 2>&1; then
  printf 'Expected the first content merge to conflict.\n' >&2
  exit 1
fi
test -f "$content_repo/.git/MERGE_HEAD"
test "$(git -C "$content_repo" status --short service.conf)" = "UU service.conf"
test "$(git -C "$content_repo" ls-files -u -- service.conf | awk '{print $3}' | sort -u | tr '\n' ' ')" = "1 2 3 "
test "$(git -C "$content_repo" show :1:service.conf | sed -n '2p')" = "mode=base"
test "$(git -C "$content_repo" show :2:service.conf | sed -n '2p')" = "mode=main"
test "$(git -C "$content_repo" show :3:service.conf | sed -n '2p')" = "mode=feature"
test "$(git -C "$content_repo" cat-file -t AUTO_MERGE)" = "tree"
git -C "$content_repo" diff --quiet AUTO_MERGE
printf 'temporary investigation\n' >> "$content_repo/service.conf"
if git -C "$content_repo" diff --quiet AUTO_MERGE; then
  printf 'Expected AUTO_MERGE to expose the working-tree investigation change.\n' >&2
  exit 1
fi

git -C "$content_repo" merge --abort
test "$(git -C "$content_repo" rev-parse HEAD)" = "$main_before_merge"
test -z "$(git -C "$content_repo" status --short)"
test ! -e "$content_repo/.git/MERGE_HEAD"

if git -C "$content_repo" merge --quiet feature/mode >/dev/null 2>&1; then
  printf 'Expected the resolution-recording merge to conflict.\n' >&2
  exit 1
fi
printf 'service settings\nmode=combined\nend\n' > "$content_repo/service.conf"
git -C "$content_repo" add service.conf
git -C "$content_repo" rerere >/dev/null 2>&1
git -C "$content_repo" commit --quiet -m "merge: reconcile service mode"

git -C "$content_repo" switch --quiet --create replay/rerere "$main_before_merge"
if git -C "$content_repo" merge --quiet "$feature_tip" >/dev/null 2>&1; then
  printf 'Expected the replay merge to stop with unmerged index stages.\n' >&2
  exit 1
fi
test "$(sed -n '2p' "$content_repo/service.conf")" = "mode=combined"
test "$(git -C "$content_repo" status --short service.conf)" = "UU service.conf"
test "$(git -C "$content_repo" ls-files -u -- service.conf | wc -l | tr -d ' ')" = "3"
test -z "$(git -C "$content_repo" rerere remaining)"
git -C "$content_repo" add service.conf
git -C "$content_repo" commit --quiet -m "merge: reuse checked service resolution"
test "$(git -C "$content_repo" show HEAD:service.conf | sed -n '2p')" = "mode=combined"

git -C "$content_repo" switch --quiet --create replay/forget "$main_before_merge"
if git -C "$content_repo" merge --quiet "$feature_tip" >/dev/null 2>&1; then
  printf 'Expected the forget-path replay to stop with a conflict.\n' >&2
  exit 1
fi
test "$(sed -n '2p' "$content_repo/service.conf")" = "mode=combined"
git -C "$content_repo" rerere forget -- service.conf >/dev/null 2>&1
test -n "$(git -C "$content_repo" ls-files -u -- service.conf)"
git -C "$content_repo" merge --abort
test "$(git -C "$content_repo" rev-parse HEAD)" = "$main_before_merge"
test -z "$(git -C "$content_repo" status --short)"

rename_repo="$lab_root/rename-delete"
mkdir -p "$rename_repo/docs"
git -C "$rename_repo" init --quiet --initial-branch=main
git -C "$rename_repo" config user.name "Rename Author"
git -C "$rename_repo" config user.email "rename@example.invalid"
printf 'retained guide\n' > "$rename_repo/docs/guide.md"
git -C "$rename_repo" add docs/guide.md
git -C "$rename_repo" commit --quiet -m "docs: add guide"

git -C "$rename_repo" switch --quiet --create feature/rename-guide
mkdir "$rename_repo/manual"
git -C "$rename_repo" mv docs/guide.md manual/guide.md
git -C "$rename_repo" commit --quiet -m "docs: move guide to manual"

git -C "$rename_repo" switch --quiet main
git -C "$rename_repo" rm --quiet docs/guide.md
git -C "$rename_repo" commit --quiet -m "docs: remove obsolete guide"
if git -C "$rename_repo" merge --quiet feature/rename-guide >/dev/null 2>&1; then
  printf 'Expected rename/delete to require a decision.\n' >&2
  exit 1
fi
test -n "$(git -C "$rename_repo" ls-files -u)"
test -f "$rename_repo/manual/guide.md"
git -C "$rename_repo" add -A
test -z "$(git -C "$rename_repo" ls-files -u)"
git -C "$rename_repo" commit --quiet -m "merge: retain guide at new path"
test "$(git -C "$rename_repo" show HEAD:manual/guide.md)" = "retained guide"

directory_repo="$lab_root/directory-rename"
mkdir -p "$directory_repo/src/old"
git -C "$directory_repo" init --quiet --initial-branch=main
git -C "$directory_repo" config user.name "Directory Author"
git -C "$directory_repo" config user.email "directory@example.invalid"
git -C "$directory_repo" config merge.directoryRenames conflict
printf 'alpha\n' > "$directory_repo/src/old/a.txt"
printf 'beta\n' > "$directory_repo/src/old/b.txt"
git -C "$directory_repo" add src
git -C "$directory_repo" commit --quiet -m "feat: add old source directory"

git -C "$directory_repo" switch --quiet --create feature/relocate-directory
mkdir "$directory_repo/src/new"
git -C "$directory_repo" mv src/old/a.txt src/new/a.txt
git -C "$directory_repo" mv src/old/b.txt src/new/b.txt
git -C "$directory_repo" commit --quiet -m "refactor: relocate source directory"

git -C "$directory_repo" switch --quiet main
printf 'gamma\n' > "$directory_repo/src/old/c.txt"
git -C "$directory_repo" add src/old/c.txt
git -C "$directory_repo" commit --quiet -m "feat: add source in old directory"
if git -C "$directory_repo" merge --quiet feature/relocate-directory >/dev/null 2>&1; then
  printf 'Expected directory rename policy to stop for the new path.\n' >&2
  exit 1
fi
test -n "$(git -C "$directory_repo" ls-files -u)"
test -f "$directory_repo/src/new/c.txt"
test ! -e "$directory_repo/src/old/c.txt"
git -C "$directory_repo" add -A
test -z "$(git -C "$directory_repo" ls-files -u)"
git -C "$directory_repo" commit --quiet -m "merge: accept relocated source path"
test "$(git -C "$directory_repo" show HEAD:src/new/a.txt)" = "alpha"
test "$(git -C "$directory_repo" show HEAD:src/new/b.txt)" = "beta"
test "$(git -C "$directory_repo" show HEAD:src/new/c.txt)" = "gamma"

printf 'Index stages, AUTO_MERGE, rerere, rename/delete, and directory rename passed.\n'
