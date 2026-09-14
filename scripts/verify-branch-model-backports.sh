#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-branch-model.XXXXXX")"
cleanup() {
  if test "${KEEP_BRANCH_MODEL_LAB:-0}" = 1; then
    printf 'Preserved branch model lab: %s\n' "$lab_root"
  else
    rm -rf -- "$lab_root"
  fi
}
trap cleanup EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
export GIT_PAGER=cat
export LC_ALL=C
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
git -C "$lab_root" init --quiet --initial-branch=main repository
git -C "$repo" config user.name 'Branch Model Fixture'
git -C "$repo" config user.email 'branch-model@example.invalid'

printf 'guard=off\n' > "$repo/app.conf"
git -C "$repo" add app.conf
git -C "$repo" commit --quiet -m 'feat: establish release baseline'
release_source="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag -a v1.0.0 "$release_source" -m 'Release v1.0.0'
test "$(git -C "$repo" rev-parse 'v1.0.0^{}')" = "$release_source"

printf 'main-only development\n' > "$repo/next-only.txt"
git -C "$repo" add next-only.txt
git -C "$repo" commit --quiet -m 'feat: continue main development'

printf 'guard=on\n' > "$repo/app.conf"
git -C "$repo" add app.conf
git -C "$repo" commit --quiet -m 'fix: enable request guard'
source_fix_oid="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet --create release/1.x "$release_source"
printf 'support_line=1.x\n' > "$repo/release.conf"
git -C "$repo" add release.conf
git -C "$repo" commit --quiet -m 'chore: record maintenance line'
target_old_oid="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" cherry-pick --quiet "$source_fix_oid" >/dev/null
picked_oid="$(git -C "$repo" rev-parse HEAD)"

test "$picked_oid" != "$source_fix_oid"
test "$(git -C "$repo" rev-parse "$picked_oid^")" = "$target_old_oid"
test "$(git -C "$repo" show "$picked_oid:app.conf")" = 'guard=on'
if git -C "$repo" cat-file -e "$picked_oid:next-only.txt" 2>/dev/null; then
  printf 'Backport unexpectedly copied main-only development.\n' >&2
  exit 1
fi

patch_id_for_commit() {
  git -C "$repo" show --pretty=format: --binary "$1" |
    git patch-id --stable |
    awk 'NR == 1 { print $1 }'
}

source_patch_id="$(patch_id_for_commit "$source_fix_oid")"
picked_patch_id="$(patch_id_for_commit "$picked_oid")"
test -n "$source_patch_id"
test "$source_patch_id" = "$picked_patch_id"
git -C "$repo" cherry main release/1.x > "$lab_root/release-vs-main.cherry"
grep -Fx -- "- $picked_oid" "$lab_root/release-vs-main.cherry" >/dev/null
if git -C "$repo" merge-base --is-ancestor "$source_fix_oid" "$picked_oid"; then
  printf 'Backport unexpectedly contains the source commit as an ancestor.\n' >&2
  exit 1
fi

git -C "$repo" switch --quiet main
git -C "$repo" switch --quiet --create feature/obsolete
printf 'recoverable branch work\n' > "$repo/experiment.txt"
git -C "$repo" add experiment.txt
git -C "$repo" commit --quiet -m 'feat: preserve experimental work'
obsolete_tip="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" switch --quiet main
git -C "$repo" branch -D feature/obsolete >/dev/null
if git -C "$repo" show-ref --verify --quiet refs/heads/feature/obsolete; then
  printf 'Deleted feature branch still exists.\n' >&2
  exit 1
fi
git -C "$repo" cat-file -e "$obsolete_tip^{commit}"

recovery_ref='refs/recovery/branch-model/feature-obsolete'
git -C "$repo" update-ref "$recovery_ref" "$obsolete_tip" ''
test "$(git -C "$repo" rev-parse "$recovery_ref")" = "$obsolete_tip"
git -C "$repo" branch recovered/feature-obsolete "$recovery_ref"
test "$(git -C "$repo" rev-parse refs/heads/recovered/feature-obsolete)" = "$obsolete_tip"
test "$(git -C "$repo" show "$obsolete_tip:experiment.txt")" = 'recoverable branch work'
test -z "$(git -C "$repo" status --short)"

printf 'Branch creation points, backport patch equivalence, maintenance isolation, deletion, and recovery refs passed.\n'
