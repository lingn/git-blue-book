#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d /tmp/git-blue-book-external-dependency.XXXXXX)"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

lfs_store="$lab_root/lfs-store"
mkdir "$lfs_store"

clean_filter="$lab_root/fixture-lfs-clean"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'store="$1"' \
  'tmp="$(mktemp /tmp/fixture-lfs-clean.XXXXXX)"' \
  'trap '\''rm -f -- "$tmp"'\'' EXIT' \
  'cat > "$tmp"' \
  'if test "$(sed -n '\''1p'\'' "$tmp")" = "version https://git-lfs.github.com/spec/v1"; then' \
  '  cat "$tmp"' \
  '  exit 0' \
  'fi' \
  'if command -v sha256sum >/dev/null 2>&1; then oid="$(sha256sum "$tmp" | awk '\''{print $1}'\'')"; else oid="$(shasum -a 256 "$tmp" | awk '\''{print $1}'\'')"; fi' \
  'size="$(wc -c < "$tmp" | tr -d '\'' '\'')"' \
  'cp "$tmp" "$store/$oid"' \
  'printf "version https://git-lfs.github.com/spec/v1\\noid sha256:%s\\nsize %s\\n" "$oid" "$size" > "$tmp.pointer"' \
  'cat "$tmp.pointer"' \
  > "$clean_filter"
chmod +x "$clean_filter"

smudge_filter="$lab_root/fixture-lfs-smudge"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'store="$1"' \
  'tmp="$(mktemp /tmp/fixture-lfs-smudge.XXXXXX)"' \
  'trap '\''rm -f -- "$tmp"'\'' EXIT' \
  'cat > "$tmp"' \
  'if test "$(sed -n '\''1p'\'' "$tmp")" != "version https://git-lfs.github.com/spec/v1"; then cat "$tmp"; exit 0; fi' \
  'oid="$(sed -n '\''s/^oid sha256://p'\'' "$tmp")"' \
  'expected_size="$(sed -n '\''s/^size //p'\'' "$tmp")"' \
  'test -n "$oid" && test -n "$expected_size"' \
  'object="$store/$oid"' \
  'test -f "$object" || { printf "missing external object %s\\n" "$oid" >&2; exit 6; }' \
  'if command -v sha256sum >/dev/null 2>&1; then actual_oid="$(sha256sum "$object" | awk '\''{print $1}'\'')"; else actual_oid="$(shasum -a 256 "$object" | awk '\''{print $1}'\'')"; fi' \
  'actual_size="$(wc -c < "$object" | tr -d '\'' '\'')"' \
  'test "$actual_oid" = "$oid" && test "$actual_size" = "$expected_size"' \
  'cat "$object"' \
  > "$smudge_filter"
chmod +x "$smudge_filter"

lfs_repo="$lab_root/lfs-repository"
git init --quiet --initial-branch=main "$lfs_repo"
git -C "$lfs_repo" config user.name 'External Dependency Fixture'
git -C "$lfs_repo" config user.email 'external-dependency@example.invalid'
git -C "$lfs_repo" config filter.fixture-lfs.clean "$clean_filter $lfs_store"
git -C "$lfs_repo" config filter.fixture-lfs.smudge "$smudge_filter $lfs_store"
git -C "$lfs_repo" config filter.fixture-lfs.required true
mkdir -p "$lfs_repo/assets"
printf '*.bin filter=fixture-lfs -text\n' > "$lfs_repo/.gitattributes"
printf 'LFS-FIXTURE-V1\000\001\002\377\n' > "$lfs_repo/assets/model.bin"
payload="$lab_root/payload.bin"
cp "$lfs_repo/assets/model.bin" "$payload"
git -C "$lfs_repo" add .gitattributes assets/model.bin
git -C "$lfs_repo" commit --quiet -m 'fixture: add external payload'
lfs_candidate="$(git -C "$lfs_repo" rev-parse HEAD)"
pointer="$lab_root/pointer.txt"
git -C "$lfs_repo" show "$lfs_candidate:assets/model.bin" > "$pointer"
grep -Fx 'version https://git-lfs.github.com/spec/v1' "$pointer" >/dev/null
lfs_oid="$(sed -n 's/^oid sha256://p' "$pointer")"
lfs_size="$(sed -n 's/^size //p' "$pointer")"
test -f "$lfs_store/$lfs_oid"
test "$lfs_size" = "$(wc -c < "$payload" | tr -d ' ')"

lfs_clone="$lab_root/lfs-clone"
git clone --quiet --no-local "$lfs_repo" "$lfs_clone"
git -C "$lfs_clone" config filter.fixture-lfs.clean "$clean_filter $lfs_store"
git -C "$lfs_clone" config filter.fixture-lfs.smudge "$smudge_filter $lfs_store"
git -C "$lfs_clone" config filter.fixture-lfs.required true
rm "$lfs_clone/assets/model.bin"
git -C "$lfs_clone" restore --source=HEAD --worktree -- assets/model.bin
cmp "$lfs_clone/assets/model.bin" "$payload"
test "$(git -C "$lfs_clone" rev-parse HEAD)" = "$lfs_candidate"

quarantined="$lab_root/quarantined-$lfs_oid"
mv "$lfs_store/$lfs_oid" "$quarantined"
rm "$lfs_clone/assets/model.bin"
if git -C "$lfs_clone" restore --source=HEAD --worktree -- assets/model.bin \
  > "$lab_root/missing-lfs.stdout" 2> "$lab_root/missing-lfs.stderr"; then
  printf 'Expected required external-object conversion to fail.\n' >&2
  exit 1
fi
git -C "$lfs_clone" fsck --full --no-progress >/dev/null
mv "$quarantined" "$lfs_store/$lfs_oid"
git -C "$lfs_clone" restore --source=HEAD --worktree -- assets/model.bin
cmp "$lfs_clone/assets/model.bin" "$payload"
test "$(sha256_file "$lfs_clone/assets/model.bin")" = "$lfs_oid"
test "$(wc -c < "$lfs_clone/assets/model.bin" | tr -d ' ')" = "$lfs_size"
git -C "$lfs_clone" add assets/model.bin
test -z "$(git -C "$lfs_clone" status --porcelain=v1)"

dependency_remote="$lab_root/dependency.git"
dependency_author="$lab_root/dependency-author"
super_remote="$lab_root/superproject.git"
super_author="$lab_root/superproject-author"

git init --quiet --bare --initial-branch=main "$dependency_remote"
git init --quiet --initial-branch=main "$dependency_author"
git -C "$dependency_author" config user.name 'Dependency Author'
git -C "$dependency_author" config user.email 'dependency@example.invalid'
printf 'api=v1\n' > "$dependency_author/engine.conf"
git -C "$dependency_author" add engine.conf
git -C "$dependency_author" commit --quiet -m 'engine: publish v1'
dependency_v1="$(git -C "$dependency_author" rev-parse HEAD)"
git -C "$dependency_author" remote add origin "$dependency_remote"
git -C "$dependency_author" push --quiet -u origin main

git init --quiet --bare --initial-branch=main "$super_remote"
git init --quiet --initial-branch=main "$super_author"
git -C "$super_author" config user.name 'Superproject Author'
git -C "$super_author" config user.email 'superproject@example.invalid'
printf 'app=v1\n' > "$super_author/application.conf"
git -C "$super_author" add application.conf
git -C "$super_author" commit --quiet -m 'app: initialize superproject'
git -C "$super_author" -c protocol.file.allow=always \
  submodule add --quiet "$dependency_remote" modules/engine
git -C "$super_author" commit --quiet -m 'build: pin engine v1'
git -C "$super_author" remote add origin "$super_remote"
git -C "$super_author" push --quiet -u origin main

git -C "$dependency_author" switch --quiet -c next
printf 'feature=v2\n' >> "$dependency_author/engine.conf"
git -C "$dependency_author" add engine.conf
git -C "$dependency_author" commit --quiet -m 'engine: prepare v2'
dependency_v2="$(git -C "$dependency_author" rev-parse HEAD)"

git -C "$super_author/modules/engine" -c protocol.file.allow=always \
  fetch --quiet "$dependency_author" "$dependency_v2"
git -C "$super_author/modules/engine" switch --quiet --detach "$dependency_v2"
git -C "$super_author" switch --quiet -c ci/missing
git -C "$super_author" add modules/engine
git -C "$super_author" commit --quiet -m 'build: pin unpublished engine v2'
missing_candidate="$(git -C "$super_author" rev-parse HEAD)"
git -C "$super_author" push --quiet origin HEAD:refs/heads/ci/missing
gitlink_oid="$(git -C "$super_author" rev-parse "HEAD:modules/engine")"
test "$gitlink_oid" = "$dependency_v2"

ci_clone="$lab_root/ci-clone"
git clone --quiet --branch ci/missing --no-recurse-submodules \
  "$super_remote" "$ci_clone"
git -C "$ci_clone" checkout --quiet --detach "$missing_candidate"
test "$(git -C "$ci_clone" rev-parse HEAD)" = "$missing_candidate"
test ! -e "$ci_clone/modules/engine/engine.conf"
if git -C "$ci_clone" -c protocol.file.allow=always \
  submodule update --init --recursive \
  > "$lab_root/missing-submodule.stdout" 2> "$lab_root/missing-submodule.stderr"; then
  printf 'Expected recursive checkout to fail before the gitlink commit was published.\n' >&2
  exit 1
fi
git -C "$ci_clone" fsck --full --no-progress >/dev/null

git -C "$dependency_author" switch --quiet main
git -C "$dependency_author" merge --quiet --ff-only next
git -C "$dependency_author" push --quiet origin HEAD:refs/heads/main
git -C "$ci_clone" -c protocol.file.allow=always \
  submodule update --quiet --init --recursive
test "$(git -C "$ci_clone/modules/engine" rev-parse HEAD)" = "$dependency_v2"
if git -C "$ci_clone/modules/engine" symbolic-ref -q HEAD >/dev/null; then
  printf 'Expected submodule checkout to remain detached at the gitlink.\n' >&2
  exit 1
fi

evidence="$lab_root/ci-input-evidence.tsv"
{
  printf 'layer\tkey\tvalue\n'
  printf 'git\tcandidate\t%s\n' "$missing_candidate"
  printf 'git\tlfs_candidate\t%s\n' "$lfs_candidate"
  printf 'lfs\tpointer_git_oid\t%s\n' "$(git -C "$lfs_clone" rev-parse "HEAD:assets/model.bin")"
  printf 'lfs\tpayload_oid\t%s\n' "$lfs_oid"
  printf 'lfs\tpayload_size\t%s\n' "$lfs_size"
  printf 'submodule\tpath\tmodules/engine\n'
  printf 'submodule\tgitlink_oid\t%s\n' "$gitlink_oid"
  printf 'submodule\tcheckout_oid\t%s\n' "$(git -C "$ci_clone/modules/engine" rev-parse HEAD)"
} > "$evidence"
grep -F "gitlink_oid	$dependency_v2" "$evidence" >/dev/null
grep -F "checkout_oid	$dependency_v2" "$evidence" >/dev/null
test "$(git -C "$lfs_clone" rev-parse HEAD)" = "$lfs_candidate"
test -z "$(git -C "$ci_clone" status --porcelain=v1)"
git -C "$ci_clone" fsck --full --no-progress >/dev/null

printf 'LFS payload boundary, unpublished gitlink failure, candidate checkout, and external dependency recovery passed.\n'
