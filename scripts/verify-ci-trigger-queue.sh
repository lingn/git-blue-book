#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-ci-queue.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
unset GIT_CONFIG_COUNT

repo="$lab_dir/repository"
mkdir -p "$repo/build" "$repo/services/payment" "$repo/services/search" "$repo/.ci"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Queue Author"
git -C "$repo" config user.email "queue@example.invalid"

printf 'shared-build=v1\n' > "$repo/build/common.conf"
printf 'payment=v1\n' > "$repo/services/payment/app.txt"
printf 'search=v1\n' > "$repo/services/search/app.txt"
printf 'shared inputs trigger both services\n' > "$repo/.ci/path-policy.txt"
git -C "$repo" add .ci build services
git -C "$repo" commit --quiet -m "build: establish queue base"
base_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet --create feature/payment
printf 'payment=v2\n' > "$repo/services/payment/app.txt"
git -C "$repo" add services/payment/app.txt
git -C "$repo" commit --quiet -m "feat: update payment"
payment_head="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet --create feature/search "$base_commit"
printf 'search=v2\n' > "$repo/services/search/app.txt"
git -C "$repo" add services/search/app.txt
git -C "$repo" commit --quiet -m "feat: update search"
search_head="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet --create feature/unusual-path "$base_commit"
unusual_path=$'services/search/line\nbreak.txt'
printf 'path bytes stay intact\n' > "$repo/$unusual_path"
git -C "$repo" add -- "$unusual_path"
git -C "$repo" commit --quiet -m "test: add an unusual path"
unusual_head="$(git -C "$repo" rev-parse HEAD)"
path_count=0
while IFS= read -r -d '' changed_path; do
  test "$changed_path" = "$unusual_path"
  path_count=$((path_count + 1))
done < <(git -C "$repo" diff --name-only -z "$base_commit" "$unusual_head")
test "$path_count" = "1"

git -C "$repo" switch --quiet main
printf 'shared-build=v2\n' > "$repo/build/common.conf"
git -C "$repo" add build/common.conf
git -C "$repo" commit --quiet -m "build: update shared input"
target_head="$(git -C "$repo" rev-parse HEAD)"

test "$(git -C "$repo" merge-base "$target_head" "$payment_head")" = "$base_commit"
test "$(git -C "$repo" merge-base "$target_head" "$search_head")" = "$base_commit"
test "$(git -C "$repo" diff --name-only "$target_head...$payment_head")" = \
  "services/payment/app.txt"
test "$(git -C "$repo" diff --name-only "$target_head...$search_head")" = \
  "services/search/app.txt"

git -C "$repo" switch --quiet --create candidate/search-before-payment "$target_head"
git -C "$repo" merge --quiet --no-ff feature/search \
  -m "merge: test search before payment"
stale_search_candidate="$(git -C "$repo" rev-parse HEAD)"
test "$(git -C "$repo" rev-parse "$stale_search_candidate^1")" = "$target_head"
test "$(git -C "$repo" rev-parse "$stale_search_candidate^2")" = "$search_head"

git -C "$repo" switch --quiet --create queue/payment "$target_head"
git -C "$repo" merge --quiet --no-ff feature/payment \
  -m "merge: queue payment first"
payment_candidate="$(git -C "$repo" rev-parse HEAD)"
test "$(git -C "$repo" rev-parse "$payment_candidate^1")" = "$target_head"
test "$(git -C "$repo" rev-parse "$payment_candidate^2")" = "$payment_head"
test "$(git -C "$repo" diff --name-only "$target_head" "$payment_candidate")" = \
  "services/payment/app.txt"
test "$(git -C "$repo" show "$payment_candidate:build/common.conf")" = \
  "shared-build=v2"
test "$(git -C "$repo" show "$payment_head:build/common.conf")" = \
  "shared-build=v1"
git -C "$repo" diff --quiet "$target_head" "$payment_candidate" -- build/common.conf

git -C "$repo" switch --quiet --create queue/search "$payment_candidate"
git -C "$repo" merge --quiet --no-ff feature/search \
  -m "merge: queue search after payment"
search_candidate="$(git -C "$repo" rev-parse HEAD)"
test "$(git -C "$repo" rev-parse "$search_candidate^1")" = "$payment_candidate"
test "$(git -C "$repo" rev-parse "$search_candidate^2")" = "$search_head"
test "$(git -C "$repo" diff --name-only "$payment_candidate" "$search_candidate")" = \
  "services/search/app.txt"
test "$(git -C "$repo" show "$search_candidate:services/payment/app.txt")" = \
  "payment=v2"
test "$(git -C "$repo" show "$search_candidate:services/search/app.txt")" = \
  "search=v2"
test "$(git -C "$repo" show "$search_candidate:build/common.conf")" = \
  "shared-build=v2"

test "$stale_search_candidate" != "$search_candidate"
if git -C "$repo" merge-base --is-ancestor \
  "$stale_search_candidate" "$search_candidate"; then
  printf 'A stale queue candidate unexpectedly became an ancestor of the rebuilt candidate.\n' >&2
  exit 1
fi
if git -C "$repo" diff --quiet \
  "$stale_search_candidate^{tree}" "$search_candidate^{tree}"; then
  printf 'Queue position unexpectedly produced the same candidate tree.\n' >&2
  exit 1
fi

git -C "$repo" update-ref refs/heads/main "$payment_candidate" "$target_head"
test "$(git -C "$repo" rev-parse main)" = "$payment_candidate"

if git -C "$repo" update-ref refs/heads/main \
  "$search_candidate" "$target_head" 2>/dev/null; then
  printf 'Expected a stale target lease to reject the second queue update.\n' >&2
  exit 1
fi
test "$(git -C "$repo" rev-parse main)" = "$payment_candidate"

git -C "$repo" update-ref refs/heads/main \
  "$search_candidate" "$payment_candidate"
test "$(git -C "$repo" rev-parse main)" = "$search_candidate"
git -C "$repo" merge-base --is-ancestor "$payment_candidate" main

printf 'CI path selection, stale candidate, queue order, and conditional ref updates passed.\n'
