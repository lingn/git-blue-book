#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part04-exercise.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

repo="$lab_dir/repo"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name "Part 04 Exercise"
git -C "$repo" config user.email "part04@example.invalid"
printf 'service baseline\n' > "$repo/service.txt"
printf 'timeout=15\n' > "$repo/runtime.conf"
git -C "$repo" add service.txt runtime.conf
git -C "$repo" commit --quiet -m "build: create service baseline"
base_oid="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet -c feature/retry
printf 'retry feature\n' > "$repo/retry.txt"
printf 'timeout=30\n' > "$repo/runtime.conf"
git -C "$repo" add retry.txt runtime.conf
git -C "$repo" commit --quiet -m "feat: add retry with extended timeout"
feature_oid="$(git -C "$repo" rev-parse HEAD)"
test "$(git -C "$repo" rev-parse HEAD^)" = "$base_oid"

git -C "$repo" switch --quiet main
printf 'hotfix guard\n' > "$repo/hotfix.txt"
printf 'timeout=10\n' > "$repo/runtime.conf"
git -C "$repo" add hotfix.txt runtime.conf
git -C "$repo" commit --quiet -m "fix: cap runtime timeout during incident"
hotfix_oid="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag -a hotfix-20260914 "$hotfix_oid" -m "Incident timeout hotfix"
test "$(git -C "$repo" rev-parse 'hotfix-20260914^{}')" = "$hotfix_oid"

git -C "$repo" switch --quiet -c integration/retry "$hotfix_oid"
test "$(git -C "$repo" rev-list --left-right --count "$hotfix_oid...$feature_oid")" = $'1\t1'
if git -C "$repo" merge --ff-only "$feature_oid" \
  >"$lab_dir/ff-only.out" 2>"$lab_dir/ff-only.err"; then
  printf 'Expected ff-only to reject the divergent feature.\n' >&2
  exit 1
fi
test "$(git -C "$repo" rev-parse HEAD)" = "$hotfix_oid"
test -z "$(git -C "$repo" status --short)"

if git -C "$repo" merge --no-ff "$feature_oid" \
  >"$lab_dir/conflict.out" 2>"$lab_dir/conflict.err"; then
  printf 'Expected the runtime configuration to conflict.\n' >&2
  exit 1
fi
test "$(git -C "$repo" rev-parse HEAD)" = "$hotfix_oid"
test "$(git -C "$repo" rev-parse MERGE_HEAD)" = "$feature_oid"
test "$(git -C "$repo" ls-files -u -- runtime.conf | awk '{print $3}' | tr '\n' ' ')" = "1 2 3 "
test "$(git -C "$repo" show :1:runtime.conf)" = "timeout=15"
test "$(git -C "$repo" show :2:runtime.conf)" = "timeout=10"
test "$(git -C "$repo" show :3:runtime.conf)" = "timeout=30"

printf 'timeout=20\n' > "$repo/runtime.conf"
git -C "$repo" add runtime.conf
test -z "$(git -C "$repo" ls-files --unmerged)"
result_tree="$(git -C "$repo" write-tree)"
test "$(git -C "$repo" show "$result_tree:runtime.conf")" = "timeout=20"
test "$(git -C "$repo" show "$result_tree:retry.txt")" = "retry feature"
test "$(git -C "$repo" show "$result_tree:hotfix.txt")" = "hotfix guard"
GIT_EDITOR=true git -C "$repo" merge --continue \
  >"$lab_dir/continue.out" 2>"$lab_dir/continue.err"
integration_oid="$(git -C "$repo" rev-parse HEAD)"
parents="$(git -C "$repo" show -s --format=%P "$integration_oid")"
test "$(printf '%s\n' "$parents" | awk '{print $1}')" = "$hotfix_oid"
test "$(printf '%s\n' "$parents" | awk '{print $2}')" = "$feature_oid"
test "$(git -C "$repo" rev-parse 'HEAD^{tree}')" = "$result_tree"

git -C "$repo" switch --quiet main
test "$(git -C "$repo" rev-parse HEAD)" = "$hotfix_oid"
git -C "$repo" merge --quiet --ff-only integration/retry
test "$(git -C "$repo" rev-parse HEAD)" = "$integration_oid"
git -C "$repo" tag -a candidate-2.0.0 "$integration_oid" -m "Candidate 2.0.0"
test "$(git -C "$repo" rev-parse 'candidate-2.0.0^{}')" = "$integration_oid"
git -C "$repo" merge-base --is-ancestor "$feature_oid" main
git -C "$repo" branch -d feature/retry integration/retry >/dev/null
if git -C "$repo" show-ref --verify --quiet refs/heads/feature/retry; then
  printf 'Expected merged feature branch to be deleted.\n' >&2
  exit 1
fi
git -C "$repo" cat-file -e "$feature_oid^{commit}"
git -C "$repo" fsck --full --strict >/dev/null
test -z "$(git -C "$repo" status --short)"

printf 'Part 04 hotfix, divergence, conflict resolution, integration, tags, and cleanup passed.\n'
