#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-lease.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

mkdir "$lab_dir/seed"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"
printf 'stable\n' > "$lab_dir/seed/app.txt"
git -C "$lab_dir/seed" add app.txt
git -C "$lab_dir/seed" commit --quiet -m "feat: add stable behavior"

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
git clone --quiet "$lab_dir/server.git" "$lab_dir/alice"
git -C "$lab_dir/alice" config user.name "Alice"
git -C "$lab_dir/alice" config user.email "alice@example.invalid"

git -C "$lab_dir/alice" switch --quiet -c feature/rewrite
printf 'first feature version\n' > "$lab_dir/alice/feature.txt"
git -C "$lab_dir/alice" add feature.txt
git -C "$lab_dir/alice" commit --quiet -m "feat: add feature draft"
git -C "$lab_dir/alice" push --quiet -u origin feature/rewrite
expected_remote="$(git -C "$lab_dir/alice" rev-parse origin/feature/rewrite)"
git -C "$lab_dir/alice" branch recovery/feature-before-rewrite "$expected_remote"

git clone --quiet "$lab_dir/server.git" "$lab_dir/bob"
git -C "$lab_dir/bob" config user.name "Bob"
git -C "$lab_dir/bob" config user.email "bob@example.invalid"
git -C "$lab_dir/bob" switch --quiet --create feature/rewrite --track origin/feature/rewrite
printf 'Bob contribution\n' > "$lab_dir/bob/bob-note.txt"
git -C "$lab_dir/bob" add bob-note.txt
git -C "$lab_dir/bob" commit --quiet -m "docs: add Bob contribution"
bob_commit="$(git -C "$lab_dir/bob" rev-parse HEAD)"
git -C "$lab_dir/bob" push --quiet origin feature/rewrite
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/feature/rewrite)" = "$bob_commit"

printf 'Alice rewritten version\n' > "$lab_dir/alice/feature.txt"
git -C "$lab_dir/alice" add feature.txt
git -C "$lab_dir/alice" commit --quiet --amend -m "feat: rewrite feature draft"

if git -C "$lab_dir/alice" push --quiet \
  --force-with-lease=refs/heads/feature/rewrite:"$expected_remote" \
  origin HEAD:refs/heads/feature/rewrite >/dev/null 2>&1; then
  printf 'Expected stale explicit lease to reject the force push.\n' >&2
  exit 1
fi
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/feature/rewrite)" = "$bob_commit"

git -C "$lab_dir/alice" fetch --quiet origin
current_remote="$(git -C "$lab_dir/alice" rev-parse origin/feature/rewrite)"
test "$current_remote" = "$bob_commit"
git -C "$lab_dir/alice" branch recovery/server-before-coordinated-force "$current_remote"

git -C "$lab_dir/alice" cherry-pick "$bob_commit" >/dev/null
coordinated_rewrite="$(git -C "$lab_dir/alice" rev-parse HEAD)"
test "$(git -C "$lab_dir/alice" show HEAD:bob-note.txt)" = "Bob contribution"
git -C "$lab_dir/alice" push --quiet \
  --force-with-lease=refs/heads/feature/rewrite:"$current_remote" \
  origin HEAD:refs/heads/feature/rewrite
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/feature/rewrite)" = "$coordinated_rewrite"

git -C "$lab_dir/alice" push --quiet \
  --force-with-lease=refs/heads/feature/rewrite:"$coordinated_rewrite" \
  origin recovery/server-before-coordinated-force:refs/heads/feature/rewrite
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/feature/rewrite)" = "$bob_commit"
test "$(git --git-dir="$lab_dir/server.git" show refs/heads/feature/rewrite:bob-note.txt)" = "Bob contribution"

printf 'Explicit lease rejection, coordinated update, and recovery passed.\n'
