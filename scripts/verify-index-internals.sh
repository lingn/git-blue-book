#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-index.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

index_repo="$lab_dir/index"
add_add_repo="$lab_dir/add-add"
sparse_repo="$lab_dir/sparse"

git init --quiet --initial-branch=main "$index_repo"
git -C "$index_repo" config user.name "Index Lab"
git -C "$index_repo" config user.email "index@example.invalid"
mkdir -p "$index_repo/app" "$index_repo/docs" "$index_repo/ops"
printf 'base service\n' > "$index_repo/app/service.txt"
printf 'base conflict\n' > "$index_repo/conflict.txt"
printf 'guide\n' > "$index_repo/docs/guide.md"
printf 'runbook\n' > "$index_repo/ops/runbook.md"
printf '#!/bin/sh\nprintf "ok\\n"\n' > "$index_repo/run.sh"
chmod +x "$index_repo/run.sh"
ln -s app/service.txt "$index_repo/service-link"
git -C "$index_repo" add .
git -C "$index_repo" commit --quiet -m "build: add index fixture"
base_commit="$(git -C "$index_repo" rev-parse HEAD)"
base_tree="$(git -C "$index_repo" rev-parse 'HEAD^{tree}')"

test "$(git -C "$index_repo" ls-files --stage -- app/service.txt | awk '{print $1}')" = "100644"
test "$(git -C "$index_repo" ls-files --stage -- run.sh | awk '{print $1}')" = "100755"
test "$(git -C "$index_repo" ls-files --stage -- service-link | awk '{print $1}')" = "120000"
test "$(git -C "$index_repo" ls-files --stage -- app/service.txt | awk '{print $3}')" = "0"
test "$(git -C "$index_repo" write-tree)" = "$base_tree"

git -C "$index_repo" update-index --index-version 4
test "$(git -C "$index_repo" update-index --show-index-version)" = "4"
test "$(git -C "$index_repo" write-tree)" = "$base_tree"

printf 'staged service\n' > "$index_repo/app/service.txt"
git -C "$index_repo" add app/service.txt
staged_oid="$(git -C "$index_repo" rev-parse ':app/service.txt')"
test "$(git -C "$index_repo" show :app/service.txt)" = "staged service"
printf 'worktree service\n' > "$index_repo/app/service.txt"
worktree_oid="$(git -C "$index_repo" hash-object --path=app/service.txt app/service.txt)"
test "$worktree_oid" != "$staged_oid"
test -n "$(git -C "$index_repo" diff --staged -- app/service.txt)"
test -n "$(git -C "$index_repo" diff -- app/service.txt)"
git -C "$index_repo" reset --quiet --hard "$base_commit"

main_index_path="$(git -C "$index_repo" rev-parse --path-format=absolute --git-path index)"
main_index_before="$(git hash-object "$main_index_path")"
alternate_index="$lab_dir/alternate.index"
GIT_INDEX_FILE="$alternate_index" git -C "$index_repo" read-tree HEAD
test "$(GIT_INDEX_FILE="$alternate_index" git -C "$index_repo" write-tree)" = "$base_tree"
GIT_INDEX_FILE="$alternate_index" git -C "$index_repo" update-index --force-remove -- app/service.txt
test "$(GIT_INDEX_FILE="$alternate_index" git -C "$index_repo" write-tree)" != "$base_tree"
test "$(git hash-object "$main_index_path")" = "$main_index_before"
test "$(git -C "$index_repo" write-tree)" = "$base_tree"

git -C "$index_repo" switch --quiet -c feature/conflict
printf 'feature conflict\n' > "$index_repo/conflict.txt"
git -C "$index_repo" add conflict.txt
git -C "$index_repo" commit --quiet -m "feat: change conflict file"
feature_tip="$(git -C "$index_repo" rev-parse HEAD)"

git -C "$index_repo" switch --quiet main
printf 'main conflict\n' > "$index_repo/conflict.txt"
git -C "$index_repo" add conflict.txt
git -C "$index_repo" commit --quiet -m "fix: change conflict file"
main_before_merge="$(git -C "$index_repo" rev-parse HEAD)"
if git -C "$index_repo" merge --quiet "$feature_tip" >/dev/null 2>&1; then
  printf 'Expected content/content merge to conflict.\n' >&2
  exit 1
fi
test "$(git -C "$index_repo" ls-files -u -- conflict.txt | awk '{print $3}' | tr '\n' ' ')" = "1 2 3 "
test "$(git -C "$index_repo" show :1:conflict.txt)" = "base conflict"
test "$(git -C "$index_repo" show :2:conflict.txt)" = "main conflict"
test "$(git -C "$index_repo" show :3:conflict.txt)" = "feature conflict"
if git -C "$index_repo" write-tree >"$lab_dir/unmerged-tree.out" 2>"$lab_dir/unmerged-tree.err"; then
  printf 'Expected write-tree to reject unmerged index stages.\n' >&2
  exit 1
fi
test -s "$lab_dir/unmerged-tree.err"
printf 'resolved conflict\n' > "$index_repo/conflict.txt"
git -C "$index_repo" add conflict.txt
test -z "$(git -C "$index_repo" ls-files -u -- conflict.txt)"
test "$(git -C "$index_repo" ls-files --stage -- conflict.txt | awk '{print $3}')" = "0"
git -C "$index_repo" write-tree >/dev/null
git -C "$index_repo" merge --abort
test "$(git -C "$index_repo" rev-parse HEAD)" = "$main_before_merge"
test -z "$(git -C "$index_repo" status --short)"

git init --quiet --initial-branch=main "$add_add_repo"
git -C "$add_add_repo" config user.name "Add Add Lab"
git -C "$add_add_repo" config user.email "add-add@example.invalid"
printf 'root\n' > "$add_add_repo/README.md"
git -C "$add_add_repo" add README.md
git -C "$add_add_repo" commit --quiet -m "build: add root"
git -C "$add_add_repo" switch --quiet -c feature/add
printf 'feature addition\n' > "$add_add_repo/new.txt"
git -C "$add_add_repo" add new.txt
git -C "$add_add_repo" commit --quiet -m "feat: add new file"
add_feature_tip="$(git -C "$add_add_repo" rev-parse HEAD)"
git -C "$add_add_repo" switch --quiet main
printf 'main addition\n' > "$add_add_repo/new.txt"
git -C "$add_add_repo" add new.txt
git -C "$add_add_repo" commit --quiet -m "feat: add competing file"
if git -C "$add_add_repo" merge --quiet "$add_feature_tip" >/dev/null 2>&1; then
  printf 'Expected add/add merge to conflict.\n' >&2
  exit 1
fi
test "$(git -C "$add_add_repo" ls-files -u -- new.txt | awk '{print $3}' | tr '\n' ' ')" = "2 3 "
git -C "$add_add_repo" merge --abort
test -z "$(git -C "$add_add_repo" status --short)"

git clone --quiet "$index_repo" "$sparse_repo"
git -C "$sparse_repo" sparse-checkout set --cone --sparse-index app
test "$(git -C "$sparse_repo" config --get index.sparse)" = "true"
test -f "$sparse_repo/app/service.txt"
test ! -e "$sparse_repo/docs/guide.md"
test ! -e "$sparse_repo/ops/runbook.md"
sparse_tree="$(git -C "$sparse_repo" write-tree)"
test "$sparse_tree" = "$(git -C "$sparse_repo" rev-parse 'HEAD^{tree}')"
git -C "$sparse_repo" ls-files --sparse --stage > "$lab_dir/sparse-index.txt"
sparse_directory_count="$(awk '$1 == "040000" {count++} END {print count+0}' "$lab_dir/sparse-index.txt")"
test "$sparse_directory_count" -ge 2
git -C "$sparse_repo" sparse-checkout reapply --no-sparse-index \
  2>"$lab_dir/no-sparse-index.err"
test "$(git -C "$sparse_repo" config --get index.sparse)" = "false"
test "$(git -C "$sparse_repo" write-tree)" = "$sparse_tree"
git -C "$sparse_repo" ls-files --sparse --stage > "$lab_dir/full-index.txt"
if awk '$1 == "040000" {found=1} END {exit !found}' "$lab_dir/full-index.txt"; then
  printf 'Expected a full index after disabling sparse-index.\n' >&2
  exit 1
fi
test "$(awk '$4 == "docs/guide.md" {print $1}' "$lab_dir/full-index.txt")" = "100644"
test "$(awk '$4 == "ops/runbook.md" {print $1}' "$lab_dir/full-index.txt")" = "100644"
test ! -e "$sparse_repo/docs/guide.md"
test ! -e "$sparse_repo/ops/runbook.md"

git -C "$sparse_repo" sparse-checkout reapply --sparse-index \
  2>"$lab_dir/sparse-index.err"
test "$(git -C "$sparse_repo" config --get index.sparse)" = "true"
git -C "$sparse_repo" ls-files --sparse --stage > "$lab_dir/sparse-index-again.txt"
test "$(awk '$1 == "040000" {count++} END {print count+0}' "$lab_dir/sparse-index-again.txt")" -ge 2
sparse_status="$(git -C "$sparse_repo" status --short 2>"$lab_dir/sparse-status.err")"
test -z "$sparse_status"

git -C "$index_repo" fsck --full --strict >/dev/null
git -C "$add_add_repo" fsck --full --strict >/dev/null
if ! git -C "$sparse_repo" fsck --full --strict \
  >"$lab_dir/sparse-fsck.out" 2>"$lab_dir/sparse-fsck.err"; then
  cat "$lab_dir/sparse-fsck.err" >&2
  exit 1
fi

printf 'Index modes, versions, alternate files, conflict stages, and sparse directories passed.\n'
