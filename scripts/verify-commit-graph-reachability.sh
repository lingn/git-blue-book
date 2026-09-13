#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-commit-graph.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$lab_dir"
  exit "$status"
}
trap cleanup EXIT

source_repo="$lab_dir/source"
shallow_repo="$lab_dir/shallow"

git init --quiet --initial-branch=main "$source_repo"
git -C "$source_repo" config user.name "Commit Graph Lab"
git -C "$source_repo" config user.email "commit-graph@example.invalid"

printf 'base\n' > "$source_repo/base.txt"
git -C "$source_repo" add base.txt
git -C "$source_repo" commit --quiet -m "base"
base_commit="$(git -C "$source_repo" rev-parse HEAD)"
test "$(git -C "$source_repo" rev-list --parents --max-count=1 "$base_commit" | wc -w | tr -d '[:space:]')" = "1"

git -C "$source_repo" branch feature "$base_commit"
printf 'main\n' > "$source_repo/main.txt"
git -C "$source_repo" add main.txt
git -C "$source_repo" commit --quiet -m "main work"
main_commit="$(git -C "$source_repo" rev-parse HEAD)"

git -C "$source_repo" switch --quiet feature
printf 'feature\n' > "$source_repo/feature.txt"
git -C "$source_repo" add feature.txt
git -C "$source_repo" commit --quiet -m "feature work"
feature_commit="$(git -C "$source_repo" rev-parse HEAD)"

test "$(git -C "$source_repo" merge-base --all "$main_commit" "$feature_commit")" = "$base_commit"
test "$(git -C "$source_repo" rev-list --left-right --count "$main_commit...$feature_commit")" = $'1\t1'
git -C "$source_repo" merge-base --is-ancestor "$base_commit" "$main_commit"
git -C "$source_repo" merge-base --is-ancestor "$base_commit" "$feature_commit"
if git -C "$source_repo" merge-base --is-ancestor "$main_commit" "$feature_commit"; then
  printf 'The two branch tips must be independent descendants of the base.\n' >&2
  exit 1
fi

git -C "$source_repo" switch --quiet main
git -C "$source_repo" merge --quiet --no-ff feature -m "merge feature"
merge_commit="$(git -C "$source_repo" rev-parse HEAD)"
read -r parsed_merge parsed_first_parent parsed_second_parent <<EOF
$(git -C "$source_repo" rev-list --parents --max-count=1 "$merge_commit")
EOF
test "$parsed_merge" = "$merge_commit"
test "$parsed_first_parent" = "$main_commit"
test "$parsed_second_parent" = "$feature_commit"
git -C "$source_repo" merge-base --is-ancestor "$main_commit" "$merge_commit"
git -C "$source_repo" merge-base --is-ancestor "$feature_commit" "$merge_commit"

merge_tree="$(git -C "$source_repo" rev-parse "$merge_commit^{tree}")"
skewed_commit="$(
  printf 'clock-skewed descendant\n' |
    GIT_AUTHOR_DATE='2000-01-01T00:00:00+0000' \
    GIT_COMMITTER_DATE='2000-01-01T00:00:00+0000' \
    git -C "$source_repo" commit-tree "$merge_tree" -p "$merge_commit"
)"
git -C "$source_repo" update-ref -m "lab: add skewed descendant" \
  refs/heads/main "$skewed_commit" "$merge_commit"
git -C "$source_repo" merge-base --is-ancestor "$merge_commit" "$skewed_commit"
merge_time="$(git -C "$source_repo" show -s --format=%ct "$merge_commit")"
skewed_time="$(git -C "$source_repo" show -s --format=%ct "$skewed_commit")"
test "$skewed_time" -lt "$merge_time"

unreachable_commit="$(
  printf 'unreachable side commit\n' |
    git -C "$source_repo" commit-tree "$merge_tree" -p "$base_commit"
)"
git -C "$source_repo" cat-file -e "$unreachable_commit^{commit}"
if git -C "$source_repo" rev-list --all | grep -Fx "$unreachable_commit" >/dev/null; then
  printf 'Expected the synthetic commit to be outside all refs.\n' >&2
  exit 1
fi
printf 'create refs/recovery/unreachable-lab %s\n' "$unreachable_commit" |
  git -C "$source_repo" update-ref --stdin
git -C "$source_repo" rev-list --all | grep -Fx "$unreachable_commit" >/dev/null

refs_before="$(git -C "$source_repo" for-each-ref --format='%(refname) %(objectname)' | LC_ALL=C sort)"
history_before="$(git -C "$source_repo" rev-list --all | LC_ALL=C sort)"
main_tree_before="$(git -C "$source_repo" rev-parse 'refs/heads/main^{tree}')"

git -C "$source_repo" commit-graph write --reachable --changed-paths
git -C "$source_repo" commit-graph verify
commit_graph_path="$(git -C "$source_repo" rev-parse --path-format=absolute --git-path objects/info/commit-graph)"
test -f "$commit_graph_path"
test "$(git -C "$source_repo" for-each-ref --format='%(refname) %(objectname)' | LC_ALL=C sort)" = "$refs_before"
test "$(git -C "$source_repo" rev-list --all | LC_ALL=C sort)" = "$history_before"
test "$(git -C "$source_repo" -c core.commitGraph=false rev-list --all | LC_ALL=C sort)" = "$history_before"
test "$(git -C "$source_repo" rev-parse 'refs/heads/main^{tree}')" = "$main_tree_before"

printf 'after graph\n' > "$source_repo/after.txt"
git -C "$source_repo" add after.txt
git -C "$source_repo" commit --quiet -m "commit after graph write"
after_graph_commit="$(git -C "$source_repo" rev-parse HEAD)"
git -C "$source_repo" merge-base --is-ancestor "$skewed_commit" "$after_graph_commit"
test "$(git -C "$source_repo" rev-list --count "$skewed_commit..$after_graph_commit")" = "1"
git -C "$source_repo" commit-graph verify
git -C "$source_repo" commit-graph write --reachable --changed-paths
git -C "$source_repo" commit-graph verify

git clone --quiet --depth=1 "file://$source_repo" "$shallow_repo"
test "$(git -C "$shallow_repo" rev-parse --is-shallow-repository)" = "true"
test "$(git -C "$shallow_repo" rev-list --count HEAD)" = "1"
if git -C "$shallow_repo" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
  printf 'Expected the depth-one clone not to contain the base commit.\n' >&2
  exit 1
fi
if git -C "$shallow_repo" merge-base HEAD "$base_commit" >/dev/null 2>&1; then
  printf 'Expected merge-base to fail while the base object is outside the shallow clone.\n' >&2
  exit 1
fi

git -C "$shallow_repo" fetch --quiet --unshallow origin
test "$(git -C "$shallow_repo" rev-parse --is-shallow-repository)" = "false"
git -C "$shallow_repo" cat-file -e "$base_commit^{commit}"
test "$(git -C "$shallow_repo" merge-base HEAD "$base_commit")" = "$base_commit"

git -C "$source_repo" fsck --full --strict >/dev/null
git -C "$shallow_repo" fsck --full --strict >/dev/null
test -z "$(git -C "$source_repo" status --short)"
test -z "$(git -C "$shallow_repo" status --short)"

printf 'Commit parents, reachability, ranges, merge-base, generation data, and shallow boundaries passed.\n'
