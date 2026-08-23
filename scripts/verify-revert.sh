#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-revert.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

single_repo="$lab_root/single"
git -C "$lab_root" init --quiet --initial-branch=main "$single_repo"
git -C "$single_repo" config user.name "Revert Test"
git -C "$single_repo" config user.email "revert@example.invalid"

printf 'stable\n' > "$single_repo/app.txt"
git -C "$single_repo" add app.txt
git -C "$single_repo" commit --quiet -m "feat: add stable behavior"
stable_commit="$(git -C "$single_repo" rev-parse HEAD)"

printf 'broken\n' > "$single_repo/app.txt"
git -C "$single_repo" add app.txt
git -C "$single_repo" commit --quiet -m "feat: introduce broken behavior"
bad_commit="$(git -C "$single_repo" rev-parse HEAD)"

printf 'later correct work\n' > "$single_repo/README.md"
git -C "$single_repo" add README.md
git -C "$single_repo" commit --quiet -m "docs: add later correct work"
later_commit="$(git -C "$single_repo" rev-parse HEAD)"

git -C "$single_repo" revert --quiet --no-edit "$bad_commit" >/dev/null
revert_commit="$(git -C "$single_repo" rev-parse HEAD)"
test "$revert_commit" != "$bad_commit"
test "$(git -C "$single_repo" rev-parse HEAD^)" = "$later_commit"
git -C "$single_repo" merge-base --is-ancestor "$bad_commit" "$revert_commit"
test "$(cat "$single_repo/app.txt")" = "stable"
test "$(cat "$single_repo/README.md")" = "later correct work"
test "$(git -C "$single_repo" rev-parse "$stable_commit^{tree}")" != "$(git -C "$single_repo" rev-parse 'HEAD^{tree}')"
test -z "$(git -C "$single_repo" status --short)"

conflict_repo="$lab_root/conflict"
git -C "$lab_root" init --quiet --initial-branch=main "$conflict_repo"
git -C "$conflict_repo" config user.name "Conflict Test"
git -C "$conflict_repo" config user.email "conflict@example.invalid"

printf 'mode=base\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "config: add base mode"

printf 'mode=bad\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "config: introduce bad mode"
conflict_bad="$(git -C "$conflict_repo" rev-parse HEAD)"

printf 'mode=later\n' > "$conflict_repo/config.txt"
git -C "$conflict_repo" add config.txt
git -C "$conflict_repo" commit --quiet -m "config: add later mode"
before_conflict="$(git -C "$conflict_repo" rev-parse HEAD)"
before_conflict_tree="$(git -C "$conflict_repo" rev-parse 'HEAD^{tree}')"

if GIT_EDITOR=true git -C "$conflict_repo" revert --no-edit "$conflict_bad" \
  > "$lab_root/conflict-revert.log" 2>&1; then
  printf 'Expected revert conflict did not occur.\n' >&2
  exit 1
fi

test "$(git -C "$conflict_repo" rev-parse REVERT_HEAD)" = "$conflict_bad"
grep -q '^UU config.txt$' < <(git -C "$conflict_repo" status --short)
git -C "$conflict_repo" revert --abort
test "$(git -C "$conflict_repo" rev-parse HEAD)" = "$before_conflict"
test "$(git -C "$conflict_repo" rev-parse 'HEAD^{tree}')" = "$before_conflict_tree"
test "$(cat "$conflict_repo/config.txt")" = "mode=later"
test -z "$(git -C "$conflict_repo" status --short)"

merge_repo="$lab_root/merge"
git -C "$lab_root" init --quiet --initial-branch=main "$merge_repo"
git -C "$merge_repo" config user.name "Merge Revert Test"
git -C "$merge_repo" config user.email "merge-revert@example.invalid"

printf 'base\n' > "$merge_repo/README.md"
git -C "$merge_repo" add README.md
git -C "$merge_repo" commit --quiet -m "docs: add base"
merge_base="$(git -C "$merge_repo" rev-parse HEAD)"

git -C "$merge_repo" switch --quiet -c feature/topic
printf 'feature\n' > "$merge_repo/feature.txt"
git -C "$merge_repo" add feature.txt
git -C "$merge_repo" commit --quiet -m "feat: add topic"
feature_commit="$(git -C "$merge_repo" rev-parse HEAD)"

git -C "$merge_repo" switch --quiet main
printf 'main\n' > "$merge_repo/main.txt"
git -C "$merge_repo" add main.txt
git -C "$merge_repo" commit --quiet -m "feat: add main work"
main_parent="$(git -C "$merge_repo" rev-parse HEAD)"

git -C "$merge_repo" merge --quiet --no-ff feature/topic -m "merge: add topic"
merge_commit="$(git -C "$merge_repo" rev-parse HEAD)"
test "$(git -C "$merge_repo" rev-parse "$merge_commit^1")" = "$main_parent"
test "$(git -C "$merge_repo" rev-parse "$merge_commit^2")" = "$feature_commit"
test -f "$merge_repo/main.txt"
test -f "$merge_repo/feature.txt"

if GIT_EDITOR=true git -C "$merge_repo" revert --no-edit "$merge_commit" \
  > "$lab_root/merge-without-mainline.log" 2>&1; then
  printf 'Expected merge revert without mainline to fail.\n' >&2
  exit 1
fi
test "$(git -C "$merge_repo" rev-parse HEAD)" = "$merge_commit"
test -z "$(git -C "$merge_repo" status --short)"

git -C "$merge_repo" revert --quiet --no-edit --mainline 1 "$merge_commit" >/dev/null
merge_revert="$(git -C "$merge_repo" rev-parse HEAD)"
test "$(git -C "$merge_repo" rev-parse HEAD^)" = "$merge_commit"
git -C "$merge_repo" merge-base --is-ancestor "$merge_commit" "$merge_revert"
test -f "$merge_repo/main.txt"
test ! -e "$merge_repo/feature.txt"
test "$(cat "$merge_repo/README.md")" = "base"
test "$(git -C "$merge_repo" merge-base main feature/topic)" = "$feature_commit"
test "$(git -C "$merge_repo" merge-base "$merge_base" "$merge_revert")" = "$merge_base"
test -z "$(git -C "$merge_repo" status --short)"

printf 'Single-commit revert, conflict abort, and merge mainline revert passed.\n'
