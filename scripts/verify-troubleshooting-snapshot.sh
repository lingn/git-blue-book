#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-troubleshooting.XXXXXX")"
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

verify_sha256_manifest() {
  local package_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    (cd "$package_path" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1)
  else
    (cd "$package_path" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
  fi
}

refs_manifest() {
  local repository_path="$1"

  GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" for-each-ref \
    --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
    LC_ALL=C sort
}

capture_git() {
  local repository_path="$1"
  local package_path="$2"
  local label="$3"
  local output_name="$4"
  shift 4
  local command_status

  set +e
  GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" "$@" \
    > "$package_path/$output_name" \
    2> "$package_path/$output_name.stderr"
  command_status="$?"
  set -e
  printf '%s\t%s\t%s\t%s\n' \
    "$label" "$command_status" "$output_name" "$output_name.stderr" \
    >> "$package_path/command-results.tsv"
  test "$command_status" -eq 0
}

collect_snapshot() {
  local repository_path="$1"
  local package_path="$2"
  local toplevel
  local git_dir
  local common_dir
  local marker
  local marker_path
  local evidence_file

  mkdir "$package_path"
  toplevel="$(GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" rev-parse --show-toplevel)"
  git_dir="$(GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" \
    rev-parse --path-format=absolute --git-dir)"
  common_dir="$(GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" \
    rev-parse --path-format=absolute --git-common-dir)"

  {
    printf 'key\tvalue\tsource_status\n'
    printf 'git_version\t%s\tavailable\n' "$(git --version)"
    printf 'working_directory\t%s\tavailable\n' "$repository_path"
    printf 'captured_at\t2026-08-21T12:00:00Z\tfixture\n'
    printf 'trust_scope\ttrusted-local-fixture\tfixture\n'
  } > "$package_path/environment.tsv"
  {
    printf 'key\tvalue\tsource_status\n'
    printf 'toplevel\t%s\tavailable\n' "$toplevel"
    printf 'git_dir\t%s\tavailable\n' "$git_dir"
    printf 'common_dir\t%s\tavailable\n' "$common_dir"
    printf 'is_bare\t%s\tavailable\n' \
      "$(git -C "$repository_path" rev-parse --is-bare-repository)"
    printf 'inside_worktree\t%s\tavailable\n' \
      "$(git -C "$repository_path" rev-parse --is-inside-work-tree)"
  } > "$package_path/layout.tsv"
  printf 'label\texit_status\tstdout_file\tstderr_file\n' \
    > "$package_path/command-results.tsv"

  capture_git "$repository_path" "$package_path" status \
    status.porcelain-v2 status --porcelain=v2 --branch
  capture_git "$repository_path" "$package_path" index \
    index-stages.tsv ls-files --stage
  capture_git "$repository_path" "$package_path" refs \
    refs.tsv for-each-ref \
    '--format=%(refname) %(objecttype) %(objectname) %(*objectname)'
  LC_ALL=C sort "$package_path/refs.tsv" \
    > "$package_path/refs.sorted.tsv"
  mv "$package_path/refs.sorted.tsv" "$package_path/refs.tsv"
  capture_git "$repository_path" "$package_path" graph \
    graph.txt log --graph --decorate --oneline --all -30
  capture_git "$repository_path" "$package_path" worktree_diff \
    worktree.patch diff --no-ext-diff --no-textconv --binary
  capture_git "$repository_path" "$package_path" staged_diff \
    staged.patch diff --staged --no-ext-diff --no-textconv --binary
  capture_git "$repository_path" "$package_path" remotes \
    remote-names.txt remote
  capture_git "$repository_path" "$package_path" branches \
    branches.txt branch -vv

  printf 'marker\tpath\tstatus\n' > "$package_path/operation-state.tsv"
  for marker in \
    MERGE_HEAD \
    CHERRY_PICK_HEAD \
    REVERT_HEAD \
    rebase-merge \
    rebase-apply \
    BISECT_LOG \
    sequencer
  do
    marker_path="$(git -C "$repository_path" rev-parse \
      --path-format=absolute --git-path "$marker")"
    if test -e "$marker_path"; then
      printf '%s\t%s\tpresent\n' "$marker" "$marker_path" \
        >> "$package_path/operation-state.tsv"
    else
      printf '%s\t%s\tabsent\n' "$marker" "$marker_path" \
        >> "$package_path/operation-state.tsv"
    fi
  done

  {
    printf 'item\tstatus\tdetail\n'
    printf 'network\tnot_collected\tinitial snapshot does not contact remotes\n'
    printf 'remote_urls\tredacted\tonly remote names are in the shareable package\n'
    printf 'platform_control_plane\tnot_collected\tlocal fixture has no platform\n'
  } > "$package_path/gaps-and-redactions.tsv"

  {
    printf 'path\tsource\texit_status\tsensitivity\tstatus\n'
    printf 'environment.tsv\tprocess and fixed fixture time\t0\trestricted\tcomplete\n'
    printf 'layout.tsv\tgit rev-parse\t0\trestricted\tcomplete\n'
    printf 'command-results.tsv\tcollector\t0\tinternal\tcomplete\n'
    printf 'status.porcelain-v2\tgit status --porcelain=v2 --branch\t0\trestricted\tcomplete\n'
    printf 'index-stages.tsv\tgit ls-files --stage\t0\trestricted\tcomplete\n'
    printf 'operation-state.tsv\tgit rev-parse --git-path\t0\trestricted\tcomplete\n'
    printf 'refs.tsv\tgit for-each-ref\t0\trestricted\tcomplete\n'
    printf 'graph.txt\tgit log --all -30\t0\trestricted\tcomplete\n'
    printf 'worktree.patch\tgit diff --binary\t0\thigh\tcomplete\n'
    printf 'staged.patch\tgit diff --staged --binary\t0\thigh\tcomplete\n'
    printf 'remote-names.txt\tgit remote\t0\tinternal\tcomplete\n'
    printf 'branches.txt\tgit branch -vv\t0\trestricted\tcomplete\n'
    printf 'gaps-and-redactions.tsv\tcollector\t0\tinternal\tcomplete\n'
  } > "$package_path/manifest.tsv"

  : > "$package_path/SHA256SUMS"
  for evidence_file in \
    environment.tsv \
    layout.tsv \
    command-results.tsv \
    status.porcelain-v2 \
    status.porcelain-v2.stderr \
    index-stages.tsv \
    index-stages.tsv.stderr \
    operation-state.tsv \
    refs.tsv \
    refs.tsv.stderr \
    graph.txt \
    graph.txt.stderr \
    worktree.patch \
    worktree.patch.stderr \
    staged.patch \
    staged.patch.stderr \
    remote-names.txt \
    remote-names.txt.stderr \
    branches.txt \
    branches.txt.stderr \
    gaps-and-redactions.tsv \
    manifest.tsv
  do
    printf '%s  %s\n' \
      "$(sha256_file "$package_path/$evidence_file")" "$evidence_file" \
      >> "$package_path/SHA256SUMS"
  done
}

validate_snapshot() {
  local package_path="$1"
  local required_file

  for required_file in \
    manifest.tsv \
    environment.tsv \
    layout.tsv \
    command-results.tsv \
    status.porcelain-v2 \
    index-stages.tsv \
    operation-state.tsv \
    refs.tsv \
    graph.txt \
    worktree.patch \
    staged.patch \
    gaps-and-redactions.tsv \
    SHA256SUMS
  do
    if test ! -f "$package_path/$required_file"; then
      printf 'inconclusive\n'
      return 30
    fi
  done

  if ! verify_sha256_manifest "$package_path"; then
    printf 'fail\n'
    return 20
  fi
  if ! awk -F '\t' '
      NR == 1 {
        if ($0 != "label\texit_status\tstdout_file\tstderr_file") {
          exit 1
        }
        next
      }
      $2 != 0 { failed++ }
      END { exit failed > 0 }
    ' "$package_path/command-results.tsv"
  then
    printf 'inconclusive\n'
    return 30
  fi

  printf 'pass\n'
}

state_fingerprint() {
  local repository_path="$1"
  local output_path="$2"

  {
    printf 'HEAD %s\n' "$(git -C "$repository_path" rev-parse HEAD)"
    refs_manifest "$repository_path"
    printf 'INDEX %s\n' "$(sha256_file "$(git -C "$repository_path" rev-parse \
      --path-format=absolute --git-path index)")"
    printf 'CONFLICT %s\n' "$(sha256_file "$repository_path/conflict.txt")"
    printf 'STABLE %s\n' "$(sha256_file "$repository_path/stable.txt")"
    printf 'UNTRACKED %s\n' "$(sha256_file "$repository_path/local-only.txt")"
    GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" status \
      --porcelain=v2 --branch
    GIT_OPTIONAL_LOCKS=0 git -C "$repository_path" ls-files --stage
  } > "$output_path"
}

repository="$lab_root/conflicted-repository"
package="$lab_root/snapshot"
git init --quiet --initial-branch=main "$repository"
git -C "$repository" config user.name 'Troubleshooting Fixture'
git -C "$repository" config user.email 'troubleshooting@example.invalid'
printf 'base\n' > "$repository/conflict.txt"
printf 'stable\n' > "$repository/stable.txt"
git -C "$repository" add conflict.txt stable.txt
GIT_AUTHOR_DATE='2026-08-21T10:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T10:00:00+00:00' \
  git -C "$repository" commit --quiet -m 'fixture: establish diagnostic base'

git -C "$repository" switch --quiet -c topic
printf 'topic\n' > "$repository/conflict.txt"
git -C "$repository" add conflict.txt
GIT_AUTHOR_DATE='2026-08-21T10:05:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T10:05:00+00:00' \
  git -C "$repository" commit --quiet -m 'topic: change shared line'
topic_oid="$(git -C "$repository" rev-parse HEAD)"

git -C "$repository" switch --quiet main
printf 'main\n' > "$repository/conflict.txt"
git -C "$repository" add conflict.txt
GIT_AUTHOR_DATE='2026-08-21T10:10:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T10:10:00+00:00' \
  git -C "$repository" commit --quiet -m 'main: change shared line'
pre_merge_oid="$(git -C "$repository" rev-parse HEAD)"
git -C "$repository" remote add support \
  'https://fixture-user:synthetic-secret@example.invalid/org/repo.git'

if git -C "$repository" merge topic \
  > "$lab_root/merge.stdout" 2> "$lab_root/merge.stderr"; then
  printf 'Expected the diagnostic fixture to enter a merge conflict.\n' >&2
  exit 1
fi
printf 'untracked evidence must survive abort\n' \
  > "$repository/local-only.txt"
test -f "$(git -C "$repository" rev-parse \
  --path-format=absolute --git-path MERGE_HEAD)"
test "$(git -C "$repository" rev-parse MERGE_HEAD)" = "$topic_oid"

state_fingerprint "$repository" "$lab_root/before-collection.txt"
collect_snapshot "$repository" "$package"
state_fingerprint "$repository" "$lab_root/after-collection.txt"
cmp "$lab_root/before-collection.txt" "$lab_root/after-collection.txt"

validate_snapshot "$package" > "$lab_root/snapshot.classification"
grep -Fx pass "$lab_root/snapshot.classification" >/dev/null
grep -F $'MERGE_HEAD\t' "$package/operation-state.tsv" |
  grep -F $'\tpresent' >/dev/null
for stage in 1 2 3
do
  awk -v stage="$stage" \
    '$3 == stage && $4 == "conflict.txt" { found = 1 } END { exit !found }' \
    "$package/index-stages.tsv"
done
grep -F '? local-only.txt' "$package/status.porcelain-v2" >/dev/null
if grep -R -F 'synthetic-secret' "$package" >/dev/null; then
  printf 'Expected the shareable package to omit remote URL secrets.\n' >&2
  exit 1
fi
grep -Fx support "$package/remote-names.txt" >/dev/null

cp -R "$package" "$lab_root/missing-package"
mv "$lab_root/missing-package/refs.tsv" \
  "$lab_root/missing-package/refs.tsv.omitted"
missing_status=0
validate_snapshot "$lab_root/missing-package" \
  > "$lab_root/missing.classification" || missing_status="$?"
if test "$missing_status" -ne 30; then
  printf 'Expected a missing required evidence file to return 30, got %s.\n' \
    "$missing_status" >&2
  exit 1
fi
grep -Fx inconclusive "$lab_root/missing.classification" >/dev/null

cp -R "$package" "$lab_root/tampered-package"
printf 'tampered\n' >> "$lab_root/tampered-package/refs.tsv"
tampered_status=0
validate_snapshot "$lab_root/tampered-package" \
  > "$lab_root/tampered.classification" || tampered_status="$?"
if test "$tampered_status" -ne 20; then
  printf 'Expected a digest mismatch to return 20, got %s.\n' \
    "$tampered_status" >&2
  exit 1
fi
grep -Fx fail "$lab_root/tampered.classification" >/dev/null

state_fingerprint "$repository" "$lab_root/before-failed-switch.txt"
switch_status=0
git -C "$repository" switch topic \
  > "$lab_root/switch.stdout" 2> "$lab_root/switch.stderr" || \
  switch_status="$?"
if test "$switch_status" -eq 0; then
  printf 'Expected switch to fail while the index contains conflicts.\n' >&2
  exit 1
fi
grep -E 'needs merge|resolve your current index|you need to resolve|cannot switch branch while merging' \
  "$lab_root/switch.stderr" >/dev/null
state_fingerprint "$repository" "$lab_root/after-failed-switch.txt"
cmp "$lab_root/before-failed-switch.txt" "$lab_root/after-failed-switch.txt"
{
  printf 'command\texit_status\tstdout\tstderr\n'
  printf 'git switch topic\t%s\tswitch.stdout\tswitch.stderr\n' \
    "$switch_status"
} > "$lab_root/original-failure.tsv"

git -C "$repository" merge --abort
test ! -e "$(git -C "$repository" rev-parse \
  --path-format=absolute --git-path MERGE_HEAD)"
test "$(git -C "$repository" rev-parse HEAD)" = "$pre_merge_oid"
test "$(cat "$repository/conflict.txt")" = main
test "$(cat "$repository/local-only.txt")" = \
  'untracked evidence must survive abort'
test -z "$(git -C "$repository" ls-files --unmerged)"

publisher="$lab_root/publisher"
remote="$lab_root/remote.git"
fetch_client="$lab_root/fetch-client"
git init --quiet --initial-branch=main "$publisher"
git -C "$publisher" config user.name 'Fetch Boundary Fixture'
git -C "$publisher" config user.email 'fetch-boundary@example.invalid'
printf 'version=1\n' > "$publisher/service.conf"
git -C "$publisher" add service.conf
git -C "$publisher" commit --quiet -m 'fixture: remote version one'
git init --quiet --bare --initial-branch=main "$remote"
git -C "$publisher" remote add origin "$remote"
git -C "$publisher" push --quiet origin main
git -C "$remote" symbolic-ref HEAD refs/heads/main
git clone --quiet --no-local "$remote" "$fetch_client"
client_head_before="$(git -C "$fetch_client" rev-parse HEAD)"
tracking_before="$(git -C "$fetch_client" rev-parse refs/remotes/origin/main)"

printf 'version=2\n' > "$publisher/service.conf"
git -C "$publisher" add service.conf
git -C "$publisher" commit --quiet -m 'fixture: remote version two'
remote_new_oid="$(git -C "$publisher" rev-parse HEAD)"
git -C "$publisher" push --quiet origin main
test "$tracking_before" != "$remote_new_oid"

git -C "$fetch_client" fetch --quiet --no-tags origin \
  'refs/heads/main:refs/remotes/origin/main'
tracking_after="$(git -C "$fetch_client" rev-parse refs/remotes/origin/main)"
test "$tracking_after" = "$remote_new_oid"
test "$(git -C "$fetch_client" rev-parse HEAD)" = "$client_head_before"
test -s "$(git -C "$fetch_client" rev-parse \
  --path-format=absolute --git-path FETCH_HEAD)"
grep -F "$remote_new_oid" \
  "$(git -C "$fetch_client" rev-parse \
    --path-format=absolute --git-path FETCH_HEAD)" >/dev/null
test "$(cat "$fetch_client/service.conf")" = 'version=1'

printf 'Troubleshooting snapshot non-mutation, conflict evidence, tri-state validation, abort recovery, redaction, and fetch mutation passed.\n'
