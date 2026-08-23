#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-disaster-recovery.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

refs_manifest() {
  local repo_path="$1"

  git -C "$repo_path" for-each-ref \
    --format='%(refname) %(objecttype) %(objectname) %(*objectname)' \
    refs/heads refs/tags refs/notes refs/archive |
    LC_ALL=C sort
}

primary="$lab_root/primary.git"
quarantined_primary="$lab_root/quarantined-primary.git"
standby="$lab_root/standby.git"
recovered_primary="$lab_root/recovered-primary.git"
producer="$lab_root/producer"

git init --quiet --initial-branch=main "$producer"
git -C "$producer" config user.name 'Disaster Recovery Fixture'
git -C "$producer" config user.email 'disaster-recovery@example.invalid'
mkdir -p "$producer/src"
printf 'version=1\n' > "$producer/src/service.conf"
git -C "$producer" add src/service.conf
GIT_AUTHOR_DATE='2026-08-18T09:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-18T09:00:00+00:00' \
  git -C "$producer" commit --quiet -m 'fixture: establish primary history'
checkpoint_commit="$(git -C "$producer" rev-parse HEAD)"
checkpoint_tree="$(git -C "$producer" rev-parse HEAD^{tree})"
git -C "$producer" tag -a checkpoint-v1 \
  -m 'fixture: checkpoint release' "$checkpoint_commit"
git -C "$producer" notes add \
  -m 'fixture: checkpoint review REVIEW-DR-1' "$checkpoint_commit"
git -C "$producer" update-ref refs/archive/checkpoint "$checkpoint_commit"

git init --quiet --bare --initial-branch=main "$primary"
git -C "$producer" remote add primary "$primary"
git -C "$producer" push --quiet primary --all
git -C "$producer" push --quiet primary --tags
git -C "$producer" push --quiet primary \
  refs/notes/commits:refs/notes/commits \
  refs/archive/checkpoint:refs/archive/checkpoint
git -C "$primary" symbolic-ref HEAD refs/heads/main

git clone --quiet --mirror --no-local "$primary" "$standby"
test "$(git -C "$standby" rev-parse refs/heads/main)" = "$checkpoint_commit"
test ! -e "$standby/objects/info/alternates"
if git -C "$standby" config --get extensions.partialClone >/dev/null; then
  printf 'Expected the standby fixture to be a self-contained full clone.\n' >&2
  exit 1
fi

printf 'version=2\n' > "$producer/src/service.conf"
printf 'late primary commit\n' > "$producer/src/late.txt"
git -C "$producer" add src/service.conf src/late.txt
GIT_AUTHOR_DATE='2026-08-18T10:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-18T10:00:00+00:00' \
  git -C "$producer" commit --quiet -m 'feat: arrive after standby checkpoint'
late_commit="$(git -C "$producer" rev-parse HEAD)"
late_tree="$(git -C "$producer" rev-parse HEAD^{tree})"
git -C "$producer" push --quiet primary main
test "$(git -C "$primary" rev-parse refs/heads/main)" = "$late_commit"
test "$(git -C "$standby" rev-parse refs/heads/main)" = "$checkpoint_commit"

primary_refs_before_failure="$lab_root/primary-before-failure.refs"
refs_manifest "$primary" > "$primary_refs_before_failure"

donor="$lab_root/donor"
git clone --quiet --no-local "$primary" "$donor"
test "$(git -C "$donor" rev-parse refs/heads/main)" = "$late_commit"

mv "$primary" "$quarantined_primary"
if git -C "$producer" ls-remote primary \
  > "$lab_root/primary-unavailable.out" \
  2> "$lab_root/primary-unavailable.err"; then
  printf 'Expected the primary endpoint to be unavailable after isolation.\n' >&2
  exit 1
fi

standby_commit="$(git -C "$standby" rev-parse refs/heads/main)"
test "$standby_commit" = "$checkpoint_commit"
test "$(git -C "$donor" rev-list --count "$standby_commit..$late_commit")" -eq 1
git -C "$standby" fsck --full --strict --no-progress \
  > "$lab_root/standby.fsck" 2>&1

donor_bundle="$lab_root/donor-incremental.bundle"
git -C "$donor" bundle create "$donor_bundle" \
  "$checkpoint_commit..refs/heads/main"
git -C "$standby" bundle verify "$donor_bundle" \
  > "$lab_root/donor-bundle.verify"
git -C "$standby" fetch --quiet "$donor_bundle" \
  '+refs/heads/main:refs/recovery/donor/main'
test "$(git -C "$standby" rev-parse refs/recovery/donor/main)" = "$late_commit"
test "$(git -C "$standby" rev-parse refs/recovery/donor/main^{tree})" = \
  "$late_tree"
test "$(git -C "$standby" show -s --format='%P' "$late_commit")" = \
  "$checkpoint_commit"

git -C "$standby" update-ref refs/heads/main \
  "$late_commit" "$checkpoint_commit"
test "$(git -C "$standby" rev-parse refs/heads/main)" = "$late_commit"
if git -C "$standby" update-ref refs/heads/main \
  "$checkpoint_commit" "$checkpoint_commit" \
  > "$lab_root/stale-promotion.out" \
  2> "$lab_root/stale-promotion.err"; then
  printf 'Expected a stale promotion lease to be rejected.\n' >&2
  exit 1
fi

git init --quiet --bare --initial-branch=main "$recovered_primary"
git -C "$recovered_primary" fetch --quiet "$standby" \
  '+refs/heads/*:refs/heads/*' \
  '+refs/tags/*:refs/tags/*' \
  '+refs/notes/*:refs/notes/*' \
  '+refs/archive/*:refs/archive/*'
git -C "$recovered_primary" symbolic-ref HEAD refs/heads/main
git -C "$recovered_primary" fsck --full --strict --no-progress \
  > "$lab_root/recovered-primary.fsck" 2>&1
test ! -e "$recovered_primary/objects/info/alternates"

recovered_refs="$lab_root/recovered.refs"
refs_manifest "$recovered_primary" > "$recovered_refs"
cmp "$primary_refs_before_failure" "$recovered_refs"
test "$(git -C "$recovered_primary" rev-parse refs/heads/main)" = "$late_commit"
test "$(git -C "$recovered_primary" rev-parse "$checkpoint_commit^{tree}")" = \
  "$checkpoint_tree"
git -C "$recovered_primary" notes show "$checkpoint_commit" |
  grep -F 'REVIEW-DR-1' >/dev/null

printf '#!/usr/bin/env bash\nprintf "old primary is fenced after failover\\n" >&2\nexit 1\n' \
  > "$quarantined_primary/hooks/pre-receive"
chmod +x "$quarantined_primary/hooks/pre-receive"

acceptance="$lab_root/acceptance"
git clone --quiet --no-local "$recovered_primary" "$acceptance"
git -C "$acceptance" config user.name 'Failover Acceptance Client'
git -C "$acceptance" config user.email 'failover-client@example.invalid'
test "$(git -C "$acceptance" rev-parse HEAD)" = "$late_commit"
test "$(cat "$acceptance/src/service.conf")" = 'version=2'
printf 'accepted after failover\n' > "$acceptance/src/post-failover.txt"
git -C "$acceptance" add src/post-failover.txt
git -C "$acceptance" commit --quiet -m 'feat: continue on recovered primary'
post_failover_commit="$(git -C "$acceptance" rev-parse HEAD)"
git -C "$acceptance" push --quiet origin main
test "$(git -C "$recovered_primary" rev-parse refs/heads/main)" = \
  "$post_failover_commit"

git -C "$acceptance" remote add old-primary "$quarantined_primary"
if git -C "$acceptance" push old-primary main \
  > "$lab_root/old-primary-reject.out" \
  2> "$lab_root/old-primary-reject.err"; then
  printf 'Expected the returned old primary to stay fenced.\n' >&2
  exit 1
fi
grep -F 'old primary is fenced after failover' \
  "$lab_root/old-primary-reject.err" >/dev/null
test "$(git -C "$quarantined_primary" rev-parse refs/heads/main)" = "$late_commit"
test "$(git -C "$recovered_primary" rev-parse refs/heads/main)" = \
  "$post_failover_commit"

{
  printf 'checkpoint=%s\n' "$checkpoint_commit"
  printf 'primary_at_failure=%s\n' "$late_commit"
  printf 'standby_at_failure=%s\n' "$standby_commit"
  printf 'lag_commits=1\n'
  printf 'donor_candidate=%s\n' "$late_commit"
  printf 'promoted=%s\n' "$late_commit"
  printf 'post_failover=%s\n' "$post_failover_commit"
  printf 'old_primary_fenced=true\n'
} > "$lab_root/failover-manifest.txt"
grep -F 'lag_commits=1' "$lab_root/failover-manifest.txt" >/dev/null
grep -F 'old_primary_fenced=true' "$lab_root/failover-manifest.txt" >/dev/null

printf 'Replication lag detection, donor recovery, conditional promotion, acceptance, and old-primary fencing passed.\n'
