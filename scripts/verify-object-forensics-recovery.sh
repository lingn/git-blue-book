#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-object-forensics.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

assert_fsck_ok() {
  local repo_path="$1"
  git --no-optional-locks -C "$repo_path" fsck --full --no-progress \
    > "$lab_root/fsck-ok.out" 2>&1
}

repo="$lab_root/repository"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Object Forensics Fixture'
git -C "$repo" config user.email 'object-forensics@example.invalid'

printf 'important-v1\n' > "$repo/important.txt"
printf 'stable\n' > "$repo/stable.txt"
git -C "$repo" add important.txt stable.txt
git -C "$repo" commit --quiet -m 'fixture: trusted base'
base_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" switch --quiet -c doomed
printf 'unreachable history\n' > "$repo/lost.txt"
git -C "$repo" add lost.txt
git -C "$repo" commit --quiet -m 'fixture: later branch to recover'
doomed_commit="$(git -C "$repo" rev-parse HEAD)"
doomed_blob="$(git -C "$repo" rev-parse HEAD:lost.txt)"
git -C "$repo" switch --quiet main
git -C "$repo" branch --delete --force doomed >/dev/null

printf 'important-v2\n' > "$repo/important.txt"
git -C "$repo" add important.txt
git -C "$repo" commit --quiet -m 'fixture: current main'
main_commit="$(git -C "$repo" rev-parse HEAD)"
missing_blob="$(git -C "$repo" rev-parse HEAD:important.txt)"

donor="$lab_root/donor"
git clone --quiet --no-local "$repo" "$donor"

pristine="$lab_root/pristine"
cp -R "$repo" "$pristine"
test ! -e "$pristine/.git/lost-found"

lost_copy="$lab_root/lost-found-copy"
cp -R "$repo" "$lost_copy"
git -C "$lost_copy" fsck --no-reflogs --lost-found --no-progress \
  > "$lab_root/lost-found.out" 2>&1
lost_found_path="$(
  git -C "$lost_copy" rev-parse --path-format=absolute --git-dir
)/lost-found/commit/$doomed_commit"
test -f "$lost_found_path"
test "$(cat "$lost_found_path")" = "$doomed_commit"
test ! -e "$pristine/.git/lost-found"
grep -F "$doomed_commit" "$lab_root/lost-found.out" >/dev/null
git -C "$lost_copy" cat-file -e "$doomed_blob"

damaged="$lab_root/damaged"
cp -R "$repo" "$damaged"
damaged_objects="$(
  git -C "$damaged" rev-parse --path-format=absolute --git-path objects
)"
missing_object_path="$damaged_objects/${missing_blob:0:2}/${missing_blob:2}"
test -f "$missing_object_path"
mkdir "$lab_root/quarantine"
mv "$missing_object_path" "$lab_root/quarantine/missing-blob"
if git -C "$damaged" fsck --full --no-progress \
  > "$lab_root/missing.out" 2>&1; then
  printf 'Expected fsck to fail while a reachable blob is missing.\n' >&2
  exit 1
fi
grep -E "missing blob $missing_blob|missing" "$lab_root/missing.out" >/dev/null

alternate_path="$damaged_objects/info/alternates"
printf '%s\n' \
  "$(git -C "$donor" rev-parse --path-format=absolute --git-path objects)" \
  > "$alternate_path"
git -C "$damaged" fsck --full --no-progress \
  > "$lab_root/alternate-ok.out" 2>&1
mv "$alternate_path" "$lab_root/quarantine/alternates"
if git -C "$damaged" fsck --full --no-progress \
  > "$lab_root/alternate-removed.out" 2>&1; then
  printf 'Expected fsck to expose the missing blob after alternate removal.\n' >&2
  exit 1
fi

payload="$lab_root/missing-blob.payload"
git -C "$donor" cat-file blob "$missing_blob" > "$payload"
test "$(git -C "$damaged" hash-object "$payload")" = "$missing_blob"
test "$(git -C "$damaged" hash-object -w "$payload")" = "$missing_blob"
assert_fsck_ok "$damaged"
test "$(git -C "$damaged" show HEAD:important.txt)" = 'important-v2'

replace_repo="$lab_root/replace-repository"
cp -R "$repo" "$replace_repo"
git -C "$replace_repo" replace "$base_commit" "$main_commit"
if test "$(git -C "$replace_repo" show "$base_commit:important.txt")" != 'important-v2'; then
  printf 'Expected the replacement ref to change normal object reads.\n' >&2
  exit 1
fi
if test "$(GIT_NO_REPLACE_OBJECTS=1 git -C "$replace_repo" \
  show "$base_commit:important.txt")" != 'important-v1'; then
  printf 'Expected raw object reads to ignore the replacement ref.\n' >&2
  exit 1
fi
git -C "$replace_repo" for-each-ref --format='%(refname) %(objectname)' \
  refs/replace/ | grep -F "$base_commit" >/dev/null

pack_source="$lab_root/pack-source"
git init --quiet --initial-branch=main "$pack_source"
git -C "$pack_source" config user.name 'Pack Fixture'
git -C "$pack_source" config user.email 'pack@example.invalid'
for n in $(seq 1 30); do
  printf 'pack fixture line %s repeated repeated repeated\n' "$n" \
    > "$pack_source/file-$n.txt"
done
git -C "$pack_source" add .
git -C "$pack_source" commit --quiet -m 'fixture: pack data'
git -C "$pack_source" repack -adq
pack_pristine="$lab_root/pack-pristine"
cp -R "$pack_source" "$pack_pristine"
pack_damaged="$lab_root/pack-damaged"
cp -R "$pack_source" "$pack_damaged"
pack_dir="$(
  git -C "$pack_damaged" rev-parse --path-format=absolute --git-path objects/pack
)"
pack_file="$(find "$pack_dir" -maxdepth 1 -type f -name '*.pack' | head -n 1)"
pack_idx="${pack_file%.pack}.idx"
pack_size="$(wc -c < "$pack_file" | tr -d ' ')"
test "$pack_size" -gt 32
cp "$pack_file" "$lab_root/quarantine/original.pack"
chmod u+w "$pack_file" "$pack_idx"
truncated_pack="$lab_root/quarantine/truncated.pack"
dd if="$pack_file" of="$truncated_pack" bs=1 count="$((pack_size - 16))" \
  >/dev/null 2>&1
mv "$truncated_pack" "$pack_file"
if git -C "$pack_damaged" verify-pack -v "$pack_idx" \
  > "$lab_root/verify-pack-bad.out" 2>&1; then
  printf 'Expected verify-pack to reject the truncated pack.\n' >&2
  exit 1
fi
if git -C "$pack_damaged" fsck --full --no-progress \
  > "$lab_root/pack-bad.out" 2>&1; then
  printf 'Expected fsck to reject the truncated pack.\n' >&2
  exit 1
fi
pristine_pack="$(
  find "$pack_pristine/.git/objects/pack" -maxdepth 1 \
    -type f -name "$(basename "$pack_file")" | head -n 1
)"
cp "$pristine_pack" "$pack_file"
pristine_idx="$(
  find "$pack_pristine/.git/objects/pack" -maxdepth 1 \
    -type f -name "$(basename "$pack_idx")" | head -n 1
)"
cp "$pristine_idx" "$pack_idx"
git -C "$pack_damaged" verify-pack -v "$pack_idx" \
  > "$lab_root/verify-pack-restored.out"
assert_fsck_ok "$pack_damaged"

git -C "$damaged" fsck --no-reflogs --unreachable --no-progress \
  > "$lab_root/final-unreachable.out" 2>&1
grep -F "$doomed_commit" "$lab_root/final-unreachable.out" >/dev/null
git -C "$damaged" update-ref refs/recovery/forensics/main "$main_commit"
test "$(git -C "$damaged" rev-parse refs/recovery/forensics/main)" = "$main_commit"

printf 'Object fsck scopes, lost-found isolation, alternate masking, donor recovery, replacement refs, and pack restoration passed.\n'
