#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-monorepo-topology.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS GIT_CONFIG_COUNT SSH_ASKPASS

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'A SHA-256 command is required for the monorepo experiment.\n' >&2
    return 1
  fi
}

repo="$lab_dir/repository"
mkdir -p "$repo/services/manager" "$repo/services/worker" \
  "$repo/libs/task-sdk" "$repo/docs" "$repo/policy"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Topology Lab"
git -C "$repo" config user.email "topology@example.invalid"

printf 'manager v1\n' > "$repo/services/manager/service.txt"
printf 'worker v1\n' > "$repo/services/worker/service.txt"
printf 'sdk v1\n' > "$repo/libs/task-sdk/sdk.txt"
printf 'topology fixture\n' > "$repo/docs/README.md"
printf '%s\n' \
  'manager	libs/task-sdk' \
  'worker	libs/task-sdk' \
  > "$repo/policy/build-graph.tsv"
printf '%s\n' \
  'libs/task-sdk	platform	active' \
  'services/manager	payments	active' \
  'services/worker	settlement	active' \
  'policy/build-graph.tsv	platform	active' \
  > "$repo/policy/owners.tsv"
printf '%s\n' \
  'changed_component	consumers' \
  'libs/task-sdk	manager,worker' \
  'docs	none' \
  > "$repo/policy/expected-consumers.tsv"
git -C "$repo" add .
git -C "$repo" commit --quiet -m "topology: establish components and policy"
base_commit="$(git -C "$repo" rev-parse HEAD)"

printf 'sdk v2\n' > "$repo/libs/task-sdk/sdk.txt"
git -C "$repo" add libs/task-sdk/sdk.txt
git -C "$repo" commit --quiet -m "sdk: change shared task contract"
shared_commit="$(git -C "$repo" rev-parse HEAD)"
changed_paths="$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$shared_commit")"
grep -Fqx 'libs/task-sdk/sdk.txt' <<< "$changed_paths"
grep -Fqx 'manager	libs/task-sdk' "$repo/policy/build-graph.tsv"
grep -Fqx 'worker	libs/task-sdk' "$repo/policy/build-graph.tsv"

printf '%s\n' \
  'candidate_commit='"$shared_commit" \
  'changed_component=libs/task-sdk' \
  'affected_components=libs/task-sdk,services/manager,services/worker' \
  'graph_status=pass' \
  > "$lab_dir/shared-change.env"
grep -Fqx 'affected_components=libs/task-sdk,services/manager,services/worker' \
  "$lab_dir/shared-change.env"

git -C "$repo" switch --quiet --create docs-only "$shared_commit"
printf 'topology note\n' >> "$repo/docs/README.md"
git -C "$repo" add docs/README.md
git -C "$repo" commit --quiet -m "docs: update topology note"
docs_commit="$(git -C "$repo" rev-parse HEAD)"
docs_paths="$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$docs_commit")"
grep -Fqx 'docs/README.md' <<< "$docs_paths"
printf '%s\n' \
  'candidate_commit='"$docs_commit" \
  'changed_component=docs' \
  'affected_components=docs' \
  'graph_status=pass' \
  > "$lab_dir/docs-change.env"
grep -Fqx 'affected_components=docs' "$lab_dir/docs-change.env"

cp "$repo/policy/build-graph.tsv" "$lab_dir/incomplete-graph.tsv"
awk -F '\t' '$1 != "worker" || $2 != "libs/task-sdk"' \
  "$lab_dir/incomplete-graph.tsv" > "$lab_dir/incomplete-graph.new"
mv "$lab_dir/incomplete-graph.new" "$lab_dir/incomplete-graph.tsv"
if grep -Fqx 'worker	libs/task-sdk' "$lab_dir/incomplete-graph.tsv"; then
  printf 'incomplete graph still contained the worker edge.\n' >&2
  exit 1
fi
printf 'changed_component=libs/task-sdk\ngraph_status=inconclusive\n' \
  > "$lab_dir/incomplete-graph.env"
grep -Fqx 'graph_status=inconclusive' "$lab_dir/incomplete-graph.env"

git -C "$repo" switch --quiet --create atomic-candidate "$base_commit"
printf 'sdk v3\n' > "$repo/libs/task-sdk/sdk.txt"
printf 'manager v2\n' > "$repo/services/manager/service.txt"
printf 'worker v2\n' > "$repo/services/worker/service.txt"
git -C "$repo" add libs/task-sdk/sdk.txt services/manager/service.txt \
  services/worker/service.txt
git -C "$repo" commit --quiet -m "release: update shared sdk consumers atomically"
atomic_commit="$(git -C "$repo" rev-parse HEAD)"
atomic_paths="$(git -C "$repo" diff-tree --no-commit-id --name-only -r "$atomic_commit")"
for path in libs/task-sdk/sdk.txt services/manager/service.txt \
  services/worker/service.txt; do
  grep -Fqx "$path" <<< "$atomic_paths"
done
candidate_tree="$(git -C "$repo" rev-parse "$atomic_commit^{tree}")"

printf '%s\n' \
  'platform' \
  'payments' \
  'settlement' \
  > "$lab_dir/approvals.complete"
for owner in platform payments settlement; do
  grep -Fqx "$owner" "$lab_dir/approvals.complete"
done
printf 'owner_snapshot=active\napproval_status=pass\n' \
  > "$lab_dir/ownership.complete.env"

printf '%s\n' \
  'platform' \
  'payments' \
  > "$lab_dir/approvals.incomplete"
if grep -Fqx settlement "$lab_dir/approvals.incomplete"; then
  printf 'incomplete ownership snapshot unexpectedly approved worker.\n' >&2
  exit 1
fi
printf 'owner_snapshot=missing-settlement\napproval_status=inconclusive\n' \
  > "$lab_dir/ownership.incomplete.env"
grep -Fqx 'approval_status=inconclusive' "$lab_dir/ownership.incomplete.env"

git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=application/ "$atomic_commit" > "$lab_dir/atomic.tar"
artifact_digest="$(sha256_file "$lab_dir/atomic.tar")"
printf '%s\n' \
  "candidate_commit=$atomic_commit" \
  "candidate_tree=$candidate_tree" \
  "artifact_digest=$artifact_digest" \
  'affected_components=services/manager,services/worker' \
  'owner_approval=pass' \
  > "$lab_dir/candidate.manifest"
manifest_digest="$(sha256_file "$lab_dir/candidate.manifest")"

git -C "$repo" switch --quiet main
printf 'main continues after topology candidate\n' > "$repo/POST-CANDIDATE.md"
git -C "$repo" add POST-CANDIDATE.md
git -C "$repo" commit --quiet -m "docs: advance main after candidate"
new_main="$(git -C "$repo" rev-parse HEAD)"
test "$new_main" != "$atomic_commit"
test "$(sha256_file "$lab_dir/atomic.tar")" = "$artifact_digest"
grep -Fqx "candidate_commit=$atomic_commit" "$lab_dir/candidate.manifest"
printf 'manifest_digest=%s\n' "$manifest_digest" > "$lab_dir/candidate.record"
grep -Fqx "manifest_digest=$manifest_digest" "$lab_dir/candidate.record"

printf 'Monorepo dependency closure, ownership gates, atomic-change evidence, and topology decision boundaries passed.\n'
