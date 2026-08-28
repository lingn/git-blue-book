#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-part4.XXXXXX")"
trap 'rm -rf "$lab_dir"' EXIT

mkdir "$lab_dir/seed"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"
printf '# Remote Lab\n' > "$lab_dir/seed/README.md"
git -C "$lab_dir/seed" add README.md
git -C "$lab_dir/seed" commit --quiet -m "docs: initialize remote lab"

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
git clone --quiet "$lab_dir/server.git" "$lab_dir/alice"
git clone --quiet "$lab_dir/server.git" "$lab_dir/bob"

git -C "$lab_dir/alice" config user.name "Alice"
git -C "$lab_dir/alice" config user.email "alice@example.invalid"
git -C "$lab_dir/bob" config user.name "Bob"
git -C "$lab_dir/bob" config user.email "bob@example.invalid"

test "$(git -C "$lab_dir/alice" remote)" = "origin"
test "$(git -C "$lab_dir/alice" rev-parse main)" = "$(git -C "$lab_dir/alice" rev-parse origin/main)"
test "$(git -C "$lab_dir/alice" rev-parse --is-inside-work-tree)" = "true"
test "$(git -C "$lab_dir/alice" remote get-url origin)" = "$lab_dir/server.git"
test "$(git -C "$lab_dir/alice" remote get-url --push origin)" = "$lab_dir/server.git"

printf '\nWritten by Alice.\n' >> "$lab_dir/alice/README.md"
git -C "$lab_dir/alice" add README.md
git -C "$lab_dir/alice" commit --quiet -m "docs: add Alice note"
git -C "$lab_dir/alice" push --quiet origin main

bob_before="$(git -C "$lab_dir/bob" rev-parse main)"
git -C "$lab_dir/bob" fetch --quiet origin
test "$(git -C "$lab_dir/bob" rev-parse main)" = "$bob_before"
test "$(git -C "$lab_dir/bob" rev-list --count main..origin/main)" = "1"
test "$(git -C "$lab_dir/bob" rev-parse origin/main)" = "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/main)"
grep -F "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/main)" "$lab_dir/bob/.git/FETCH_HEAD" >/dev/null

git -C "$lab_dir/bob" pull --quiet --ff-only
test "$(git -C "$lab_dir/bob" rev-parse main)" = "$(git -C "$lab_dir/bob" rev-parse origin/main)"

git -C "$lab_dir/bob" switch --quiet -c feature/search
printf '# Search\n' > "$lab_dir/bob/SEARCH.md"
git -C "$lab_dir/bob" add SEARCH.md
git -C "$lab_dir/bob" commit --quiet -m "docs: add search guide"
git -C "$lab_dir/bob" push --quiet -u origin feature/search
test "$(git -C "$lab_dir/bob" rev-parse '@{upstream}')" = "$(git -C "$lab_dir/bob" rev-parse HEAD)"
test "$(git -C "$lab_dir/bob" config --get branch.feature/search.remote)" = "origin"
test "$(git -C "$lab_dir/bob" config --get branch.feature/search.merge)" = "refs/heads/feature/search"

git -C "$lab_dir/bob" tag -a v0.1.0 -m "Remote lab release" main
git -C "$lab_dir/bob" push --quiet origin v0.1.0
test "$(git --git-dir="$lab_dir/server.git" cat-file -t v0.1.0)" = "tag"
test "$(git --git-dir="$lab_dir/server.git" rev-parse v0.1.0^{commit})" = "$(git -C "$lab_dir/bob" rev-parse main)"

printf 'Part 4 clone, fetch, pull, push, upstream, and tag experiments passed.\n'
