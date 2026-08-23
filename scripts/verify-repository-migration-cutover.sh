#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-migration.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

commit_as() {
  local message="$1"
  local timestamp="$2"
  local author_name="$3"
  local author_email="$4"

  GIT_AUTHOR_NAME="$author_name" \
  GIT_AUTHOR_EMAIL="$author_email" \
  GIT_COMMITTER_NAME='Migration Fixture Importer' \
  GIT_COMMITTER_EMAIL='migration-importer@example.invalid' \
  GIT_AUTHOR_DATE="$timestamp" \
  GIT_COMMITTER_DATE="$timestamp" \
    git -C "$source_work" commit --quiet -m "$message"
}

refs_manifest() {
  local repo_path="$1"

  git -C "$repo_path" for-each-ref \
    --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
    LC_ALL=C sort
}

source_work="$lab_root/source-work"
source_service="$lab_root/source.git"
target_service="$lab_root/target.git"
staging_mirror="$lab_root/staging.git"

git init --quiet --initial-branch=main "$source_work"
git -C "$source_work" config user.name 'Migration Fixture Importer'
git -C "$source_work" config user.email 'migration-importer@example.invalid'
mkdir -p "$source_work/src"

printf '%s\n' \
  'Canonical Engineer <canonical@example.invalid> Legacy User <legacy@old.invalid>' \
  > "$source_work/.mailmap"
printf 'version=1\n' > "$source_work/src/app.conf"
git -C "$source_work" add .mailmap src/app.conf
commit_as 'fixture: import legacy base' '2026-08-14T09:00:00+00:00' \
  'Legacy User' 'legacy@old.invalid'
base_commit="$(git -C "$source_work" rev-parse HEAD)"

raw_identity="$(
  git -C "$source_work" log -1 --format='%an <%ae>' "$base_commit"
)"
mapped_identity="$(
  git -C "$source_work" log -1 --use-mailmap \
    --format='%aN <%aE>' "$base_commit"
)"
test "$raw_identity" = 'Legacy User <legacy@old.invalid>'
test "$mapped_identity" = 'Canonical Engineer <canonical@example.invalid>'
test "$(git -C "$source_work" rev-parse HEAD)" = "$base_commit"

git -C "$source_work" switch --quiet -c release/1.x
printf 'maintenance line\n' > "$source_work/RELEASE.txt"
git -C "$source_work" add RELEASE.txt
commit_as 'release: preserve maintenance branch' '2026-08-15T09:00:00+00:00' \
  'Release Maintainer' 'release@example.invalid'
release_commit="$(git -C "$source_work" rev-parse HEAD)"

git -C "$source_work" switch --quiet main
printf 'version=2\n' > "$source_work/src/app.conf"
git -C "$source_work" add src/app.conf
commit_as 'feat: advance imported main' '2026-08-16T09:00:00+00:00' \
  'Legacy User' 'legacy@old.invalid'
initial_main="$(git -C "$source_work" rev-parse HEAD)"
initial_tree="$(git -C "$source_work" rev-parse HEAD^{tree})"
GIT_COMMITTER_NAME='Migration Fixture Importer' \
GIT_COMMITTER_EMAIL='migration-importer@example.invalid' \
GIT_COMMITTER_DATE='2026-08-16T10:00:00+00:00' \
  git -C "$source_work" tag -a legacy-v1 \
    -m 'fixture: annotated legacy release' "$initial_main"
tag_oid="$(git -C "$source_work" rev-parse refs/tags/legacy-v1)"
git -C "$source_work" notes add \
  -m 'fixture: migration review reference REVIEW-100' "$initial_main"
git -C "$source_work" update-ref refs/archive/pre-migration "$release_commit"

git init --quiet --bare --initial-branch=main "$source_service"
git -C "$source_work" remote add source "$source_service"
git -C "$source_work" push --quiet source --all
git -C "$source_work" push --quiet source --tags
git -C "$source_work" push --quiet source \
  refs/notes/commits:refs/notes/commits \
  refs/archive/pre-migration:refs/archive/pre-migration
git -C "$source_service" symbolic-ref HEAD refs/heads/main

git clone --quiet --mirror --no-local "$source_service" "$staging_mirror"
test "$(git -C "$staging_mirror" rev-parse refs/heads/main)" = "$initial_main"

printf 'late source change\n' > "$source_work/src/late.txt"
git -C "$source_work" add src/late.txt
commit_as 'feat: arrive during migration window' '2026-08-17T09:00:00+00:00' \
  'Legacy User' 'legacy@old.invalid'
cutover_main="$(git -C "$source_work" rev-parse HEAD)"
GIT_COMMITTER_NAME='Migration Fixture Importer' \
GIT_COMMITTER_EMAIL='migration-importer@example.invalid' \
GIT_COMMITTER_DATE='2026-08-17T10:00:00+00:00' \
  git -C "$source_work" tag -a cutover-v2 \
    -m 'fixture: cutover candidate' "$cutover_main"
git -C "$source_work" push --quiet source main refs/tags/cutover-v2

test "$(git -C "$staging_mirror" rev-parse refs/heads/main)" = "$initial_main"
git -C "$staging_mirror" remote update --prune >/dev/null
test "$(git -C "$staging_mirror" rev-parse refs/heads/main)" = "$cutover_main"

source_refs="$lab_root/source.refs"
staging_refs="$lab_root/staging.refs"
refs_manifest "$source_service" > "$source_refs"
refs_manifest "$staging_mirror" > "$staging_refs"
cmp "$source_refs" "$staging_refs"

git init --quiet --bare --initial-branch=legacy-default "$target_service"
test "$(git -C "$target_service" symbolic-ref HEAD)" = \
  'refs/heads/legacy-default'
git -C "$staging_mirror" push --quiet --mirror "$target_service"
test "$(git -C "$target_service" symbolic-ref HEAD)" = \
  'refs/heads/legacy-default'
git -C "$target_service" symbolic-ref HEAD refs/heads/main

target_refs="$lab_root/target.refs"
refs_manifest "$target_service" > "$target_refs"
cmp "$source_refs" "$target_refs"
git -C "$target_service" fsck --full --strict --no-progress \
  > "$lab_root/target.fsck" 2>&1
test "$(git -C "$target_service" rev-parse refs/heads/main)" = "$cutover_main"
test "$(git -C "$target_service" rev-parse "$initial_main^{tree}")" = "$initial_tree"
test "$(git -C "$target_service" rev-parse refs/tags/legacy-v1)" = "$tag_oid"
test "$(git -C "$target_service" rev-parse refs/archive/pre-migration)" = \
  "$release_commit"
git -C "$target_service" notes show "$initial_main" |
  grep -F 'REVIEW-100' >/dev/null
cmp \
  <(git -C "$source_service" cat-file commit "$base_commit") \
  <(git -C "$target_service" cat-file commit "$base_commit")

printf '#!/usr/bin/env bash\nprintf "source is frozen after cutover\\n" >&2\nexit 1\n' \
  > "$source_service/hooks/pre-receive"
chmod +x "$source_service/hooks/pre-receive"

client="$lab_root/client"
git clone --quiet --no-local "$source_service" "$client"
git -C "$client" config user.name 'Post Cutover Client'
git -C "$client" config user.email 'post-cutover@example.invalid'
printf 'post-cutover work\n' > "$client/src/post-cutover.txt"
git -C "$client" add src/post-cutover.txt
git -C "$client" commit --quiet -m 'feat: continue after cutover'
post_cutover_commit="$(git -C "$client" rev-parse HEAD)"
source_before_reject="$(git -C "$source_service" rev-parse refs/heads/main)"
if git -C "$client" push origin main \
  > "$lab_root/source-reject.out" 2> "$lab_root/source-reject.err"; then
  printf 'Expected the frozen source service to reject a late push.\n' >&2
  exit 1
fi
grep -F 'source is frozen after cutover' "$lab_root/source-reject.err" >/dev/null
test "$(git -C "$source_service" rev-parse refs/heads/main)" = \
  "$source_before_reject"

git -C "$client" remote set-url origin "$target_service"
git -C "$client" push --quiet origin main
test "$(git -C "$target_service" rev-parse refs/heads/main)" = \
  "$post_cutover_commit"
test "$(git -C "$source_service" rev-parse refs/heads/main)" = "$cutover_main"

acceptance="$lab_root/acceptance"
git clone --quiet --no-local "$target_service" "$acceptance"
test -f "$acceptance/src/post-cutover.txt"
test "$(git -C "$acceptance" rev-parse HEAD)" = "$post_cutover_commit"

{
  printf 'source_head=%s\n' "$cutover_main"
  printf 'target_head_at_cutover=%s\n' "$cutover_main"
  printf 'source_default=%s\n' \
    "$(git -C "$source_service" symbolic-ref HEAD)"
  printf 'target_default=%s\n' \
    "$(git -C "$target_service" symbolic-ref HEAD)"
  printf 'legacy_identity=%s\n' "$raw_identity"
  printf 'display_identity=%s\n' "$mapped_identity"
  printf 'oid_policy=preserve\n'
} > "$lab_root/migration-manifest.txt"
grep -F 'oid_policy=preserve' "$lab_root/migration-manifest.txt" >/dev/null

printf 'Full-ref Git migration, OID preservation, mailmap boundary, source fencing, and client cutover passed.\n'
