#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part5-recovery.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

mkdir "$lab_dir/seed"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"
printf 'stable\n' > "$lab_dir/seed/app.txt"
git -C "$lab_dir/seed" add app.txt
git -C "$lab_dir/seed" commit --quiet -m "feat: add stable behavior"

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
git clone --quiet "$lab_dir/server.git" "$lab_dir/alice"
git -C "$lab_dir/alice" config user.name "Alice"
git -C "$lab_dir/alice" config user.email "alice@example.invalid"

printf 'broken\n' > "$lab_dir/alice/app.txt"
git -C "$lab_dir/alice" add app.txt
git -C "$lab_dir/alice" commit --quiet -m "feat: introduce broken behavior"
bad_sha="$(git -C "$lab_dir/alice" rev-parse HEAD)"
git -C "$lab_dir/alice" push --quiet origin main
git -C "$lab_dir/alice" revert --quiet --no-edit "$bad_sha"
revert_sha="$(git -C "$lab_dir/alice" rev-parse HEAD)"
test "$revert_sha" != "$bad_sha"
test "$(cat "$lab_dir/alice/app.txt")" = "stable"
git -C "$lab_dir/alice" push --quiet origin main

git -C "$lab_dir/alice" switch --quiet -c feature/rewrite
printf 'first feature version\n' > "$lab_dir/alice/feature.txt"
git -C "$lab_dir/alice" add feature.txt
git -C "$lab_dir/alice" commit --quiet -m "feat: add feature draft"
git -C "$lab_dir/alice" push --quiet -u origin feature/rewrite
expected_remote="$(git -C "$lab_dir/alice" rev-parse origin/feature/rewrite)"

git clone --quiet "$lab_dir/server.git" "$lab_dir/bob"
git -C "$lab_dir/bob" config user.name "Bob"
git -C "$lab_dir/bob" config user.email "bob@example.invalid"
git -C "$lab_dir/bob" switch --quiet feature/rewrite
printf 'Bob remote update\n' >> "$lab_dir/bob/feature.txt"
git -C "$lab_dir/bob" add feature.txt
git -C "$lab_dir/bob" commit --quiet -m "feat: extend feature remotely"
git -C "$lab_dir/bob" push --quiet origin feature/rewrite

printf 'Alice rewritten version\n' > "$lab_dir/alice/feature.txt"
git -C "$lab_dir/alice" add feature.txt
git -C "$lab_dir/alice" commit --quiet --amend -m "feat: rewrite feature draft"
if git -C "$lab_dir/alice" push --quiet \
  --force-with-lease=refs/heads/feature/rewrite:"$expected_remote" \
  origin feature/rewrite >/dev/null 2>&1; then
  printf 'Expected stale explicit lease to reject the force push.\n' >&2
  exit 1
fi

mkdir "$lab_dir/reset"
git -C "$lab_dir/reset" init --quiet --initial-branch=main
git -C "$lab_dir/reset" config user.name "Reset Test"
git -C "$lab_dir/reset" config user.email "reset@example.invalid"
printf 'B\n' > "$lab_dir/reset/state.txt"
git -C "$lab_dir/reset" add state.txt
git -C "$lab_dir/reset" commit --quiet -m "state B"
b_sha="$(git -C "$lab_dir/reset" rev-parse HEAD)"
printf 'C\n' > "$lab_dir/reset/state.txt"
git -C "$lab_dir/reset" add state.txt
git -C "$lab_dir/reset" commit --quiet -m "state C"
c_sha="$(git -C "$lab_dir/reset" rev-parse HEAD)"

git -C "$lab_dir/reset" reset --quiet --soft "$b_sha"
test "$(git -C "$lab_dir/reset" rev-parse HEAD)" = "$b_sha"
test -n "$(git -C "$lab_dir/reset" diff --staged)"
test "$(cat "$lab_dir/reset/state.txt")" = "C"

git -C "$lab_dir/reset" reset --quiet --hard "$c_sha"
git -C "$lab_dir/reset" reset --quiet --mixed "$b_sha"
test -z "$(git -C "$lab_dir/reset" diff --staged)"
test -n "$(git -C "$lab_dir/reset" diff)"
test "$(cat "$lab_dir/reset/state.txt")" = "C"

git -C "$lab_dir/reset" reset --quiet --hard "$c_sha"
git -C "$lab_dir/reset" reset --quiet --hard "$b_sha"
test "$(cat "$lab_dir/reset/state.txt")" = "B"
git -C "$lab_dir/reset" branch recovery/state-c "$c_sha"
test "$(git -C "$lab_dir/reset" rev-parse recovery/state-c)" = "$c_sha"
git -C "$lab_dir/reset" reflog --format=%H > "$lab_dir/reflog.txt"
grep -q "$c_sha" "$lab_dir/reflog.txt"

git -C "$lab_dir/reset" switch --quiet -c feature/deleted recovery/state-c
printf 'D\n' > "$lab_dir/reset/deleted.txt"
git -C "$lab_dir/reset" add deleted.txt
git -C "$lab_dir/reset" commit --quiet -m "recoverable feature"
d_sha="$(git -C "$lab_dir/reset" rev-parse HEAD)"
git -C "$lab_dir/reset" switch --quiet main
git -C "$lab_dir/reset" branch -D feature/deleted >/dev/null
git -C "$lab_dir/reset" branch recovery/deleted-feature "$d_sha"
test "$(git -C "$lab_dir/reset" rev-parse recovery/deleted-feature)" = "$d_sha"

printf 'Part 5 revert, lease rejection, reset modes, and reflog recovery experiments passed.\n'
