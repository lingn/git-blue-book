#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part6-collaboration.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

repo="$lab_dir/repo"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name "Collaboration Lab"
git -C "$repo" config user.email "collaboration@example.invalid"

printf 'base\n' > "$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit --quiet -m "chore: create collaboration baseline"
base_oid="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet -c feature/retry
printf 'feature api\n' > "$repo/api.txt"
git -C "$repo" add api.txt
git -C "$repo" commit --quiet -m "feat: add retry api"
printf 'feature tests\n' > "$repo/test.txt"
git -C "$repo" add test.txt
git -C "$repo" commit --quiet -m "test: cover retry api"
feature_oid="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet main
printf 'mainline change\n' > "$repo/main.txt"
git -C "$repo" add main.txt
git -C "$repo" commit --quiet -m "fix: advance main independently"
target_oid="$(git -C "$repo" rev-parse HEAD)"

printf 'Verify merge-commit evidence.\n'
git -C "$repo" switch --quiet -c integration/merge "$target_oid"
git -C "$repo" merge --quiet --no-ff --no-edit "$feature_oid"
merge_oid="$(git -C "$repo" rev-parse HEAD)"
merge_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
test "$(git -C "$repo" show -s --format=%P "$merge_oid" | awk '{print NF}')" = "2"
git -C "$repo" merge-base --is-ancestor "$feature_oid" "$merge_oid"

printf 'Verify squash evidence.\n'
git -C "$repo" switch --quiet -c integration/squash "$target_oid"
git -C "$repo" merge --quiet --squash "$feature_oid"
git -C "$repo" commit --quiet -m "feat: add retry api and tests"
squash_oid="$(git -C "$repo" rev-parse HEAD)"
squash_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
test "$(git -C "$repo" show -s --format=%P "$squash_oid" | awk '{print NF}')" = "1"
if git -C "$repo" merge-base --is-ancestor "$feature_oid" "$squash_oid"; then
  printf 'Expected the original feature tip not to be an ancestor of the squash commit.\n' >&2
  exit 1
fi
test "$squash_tree" = "$merge_tree"

printf 'Verify rebase-merge evidence.\n'
git -C "$repo" branch integration/rebase-source "$feature_oid"
git -C "$repo" switch --quiet integration/rebase-source
git -C "$repo" rebase --quiet --onto "$target_oid" "$base_oid"
rebased_oid="$(git -C "$repo" rev-parse HEAD)"
rebased_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
test "$rebased_oid" != "$feature_oid"
if git -C "$repo" merge-base --is-ancestor "$feature_oid" "$rebased_oid"; then
  printf 'Expected rebased commits to replace the original feature commits.\n' >&2
  exit 1
fi
test "$rebased_tree" = "$merge_tree"
git -C "$repo" range-diff "$base_oid..$feature_oid" "$target_oid..$rebased_oid" >/dev/null

printf 'Verify expected-old reference updates.\n'
protected_ref="refs/heads/integration/protected"
git -C "$repo" update-ref "$protected_ref" "$target_oid"
git -C "$repo" update-ref "$protected_ref" "$merge_oid" "$target_oid"
if git -C "$repo" update-ref "$protected_ref" "$squash_oid" "$target_oid" >/dev/null 2>&1; then
  printf 'Expected stale expected-old update to be rejected.\n' >&2
  exit 1
fi
test "$(git -C "$repo" rev-parse "$protected_ref")" = "$merge_oid"
git -C "$repo" update-ref "$protected_ref" "$squash_oid" "$merge_oid"
test "$(git -C "$repo" rev-parse "$protected_ref")" = "$squash_oid"

test -z "$(git -C "$repo" status --short)"
printf 'Part 6 merge strategy and expected-old collaboration experiments passed.\n'

