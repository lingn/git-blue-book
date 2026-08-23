#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-sensitive-history.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

secret_marker='EXAMPLE-LEAK-DO-NOT-USE-7f4c2a'
secret_path='config/production.env'

contains_secret_in_reachable_history() {
  local repo_path="$1"
  local commit_oid

  while IFS= read -r commit_oid; do
    if git -C "$repo_path" grep -q -F "$secret_marker" "$commit_oid" --; then
      return 0
    fi
  done < <(git -C "$repo_path" rev-list --all)

  return 1
}

delete_original_refs() {
  local repo_path="$1"
  local refname

  while IFS= read -r refname; do
    git -C "$repo_path" update-ref -d "$refname"
  done < <(git -C "$repo_path" for-each-ref \
    --format='%(refname)' refs/original/)
}

remote_repo="$lab_root/service.git"
publisher_repo="$lab_root/publisher"

git init --quiet --bare --initial-branch=main "$remote_repo"
git init --quiet --initial-branch=main "$publisher_repo"
git -C "$publisher_repo" config user.name 'Service Author'
git -C "$publisher_repo" config user.email 'service@example.invalid'

printf 'service=payments\n' > "$publisher_repo/application.conf"
git -C "$publisher_repo" add application.conf
git -C "$publisher_repo" commit --quiet -m 'app: establish safe root'
safe_root="$(git -C "$publisher_repo" rev-parse HEAD)"

mkdir -p "$publisher_repo/config"
printf 'FAKE_API_TOKEN=%s\n' "$secret_marker" > \
  "$publisher_repo/$secret_path"
git -C "$publisher_repo" add "$secret_path"
git -C "$publisher_repo" commit --quiet -m 'config: accidentally add credential fixture'
leaked_commit="$(git -C "$publisher_repo" rev-parse HEAD)"
secret_blob="$(git -C "$publisher_repo" rev-parse "HEAD:$secret_path")"
git -C "$publisher_repo" tag -a release-leaked -m 'synthetic leaked release'
git -C "$publisher_repo" branch archive "$leaked_commit"

git -C "$publisher_repo" rm --quiet -- "$secret_path"
git -C "$publisher_repo" commit --quiet -m 'config: delete credential from current tree'
old_main="$(git -C "$publisher_repo" rev-parse HEAD)"
test ! -e "$publisher_repo/$secret_path"
git -C "$publisher_repo" grep -q -F "$secret_marker" "$leaked_commit" --

git -C "$publisher_repo" remote add origin "$remote_repo"
git -C "$publisher_repo" push --quiet -u origin main archive
git -C "$publisher_repo" push --quiet origin refs/tags/release-leaked
git -C "$publisher_repo" push --quiet origin \
  "$leaked_commit:refs/review/1/head"

stale_clone="$lab_root/stale-clone"
git clone --quiet --no-local "$remote_repo" "$stale_clone"
git -C "$stale_clone" config user.name 'Stale Developer'
git -C "$stale_clone" config user.email 'stale@example.invalid'
test "$(git -C "$stale_clone" rev-parse HEAD)" = "$old_main"
contains_secret_in_reachable_history "$stale_clone"

limited_cleanup="$lab_root/limited-cleanup.git"
git clone --quiet --mirror --no-local "$remote_repo" "$limited_cleanup"
FILTER_BRANCH_SQUELCH_WARNING=1 git -C "$limited_cleanup" filter-branch \
  --force \
  --index-filter "git rm --cached --quiet --ignore-unmatch -- '$secret_path'" \
  -- refs/heads/main \
  >/dev/null 2>&1
delete_original_refs "$limited_cleanup"
git -C "$limited_cleanup" reflog expire --expire=now --all
git -C "$limited_cleanup" gc --quiet --prune=now
contains_secret_in_reachable_history "$limited_cleanup"
git -C "$limited_cleanup" for-each-ref --contains "$leaked_commit" \
  --format='%(refname)' | grep -Eq \
  '^refs/(heads/archive|review/1/head|tags/release-leaked)$'

cleanup_repo="$lab_root/full-cleanup.git"
git clone --quiet --mirror --no-local "$remote_repo" "$cleanup_repo"
git -C "$cleanup_repo" config remote.origin.mirror false
contains_secret_in_reachable_history "$cleanup_repo"

FILTER_BRANCH_SQUELCH_WARNING=1 git -C "$cleanup_repo" filter-branch \
  --force \
  --index-filter "git rm --cached --quiet --ignore-unmatch -- '$secret_path'" \
  --tag-name-filter cat \
  -- --all \
  >/dev/null 2>&1

new_main="$(git -C "$cleanup_repo" rev-parse refs/heads/main)"
new_archive="$(git -C "$cleanup_repo" rev-parse refs/heads/archive)"
new_review="$(git -C "$cleanup_repo" rev-parse refs/review/1/head)"
new_tag_commit="$(git -C "$cleanup_repo" rev-parse 'refs/tags/release-leaked^{}')"
test "$new_main" != "$old_main"
test "$new_archive" != "$leaked_commit"
test "$new_review" = "$new_archive"
test "$new_tag_commit" = "$new_archive"
test "$(git -C "$cleanup_repo" rev-list --max-parents=0 "$new_main")" = \
  "$safe_root"

contains_secret_in_reachable_history "$cleanup_repo"
delete_original_refs "$cleanup_repo"
git -C "$cleanup_repo" reflog expire --expire=now --all
git -C "$cleanup_repo" gc --quiet --prune=now

if contains_secret_in_reachable_history "$cleanup_repo"; then
  printf 'Expected every rewritten ref to exclude the synthetic secret.\n' >&2
  exit 1
fi
if git -C "$cleanup_repo" cat-file -e "$secret_blob" 2>/dev/null; then
  printf 'Expected local cleanup GC to remove the old synthetic secret blob.\n' >&2
  exit 1
fi
git -C "$cleanup_repo" fsck --full --no-progress >/dev/null

git -C "$cleanup_repo" push --quiet --force origin \
  refs/heads/main:refs/heads/main \
  refs/heads/archive:refs/heads/archive \
  refs/tags/release-leaked:refs/tags/release-leaked \
  refs/review/1/head:refs/review/1/head

if contains_secret_in_reachable_history "$remote_repo"; then
  printf 'Expected rewritten service refs to exclude the synthetic secret.\n' >&2
  exit 1
fi
git -C "$remote_repo" cat-file -e "$secret_blob"

git -C "$stale_clone" fetch --quiet origin
git -C "$stale_clone" merge --quiet --no-edit origin/main
git -C "$stale_clone" push --quiet origin main
contains_secret_in_reachable_history "$remote_repo"

git -C "$cleanup_repo" push --quiet --force origin \
  refs/heads/main:refs/heads/main
if contains_secret_in_reachable_history "$remote_repo"; then
  printf 'Expected the restored clean main ref to exclude old ancestry.\n' >&2
  exit 1
fi

git -C "$remote_repo" reflog expire --expire=now --all
git -C "$remote_repo" gc --quiet --prune=now
if git -C "$remote_repo" cat-file -e "$secret_blob" 2>/dev/null; then
  printf 'Expected disposable service GC to remove unreachable leaked objects.\n' >&2
  exit 1
fi
git -C "$remote_repo" fsck --full --no-progress >/dev/null

git -C "$stale_clone" cat-file -e "$secret_blob"
fresh_clone="$lab_root/fresh-clone"
git clone --quiet --no-local "$remote_repo" "$fresh_clone"
if git -C "$fresh_clone" cat-file -e "$secret_blob" 2>/dev/null; then
  printf 'Expected a fresh clone to omit unreachable leaked objects.\n' >&2
  exit 1
fi
if contains_secret_in_reachable_history "$fresh_clone"; then
  printf 'Expected fresh-clone reachable history to remain clean.\n' >&2
  exit 1
fi

printf 'Sensitive path rewrite, ref coverage, object retention, and stale-clone recontamination passed.\n'
