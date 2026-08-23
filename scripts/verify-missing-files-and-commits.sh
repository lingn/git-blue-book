#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-missing-state.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
export GIT_PAGER=cat
export LC_ALL=C
unset GIT_CONFIG_COUNT

sha256_file() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    sha256sum "$file_path" | awk '{print $1}'
  fi
}

local_state_fingerprint() {
  local repository_path="$1"
  local output_path="$2"
  local index_path

  index_path="$(git -C "$repository_path" rev-parse \
    --path-format=absolute --git-path index)"
  {
    printf 'HEAD %s\n' "$(git -C "$repository_path" rev-parse HEAD)"
    printf 'INDEX %s\n' "$(sha256_file "$index_path")"
    printf 'RUNBOOK %s\n' "$(sha256_file "$repository_path/docs/runbook.md")"
    printf 'STABLE %s\n' "$(sha256_file "$repository_path/stable.txt")"
    GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" \
      status --porcelain=v2 --branch
  } > "$output_path"
}

repository="$lab_root/repository"
git init --quiet --initial-branch=main "$repository"
git -C "$repository" config user.name 'Missing State Fixture'
git -C "$repository" config user.email 'missing-state@example.invalid'
mkdir -p "$repository/docs" "$repository/sparse"
printf 'runbook version one\n' > "$repository/docs/runbook.md"
printf 'stable sentinel\n' > "$repository/stable.txt"
printf 'sparse payload\n' > "$repository/sparse/only.txt"
printf '*.local\n' > "$repository/.gitignore"
git -C "$repository" add .gitignore docs/runbook.md sparse/only.txt stable.txt
GIT_AUTHOR_DATE='2026-08-21T13:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T13:00:00+00:00' \
  git -C "$repository" commit --quiet -m 'fixture: establish tracked paths'
base_oid="$(git -C "$repository" rev-parse HEAD)"
runbook_blob="$(git -C "$repository" rev-parse HEAD:docs/runbook.md)"
stable_blob="$(git -C "$repository" rev-parse HEAD:stable.txt)"
cp "$repository/docs/runbook.md" "$lab_root/runbook.expected"

mv "$repository/docs/runbook.md" "$lab_root/runbook.worktree-deletion"
git -C "$repository" status --porcelain=v2 -- docs/runbook.md \
  > "$lab_root/unstaged-delete.status"
grep -F 'docs/runbook.md' "$lab_root/unstaged-delete.status" >/dev/null
test "$(git -C "$repository" ls-files --stage -- docs/runbook.md | awk '{print $2}')" = \
  "$runbook_blob"
test "$(git -C "$repository" rev-parse HEAD:docs/runbook.md)" = \
  "$runbook_blob"
git -C "$repository" restore --worktree -- docs/runbook.md
cmp "$lab_root/runbook.expected" "$repository/docs/runbook.md"
test "$(git -C "$repository" rev-parse HEAD)" = "$base_oid"
test "$(git -C "$repository" rev-parse HEAD:stable.txt)" = "$stable_blob"
test -z "$(git -C "$repository" status --porcelain -- docs/runbook.md)"

git -C "$repository" rm --quiet docs/runbook.md
git -C "$repository" status --porcelain=v2 -- docs/runbook.md \
  > "$lab_root/staged-delete.status"
grep -F 'docs/runbook.md' "$lab_root/staged-delete.status" >/dev/null
test -z "$(git -C "$repository" ls-files --stage -- docs/runbook.md)"
test "$(git -C "$repository" rev-parse HEAD:docs/runbook.md)" = \
  "$runbook_blob"
git -C "$repository" restore --source="$base_oid" \
  --staged --worktree -- docs/runbook.md
cmp "$lab_root/runbook.expected" "$repository/docs/runbook.md"
test "$(git -C "$repository" ls-files --stage -- docs/runbook.md | awk '{print $2}')" = \
  "$runbook_blob"
test -z "$(git -C "$repository" status --porcelain -- docs/runbook.md)"

git -C "$repository" sparse-checkout set sparse
test ! -e "$repository/docs/runbook.md"
test "$(git -C "$repository" rev-parse HEAD:docs/runbook.md)" = \
  "$runbook_blob"
test -z "$(git -C "$repository" status --porcelain -- docs/runbook.md)"
git -C "$repository" ls-files -v -- docs/runbook.md \
  > "$lab_root/sparse-index.txt"
grep -F 'S docs/runbook.md' "$lab_root/sparse-index.txt" >/dev/null
git -C "$repository" sparse-checkout add docs
test -f "$repository/docs/runbook.md"
cmp "$lab_root/runbook.expected" "$repository/docs/runbook.md"
test -z "$(git -C "$repository" status --porcelain -- docs/runbook.md)"
git -C "$repository" sparse-checkout disable

printf 'ignored bytes remain on disk\n' > "$repository/scratch.local"
test -f "$repository/scratch.local"
git -C "$repository" check-ignore -v -- scratch.local \
  > "$lab_root/check-ignore.txt"
grep -F '*.local' "$lab_root/check-ignore.txt" >/dev/null
if git -C "$repository" status --porcelain --untracked-files=all |
  grep -F 'scratch.local' >/dev/null
then
  printf 'Expected an ignored untracked file to stay out of default status.\n' >&2
  exit 1
fi

printf 'untracked bytes never written by Git\n' \
  > "$repository/untracked-only.txt"
cp "$repository/untracked-only.txt" "$lab_root/untracked.external-copy"
untracked_oid="$(git -C "$repository" hash-object \
  --no-filters untracked-only.txt)"
if git -C "$repository" cat-file -e "$untracked_oid" \
  > "$lab_root/untracked-cat-file.stdout" \
  2> "$lab_root/untracked-cat-file.stderr"
then
  printf 'Expected hash-object without -w not to store the untracked blob.\n' >&2
  exit 1
fi
mv "$repository/untracked-only.txt" "$lab_root/untracked.removed-from-worktree"
test ! -e "$repository/untracked-only.txt"
if git -C "$repository" restore -- untracked-only.txt \
  > "$lab_root/untracked-restore.stdout" \
  2> "$lab_root/untracked-restore.stderr"
then
  printf 'Expected Git restore to reject an unknown untracked path.\n' >&2
  exit 1
fi
cp "$lab_root/untracked.external-copy" "$repository/untracked-only.txt"
cmp "$lab_root/untracked.external-copy" "$repository/untracked-only.txt"

printf 'lost commit payload\n' > "$repository/feature.txt"
git -C "$repository" add feature.txt
GIT_AUTHOR_DATE='2026-08-21T13:10:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T13:10:00+00:00' \
  git -C "$repository" commit --quiet -m 'fixture: commit later removed from branch'
lost_oid="$(git -C "$repository" rev-parse HEAD)"
lost_tree="$(git -C "$repository" rev-parse HEAD^{tree})"
lost_feature_blob="$(git -C "$repository" rev-parse HEAD:feature.txt)"
test "$lost_oid" != "$base_oid"

git -C "$repository" reset --hard --quiet "$base_oid"
test "$(git -C "$repository" rev-parse HEAD)" = "$base_oid"
test ! -e "$repository/feature.txt"
git -C "$repository" cat-file -e "$lost_oid^{commit}"
git -C "$repository" reflog show --format='%H %gs' HEAD \
  > "$lab_root/head.reflog"
grep -F "$lost_oid" "$lab_root/head.reflog" >/dev/null
test -z "$(git -C "$repository" for-each-ref --contains "$lost_oid" \
  --format='%(refname)' refs/heads)"

local_state_fingerprint "$repository" "$lab_root/before-recovery-ref.txt"
git -C "$repository" branch recovery/missing-work "$lost_oid"
local_state_fingerprint "$repository" "$lab_root/after-recovery-ref.txt"
cmp "$lab_root/before-recovery-ref.txt" "$lab_root/after-recovery-ref.txt"
test "$(git -C "$repository" rev-parse refs/heads/recovery/missing-work)" = \
  "$lost_oid"
test "$(git -C "$repository" rev-parse recovery/missing-work^{tree})" = \
  "$lost_tree"
test "$(git -C "$repository" rev-parse \
  recovery/missing-work:feature.txt)" = "$lost_feature_blob"
test "$(git -C "$repository" rev-parse HEAD)" = "$base_oid"
test ! -e "$repository/feature.txt"

source_repo="$lab_root/source-repository"
remote="$lab_root/source-remote.git"
shallow="$lab_root/shallow-client"
git init --quiet --initial-branch=main "$source_repo"
git -C "$source_repo" config user.name 'Shallow Boundary Fixture'
git -C "$source_repo" config user.email 'shallow-boundary@example.invalid'
for version in 1 2 3
do
  printf 'version=%s\n' "$version" > "$source_repo/version.txt"
  git -C "$source_repo" add version.txt
  GIT_AUTHOR_DATE="2026-08-21T14:0${version}:00+00:00" \
  GIT_COMMITTER_DATE="2026-08-21T14:0${version}:00+00:00" \
    git -C "$source_repo" commit --quiet \
      -m "fixture: shallow history version $version"
  if test "$version" -eq 1; then
    oldest_oid="$(git -C "$source_repo" rev-parse HEAD)"
  fi
done
source_tip="$(git -C "$source_repo" rev-parse HEAD)"
git init --quiet --bare --initial-branch=main "$remote"
git -C "$source_repo" remote add origin "$remote"
git -C "$source_repo" push --quiet origin main
git -C "$remote" symbolic-ref HEAD refs/heads/main
git clone --quiet --depth=1 "file://$remote" "$shallow"
test "$(git -C "$shallow" rev-parse --is-shallow-repository)" = true
test "$(git -C "$shallow" rev-parse HEAD)" = "$source_tip"
test "$(cat "$shallow/version.txt")" = 'version=3'
if git -C "$shallow" cat-file -e "$oldest_oid^{commit}" \
  > "$lab_root/shallow-before.stdout" \
  2> "$lab_root/shallow-before.stderr"
then
  printf 'Expected a depth-1 clone not to contain the oldest commit.\n' >&2
  exit 1
fi

git -C "$shallow" fetch --quiet --unshallow origin
test "$(git -C "$shallow" rev-parse --is-shallow-repository)" = false
git -C "$shallow" cat-file -e "$oldest_oid^{commit}"
test "$(git -C "$shallow" rev-parse HEAD)" = "$source_tip"
test "$(cat "$shallow/version.txt")" = 'version=3'
test -s "$(git -C "$shallow" rev-parse \
  --path-format=absolute --git-path FETCH_HEAD)"

printf 'Tracked deletion, staged recovery, sparse expansion, ignore visibility, untracked limits, reflog recovery refs, and shallow completion passed.\n'
