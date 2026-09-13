#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-push-refs.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

seed="$lab_dir/seed"
remote="$lab_dir/remote.git"
client="$lab_dir/client"
options_log="$lab_dir/push-options.log"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "Push Ref Lab"
git -C "$seed" config user.email "push-ref@example.invalid"
printf 'base\n' > "$seed/base.txt"
git -C "$seed" add base.txt
git -C "$seed" commit --quiet -m "build: create push base"
base_oid="$(git -C "$seed" rev-parse HEAD)"
git clone --quiet --bare "$seed" "$remote"
git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
remote_url="file://$remote"
git clone --quiet "$remote_url" "$client"
git -C "$client" config user.name "Push Client"
git -C "$client" config user.email "push-client@example.invalid"

git -C "$client" switch --quiet -c topic
printf 'topic one\n' > "$client/topic.txt"
git -C "$client" add topic.txt
git -C "$client" commit --quiet -m "feat: create topic"
topic_v1="$(git -C "$client" rev-parse HEAD)"
git -C "$client" push --quiet --set-upstream origin \
  refs/heads/topic:refs/heads/topic
test "$(git --git-dir="$remote" rev-parse refs/heads/topic)" = "$topic_v1"
test "$(git -C "$client" rev-parse '@{upstream}')" = "$topic_v1"
test "$(git -C "$client" config --get branch.topic.remote)" = "origin"

printf 'topic two\n' >> "$client/topic.txt"
git -C "$client" add topic.txt
git -C "$client" commit --quiet -m "feat: advance topic"
topic_v2="$(git -C "$client" rev-parse HEAD)"
git -C "$client" push --dry-run origin \
  refs/heads/topic:refs/heads/topic \
  >"$lab_dir/dry-run.out" 2>"$lab_dir/dry-run.err"
test "$(git --git-dir="$remote" rev-parse refs/heads/topic)" = "$topic_v1"
git -C "$client" push --quiet origin \
  refs/heads/topic:refs/heads/topic
test "$(git --git-dir="$remote" rev-parse refs/heads/topic)" = "$topic_v2"

git -C "$client" tag -a v1.0.0 "$topic_v2" -m "Release v1.0.0"
git -C "$client" push --quiet origin refs/tags/v1.0.0:refs/tags/v1.0.0
remote_tag="$(git --git-dir="$remote" rev-parse refs/tags/v1.0.0)"
git -C "$client" tag -f -a v1.0.0 "$base_oid" -m "Conflicting tag" >/dev/null
if git -C "$client" push origin refs/tags/v1.0.0:refs/tags/v1.0.0 \
  >"$lab_dir/tag-reject.out" 2>"$lab_dir/tag-reject.err"; then
  printf 'Expected existing tag replacement to be rejected.\n' >&2
  exit 1
fi
test "$(git --git-dir="$remote" rev-parse refs/tags/v1.0.0)" = "$remote_tag"

git -C "$client" push --quiet origin :refs/heads/topic
if git --git-dir="$remote" show-ref --verify --quiet refs/heads/topic; then
  printf 'Expected explicit empty-source refspec to delete remote topic.\n' >&2
  exit 1
fi
test "$(git -C "$client" rev-parse refs/heads/topic)" = "$topic_v2"

git --git-dir="$remote" config receive.advertisePushOptions true
printf '%s\n' \
  '#!/bin/sh' \
  'count=${GIT_PUSH_OPTION_COUNT:-0}' \
  'printf "count=%s\n" "$count" > "$PUSH_OPTIONS_LOG"' \
  'i=0' \
  'while test "$i" -lt "$count"' \
  'do' \
  '  eval "value=\${GIT_PUSH_OPTION_$i}"' \
  '  printf "option[%s]=%s\n" "$i" "$value" >> "$PUSH_OPTIONS_LOG"' \
  '  i=$((i + 1))' \
  'done' \
  'exit 0' > "$remote/hooks/pre-receive"
chmod +x "$remote/hooks/pre-receive"
printf '%s\n' \
  '#!/bin/sh' \
  'ref=$1' \
  'if test "$ref" = "refs/heads/blocked"; then' \
  '  printf "blocked ref rejected\n" >&2' \
  '  exit 1' \
  'fi' \
  'exit 0' > "$remote/hooks/update"
chmod +x "$remote/hooks/update"

PUSH_OPTIONS_LOG="$options_log" git -C "$client" push --quiet \
  -o ci.skip=false -o change-ticket=INC-42 \
  origin refs/heads/topic:refs/heads/option-test
grep -F 'count=2' "$options_log" >/dev/null
grep -F 'option[0]=ci.skip=false' "$options_log" >/dev/null
grep -F 'option[1]=change-ticket=INC-42' "$options_log" >/dev/null
test "$(git --git-dir="$remote" rev-parse refs/heads/option-test)" = "$topic_v2"

git --git-dir="$remote" update-ref refs/heads/atomic-a "$base_oid"
git --git-dir="$remote" update-ref refs/heads/blocked "$base_oid"
if PUSH_OPTIONS_LOG="$options_log" git -C "$client" push --atomic origin \
  "$topic_v2:refs/heads/atomic-a" \
  "$topic_v2:refs/heads/blocked" \
  >"$lab_dir/atomic-reject.out" 2>"$lab_dir/atomic-reject.err"; then
  printf 'Expected hook rejection to fail the atomic push.\n' >&2
  exit 1
fi
test "$(git --git-dir="$remote" rev-parse refs/heads/atomic-a)" = "$base_oid"
test "$(git --git-dir="$remote" rev-parse refs/heads/blocked)" = "$base_oid"

if PUSH_OPTIONS_LOG="$options_log" git -C "$client" push --porcelain origin \
  "$topic_v2:refs/heads/atomic-a" \
  "$topic_v2:refs/heads/blocked" \
  >"$lab_dir/non-atomic.out" 2>"$lab_dir/non-atomic.err"; then
  printf 'Expected the non-atomic multi-ref push to report one rejected ref.\n' >&2
  exit 1
fi
test "$(git --git-dir="$remote" rev-parse refs/heads/atomic-a)" = "$topic_v2"
test "$(git --git-dir="$remote" rev-parse refs/heads/blocked)" = "$base_oid"
grep -F 'refs/heads/atomic-a' "$lab_dir/non-atomic.out" >/dev/null
grep -F 'refs/heads/blocked' "$lab_dir/non-atomic.out" >/dev/null

git --git-dir="$remote" fsck --full --strict >/dev/null
git -C "$client" fsck --full --strict >/dev/null
test -z "$(git -C "$client" status --short)"

printf 'Push ref updates, upstream, dry-run, tag rejection, deletion, options, and atomic rejection passed.\n'
