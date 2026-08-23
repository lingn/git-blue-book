#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-forensic-acquisition.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

hash_file() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path"
  else
    sha256sum "$file_path"
  fi
}

verify_manifest() {
  local evidence_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    (cd "$evidence_path" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1)
  else
    (cd "$evidence_path" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
  fi
}

collect_forensic_evidence() {
  local repo_path="$1"
  local evidence_path="$2"
  local repo_root git_dir common_dir evidence_parent evidence_name evidence_abs
  local state_name state_path fsck_exit

  repo_root="$(
    git --no-optional-locks -C "$repo_path" \
      rev-parse --path-format=absolute --show-toplevel
  )"
  git_dir="$(
    git --no-optional-locks -C "$repo_path" \
      rev-parse --path-format=absolute --git-dir
  )"
  common_dir="$(
    git --no-optional-locks -C "$repo_path" \
      rev-parse --path-format=absolute --git-common-dir
  )"

  evidence_parent="$(dirname "$evidence_path")"
  evidence_name="$(basename "$evidence_path")"
  evidence_abs="$(cd "$evidence_parent" && pwd -P)/$evidence_name"

  case "$evidence_abs/" in
    "$repo_root/"*|"$git_dir/"*|"$common_dir/"*)
      return 64
      ;;
  esac

  install -d -m 0700 "$evidence_abs"

  {
    date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
    printf 'repo=%s\n' "$repo_root"
    git --version
    uname -a
  } > "$evidence_abs/environment.txt"

  git --no-optional-locks -C "$repo_path" \
    rev-parse --path-format=absolute \
    --show-toplevel --git-dir --git-common-dir \
    > "$evidence_abs/layout.txt" \
    2> "$evidence_abs/layout.stderr"
  git --no-optional-locks -C "$repo_path" \
    worktree list --porcelain \
    > "$evidence_abs/worktrees.txt"

  git --no-optional-locks -C "$repo_path" \
    status --porcelain=v2 --branch -z \
    > "$evidence_abs/status.porcelain-v2.nul"
  git --no-optional-locks -C "$repo_path" \
    ls-files --stage -z \
    > "$evidence_abs/index-stage.nul"
  git --no-optional-locks -C "$repo_path" \
    diff --binary --no-ext-diff --no-textconv -- \
    > "$evidence_abs/worktree.diff"
  git --no-optional-locks -C "$repo_path" \
    diff --cached --binary --no-ext-diff --no-textconv -- \
    > "$evidence_abs/index.diff"

  git --no-optional-locks -C "$repo_path" \
    rev-parse --verify HEAD \
    > "$evidence_abs/head.oid"
  if ! git --no-optional-locks -C "$repo_path" \
    symbolic-ref -q HEAD \
    > "$evidence_abs/head.symbolic" \
    2> "$evidence_abs/head.symbolic.stderr"; then
    printf '%s\n' "$?" > "$evidence_abs/head.symbolic.exit"
  else
    printf '0\n' > "$evidence_abs/head.symbolic.exit"
  fi
  git --no-optional-locks -C "$repo_path" \
    for-each-ref \
    --format='%(refname)%00%(objecttype)%00%(objectname)%00%(*objectname)%00' \
    > "$evidence_abs/refs.nul"
  git --no-optional-locks -C "$repo_path" \
    reflog show --all --date=iso-strict \
    --format='%H%x00%gD%x00%gs%x00' \
    > "$evidence_abs/reflog.nul"

  : > "$evidence_abs/operation-state.paths"
  for state_name in \
    MERGE_HEAD MERGE_MSG CHERRY_PICK_HEAD REVERT_HEAD REBASE_HEAD \
    rebase-merge rebase-apply sequencer
  do
    state_path="$(
      git --no-optional-locks -C "$repo_path" \
        rev-parse --path-format=absolute --git-path "$state_name"
    )"
    if test -e "$state_path"; then
      printf '%s\t%s\n' "$state_name" "$state_path" \
        >> "$evidence_abs/operation-state.paths"
    fi
  done

  git --no-optional-locks -C "$repo_path" \
    config --show-origin --show-scope --null --list \
    > "$evidence_abs/config.nul"
  git --no-optional-locks -C "$repo_path" remote --verbose \
    > "$evidence_abs/remotes.txt"
  git --no-optional-locks -C "$repo_path" count-objects -vH \
    > "$evidence_abs/count-objects.txt"
  git --no-optional-locks -C "$repo_path" cat-file --batch-all-objects \
    --batch-check='%(objectname) %(objecttype) %(objectsize)' \
    > "$evidence_abs/objects.txt"

  set +e
  git --no-optional-locks -C "$repo_path" \
    fsck --connectivity-only --no-progress \
    > "$evidence_abs/fsck-connectivity.stdout" \
    2> "$evidence_abs/fsck-connectivity.stderr"
  fsck_exit="$?"
  set -e
  printf '%s\n' "$fsck_exit" > "$evidence_abs/fsck-connectivity.exit"

  (
    cd "$evidence_abs"
    find . -type f ! -name SHA256SUMS -print |
      LC_ALL=C sort |
      while IFS= read -r evidence_file; do
        hash_file "$evidence_file"
      done
  ) > "$evidence_abs/SHA256SUMS"
}

repo="$lab_root/incident"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Forensic Fixture'
git -C "$repo" config user.email 'forensic@example.invalid'
git -C "$repo" config incident.fixture 'local-config-is-not-cloned'

printf 'base\n' > "$repo/conflict.txt"
printf 'tracked base\n' > "$repo/tracked.txt"
git -C "$repo" add conflict.txt tracked.txt
git -C "$repo" commit --quiet -m 'fixture: establish base'

git -C "$repo" switch --quiet -c feature
printf 'feature\n' > "$repo/conflict.txt"
printf 'feature evidence\n' > "$repo/feature.txt"
git -C "$repo" add conflict.txt feature.txt
git -C "$repo" commit --quiet -m 'fixture: feature side'
feature_tip="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet main
printf 'main\n' > "$repo/conflict.txt"
git -C "$repo" add conflict.txt
git -C "$repo" commit --quiet -m 'fixture: main side'
main_tip="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag -a incident-tag -m 'fixture annotated tag' "$main_tip"
git -C "$repo" notes add -m 'fixture note kept in a separate ref' "$main_tip"
GIT_REFLOG_ACTION='fixture: preserve this reflog marker' \
  git -C "$repo" update-ref refs/heads/main "$main_tip" "$main_tip"

unreachable_blob="$(
  printf 'unreachable forensic fixture\n' |
    git -C "$repo" hash-object -w --stdin
)"

if git -C "$repo" merge --no-edit feature >/dev/null 2>&1; then
  printf 'Expected the fixture merge to stop with a conflict.\n' >&2
  exit 1
fi
printf 'untracked evidence\n' > "$repo/untracked.txt"
printf 'working tree edit after merge stopped\n' >> "$repo/tracked.txt"

git_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-dir)"
head_before="$(git -C "$repo" rev-parse HEAD)"
refs_before="$(
  git -C "$repo" for-each-ref \
    --format='%(refname) %(objectname)' | LC_ALL=C sort
)"
index_before="$(git hash-object "$git_dir/index")"
conflict_before="$(git hash-object "$repo/conflict.txt")"
tracked_before="$(git hash-object "$repo/tracked.txt")"
merge_head_before="$(cat "$git_dir/MERGE_HEAD")"

mkdir -p "$repo/forbidden-parent"
if collect_forensic_evidence "$repo" "$repo/forbidden-parent/evidence"; then
  printf 'Expected evidence output inside the incident worktree to be rejected.\n' >&2
  exit 1
fi
test ! -e "$repo/forbidden-parent/evidence"

evidence_parent="$lab_root/restricted-evidence"
mkdir -m 0700 "$evidence_parent"
evidence="$evidence_parent/acquisition-001"
collect_forensic_evidence "$repo" "$evidence"

test "$(git -C "$repo" rev-parse HEAD)" = "$head_before"
test "$(
  git -C "$repo" for-each-ref \
    --format='%(refname) %(objectname)' | LC_ALL=C sort
)" = "$refs_before"
test "$(git hash-object "$git_dir/index")" = "$index_before"
test "$(git hash-object "$repo/conflict.txt")" = "$conflict_before"
test "$(git hash-object "$repo/tracked.txt")" = "$tracked_before"
test "$(cat "$git_dir/MERGE_HEAD")" = "$merge_head_before"

test -s "$evidence/status.porcelain-v2.nul"
test -s "$evidence/index-stage.nul"
test -s "$evidence/worktree.diff"
test -s "$evidence/index.diff"
test -s "$evidence/refs.nul"
test -s "$evidence/reflog.nul"
test -s "$evidence/config.nul"
test -s "$evidence/objects.txt"
test -s "$evidence/SHA256SUMS"
grep -F 'MERGE_HEAD' "$evidence/operation-state.paths" >/dev/null
grep -F "$unreachable_blob" "$evidence/objects.txt" >/dev/null
test "$(cat "$evidence/head.oid")" = "$main_tip"
verify_manifest "$evidence"

tampered="$evidence_parent/tampered-copy"
cp -R "$evidence" "$tampered"
printf 'tampered\n' >> "$tampered/environment.txt"
if verify_manifest "$tampered"; then
  printf 'Expected the manifest to detect a changed evidence file.\n' >&2
  exit 1
fi
rm -rf -- "$tampered"
regenerated="$evidence_parent/regenerated-copy"
cp -R "$evidence" "$regenerated"
verify_manifest "$regenerated"

clone_repo="$lab_root/ordinary-clone"
git clone --quiet --no-local "$repo" "$clone_repo"
test ! -e "$clone_repo/.git/MERGE_HEAD"
test ! -e "$clone_repo/untracked.txt"
test "$(cat "$clone_repo/conflict.txt")" = 'main'
test "$(git -C "$clone_repo" config --get incident.fixture || :)" = ''
if git -C "$clone_repo" cat-file -e "$unreachable_blob" 2>/dev/null; then
  printf 'Expected an ordinary no-local clone to omit the unreachable blob.\n' >&2
  exit 1
fi
if git -C "$clone_repo" show-ref --verify --quiet refs/notes/commits; then
  printf 'Expected the default clone refspec to omit the notes ref.\n' >&2
  exit 1
fi
if git -C "$clone_repo" reflog --all |
  grep -F 'preserve this reflog marker' >/dev/null; then
  printf 'Expected the clone to have its own reflog, not the source reflog.\n' >&2
  exit 1
fi
test "$(git -C "$clone_repo" rev-parse refs/remotes/origin/feature)" = "$feature_tip"

git -C "$repo" merge --abort
test ! -e "$git_dir/MERGE_HEAD"
test "$(cat "$repo/conflict.txt")" = 'main'
test -s "$evidence/operation-state.paths"
verify_manifest "$evidence"

printf 'Forensic layout, logical acquisition, non-mutation, clone omissions, manifest detection, and recovery separation passed.\n'
