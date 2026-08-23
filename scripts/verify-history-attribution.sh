#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-history-attribution.XXXXXX")"
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

commit_at() {
  local message="$1"
  local timestamp="$2"

  GIT_AUTHOR_DATE="$timestamp" GIT_COMMITTER_DATE="$timestamp" \
    git -C "$repo" commit --quiet -m "$message"
}

assert_contains() {
  local needle="$1"
  local haystack="$2"

  grep -F -- "$needle" "$haystack" >/dev/null
}

repo="$lab_root/repository"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'History Attribution Fixture'
git -C "$repo" config user.email 'history-attribution@example.invalid'
mkdir -p "$repo/src" "$repo/docs"

printf 'timeout = 30\nmode = stable\n' > "$repo/src/service.conf"
git -C "$repo" add src/service.conf
commit_at 'fixture: establish service configuration' '2026-08-01T09:00:00+00:00'
base_commit="$(git -C "$repo" rev-parse HEAD)"

printf 'timeout = 60\nmode = stable\nretry = 2\n' > "$repo/src/service.conf"
git -C "$repo" add src/service.conf
commit_at 'feat: tune timeout INC-2026-001' '2026-08-02T09:00:00+00:00'
logic_commit="$(git -C "$repo" rev-parse HEAD)"

sed -i.bak 's/^/  /' "$repo/src/service.conf"
rm -f -- "$repo/src/service.conf.bak"
git -C "$repo" add src/service.conf
commit_at 'chore: format service configuration' '2026-08-03T09:00:00+00:00'
format_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet -c feature
git -C "$repo" mv src/service.conf src/runtime.conf
printf '  feature_flag = true\n' >> "$repo/src/runtime.conf"
git -C "$repo" add src/runtime.conf
commit_at 'refactor: rename service configuration' '2026-08-04T09:00:00+00:00'
rename_commit="$(git -C "$repo" rev-parse HEAD)"

cp "$repo/src/runtime.conf" "$repo/docs/runtime-example.conf"
git -C "$repo" add docs/runtime-example.conf
commit_at 'docs: copy runtime configuration example' '2026-08-05T09:00:00+00:00'
copy_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet main
printf 'main-only evidence\n' > "$repo/src/main-only.txt"
git -C "$repo" add src/main-only.txt
commit_at 'chore: record mainline release note' '2026-08-06T09:00:00+00:00'
mainline_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" merge --quiet --no-ff -m 'merge: integrate feature configuration' feature
merge_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet -c investigation
printf 'unmerged investigation marker\n' > "$repo/src/investigation.txt"
git -C "$repo" add src/investigation.txt
commit_at 'investigate: reproduce timeout report' '2026-08-07T09:00:00+00:00'
unmerged_commit="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" switch --quiet main

test "$(git -C "$repo" rev-list --count --first-parent main)" -lt \
  "$(git -C "$repo" rev-list --count --all)"
git -C "$repo" rev-parse --verify "$merge_commit^{commit}" >/dev/null
test "$(git -C "$repo" show -s --format='%P' "$merge_commit" | wc -w | tr -d ' ')" -eq 2

blame_default="$lab_root/blame-default.porcelain"
git -C "$repo" blame --line-porcelain -L 1,1 -- src/runtime.conf > "$blame_default"
assert_contains "$format_commit" "$blame_default"
assert_contains 'filename ' "$blame_default"
assert_contains 'summary ' "$blame_default"

ignore_file="$lab_root/blame-ignore-revs.txt"
printf '%s\n' "$format_commit" > "$ignore_file"
blame_ignored="$lab_root/blame-ignored.porcelain"
git -C "$repo" blame --ignore-revs-file "$ignore_file" \
  --line-porcelain -L 1,1 -- src/runtime.conf > "$blame_ignored"
assert_contains "$logic_commit" "$blame_ignored"
if git -C "$repo" blame --ignore-rev \
  '0000000000000000000000000000000000000000' -- src/runtime.conf \
  > "$lab_root/invalid-ignore.out" 2> "$lab_root/invalid-ignore.err"; then
  printf 'Expected blame to reject an unknown ignore revision.\n' >&2
  exit 1
fi

follow_log="$lab_root/follow.log"
git -C "$repo" log --follow --format='%H%x00%P%x00%s%x00' \
  -- src/runtime.conf > "$follow_log"
assert_contains "$logic_commit" "$follow_log"
assert_contains "$rename_commit" "$follow_log"

copy_log="$lab_root/copy.log"
git -C "$repo" diff-tree --no-commit-id --find-renames \
  --find-copies=40% --find-copies-harder --name-status -r \
  "$copy_commit^" "$copy_commit" \
  > "$copy_log"
assert_contains 'C100' "$copy_log"
assert_contains 'src/runtime.conf' "$copy_log"
assert_contains 'docs/runtime-example.conf' "$copy_log"

pickaxe_s="$lab_root/pickaxe-s.log"
git -C "$repo" log --all --full-history -S'timeout = 60' \
  --format='%H%x00%P%x00%s%x00' -- src/service.conf > "$pickaxe_s"
assert_contains "$logic_commit" "$pickaxe_s"

pickaxe_g="$lab_root/pickaxe-g.log"
git -C "$repo" log --all --full-history \
  -G'timeout[[:space:]]*=[[:space:]]*[0-9]+' --pickaxe-all \
  --format='%H%x00%P%x00%s%x00' -- src/service.conf > "$pickaxe_g"
assert_contains "$logic_commit" "$pickaxe_g"

grep_log="$lab_root/message-grep.log"
git -C "$repo" log --all --grep='INC-2026-001' \
  --format='%H%x00%aI%x00%an%x00%s%x00' > "$grep_log"
assert_contains "$logic_commit" "$grep_log"

first_parent_log="$lab_root/first-parent.log"
git -C "$repo" log --first-parent --format='%H%x00%s%x00' main > "$first_parent_log"
if grep -F -- "$rename_commit" "$first_parent_log" >/dev/null; then
  printf 'Expected first-parent history to hide the feature-side rename.\n' >&2
  exit 1
fi
all_log="$lab_root/all.log"
git -C "$repo" log --all --format='%H%x00%s%x00' > "$all_log"
assert_contains "$rename_commit" "$all_log"
assert_contains "$unmerged_commit" "$all_log"
if git -C "$repo" log --format='%H%x00%s%x00' main | \
  grep -F -- "$unmerged_commit" >/dev/null; then
  printf 'Expected the unmerged investigation commit to stay off main.\n' >&2
  exit 1
fi

parents=( $(git -C "$repo" show -s --format='%P' "$merge_commit") )
test "${#parents[@]}" -eq 2
test "${parents[0]}" = "$mainline_commit"
test "${parents[1]}" = "$copy_commit"
for parent in "${parents[@]}"; do
  git -C "$repo" diff --find-renames --find-copies \
    "$parent" "$merge_commit" -- src/runtime.conf > \
    "$lab_root/diff-${parent}.txt"
  test -f "$lab_root/diff-${parent}.txt"
done
test -s "$lab_root/diff-${parents[0]}.txt"
test ! -s "$lab_root/diff-${parents[1]}.txt"

manifest="$lab_root/history-manifest"
install -d -m 0700 "$manifest"
{
  printf 'candidate=%s\n' "$merge_commit"
  printf 'base=%s\n' "$base_commit"
  printf 'logic=%s\n' "$logic_commit"
  printf 'format=%s\n' "$format_commit"
  printf 'rename=%s\n' "$rename_commit"
  printf 'copy=%s\n' "$copy_commit"
  printf 'unmerged=%s\n' "$unmerged_commit"
  git -C "$repo" show -s --format='parents=%P%ntree=%T%nsubject=%s' "$merge_commit"
  printf 'query=blame --line-porcelain -L 1,1 -- src/runtime.conf\n'
  printf 'query=log --follow -- src/runtime.conf\n'
  printf 'query=log --all --full-history -S timeout = 60 -- src/service.conf\n'
} > "$manifest/history-manifest.txt"
cp "$blame_default" "$manifest/blame-default.porcelain"
cp "$blame_ignored" "$manifest/blame-ignored.porcelain"
{
  printf 'refs\n'
  git -C "$repo" for-each-ref --format='%(refname) %(objectname)' | LC_ALL=C sort
} > "$manifest/refs.txt"
(
  cd "$manifest"
  find . -type f ! -name SHA256SUMS -print |
    LC_ALL=C sort |
    while IFS= read -r evidence_file; do
      hash_file "$evidence_file"
    done
) > "$manifest/SHA256SUMS"
verify_manifest "$manifest"

cp -R "$manifest" "$lab_root/tampered-manifest"
printf 'tampered\n' >> "$lab_root/tampered-manifest/history-manifest.txt"
if verify_manifest "$lab_root/tampered-manifest"; then
  printf 'Expected the manifest to detect a changed evidence file.\n' >&2
  exit 1
fi

printf 'History attribution, blame/pickaxe boundaries, merge-parent comparison, and manifest tamper detection passed.\n'
