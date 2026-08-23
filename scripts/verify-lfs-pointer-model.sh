#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-lfs-pointer.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

object_store="$lab_root/external-object-store"
mkdir "$object_store"

clean_filter="$lab_root/model-lfs-clean"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'store="$1"' \
  'tmp="$(mktemp "${TMPDIR:-/tmp}/model-lfs-clean.XXXXXX")"' \
  'trap '\''rm -f -- "$tmp"'\'' EXIT' \
  'cat > "$tmp"' \
  'version="$(sed -n '\''1p'\'' "$tmp")"' \
  'oid_line="$(sed -n '\''2p'\'' "$tmp")"' \
  'size_line="$(sed -n '\''3p'\'' "$tmp")"' \
  'fourth_line="$(sed -n '\''4p'\'' "$tmp")"' \
  'if test "$version" = "version https://git-lfs.github.com/spec/v1" &&' \
  '   test "${oid_line#oid sha256:}" != "$oid_line" &&' \
  '   test "${size_line#size }" != "$size_line" &&' \
  '   test -z "$fourth_line"; then' \
  '  cat "$tmp"' \
  '  exit 0' \
  'fi' \
  'if command -v sha256sum >/dev/null 2>&1; then' \
  '  oid="$(sha256sum "$tmp" | awk '\''{print $1}'\'')"' \
  'else' \
  '  oid="$(shasum -a 256 "$tmp" | awk '\''{print $1}'\'')"' \
  'fi' \
  'size="$(wc -c < "$tmp" | tr -d '\'' '\'')"' \
  'cp "$tmp" "$store/$oid"' \
  'printf "version https://git-lfs.github.com/spec/v1\\noid sha256:%s\\nsize %s\\n" "$oid" "$size"' \
  > "$clean_filter"
chmod +x "$clean_filter"

smudge_filter="$lab_root/model-lfs-smudge"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'store="$1"' \
  'tmp="$(mktemp "${TMPDIR:-/tmp}/model-lfs-smudge.XXXXXX")"' \
  'trap '\''rm -f -- "$tmp"'\'' EXIT' \
  'cat > "$tmp"' \
  'version="$(sed -n '\''1p'\'' "$tmp")"' \
  'oid_line="$(sed -n '\''2p'\'' "$tmp")"' \
  'size_line="$(sed -n '\''3p'\'' "$tmp")"' \
  'fourth_line="$(sed -n '\''4p'\'' "$tmp")"' \
  'if test "$version" != "version https://git-lfs.github.com/spec/v1" ||' \
  '   test "${oid_line#oid sha256:}" = "$oid_line" ||' \
  '   test "${size_line#size }" = "$size_line" ||' \
  '   test -n "$fourth_line"; then' \
  '  cat "$tmp"' \
  '  exit 0' \
  'fi' \
  'oid="${oid_line#oid sha256:}"' \
  'expected_size="${size_line#size }"' \
  'case "$oid" in *[!0-9a-f]*|'\''\'''\'') exit 4 ;; esac' \
  'test "${#oid}" = 64' \
  'case "$expected_size" in *[!0-9]*|'\''\'''\'') exit 5 ;; esac' \
  'object="$store/$oid"' \
  'test -f "$object" || { printf "missing external object %s\\n" "$oid" >&2; exit 6; }' \
  'if command -v sha256sum >/dev/null 2>&1; then' \
  '  actual_oid="$(sha256sum "$object" | awk '\''{print $1}'\'')"' \
  'else' \
  '  actual_oid="$(shasum -a 256 "$object" | awk '\''{print $1}'\'')"' \
  'fi' \
  'actual_size="$(wc -c < "$object" | tr -d '\'' '\'')"' \
  'test "$actual_oid" = "$oid"' \
  'test "$actual_size" = "$expected_size"' \
  'cat "$object"' \
  > "$smudge_filter"
chmod +x "$smudge_filter"

repo="$lab_root/source"
git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Asset Author'
git -C "$repo" config user.email 'asset@example.invalid'
git -C "$repo" config filter.model-lfs.clean "$clean_filter '$object_store'"
git -C "$repo" config filter.model-lfs.smudge "$smudge_filter '$object_store'"
git -C "$repo" config filter.model-lfs.required true

mkdir -p "$repo/assets"
printf '*.bin filter=model-lfs -text\n' > "$repo/.gitattributes"
printf 'MODEL-ASSET-V1\000\001\002\377\n' > "$repo/assets/model.bin"
cp "$repo/assets/model.bin" "$lab_root/model-v1.bin"
git -C "$repo" add .gitattributes assets/model.bin
git -C "$repo" commit --quiet -m 'asset: add first external binary revision'

pointer_v1="$lab_root/pointer-v1"
git -C "$repo" show HEAD:assets/model.bin > "$pointer_v1"
grep -q '^version https://git-lfs.github.com/spec/v1$' "$pointer_v1"
grep -Eq '^oid sha256:[0-9a-f]{64}$' "$pointer_v1"
grep -Eq '^size [0-9]+$' "$pointer_v1"
test "$(wc -l < "$pointer_v1" | tr -d ' ')" = '3'
cmp "$repo/assets/model.bin" "$lab_root/model-v1.bin"

oid_v1="$(sed -n 's/^oid sha256://p' "$pointer_v1")"
size_v1="$(sed -n 's/^size //p' "$pointer_v1")"
test -f "$object_store/$oid_v1"
test "$(wc -c < "$object_store/$oid_v1" | tr -d ' ')" = "$size_v1"

printf 'MODEL-ASSET-V2\000\003\004\376\n' > "$repo/assets/model.bin"
cp "$repo/assets/model.bin" "$lab_root/model-v2.bin"
git -C "$repo" add assets/model.bin
git -C "$repo" commit --quiet -m 'asset: add second external binary revision'

pointer_v2="$lab_root/pointer-v2"
git -C "$repo" show HEAD:assets/model.bin > "$pointer_v2"
oid_v2="$(sed -n 's/^oid sha256://p' "$pointer_v2")"
test "$oid_v2" != "$oid_v1"
test -f "$object_store/$oid_v1"
test -f "$object_store/$oid_v2"
test "$(find "$object_store" -type f | wc -l | tr -d ' ')" = '2'

clone="$lab_root/clone"
git clone --quiet --no-local "$repo" "$clone"
cmp "$clone/assets/model.bin" "$pointer_v2"
test "$(git -C "$clone" config --get filter.model-lfs.smudge || :)" = ''

git -C "$clone" config filter.model-lfs.clean "$clean_filter '$object_store'"
git -C "$clone" config filter.model-lfs.smudge "$smudge_filter '$object_store'"
git -C "$clone" config filter.model-lfs.required true
rm "$clone/assets/model.bin"
git -C "$clone" restore --source=HEAD --worktree -- assets/model.bin
cmp "$clone/assets/model.bin" "$lab_root/model-v2.bin"

cleaned_clone="$lab_root/cleaned-clone-v2"
"$clean_filter" "$object_store" < "$clone/assets/model.bin" > "$cleaned_clone"
cmp "$cleaned_clone" "$pointer_v2"
expected_blob="$(git -C "$clone" rev-parse 'HEAD:assets/model.bin')"
actual_blob="$(git -C "$clone" hash-object --path assets/model.bin assets/model.bin)"
test "$actual_blob" = "$expected_blob"
git -C "$clone" add -- assets/model.bin

status_after_hydration="$(git -C "$clone" status --porcelain=v1)"
if test -n "$status_after_hydration"; then
  printf 'Expected a clean worktree after reversible clean/smudge conversion; got:\n%s\n' \
    "$status_after_hydration" >&2
  exit 1
fi

quarantined_object="$lab_root/quarantined-$oid_v2"
mv "$object_store/$oid_v2" "$quarantined_object"
rm "$clone/assets/model.bin"
if git -C "$clone" restore --source=HEAD --worktree -- assets/model.bin \
  >/dev/null 2>&1; then
  printf 'Expected required smudge to fail when the external object is missing.\n' >&2
  exit 1
fi
git -C "$clone" fsck --full --no-progress >/dev/null
mv "$quarantined_object" "$object_store/$oid_v2"
git -C "$clone" restore --source=HEAD --worktree -- assets/model.bin
cmp "$clone/assets/model.bin" "$lab_root/model-v2.bin"
git -C "$clone" add -- assets/model.bin
test -z "$(git -C "$clone" status --porcelain=v1)"

printf 'LFS pointer model, external object integrity, missing-object failure, and recovery passed.\n'
