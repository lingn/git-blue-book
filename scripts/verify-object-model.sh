#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-objects.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  if [[ "${KEEP_OBJECT_LAB:-0}" = "1" ]]; then
    printf 'Object model lab kept at: %s\n' "$lab_dir"
  else
    rm -rf -- "$lab_dir"
  fi
  exit "$status"
}
trap cleanup EXIT

git -C "$lab_dir" init --quiet --initial-branch=main
git -C "$lab_dir" config user.name "Object Model Test"
git -C "$lab_dir" config user.email "object-model@example.invalid"

mkdir "$lab_dir/docs"
printf 'same content\n' > "$lab_dir/README.md"
printf 'same content\n' > "$lab_dir/docs/copy.md"

readme_blob="$(git -C "$lab_dir" hash-object README.md)"
copy_blob="$(git -C "$lab_dir" hash-object docs/copy.md)"
test "$readme_blob" = "$copy_blob"

git -C "$lab_dir" add README.md docs/copy.md
indexed_readme="$(git -C "$lab_dir" ls-files --stage -- README.md | awk '{print $2}')"
indexed_copy="$(git -C "$lab_dir" ls-files --stage -- docs/copy.md | awk '{print $2}')"
test "$indexed_readme" = "$readme_blob"
test "$indexed_copy" = "$copy_blob"
test "$(git -C "$lab_dir" cat-file -t "$readme_blob")" = "blob"

first_tree="$(git -C "$lab_dir" write-tree)"
test "$(git -C "$lab_dir" cat-file -t "$first_tree")" = "tree"
git -C "$lab_dir" commit --quiet -m "docs: add identical files"
first_commit="$(git -C "$lab_dir" rev-parse HEAD)"
test "$(git -C "$lab_dir" cat-file -t "$first_commit")" = "commit"
test "$(git -C "$lab_dir" rev-parse 'HEAD^{tree}')" = "$first_tree"

printf 'changed content\n' > "$lab_dir/README.md"
git -C "$lab_dir" add README.md
changed_blob="$(git -C "$lab_dir" ls-files --stage -- README.md | awk '{print $2}')"
unchanged_copy="$(git -C "$lab_dir" ls-files --stage -- docs/copy.md | awk '{print $2}')"
test "$changed_blob" != "$readme_blob"
test "$unchanged_copy" = "$copy_blob"

git -C "$lab_dir" commit --quiet -m "docs: revise readme"
pre_amend_commit="$(git -C "$lab_dir" rev-parse HEAD)"
pre_amend_tree="$(git -C "$lab_dir" rev-parse 'HEAD^{tree}')"
pre_amend_parent="$(git -C "$lab_dir" rev-parse 'HEAD^')"
test "$pre_amend_parent" = "$first_commit"

git -C "$lab_dir" commit --quiet --amend -m "docs: explain revised readme"
amended_commit="$(git -C "$lab_dir" rev-parse HEAD)"
test "$amended_commit" != "$pre_amend_commit"
test "$(git -C "$lab_dir" rev-parse 'HEAD^{tree}')" = "$pre_amend_tree"
test "$(git -C "$lab_dir" rev-parse 'HEAD^')" = "$pre_amend_parent"
test "$(git -C "$lab_dir" cat-file -t "$pre_amend_commit")" = "commit"

git -C "$lab_dir" tag --annotate v1.0.0 --message "object model release"
git -C "$lab_dir" tag snapshot HEAD
test "$(git -C "$lab_dir" cat-file -t v1.0.0)" = "tag"
test "$(git -C "$lab_dir" cat-file -t snapshot)" = "commit"

git -C "$lab_dir" repack -ad
test "$(git -C "$lab_dir" rev-parse HEAD)" = "$amended_commit"
test "$(git -C "$lab_dir" cat-file -t "$changed_blob")" = "blob"

printf 'Object model experiment passed in isolated repository.\n'
