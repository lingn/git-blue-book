#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-bundle-recovery.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

commit_at() {
  local message="$1"
  local timestamp="$2"

  GIT_AUTHOR_DATE="$timestamp" GIT_COMMITTER_DATE="$timestamp" \
    git -C "$source_repo" commit --quiet -m "$message"
}

refs_manifest() {
  local repo_path="$1"

  git -C "$repo_path" for-each-ref \
    --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
    LC_ALL=C sort
}

source_repo="$lab_root/source"
git init --quiet --initial-branch=main "$source_repo"
git -C "$source_repo" config user.name 'Backup Fixture'
git -C "$source_repo" config user.email 'backup@example.invalid'
git -C "$source_repo" config backup.fixture 'source-local-config'
mkdir -p "$source_repo/src"

printf 'version=1\n' > "$source_repo/src/app.conf"
git -C "$source_repo" add src/app.conf
commit_at 'fixture: establish recoverable base' '2026-08-10T09:00:00+00:00'
base_commit="$(git -C "$source_repo" rev-parse HEAD)"

git -C "$source_repo" switch --quiet -c release/1.x
printf 'release-line\n' > "$source_repo/RELEASE.txt"
git -C "$source_repo" add RELEASE.txt
commit_at 'release: prepare maintenance line' '2026-08-11T09:00:00+00:00'
release_commit="$(git -C "$source_repo" rev-parse HEAD)"

git -C "$source_repo" switch --quiet main
printf 'version=2\n' > "$source_repo/src/app.conf"
git -C "$source_repo" add src/app.conf
commit_at 'feat: advance main configuration' '2026-08-12T09:00:00+00:00'
full_tip="$(git -C "$source_repo" rev-parse HEAD)"
full_tree="$(git -C "$source_repo" rev-parse HEAD^{tree})"
git -C "$source_repo" tag -a v1.0 -m 'fixture: annotated release marker' "$full_tip"
tag_oid="$(git -C "$source_repo" rev-parse refs/tags/v1.0)"
git -C "$source_repo" notes add -m 'fixture: external review reference REVIEW-001' "$full_tip"
git -C "$source_repo" update-ref refs/archive/quarterly "$release_commit"

printf 'untracked operator note\n' > "$source_repo/operator-note.txt"
unreachable_blob="$(
  printf 'unreachable backup fixture\n' |
    git -C "$source_repo" hash-object -w --stdin
)"

full_refs="$lab_root/full.refs"
refs_manifest "$source_repo" > "$full_refs"
bundle_refs=()
while IFS= read -r ref_name; do
  bundle_refs+=("$ref_name")
done < <(
  git -C "$source_repo" for-each-ref --format='%(refname)' \
    refs/heads refs/tags refs/notes refs/archive
)
test "${#bundle_refs[@]}" -ge 5

full_bundle="$lab_root/full.bundle"
git -C "$source_repo" bundle create "$full_bundle" "${bundle_refs[@]}"
git -C "$source_repo" bundle verify "$full_bundle" \
  > "$lab_root/full-bundle.verify"
test -s "$full_bundle"

restored_repo="$lab_root/restored.git"
git init --quiet --bare --initial-branch=main "$restored_repo"
git -C "$restored_repo" fetch --quiet "$full_bundle" '+refs/*:refs/*'
git -C "$restored_repo" symbolic-ref HEAD refs/heads/main
refs_manifest "$restored_repo" > "$lab_root/restored.refs"
cmp "$full_refs" "$lab_root/restored.refs"
git -C "$restored_repo" fsck --full --no-progress \
  > "$lab_root/restored.fsck" 2>&1
test "$(git -C "$restored_repo" rev-parse refs/heads/main)" = "$full_tip"
test "$(git -C "$restored_repo" rev-parse refs/heads/main^{tree})" = "$full_tree"
test "$(git -C "$restored_repo" rev-parse refs/tags/v1.0)" = "$tag_oid"
test "$(git -C "$restored_repo" rev-parse refs/archive/quarterly)" = "$release_commit"
git -C "$restored_repo" notes show "$full_tip" | grep -F 'REVIEW-001' >/dev/null
if git -C "$restored_repo" cat-file -e "$unreachable_blob" 2>/dev/null; then
  printf 'Expected an unreferenced blob to stay outside the logical bundle.\n' >&2
  exit 1
fi

printf 'version=3\n' > "$source_repo/src/app.conf"
git -C "$source_repo" add src/app.conf
commit_at 'feat: advance after full backup' '2026-08-13T09:00:00+00:00'
incremental_tip="$(git -C "$source_repo" rev-parse HEAD)"

incremental_bundle="$lab_root/incremental.bundle"
git -C "$source_repo" bundle create "$incremental_bundle" \
  "$full_tip..refs/heads/main"
empty_repo="$lab_root/empty.git"
git init --quiet --bare --initial-branch=main "$empty_repo"
if git -C "$empty_repo" bundle verify "$incremental_bundle" \
  > "$lab_root/incremental-empty.out" \
  2> "$lab_root/incremental-empty.err"; then
  printf 'Expected an incremental bundle to require its prerequisite commit.\n' >&2
  exit 1
fi
grep -F "$full_tip" "$lab_root/incremental-empty.err" >/dev/null

git -C "$restored_repo" bundle verify "$incremental_bundle" \
  > "$lab_root/incremental-restored.verify"
git -C "$restored_repo" fetch --quiet "$incremental_bundle" \
  '+refs/heads/main:refs/heads/main'
test "$(git -C "$restored_repo" rev-parse refs/heads/main)" = "$incremental_tip"
git -C "$restored_repo" fsck --full --no-progress \
  > "$lab_root/incremental-restored.fsck" 2>&1

printf '#!/usr/bin/env bash\nprintf "source-only hook\\n"\n' \
  > "$source_repo/.git/hooks/pre-commit"
chmod +x "$source_repo/.git/hooks/pre-commit"

mirror_repo="$lab_root/mirror.git"
git clone --quiet --mirror --no-local "$source_repo" "$mirror_repo"
test "$(git -C "$mirror_repo" rev-parse refs/heads/main)" = "$incremental_tip"
test "$(git -C "$mirror_repo" rev-parse refs/notes/commits)" = \
  "$(git -C "$source_repo" rev-parse refs/notes/commits)"
test "$(git -C "$mirror_repo" config --get remote.origin.mirror)" = 'true'
if git -C "$mirror_repo" config --get backup.fixture >/dev/null; then
  printf 'Expected clone --mirror not to copy arbitrary source-local config.\n' >&2
  exit 1
fi
test ! -e "$mirror_repo/hooks/pre-commit"
if git -C "$mirror_repo" cat-file -e "$unreachable_blob" 2>/dev/null; then
  printf 'Expected a transport mirror not to copy an unreferenced blob.\n' >&2
  exit 1
fi

git -C "$mirror_repo" update-ref refs/heads/mirror-only "$incremental_tip"
git -C "$source_repo" branch --delete --force release/1.x >/dev/null
git -C "$source_repo" tag --delete v1.0 >/dev/null
git -C "$source_repo" tag -a v2.0 -m 'fixture: replacement release marker' \
  "$incremental_tip"
git -C "$mirror_repo" remote update --prune >/dev/null
if git -C "$mirror_repo" show-ref --verify --quiet refs/heads/release/1.x; then
  printf 'Expected mirror pruning to propagate a deleted source branch.\n' >&2
  exit 1
fi
if git -C "$mirror_repo" show-ref --verify --quiet refs/tags/v1.0; then
  printf 'Expected mirror pruning to propagate a deleted source tag.\n' >&2
  exit 1
fi
if git -C "$mirror_repo" show-ref --verify --quiet refs/heads/mirror-only; then
  printf 'Expected mirror pruning to remove a ref absent from the source.\n' >&2
  exit 1
fi
git -C "$mirror_repo" show-ref --verify --quiet refs/tags/v2.0

test ! -e "$mirror_repo/operator-note.txt"
test "$base_commit" != "$incremental_tip"

printf 'Full and incremental bundles, ref-complete restore, mirror omissions, and prune propagation passed.\n'
