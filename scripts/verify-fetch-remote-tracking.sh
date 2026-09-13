#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-fetch.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

seed="$lab_dir/seed"
server="$lab_dir/server.git"
client="$lab_dir/client"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "Fetch Lab"
git -C "$seed" config user.email "fetch@example.invalid"
printf 'base\n' > "$seed/state.txt"
git -C "$seed" add state.txt
git -C "$seed" commit --quiet -m "build: create fetch base"
base_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" branch obsolete "$base_oid"
git clone --quiet --bare "$seed" "$server"
git --git-dir="$server" symbolic-ref HEAD refs/heads/main
server_url="file://$server"
git clone --quiet "$server_url" "$client"
git -C "$client" config user.name "Fetch Client"
git -C "$client" config user.email "fetch-client@example.invalid"
client_main_before="$(git -C "$client" rev-parse refs/heads/main)"
client_tracking_before="$(git -C "$client" rev-parse refs/remotes/origin/main)"
obsolete_before="$(git -C "$client" rev-parse refs/remotes/origin/obsolete)"
fetch_head_path="$(git -C "$client" rev-parse --path-format=absolute --git-path FETCH_HEAD)"

printf 'server main\n' > "$seed/state.txt"
git -C "$seed" add state.txt
git -C "$seed" commit --quiet -m "feat: advance remote main"
remote_main_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" switch --quiet -c feature/remote
printf 'remote feature\n' > "$seed/feature.txt"
git -C "$seed" add feature.txt
git -C "$seed" commit --quiet -m "feat: add remote feature"
remote_feature_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" switch --quiet main
git --git-dir="$server" fetch --quiet "$seed" \
  refs/heads/main:refs/heads/main \
  refs/heads/feature/remote:refs/heads/feature/remote
git --git-dir="$server" update-ref -d refs/heads/obsolete "$base_oid"

git -C "$client" fetch --atomic --prune origin \
  >"$lab_dir/fetch.out" 2>"$lab_dir/fetch.err"
test "$(git -C "$client" rev-parse refs/heads/main)" = "$client_main_before"
test "$(git -C "$client" rev-parse refs/remotes/origin/main)" = "$remote_main_oid"
test "$(git -C "$client" rev-parse refs/remotes/origin/feature/remote)" = "$remote_feature_oid"
if git -C "$client" show-ref --verify --quiet refs/remotes/origin/obsolete; then
  printf 'Expected --prune to remove the deleted tracking ref.\n' >&2
  exit 1
fi
test "$(git -C "$client" rev-parse refs/heads/main)" = "$client_main_before"
test "$(git -C "$client" rev-parse refs/remotes/origin/main)" != "$client_tracking_before"

git -C "$client" fetch --no-write-fetch-head origin \
  >"$lab_dir/no-fetch-head.out" 2>"$lab_dir/no-fetch-head.err"
test -s "$fetch_head_path"
fetch_head_before="$(git hash-object "$fetch_head_path")"
git -C "$client" fetch --no-write-fetch-head origin main \
  >"$lab_dir/no-fetch-head-2.out" 2>"$lab_dir/no-fetch-head-2.err"
test "$(git hash-object "$fetch_head_path")" = "$fetch_head_before"

git -C "$client" fetch --append origin main feature/remote \
  >"$lab_dir/append.out" 2>"$lab_dir/append.err"
append_lines="$(wc -l < "$fetch_head_path" | tr -d '[:space:]')"
test "$append_lines" -ge 2
grep -F "$remote_main_oid" "$fetch_head_path" >/dev/null
grep -F "$remote_feature_oid" "$fetch_head_path" >/dev/null

git --git-dir="$server" update-ref refs/heads/feature/remote "$base_oid"
old_feature_tracking="$(git -C "$client" rev-parse refs/remotes/origin/feature/remote)"
git -C "$client" fetch --quiet origin
test "$(git -C "$client" rev-parse refs/remotes/origin/feature/remote)" = "$base_oid"
git -C "$client" reflog show --format=%H \
  refs/remotes/origin/feature/remote > "$lab_dir/feature-reflog.txt"
grep -Fx "$base_oid" "$lab_dir/feature-reflog.txt" >/dev/null
grep -Fx "$old_feature_tracking" "$lab_dir/feature-reflog.txt" >/dev/null
if test "$old_feature_tracking" = "$base_oid"; then
  printf 'Expected the forced remote-tracking update to change the OID.\n' >&2
  exit 1
fi
git -C "$client" update-ref refs/recovery/remote-feature "$old_feature_tracking"
test "$(git -C "$client" rev-parse refs/recovery/remote-feature)" = "$remote_feature_oid"

git -C "$client" remote set-url origin "$lab_dir/missing.git"
tracking_after_force="$(git -C "$client" rev-parse refs/remotes/origin/main)"
if git -C "$client" fetch origin \
  >"$lab_dir/failed-fetch.out" 2>"$lab_dir/failed-fetch.err"; then
  printf 'Expected fetch from the missing URL to fail.\n' >&2
  exit 1
fi
test -s "$lab_dir/failed-fetch.err"
test "$(git -C "$client" rev-parse refs/remotes/origin/main)" = "$tracking_after_force"
git -C "$client" remote set-url origin "$server_url"

git -C "$client" fsck --full --strict >/dev/null
git --git-dir="$server" fsck --full --strict >/dev/null
test -z "$(git -C "$client" status --short)"

printf 'Fetch atomic/prune, FETCH_HEAD modes, forced tracking updates, and failure preservation passed.\n'
