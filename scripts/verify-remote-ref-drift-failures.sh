#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d /tmp/git-blue-book-remote-ref-drift.XXXXXX)"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

seed="$lab_root/seed"
remote="$lab_root/remote.git"
client="$lab_root/client"

git init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name 'Remote Ref Lab'
git -C "$seed" config user.email 'remote-ref@example.invalid'
printf 'main=v1\n' > "$seed/state.txt"
git -C "$seed" add state.txt
git -C "$seed" commit --quiet -m 'main: initial state'
main_v1="$(git -C "$seed" rev-parse HEAD)"

git -C "$seed" switch --quiet --create legacy
printf 'legacy=true\n' >> "$seed/state.txt"
git -C "$seed" add state.txt
git -C "$seed" commit --quiet -m 'legacy: old line'
legacy_oid="$(git -C "$seed" rev-parse HEAD)"

git -C "$seed" switch --quiet main
printf 'stable=false\n' >> "$seed/state.txt"
git -C "$seed" add state.txt
git -C "$seed" commit --quiet -m 'main: prepare stable line'
stable_oid="$(git -C "$seed" rev-parse HEAD)"

git clone --quiet --bare "$seed" "$remote"
git -C "$remote" symbolic-ref HEAD refs/heads/main
git -C "$seed" remote add origin "$remote"
git -C "$seed" push --quiet origin main legacy

git clone --quiet "$remote" "$client"
git -C "$client" config user.name 'Client Ref Lab'
git -C "$client" config user.email 'client-ref@example.invalid'
git -C "$client" switch --quiet --track -c legacy origin/legacy
git -C "$client" switch --quiet main

test "$(git -C "$client" rev-parse refs/remotes/origin/legacy)" = "$legacy_oid"
test "$(git -C "$client" rev-parse --symbolic-full-name refs/remotes/origin/HEAD)" = refs/remotes/origin/main
test "$(git -C "$client" config --get branch.legacy.merge)" = refs/heads/legacy

# A remote branch rename is a create plus a delete. A normal fetch discovers
# the new name but deliberately keeps the old remote-tracking ref until prune.
git -C "$remote" update-ref refs/heads/stable "$stable_oid"
git -C "$remote" update-ref refs/heads/archive/legacy "$legacy_oid"
git -C "$remote" update-ref -d refs/heads/legacy "$legacy_oid"
git -C "$client" fetch --quiet origin
test "$(git -C "$client" rev-parse refs/remotes/origin/archive/legacy)" = "$legacy_oid"
test "$(git -C "$client" rev-parse refs/remotes/origin/legacy)" = "$legacy_oid"

# Keep an explicit local recovery ref before deleting the stale tracking ref.
git -C "$client" update-ref refs/recovery/remote/legacy "$legacy_oid"
git -C "$client" fetch --quiet --prune origin
if git -C "$client" rev-parse --verify --quiet refs/remotes/origin/legacy >/dev/null; then
  printf 'Expected prune to remove the deleted remote-tracking ref.\n' >&2
  exit 1
fi
test "$(git -C "$client" rev-parse refs/recovery/remote/legacy)" = "$legacy_oid"
# Pruning a remote-tracking ref does not delete a local branch or rewrite its
# upstream configuration. Reattach it explicitly after confirming the rename.
test "$(git -C "$client" rev-parse refs/heads/legacy)" = "$legacy_oid"
test "$(git -C "$client" config --get branch.legacy.merge)" = refs/heads/legacy
git -C "$client" branch --set-upstream-to=origin/archive/legacy legacy >/dev/null
test "$(git -C "$client" config --get branch.legacy.merge)" = refs/heads/archive/legacy

# The advertised default branch is a remote symbolic ref. The local
# origin/HEAD is a cache and must be refreshed after the server changes it.
git -C "$remote" symbolic-ref HEAD refs/heads/stable
git -C "$client" fetch --quiet origin
git -C "$client" remote set-head origin --auto >/dev/null
test "$(git -C "$client" symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/stable
test "$(git -C "$client" rev-parse refs/remotes/origin/stable)" = "$stable_oid"

# A tag ref is a separate namespace. Retargeting it on the source is rejected
# by an ordinary fetch; force-fetching it is a deliberate local mutation.
git -C "$remote" update-ref refs/tags/v1 "$main_v1"
git -C "$client" fetch --quiet origin
test "$(git -C "$client" rev-parse refs/tags/v1)" = "$main_v1"
git -C "$remote" update-ref refs/tags/v1 "$stable_oid"
tag_before="$(git -C "$client" rev-parse refs/tags/v1)"
# Depending on the negotiated refspec and Git version, an ordinary fetch can
# finish successfully while refusing to overwrite an existing tag. The state,
# rather than the exit code alone, is the evidence that matters here.
git -C "$client" fetch origin >"$lab_root/tag-fetch.stdout" 2>"$lab_root/tag-fetch.stderr"
test "$(git -C "$client" rev-parse refs/tags/v1)" = "$tag_before"
git -C "$client" update-ref refs/recovery/tags/v1 "$tag_before"
git -C "$client" fetch --quiet origin '+refs/tags/v1:refs/tags/v1'
test "$(git -C "$client" rev-parse refs/tags/v1)" = "$stable_oid"
test "$(git -C "$client" rev-parse refs/recovery/tags/v1)" = "$tag_before"

# Two independent listings are not one transaction. A source update between
# them must be treated as a race and resolved with a fresh, fixed snapshot.
snapshot_before="$(git ls-remote "$remote" refs/heads/stable)"
git -C "$remote" update-ref refs/heads/stable "$main_v1"
snapshot_after="$(git ls-remote "$remote" refs/heads/stable)"
test "$snapshot_before" != "$snapshot_after"
combined_snapshot="$(git ls-remote "$remote" refs/heads/stable refs/heads/archive/legacy)"
test "$(printf '%s\n' "$combined_snapshot" | wc -l | tr -d ' ')" = 2

printf 'Remote ref rename, prune recovery, default-branch refresh, tag retarget, and snapshot race boundaries passed.\n'
