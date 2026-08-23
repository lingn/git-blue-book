#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "/tmp/git-blue-book-push-boundaries.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
export GIT_PAGER=cat
export LC_ALL=C
unset GIT_CONFIG_COUNT

refs_manifest() {
  local repository_path="$1"
  git -C "$repository_path" for-each-ref \
    --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
    LC_ALL=C sort
}

client_state() {
  local repository_path="$1"
  local output_path="$2"
  {
    printf 'HEAD=%s\n' "$(git -C "$repository_path" rev-parse HEAD)"
    refs_manifest "$repository_path"
    git -C "$repository_path" status --porcelain=v2 --branch
    printf 'WORKTREE=%s\n' "$(sha256_file "$repository_path/service.txt")"
  } > "$output_path"
}

sha256_file() {
  local file_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    sha256sum "$file_path" | awk '{print $1}'
  fi
}

publisher="$lab_root/publisher"
remote="$lab_root/remote.git"
alice="$lab_root/alice"
bob="$lab_root/bob"
remote_url="file://$remote"

git init --quiet --initial-branch=main "$publisher"
git -C "$publisher" config user.name 'Push Boundary Fixture'
git -C "$publisher" config user.email 'push-boundary@example.invalid'
printf 'base\n' > "$publisher/service.txt"
git -C "$publisher" add service.txt
GIT_AUTHOR_DATE='2026-08-22T02:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-22T02:00:00+00:00' \
  git -C "$publisher" commit --quiet -m 'fixture: establish remote main'

git init --quiet --bare --initial-branch=main "$remote"
git -C "$publisher" remote add origin "$remote_url"
git -C "$publisher" push --quiet origin main
git -C "$remote" symbolic-ref HEAD refs/heads/main
git -C "$remote" config receive.denyNonFastForwards true

git clone --quiet --no-local "$remote_url" "$alice"
git clone --quiet --no-local "$remote_url" "$bob"
for client in "$alice" "$bob"
do
  git -C "$client" config user.name "Client $(basename "$client")"
  git -C "$client" config user.email "$(basename "$client")@example.invalid"
done

base_oid="$(git -C "$alice" rev-parse HEAD)"
test "$(git -C "$bob" rev-parse HEAD)" = "$base_oid"

printf 'alice change\n' > "$alice/alice.txt"
git -C "$alice" add alice.txt
GIT_AUTHOR_DATE='2026-08-22T02:10:00+00:00' \
GIT_COMMITTER_DATE='2026-08-22T02:10:00+00:00' \
  git -C "$alice" commit --quiet -m 'feat: alice change'
alice_oid="$(git -C "$alice" rev-parse HEAD)"
git -C "$alice" push --quiet origin main
test "$(git -C "$remote" rev-parse refs/heads/main)" = "$alice_oid"
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$base_oid"

printf 'bob change\n' > "$bob/bob.txt"
git -C "$bob" add bob.txt
GIT_AUTHOR_DATE='2026-08-22T02:11:00+00:00' \
GIT_COMMITTER_DATE='2026-08-22T02:11:00+00:00' \
  git -C "$bob" commit --quiet -m 'feat: bob change'
bob_oid="$(git -C "$bob" rev-parse HEAD)"
bob_before_reject="$lab_root/bob-before-reject.txt"
client_state "$bob" "$bob_before_reject"
stale_status=0
git -C "$bob" push origin main \
  > "$lab_root/stale-push.stdout" \
  2> "$lab_root/stale-push.stderr" || stale_status="$?"
if test "$stale_status" -eq 0; then
  printf 'Expected a stale non-fast-forward push to fail.\n' >&2
  exit 1
fi
grep -E 'non-fast-forward|rejected|fetch first' \
  "$lab_root/stale-push.stderr" "$lab_root/stale-push.stdout" >/dev/null
test "$(git -C "$remote" rev-parse refs/heads/main)" = "$alice_oid"
test "$(git -C "$bob" rev-parse HEAD)" = "$bob_oid"
client_state "$bob" "$lab_root/bob-after-reject.txt"
cmp "$bob_before_reject" "$lab_root/bob-after-reject.txt"

tracking_before="$(git -C "$bob" rev-parse refs/remotes/origin/main)"
head_before_fetch="$(git -C "$bob" rev-parse HEAD)"
git -C "$bob" fetch --quiet origin main
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$alice_oid"
test "$(git -C "$bob" rev-parse HEAD)" = "$head_before_fetch"
test "$tracking_before" != "$alice_oid"
test -s "$(git -C "$bob" rev-parse --path-format=absolute --git-path FETCH_HEAD)"

git -C "$bob" merge --quiet --no-edit refs/remotes/origin/main
merge_oid="$(git -C "$bob" rev-parse HEAD)"
test "$(git -C "$bob" rev-parse HEAD^1)" = "$bob_oid"
test "$(git -C "$bob" rev-parse HEAD^2)" = "$alice_oid"
git -C "$bob" push --quiet origin main
test "$(git -C "$remote" rev-parse refs/heads/main)" = "$merge_oid"

bad_url="file://$lab_root/missing-remote.git"
before_bad_probe="$(refs_manifest "$remote")"
bad_status=0
git -C "$bob" ls-remote --exit-code "$bad_url" refs/heads/main \
  > "$lab_root/bad-endpoint.stdout" \
  2> "$lab_root/bad-endpoint.stderr" || bad_status="$?"
if test "$bad_status" -eq 0; then
  printf 'Expected a missing endpoint probe to fail.\n' >&2
  exit 1
fi
test "$(refs_manifest "$remote")" = "$before_bad_probe"
test "$(git -C "$bob" rev-parse refs/remotes/origin/main)" = "$merge_oid"

old_url="$(git -C "$bob" remote get-url origin)"
bob_before_url_change="$lab_root/bob-before-url-change.txt"
client_state "$bob" "$bob_before_url_change"
git -C "$bob" remote set-url origin "$bad_url"
test "$(git -C "$bob" remote get-url origin)" = "$bad_url"
git -C "$bob" remote set-url origin "$old_url"
test "$(git -C "$bob" remote get-url origin)" = "$old_url"
client_state "$bob" "$lab_root/bob-after-url-change.txt"
cmp "$bob_before_url_change" "$lab_root/bob-after-url-change.txt"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'while read -r old new ref' \
  'do' \
  '  if test "$ref" = "refs/heads/main"; then' \
  '    printf "protected main: use review flow\\n" >&2' \
  '    exit 1' \
  '  fi' \
  'done' \
  'exit 0' > "$remote/hooks/pre-receive"
chmod +x "$remote/hooks/pre-receive"

printf 'protected attempt\n' > "$alice/protected.txt"
git -C "$alice" add protected.txt
GIT_AUTHOR_DATE='2026-08-22T02:20:00+00:00' \
GIT_COMMITTER_DATE='2026-08-22T02:20:00+00:00' \
  git -C "$alice" commit --quiet -m 'feat: protected branch attempt'
protected_oid="$(git -C "$alice" rev-parse HEAD)"
remote_before_hook="$(git -C "$remote" rev-parse refs/heads/main)"
hook_status=0
git -C "$alice" push origin main \
  > "$lab_root/protected-push.stdout" \
  2> "$lab_root/protected-push.stderr" || hook_status="$?"
if test "$hook_status" -eq 0; then
  printf 'Expected the protected-main hook to reject direct push.\n' >&2
  exit 1
fi
test -s "$lab_root/protected-push.stderr" || \
  test -s "$lab_root/protected-push.stdout"
test "$(git -C "$remote" rev-parse refs/heads/main)" = "$remote_before_hook"
test "$(git -C "$alice" rev-parse HEAD)" = "$protected_oid"
git -C "$alice" push --quiet origin \
  HEAD:refs/heads/review/protected-attempt
test "$(git -C "$remote" rev-parse refs/heads/review/protected-attempt)" = \
  "$protected_oid"
test "$(git -C "$alice" ls-remote --exit-code origin refs/heads/main | awk '{print $1}')" = \
  "$remote_before_hook"

printf 'Push boundary endpoint, non-fast-forward, fetch side effect, protected ref, and URL rollback checks passed.\n'
