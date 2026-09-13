#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-pull.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

seed="$lab_dir/seed"
server="$lab_dir/server.git"
ff="$lab_dir/ff"
diverged="$lab_dir/diverged"
rebased="$lab_dir/rebased"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "Pull Seed"
git -C "$seed" config user.email "pull-seed@example.invalid"
printf 'base\n' > "$seed/base.txt"
git -C "$seed" add base.txt
git -C "$seed" commit --quiet -m "build: create pull base"
base_oid="$(git -C "$seed" rev-parse HEAD)"
git clone --quiet --bare "$seed" "$server"
git --git-dir="$server" symbolic-ref HEAD refs/heads/main
server_url="file://$server"

git clone --quiet "$server_url" "$ff"
git -C "$ff" config user.name "Pull Fast Forward"
git -C "$ff" config user.email "pull-ff@example.invalid"
printf 'remote fast forward\n' > "$seed/ff.txt"
git -C "$seed" add ff.txt
git -C "$seed" commit --quiet -m "feat: advance for fast forward"
ff_remote_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" push --quiet "$server_url" refs/heads/main:refs/heads/main
git -C "$ff" pull --ff-only \
  >"$lab_dir/ff-pull.out" 2>"$lab_dir/ff-pull.err"
test "$(git -C "$ff" rev-parse HEAD)" = "$ff_remote_oid"
test "$(git -C "$ff" rev-parse refs/remotes/origin/main)" = "$ff_remote_oid"
test -z "$(git -C "$ff" status --short)"

git clone --quiet "$server_url" "$diverged"
git -C "$diverged" config user.name "Pull Merge"
git -C "$diverged" config user.email "pull-merge@example.invalid"
printf 'local divergent\n' > "$diverged/local.txt"
git -C "$diverged" add local.txt
git -C "$diverged" commit --quiet -m "feat: local divergent change"
local_oid="$(git -C "$diverged" rev-parse HEAD)"
printf 'remote divergent\n' > "$seed/remote.txt"
git -C "$seed" add remote.txt
git -C "$seed" commit --quiet -m "feat: remote divergent change"
remote_diverged_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" push --quiet "$server_url" refs/heads/main:refs/heads/main
if git -C "$diverged" pull --ff-only \
  >"$lab_dir/diverged-ff.out" 2>"$lab_dir/diverged-ff.err"; then
  printf 'Expected ff-only pull to reject divergent history.\n' >&2
  exit 1
fi
test -s "$lab_dir/diverged-ff.err"
test "$(git -C "$diverged" rev-parse HEAD)" = "$local_oid"
test "$(git -C "$diverged" rev-parse refs/remotes/origin/main)" = "$remote_diverged_oid"
git -C "$diverged" pull --no-rebase \
  >"$lab_dir/diverged-merge.out" 2>"$lab_dir/diverged-merge.err"
merge_oid="$(git -C "$diverged" rev-parse HEAD)"
test "$(git -C "$diverged" show -s --format=%P "$merge_oid" | awk '{print $1}')" = "$local_oid"
test "$(git -C "$diverged" show -s --format=%P "$merge_oid" | awk '{print $2}')" = "$remote_diverged_oid"
test "$(git -C "$diverged" show HEAD:local.txt)" = "local divergent"
test "$(git -C "$diverged" show HEAD:remote.txt)" = "remote divergent"
test -z "$(git -C "$diverged" status --short)"

git clone --quiet "$server_url" "$rebased"
git -C "$rebased" config user.name "Pull Rebase"
git -C "$rebased" config user.email "pull-rebase@example.invalid"
printf 'local rebase\n' > "$rebased/rebase.txt"
git -C "$rebased" add rebase.txt
git -C "$rebased" commit --quiet -m "feat: local rebase change"
rebase_old_oid="$(git -C "$rebased" rev-parse HEAD)"
printf 'remote rebase\n' > "$seed/rebase-remote.txt"
git -C "$seed" add rebase-remote.txt
git -C "$seed" commit --quiet -m "feat: remote rebase change"
rebase_remote_oid="$(git -C "$seed" rev-parse HEAD)"
git -C "$seed" push --quiet "$server_url" refs/heads/main:refs/heads/main
git -C "$rebased" pull --rebase \
  >"$lab_dir/rebase-pull.out" 2>"$lab_dir/rebase-pull.err"
rebase_new_oid="$(git -C "$rebased" rev-parse HEAD)"
test "$rebase_new_oid" != "$rebase_old_oid"
test "$(git -C "$rebased" rev-parse refs/remotes/origin/main)" = "$rebase_remote_oid"
git -C "$rebased" merge-base --is-ancestor "$rebase_remote_oid" "$rebase_new_oid"
test "$(git -C "$rebased" show HEAD:rebase.txt)" = "local rebase"
test "$(git -C "$rebased" show HEAD:rebase-remote.txt)" = "remote rebase"
test -z "$(git -C "$rebased" status --short)"

git --git-dir="$server" fsck --full --strict >/dev/null
git -C "$ff" fsck --full --strict >/dev/null
git -C "$diverged" fsck --full --strict >/dev/null
git -C "$rebased" fsck --full --strict >/dev/null

printf 'Pull fast-forward, fetch-side effects on ff-only rejection, merge, and rebase composition passed.\n'
