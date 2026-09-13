#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-refs.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

source_repo="$lab_dir/source"
linked_worktree="$lab_dir/linked"
clone_repo="$lab_dir/clone"

git init --quiet --initial-branch=main "$source_repo"
git -C "$source_repo" config user.name "Refs Lab"
git -C "$source_repo" config user.email "refs@example.invalid"

test "$(git -C "$source_repo" symbolic-ref --quiet HEAD)" = "refs/heads/main"
if git -C "$source_repo" rev-parse --verify 'HEAD^{commit}' >/dev/null 2>&1; then
  printf 'Expected an unborn HEAD before the first commit.\n' >&2
  exit 1
fi
if git -C "$source_repo" show-ref --verify --quiet refs/heads/main; then
  printf 'Expected refs/heads/main not to exist before the first commit.\n' >&2
  exit 1
fi

printf 'A\n' > "$source_repo/state.txt"
git -C "$source_repo" add state.txt
git -C "$source_repo" commit --quiet -m "state A"
commit_a="$(git -C "$source_repo" rev-parse HEAD)"
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_a"
git -C "$source_repo" reflog exists HEAD
git -C "$source_repo" reflog exists refs/heads/main

printf 'B\n' > "$source_repo/state.txt"
git -C "$source_repo" add state.txt
tree_b="$(git -C "$source_repo" write-tree)"
commit_b="$(printf 'state B\n' | git -C "$source_repo" commit-tree "$tree_b" -p "$commit_a")"
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_a"

git -C "$source_repo" update-ref -m "lab: advance main" \
  refs/heads/main "$commit_b" "$commit_a"
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_b"
test "$(git -C "$source_repo" rev-parse HEAD)" = "$commit_b"
git -C "$source_repo" reflog show --format='%H %gs' refs/heads/main > "$lab_dir/main-reflog.txt"
grep -F "$commit_b lab: advance main" "$lab_dir/main-reflog.txt" >/dev/null

if git -C "$source_repo" update-ref -m "lab: stale overwrite" \
  refs/heads/main "$commit_a" "$commit_a" 2>"$lab_dir/stale-update.err"; then
  printf 'Expected stale expected-old update to fail.\n' >&2
  exit 1
fi
test -s "$lab_dir/stale-update.err"
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_b"

git -C "$source_repo" branch topic "$commit_a"
git -C "$source_repo" pack-refs --all
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_b"
test "$(git -C "$source_repo" rev-parse refs/heads/topic)" = "$commit_a"
git -C "$source_repo" for-each-ref --format='%(refname) %(objectname)' refs/heads/ > "$lab_dir/refs.txt"
grep -F "refs/heads/main $commit_b" "$lab_dir/refs.txt" >/dev/null
grep -F "refs/heads/topic $commit_a" "$lab_dir/refs.txt" >/dev/null

git -C "$source_repo" switch --quiet --detach "$commit_a"
if git -C "$source_repo" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  printf 'Expected HEAD to be detached.\n' >&2
  exit 1
fi
test "$(git -C "$source_repo" rev-parse HEAD)" = "$commit_a"
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_b"

printf 'detached\n' > "$source_repo/state.txt"
git -C "$source_repo" add state.txt
git -C "$source_repo" commit --quiet -m "detached work"
detached_commit="$(git -C "$source_repo" rev-parse HEAD)"
test "$detached_commit" != "$commit_a"
test "$(git -C "$source_repo" rev-parse refs/heads/main)" = "$commit_b"
git -C "$source_repo" reflog show --format=%H HEAD > "$lab_dir/head-reflog.txt"
grep -Fx "$detached_commit" "$lab_dir/head-reflog.txt" >/dev/null

printf 'create refs/recovery/detached-lab %s\n' "$detached_commit" |
  git -C "$source_repo" update-ref --stdin
test "$(git -C "$source_repo" rev-parse refs/recovery/detached-lab)" = "$detached_commit"
if printf 'create refs/recovery/detached-lab %s\n' "$commit_a" |
  git -C "$source_repo" update-ref --stdin 2>"$lab_dir/duplicate-create.err"; then
  printf 'Expected duplicate recovery ref creation to fail.\n' >&2
  exit 1
fi
test -s "$lab_dir/duplicate-create.err"

git -C "$source_repo" switch --quiet main
test "$(git -C "$source_repo" rev-parse HEAD)" = "$commit_b"
test -z "$(git -C "$source_repo" status --short)"

git -C "$source_repo" worktree add --quiet -b linked "$linked_worktree" "$commit_a"
source_common="$(git -C "$source_repo" rev-parse --path-format=absolute --git-common-dir)"
linked_common="$(git -C "$linked_worktree" rev-parse --path-format=absolute --git-common-dir)"
source_head_log="$(git -C "$source_repo" rev-parse --path-format=absolute --git-path logs/HEAD)"
linked_head_log="$(git -C "$linked_worktree" rev-parse --path-format=absolute --git-path logs/HEAD)"
test "$source_common" = "$linked_common"
test "$source_head_log" != "$linked_head_log"

printf 'linked\n' > "$linked_worktree/linked.txt"
git -C "$linked_worktree" add linked.txt
git -C "$linked_worktree" commit --quiet -m "linked worktree commit"
linked_commit="$(git -C "$linked_worktree" rev-parse HEAD)"
test "$(git -C "$source_repo" rev-parse refs/heads/linked)" = "$linked_commit"
git -C "$linked_worktree" reflog show --format=%H HEAD > "$lab_dir/linked-head-reflog.txt"
grep -Fx "$linked_commit" "$lab_dir/linked-head-reflog.txt" >/dev/null
git -C "$source_repo" reflog show --format=%H refs/heads/linked > "$lab_dir/linked-branch-reflog.txt"
grep -Fx "$linked_commit" "$lab_dir/linked-branch-reflog.txt" >/dev/null
if grep -Fx "$linked_commit" "$lab_dir/head-reflog.txt" >/dev/null; then
  printf 'The source worktree HEAD reflog must not include linked worktree actions.\n' >&2
  exit 1
fi

git clone --quiet "$source_repo" "$clone_repo"
test "$(git -C "$clone_repo" rev-parse refs/heads/main)" = "$commit_b"
git -C "$clone_repo" reflog show --format=%gs refs/heads/main > "$lab_dir/clone-main-reflog.txt"
if grep -F "lab: advance main" "$lab_dir/clone-main-reflog.txt" >/dev/null; then
  printf 'Source reflog messages must not be transferred by clone.\n' >&2
  exit 1
fi

git -C "$source_repo" fsck --full --strict >/dev/null
git -C "$clone_repo" fsck --full --strict >/dev/null
test -z "$(git -C "$source_repo" status --short)"
test -z "$(git -C "$linked_worktree" status --short)"
test -z "$(git -C "$clone_repo" status --short)"

printf 'Refs, HEAD states, conditional updates, worktree reflogs, and clone locality passed.\n'
