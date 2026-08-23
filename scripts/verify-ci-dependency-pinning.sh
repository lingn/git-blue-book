#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-ci-dependencies.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS GIT_CONFIG_COUNT

init_work_repo() {
  repo_dir="$1"
  author_name="$2"
  author_email="$3"

  mkdir "$repo_dir"
  git -C "$repo_dir" init --quiet --initial-branch=main
  git -C "$repo_dir" config user.name "$author_name"
  git -C "$repo_dir" config user.email "$author_email"
}

lock_value() {
  lock_file="$1"
  lock_key="$2"
  sed -n "s/^${lock_key}=//p" "$lock_file"
}

validate_lock() {
  lock_file="$1"
  action_git_dir="$2"
  nested_git_dir="$3"

  expected_action="$(lock_value "$lock_file" action_commit)"
  expected_nested="$(lock_value "$lock_file" nested_commit)"
  resolved_action="$(git --git-dir="$action_git_dir" rev-parse 'refs/tags/v1^{commit}')"
  resolved_nested="$(git --git-dir="$nested_git_dir" rev-parse refs/heads/main)"

  if test "$resolved_action" = "$expected_action" && \
    test "$resolved_nested" = "$expected_nested"; then
    return 0
  fi
  return 1
}

init_work_repo "$lab_dir/nested-src" "Nested Tool Maintainer" "nested@example.invalid"
printf 'tool implementation v1\n' > "$lab_dir/nested-src/tool.txt"
git -C "$lab_dir/nested-src" add tool.txt
git -C "$lab_dir/nested-src" commit --quiet -m 'tool: publish reviewed implementation'
nested_v1="$(git -C "$lab_dir/nested-src" rev-parse HEAD)"
git clone --quiet --bare "$lab_dir/nested-src" "$lab_dir/nested-origin.git"
git -C "$lab_dir/nested-src" remote add origin "$lab_dir/nested-origin.git"

init_work_repo "$lab_dir/action-src" "Action Maintainer" "action@example.invalid"
printf 'action implementation v1\n' > "$lab_dir/action-src/action.txt"
printf '%s\n' \
  "nested_url=$lab_dir/nested-origin.git" \
  'nested_selector=refs/heads/main' > "$lab_dir/action-src/dependency.conf"
git -C "$lab_dir/action-src" add action.txt dependency.conf
git -C "$lab_dir/action-src" commit --quiet -m 'action: publish reviewed implementation'
action_v1="$(git -C "$lab_dir/action-src" rev-parse HEAD)"
git -C "$lab_dir/action-src" tag -a v1 -m 'action v1 movable compatibility tag'
git clone --quiet --bare "$lab_dir/action-src" "$lab_dir/action-origin.git"
git -C "$lab_dir/action-src" remote add origin "$lab_dir/action-origin.git"

git clone --quiet --mirror "$lab_dir/action-origin.git" "$lab_dir/action-runner.git"
git clone --quiet --mirror "$lab_dir/nested-origin.git" "$lab_dir/nested-runner.git"

test "$(git --git-dir="$lab_dir/action-runner.git" rev-parse 'refs/tags/v1^{commit}')" = "$action_v1"
test "$(git --git-dir="$lab_dir/nested-runner.git" rev-parse refs/heads/main)" = "$nested_v1"

init_work_repo "$lab_dir/consumer" "Pipeline Owner" "pipeline@example.invalid"
mkdir "$lab_dir/consumer/ci"
lock_file="$lab_dir/consumer/ci/dependencies.lock"
printf '%s\n' \
  "action_url=$lab_dir/action-origin.git" \
  'action_selector=refs/tags/v1' \
  "action_commit=$action_v1" \
  "nested_url=$lab_dir/nested-origin.git" \
  'nested_selector=refs/heads/main' \
  "nested_commit=$nested_v1" > "$lock_file"
git -C "$lab_dir/consumer" add ci/dependencies.lock
git -C "$lab_dir/consumer" commit --quiet -m 'ci: lock reviewed dependency objects'
lock_v1_blob="$(git -C "$lab_dir/consumer" rev-parse HEAD:ci/dependencies.lock)"
validate_lock "$lock_file" "$lab_dir/action-runner.git" "$lab_dir/nested-runner.git"

printf 'action implementation v2\n' > "$lab_dir/action-src/action.txt"
git -C "$lab_dir/action-src" add action.txt
git -C "$lab_dir/action-src" commit --quiet -m 'action: publish changed implementation'
action_v2="$(git -C "$lab_dir/action-src" rev-parse HEAD)"
git -C "$lab_dir/action-src" tag --force -a v1 -m 'action v1 tag moved to changed implementation' >/dev/null
git -C "$lab_dir/action-src" push --quiet origin main
git -C "$lab_dir/action-src" push --quiet --force origin refs/tags/v1

git --git-dir="$lab_dir/action-runner.git" fetch --quiet --force origin '+refs/tags/v1:refs/tags/v1'
test "$(git --git-dir="$lab_dir/action-runner.git" rev-parse 'refs/tags/v1^{commit}')" = "$action_v2"
test "$action_v1" != "$action_v2"
git --git-dir="$lab_dir/action-runner.git" cat-file -e "$action_v1^{commit}"
test "$(git --git-dir="$lab_dir/action-runner.git" show "$action_v1:action.txt")" = 'action implementation v1'
test "$(git --git-dir="$lab_dir/action-runner.git" show "$action_v2:action.txt")" = 'action implementation v2'

if validate_lock "$lock_file" "$lab_dir/action-runner.git" "$lab_dir/nested-runner.git"; then
  printf 'Expected the moved action tag to violate the reviewed lock.\n' >&2
  exit 1
fi

git --git-dir="$lab_dir/action-runner.git" diff --name-only "$action_v1" "$action_v2" > "$lab_dir/action-changed-paths"
grep -Fqx 'action.txt' "$lab_dir/action-changed-paths"

printf 'tool implementation v2\n' > "$lab_dir/nested-src/tool.txt"
git -C "$lab_dir/nested-src" add tool.txt
git -C "$lab_dir/nested-src" commit --quiet -m 'tool: change transitive implementation'
nested_v2="$(git -C "$lab_dir/nested-src" rev-parse HEAD)"
git -C "$lab_dir/nested-src" push --quiet origin main
git --git-dir="$lab_dir/nested-runner.git" fetch --quiet origin '+refs/heads/main:refs/heads/main'

test "$nested_v1" != "$nested_v2"
test "$(git --git-dir="$lab_dir/nested-runner.git" rev-parse refs/heads/main)" = "$nested_v2"
test "$(git --git-dir="$lab_dir/action-runner.git" rev-parse "$action_v1")" = "$action_v1"
test "$(git --git-dir="$lab_dir/action-runner.git" show "$action_v1:dependency.conf" | sed -n 's/^nested_selector=//p')" = 'refs/heads/main'
git --git-dir="$lab_dir/nested-runner.git" cat-file -e "$nested_v1^{commit}"

if validate_lock "$lock_file" "$lab_dir/action-runner.git" "$lab_dir/nested-runner.git"; then
  printf 'Expected mutable direct and transitive selectors to violate the reviewed lock.\n' >&2
  exit 1
fi

printf '%s\n' \
  "action_url=$lab_dir/action-origin.git" \
  'action_selector=refs/tags/v1' \
  "action_commit=$action_v2" \
  "nested_url=$lab_dir/nested-origin.git" \
  'nested_selector=refs/heads/main' \
  "nested_commit=$nested_v2" > "$lock_file"
git -C "$lab_dir/consumer" add ci/dependencies.lock
git -C "$lab_dir/consumer" commit --quiet -m 'ci: review and lock dependency updates'
lock_v2_blob="$(git -C "$lab_dir/consumer" rev-parse HEAD:ci/dependencies.lock)"

test "$lock_v1_blob" != "$lock_v2_blob"
validate_lock "$lock_file" "$lab_dir/action-runner.git" "$lab_dir/nested-runner.git"
test "$(git --git-dir="$lab_dir/nested-runner.git" show "$nested_v1:tool.txt")" = 'tool implementation v1'
test "$(git --git-dir="$lab_dir/nested-runner.git" show "$nested_v2:tool.txt")" = 'tool implementation v2'

printf 'Mutable CI dependency refs, exact pins, and transitive drift boundaries passed.\n'
