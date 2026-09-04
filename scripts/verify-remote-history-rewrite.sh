#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-remote-rewrite.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

seed="$lab_root/seed"
server="$lab_root/server.git"
client="$lab_root/client"
rewriter="$lab_root/rewriter"

git -C "$lab_root" init --quiet --initial-branch=main "$seed"
git -C "$seed" config user.name "History Seed"
git -C "$seed" config user.email "history-seed@example.invalid"

printf 'shared base\n' > "$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit --quiet -m "docs: add shared base"
common_base="$(git -C "$seed" rev-parse HEAD)"

git -C "$seed" switch --quiet --create feature/rewrite
for number in 1 2 3; do
  printf 'task change %s\n' "$number" > "$seed/task-$number.txt"
  git -C "$seed" add "task-$number.txt"
  git -C "$seed" commit --quiet -m "feat: add task change $number"
done
old_tip="$(git -C "$seed" rev-parse HEAD)"

git clone --quiet --bare "$seed" "$server"
git -C "$server" symbolic-ref HEAD refs/heads/feature/rewrite
git clone --quiet "$server" "$client"
git -C "$client" config user.name "History Client"
git -C "$client" config user.email "history-client@example.invalid"
test "$(git -C "$client" rev-parse HEAD)" = "$old_tip"

git clone --quiet "$server" "$rewriter"
git -C "$rewriter" config user.name "History Rewriter"
git -C "$rewriter" config user.email "history-rewriter@example.invalid"
git -C "$rewriter" reset --quiet --hard "$common_base"

mkdir "$rewriter/baseline"
for number in 1 2 3 4 5 6; do
  printf 'baseline change %s\n' "$number" > "$rewriter/baseline/$number.txt"
  git -C "$rewriter" add "baseline/$number.txt"
  git -C "$rewriter" commit --quiet -m "base: add upstream change $number"
done
new_series_base="$(git -C "$rewriter" rev-parse HEAD)"

# Reapply the same three patches on a new parent chain. Their patch IDs match
# the old commits, but their commit IDs differ because their parents differ.
for number in 1 2 3; do
  printf 'task change %s\n' "$number" > "$rewriter/task-$number.txt"
  git -C "$rewriter" add "task-$number.txt"
  git -C "$rewriter" commit --quiet -m "feat: add task change $number"
done
new_tip="$(git -C "$rewriter" rev-parse HEAD)"
test "$new_tip" != "$old_tip"

git -C "$rewriter" push --quiet --force \
  origin HEAD:refs/heads/feature/rewrite

LC_ALL=C git -C "$client" fetch --verbose origin \
  >"$lab_root/fetch.log" 2>&1
grep -Eiq 'forced[- ]update' "$lab_root/fetch.log"

set -- $(
  git -C "$client" rev-list --left-right --count \
    HEAD...origin/feature/rewrite
)
test "$1" = "3"
test "$2" = "9"
branch_status="$(git -C "$client" status --short --branch)"
grep -Fq 'ahead 3, behind 9' <<<"$branch_status"
test "$(git -C "$client" merge-base HEAD origin/feature/rewrite)" = "$common_base"

cherry_output="$(git -C "$client" cherry origin/feature/rewrite HEAD)"
test "$(printf '%s\n' "$cherry_output" | wc -l | tr -d ' ')" = "3"
if printf '%s\n' "$cherry_output" | grep -qv '^- '; then
  printf 'Expected all old local commits to have patch-equivalent upstream commits.\n' >&2
  exit 1
fi

git -C "$client" range-diff \
  "$common_base"..HEAD \
  "$new_series_base"..origin/feature/rewrite \
  >"$lab_root/range-diff.log"
grep -Fq 'feat: add task change 1' "$lab_root/range-diff.log"

tracking_reflog="$(
  git -C "$client" reflog show \
    --format='%gs' refs/remotes/origin/feature/rewrite
)"
grep -Fq 'forced-update' <<<"$tracking_reflog"

# Insert a failing exec before the first replay. This leaves a real rebase in
# progress after checkout of the new base, so abort can prove the old tip is
# restored without relying on a platform or a hand-crafted reflog.
sequence_editor="$lab_root/stop-before-replay.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '{ printf '\''exec false\n'\''; cat "$1"; } > "$1.tmp"' \
  'mv "$1.tmp" "$1"' > "$sequence_editor"
chmod +x "$sequence_editor"

if GIT_SEQUENCE_EDITOR="$sequence_editor" \
  git -C "$client" rebase --interactive --reapply-cherry-picks \
    origin/feature/rewrite >"$lab_root/rebase.log" 2>&1; then
  printf 'Expected the injected rebase exec to stop the rebase.\n' >&2
  exit 1
fi
test -d "$client/.git/rebase-merge"
test "$(git -C "$client" rev-parse HEAD)" = "$new_tip"

git -C "$client" rebase --abort
test "$(git -C "$client" branch --show-current)" = "feature/rewrite"
test "$(git -C "$client" rev-parse HEAD)" = "$old_tip"
test -z "$(git -C "$client" status --porcelain)"
head_reflog="$(git -C "$client" reflog show --format='%gs' HEAD)"
grep -Fq 'rebase (start): checkout origin/feature/rewrite' <<<"$head_reflog"
grep -Fq 'rebase (abort): returning to refs/heads/feature/rewrite' <<<"$head_reflog"

git -C "$client" branch recovery/before-remote-sync "$old_tip"
git -C "$client" reset --quiet --hard origin/feature/rewrite
test "$(git -C "$client" rev-parse HEAD)" = "$new_tip"
test "$(git -C "$client" rev-parse recovery/before-remote-sync)" = "$old_tip"
test -z "$(git -C "$client" status --porcelain)"
test "$(git -C "$client" rev-list --left-right --count HEAD...origin/feature/rewrite)" = $'0\t0'

printf 'Remote rewrite ahead/behind counts, evidence, abort, and recovery passed.\n'
