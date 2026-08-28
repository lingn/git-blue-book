#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part4-history.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

mkdir "$lab_dir/seed"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"
printf '# Collaboration Lab\n' > "$lab_dir/seed/README.md"
git -C "$lab_dir/seed" add README.md
git -C "$lab_dir/seed" commit --quiet -m "docs: initialize collaboration lab"

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
git clone --quiet "$lab_dir/server.git" "$lab_dir/alice"
git clone --quiet "$lab_dir/server.git" "$lab_dir/bob"
for worktree in alice bob; do
  git -C "$lab_dir/$worktree" config user.name "$worktree"
  git -C "$lab_dir/$worktree" config user.email "$worktree@example.invalid"
done

printf 'Alice remote update.\n' > "$lab_dir/alice/ALICE.md"
git -C "$lab_dir/alice" add ALICE.md
git -C "$lab_dir/alice" commit --quiet -m "docs: add Alice note"
git -C "$lab_dir/alice" push --quiet origin main

printf 'Bob local update.\n' > "$lab_dir/bob/BOB.md"
git -C "$lab_dir/bob" add BOB.md
git -C "$lab_dir/bob" commit --quiet -m "docs: add Bob note"
bob_old="$(git -C "$lab_dir/bob" rev-parse HEAD)"
if git -C "$lab_dir/bob" push --quiet origin main >/dev/null 2>&1; then
  printf 'Expected non-fast-forward push rejection.\n' >&2
  exit 1
fi

git -C "$lab_dir/bob" fetch --quiet origin
test "$(git -C "$lab_dir/bob" rev-list --count main..origin/main)" = "1"
test "$(git -C "$lab_dir/bob" rev-list --count origin/main..main)" = "1"
rebase_base="$(git -C "$lab_dir/bob" merge-base main origin/main)"
bob_old_tree="$(git -C "$lab_dir/bob" rev-parse 'HEAD^{tree}')"
git -C "$lab_dir/bob" rebase --quiet origin/main
bob_new="$(git -C "$lab_dir/bob" rev-parse HEAD)"
test "$bob_new" != "$bob_old"
test "$(git -C "$lab_dir/bob" rev-parse 'HEAD^{tree}')" != "$bob_old_tree"
git -C "$lab_dir/bob" merge-base --is-ancestor origin/main HEAD
git -C "$lab_dir/bob" range-diff "$rebase_base..$bob_old" "origin/main..$bob_new" >/dev/null
git -C "$lab_dir/bob" push --quiet origin main

git -C "$lab_dir/alice" pull --quiet --ff-only
git -C "$lab_dir/alice" switch --quiet -c release/1.x
printf 'Release-specific note.\n' > "$lab_dir/alice/RELEASE.md"
git -C "$lab_dir/alice" add RELEASE.md
git -C "$lab_dir/alice" commit --quiet -m "docs: add release note"
git -C "$lab_dir/alice" switch --quiet -c develop main
printf 'Independent maintenance fix.\n' > "$lab_dir/alice/FIX.md"
git -C "$lab_dir/alice" add FIX.md
git -C "$lab_dir/alice" commit --quiet -m "fix: add maintenance correction"
fix_sha="$(git -C "$lab_dir/alice" rev-parse HEAD)"

git -C "$lab_dir/alice" switch --quiet release/1.x
git -C "$lab_dir/alice" cherry-pick --quiet "$fix_sha"
picked_sha="$(git -C "$lab_dir/alice" rev-parse HEAD)"
test "$picked_sha" != "$fix_sha"
test "$(git -C "$lab_dir/alice" log -1 --format=%s)" = "fix: add maintenance correction"
test -z "$(git -C "$lab_dir/alice" status --short)"

printf 'Part 4 rejection, fetch, rebase, and cherry-pick experiments passed.\n'
