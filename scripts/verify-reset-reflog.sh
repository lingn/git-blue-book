#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-reset.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

git -C "$lab_dir" init --quiet --initial-branch=main
git -C "$lab_dir" config user.name "Reset Test"
git -C "$lab_dir" config user.email "reset@example.invalid"

printf 'A\n' > "$lab_dir/state.txt"
git -C "$lab_dir" add state.txt
git -C "$lab_dir" commit --quiet -m "state A"

printf 'B\n' > "$lab_dir/state.txt"
git -C "$lab_dir" add state.txt
git -C "$lab_dir" commit --quiet -m "state B"
b_commit="$(git -C "$lab_dir" rev-parse HEAD)"
b_tree="$(git -C "$lab_dir" rev-parse 'HEAD^{tree}')"

mkdir "$lab_dir/generated"
printf 'tracked report\n' > "$lab_dir/generated/report.txt"
printf 'C\n' > "$lab_dir/state.txt"
git -C "$lab_dir" add state.txt generated/report.txt
git -C "$lab_dir" commit --quiet -m "state C"
c_commit="$(git -C "$lab_dir" rev-parse HEAD)"
c_tree="$(git -C "$lab_dir" rev-parse 'HEAD^{tree}')"

printf 'unrelated note\n' > "$lab_dir/notes.txt"

git -C "$lab_dir" reset --quiet --soft "$b_commit"
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$b_commit"
test "$(git -C "$lab_dir" rev-parse ORIG_HEAD)" = "$c_commit"
test "$(git -C "$lab_dir" write-tree)" = "$c_tree"
test "$(cat "$lab_dir/state.txt")" = "C"
test "$(cat "$lab_dir/generated/report.txt")" = "tracked report"

git -C "$lab_dir" reset --quiet --hard "$c_commit"
git -C "$lab_dir" reset --quiet --mixed "$b_commit"
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$b_commit"
test "$(git -C "$lab_dir" rev-parse ORIG_HEAD)" = "$c_commit"
test "$(git -C "$lab_dir" write-tree)" = "$b_tree"
test "$(cat "$lab_dir/state.txt")" = "C"
test -f "$lab_dir/generated/report.txt"
test -n "$(git -C "$lab_dir" diff -- state.txt)"

git -C "$lab_dir" reset --quiet --hard "$c_commit"
git -C "$lab_dir" reset --quiet --hard "$b_commit"
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$b_commit"
test "$(git -C "$lab_dir" rev-parse ORIG_HEAD)" = "$c_commit"
test "$(git -C "$lab_dir" write-tree)" = "$b_tree"
test "$(cat "$lab_dir/state.txt")" = "B"
test ! -e "$lab_dir/generated/report.txt"
test "$(cat "$lab_dir/notes.txt")" = "unrelated note"

git -C "$lab_dir" branch recovery/state-c "$c_commit"
test "$(git -C "$lab_dir" rev-parse recovery/state-c)" = "$c_commit"
git -C "$lab_dir" reflog show --format=%H HEAD > "$lab_dir/reflog.txt"
grep -q "$c_commit" "$lab_dir/reflog.txt"

git -C "$lab_dir" reset --quiet --hard "$c_commit"
printf 'D\n' > "$lab_dir/state.txt"
git -C "$lab_dir" add state.txt
head_before_path_reset="$(git -C "$lab_dir" rev-parse HEAD)"
git -C "$lab_dir" reset --quiet HEAD -- state.txt
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$head_before_path_reset"
test "$(git -C "$lab_dir" write-tree)" = "$c_tree"
test "$(cat "$lab_dir/state.txt")" = "D"
test -n "$(git -C "$lab_dir" diff -- state.txt)"

git -C "$lab_dir" reset --quiet --hard "$b_commit"
mkdir -p "$lab_dir/generated"
printf 'untracked obstruction\n' > "$lab_dir/generated/report.txt"
git -C "$lab_dir" reset --quiet --hard "$c_commit"
test "$(cat "$lab_dir/generated/report.txt")" = "tracked report"
test "$(cat "$lab_dir/notes.txt")" = "unrelated note"

git -C "$lab_dir" switch --quiet -c feature/deleted
printf 'recoverable\n' > "$lab_dir/deleted.txt"
git -C "$lab_dir" add deleted.txt
git -C "$lab_dir" commit --quiet -m "feat: add recoverable work"
deleted_commit="$(git -C "$lab_dir" rev-parse HEAD)"
git -C "$lab_dir" switch --quiet main
git -C "$lab_dir" branch -D feature/deleted >/dev/null
git -C "$lab_dir" reflog show --format=%H HEAD > "$lab_dir/head-reflog.txt"
grep -q "$deleted_commit" "$lab_dir/head-reflog.txt"
git -C "$lab_dir" branch recovery/deleted-feature "$deleted_commit"
test "$(git -C "$lab_dir" rev-parse recovery/deleted-feature)" = "$deleted_commit"

printf 'Reset modes, path reset, reflog evidence, and recovery passed.\n'
