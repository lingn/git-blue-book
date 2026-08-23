#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d /tmp/git-blue-book-corruption-locks.XXXXXX)"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Corruption Lock Lab'
git -C "$repo" config user.email 'corruption-lock@example.invalid'

printf 'base\n' > "$repo/data.txt"
git -C "$repo" add data.txt
git -C "$repo" commit --quiet -m 'fixture: base'
printf 'second\n' >> "$repo/data.txt"
git -C "$repo" add data.txt
git -C "$repo" commit --quiet -m 'fixture: second'

head_before="$(git -C "$repo" rev-parse HEAD)"
status_before="$(git -C "$repo" status --porcelain=v1)"

# A live writer owns index.lock while a clean filter is running. A second
# writer must fail without changing the index or the worktree.
printf 'data.txt filter=slow\n' > "$repo/.gitattributes"
git -C "$repo" add .gitattributes
git -C "$repo" commit --quiet --no-verify -m 'fixture: slow filter setup'
printf '#!/usr/bin/env bash\nsleep 1\ncat\n' > "$repo/.git/slow-clean.sh"
chmod +x "$repo/.git/slow-clean.sh"
git -C "$repo" config filter.slow.clean "$repo/.git/slow-clean.sh"
git -C "$repo" config filter.slow.smudge cat
printf 'background\n' >> "$repo/data.txt"
git -C "$repo" add data.txt \
  > "$lab_root/slow-writer.stdout" 2> "$lab_root/slow-writer.stderr" &
writer_pid="$!"
lock_seen=0
for attempt in $(seq 1 100); do
  if test -e "$repo/.git/index.lock"; then
    lock_seen=1
    break
  fi
  sleep 0.02
done
test "$lock_seen" -eq 1
second_writer_status=0
git -C "$repo" add data.txt > "$lab_root/second-writer.stdout" \
  2> "$lab_root/second-writer.stderr" || second_writer_status="$?"
test "$second_writer_status" -ne 0
grep -E 'index\.lock|File exists|another git process' \
  "$lab_root/second-writer.stderr" >/dev/null
wait "$writer_pid"
git -C "$repo" config --unset filter.slow.clean
git -C "$repo" config --unset filter.slow.smudge
git -C "$repo" commit --quiet --no-verify -m 'fixture: slow writer completed'
test "$(git -C "$repo" rev-parse HEAD)" != "$head_before"

# A deliberately stale index lock blocks a writer. The safe sequence in this
# isolated lab is: prove the test writer has exited, compare the index, remove
# exactly this lock, and retry. Production recovery must additionally inspect
# process ownership, mtime and host/storage health before removal.
head_after_slow="$(git -C "$repo" rev-parse HEAD)"
tree_after_slow="$(git -C "$repo" rev-parse HEAD^{tree})"
index_after_slow="$(git -C "$repo" ls-files --stage)"
printf 'stale lock marker\n' > "$repo/.git/index.lock"
stale_status=0
git -C "$repo" add data.txt > "$lab_root/stale-index.stdout" \
  2> "$lab_root/stale-index.stderr" || stale_status="$?"
test "$stale_status" -ne 0
test "$(git -C "$repo" rev-parse HEAD)" = "$head_after_slow"
test "$(git -C "$repo" ls-files --stage)" = "$index_after_slow"
rm -f "$repo/.git/index.lock"

# A ref lock blocks an atomic ref update and leaves the old ref intact.
old_ref="$(git -C "$repo" rev-parse refs/heads/main)"
new_ref="$(printf 'fixture: ref candidate\n' | git -C "$repo" commit-tree \
  "$(git -C "$repo" rev-parse HEAD^{tree})" -p "$old_ref")"
printf 'stale ref lock marker\n' > "$repo/.git/refs/heads/main.lock"
ref_status=0
git -C "$repo" update-ref refs/heads/main "$new_ref" "$old_ref" \
  > "$lab_root/stale-ref.stdout" 2> "$lab_root/stale-ref.stderr" \
  || ref_status="$?"
test "$ref_status" -ne 0
test "$(git -C "$repo" rev-parse refs/heads/main)" = "$old_ref"
rm -f "$repo/.git/refs/heads/main.lock"

# The expected-value update succeeds once the exact stale lock is removed.
git -C "$repo" update-ref refs/heads/main "$new_ref" "$old_ref"
test "$(git -C "$repo" rev-parse refs/heads/main)" = "$new_ref"

# Corrupting a pack is an object-integrity incident, not a lock incident. Work
# on a disposable copy and restore the original pack from a pristine donor.
git -C "$repo" repack -adq
pristine="$lab_root/pristine"
damaged="$lab_root/damaged"
cp -R "$repo" "$pristine"
cp -R "$repo" "$damaged"
pack_dir="$(git -C "$damaged" rev-parse --path-format=absolute --git-path objects/pack)"
pack_file="$(find "$pack_dir" -maxdepth 1 -type f -name '*.pack' | head -n 1)"
pack_idx="${pack_file%.pack}.idx"
pack_size="$(wc -c < "$pack_file" | tr -d ' ')"
test "$pack_size" -gt 32
cp "$pack_file" "$lab_root/original.pack"
chmod u+w "$pack_file" "$pack_idx"
dd if="$pack_file" of="$lab_root/truncated.pack" bs=1 \
  count="$((pack_size - 16))" >/dev/null 2>&1
mv "$lab_root/truncated.pack" "$pack_file"
if git -C "$damaged" fsck --full --strict --no-progress \
  > "$lab_root/damaged.fsck" 2>&1; then
  printf 'Expected fsck to fail for the truncated pack.\n' >&2
  exit 1
fi
damaged_ref_path="$(git -C "$damaged" rev-parse \
  --path-format=absolute --git-path refs/heads/main)"
test "$(tr -d '\n' < "$damaged_ref_path")" = "$new_ref"

pristine_pack="$(find "$pristine/.git/objects/pack" -maxdepth 1 \
  -type f -name "$(basename "$pack_file")" | head -n 1)"
pristine_idx="${pristine_pack%.pack}.idx"
cp "$pristine_pack" "$pack_file"
cp "$pristine_idx" "$pack_idx"
git -C "$damaged" fsck --full --strict --no-progress \
  > "$lab_root/restored.fsck" 2>&1
test "$(git -C "$damaged" rev-parse HEAD)" = "$new_ref"
test "$(git -C "$damaged" rev-parse HEAD^{tree})" = "$tree_after_slow"

# The final repository remains internally readable and the deliberate ref
# update did not alter the worktree or index contents.
test "$(git -C "$repo" status --porcelain=v1)" = "$status_before"
git -C "$repo" fsck --full --strict --no-progress > "$lab_root/final.fsck" 2>&1
printf 'Concurrent writer rejection, stale lock boundaries, pack corruption classification, and donor restoration passed.\n'
