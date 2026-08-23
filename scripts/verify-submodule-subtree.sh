#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-submodule-subtree.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

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
git -C "$super_author" config user.name 'Application Author'
git -C "$super_author" config user.email 'application@example.invalid'
printf 'application=v1\n' > "$super_author/application.conf"
git -C "$super_author" add application.conf
git -C "$super_author" commit --quiet -m 'app: initialize superproject'
git -C "$super_author" -c protocol.file.allow=always \
  submodule add --quiet "$dependency_remote" modules/engine
git -C "$super_author" commit --quiet -m 'build: pin engine v1 as submodule'
git -C "$super_author" remote add origin "$super_remote"
git -C "$super_author" push --quiet -u origin main

gitlink_line="$(git -C "$super_author" ls-tree HEAD -- modules/engine)"
printf '%s\n' "$gitlink_line" | grep -Eq "^160000 commit ${dependency_v1}[[:space:]]+modules/engine$"
grep -q 'path = modules/engine' "$super_author/.gitmodules"
grep -Fq "url = $dependency_remote" "$super_author/.gitmodules"

consumer="$lab_root/consumer"
git clone --quiet --no-recurse-submodules "$super_remote" "$consumer"
git -C "$consumer" config user.name 'Integrator'
git -C "$consumer" config user.email 'integrator@example.invalid'
test ! -e "$consumer/modules/engine/engine.conf"
printf '%s\n' "$(git -C "$consumer" submodule status)" | \
  grep -Eq "^-${dependency_v1}[[:space:]]+modules/engine"

if git -C "$consumer" submodule update --init --recursive >/dev/null 2>&1; then
  printf 'Expected recursive file transport to require an explicit command-level allowance.\n' >&2
  exit 1
fi
git -C "$consumer" -c protocol.file.allow=always \
  submodule update --quiet --init --recursive
test "$(git -C "$consumer/modules/engine" rev-parse HEAD)" = "$dependency_v1"
if git -C "$consumer/modules/engine" symbolic-ref -q HEAD >/dev/null; then
  printf 'Expected default submodule update to check out a detached HEAD.\n' >&2
  exit 1
fi

printf 'feature=v2\n' >> "$dependency_author/engine.conf"
git -C "$dependency_author" add engine.conf
git -C "$dependency_author" commit --quiet -m 'engine: publish v2'
dependency_v2="$(git -C "$dependency_author" rev-parse HEAD)"
git -C "$dependency_author" push --quiet origin main

git -C "$consumer/modules/engine" -c protocol.file.allow=always fetch --quiet origin
git -C "$consumer/modules/engine" switch --quiet -c app-integration "$dependency_v2"
git -C "$consumer/modules/engine" config user.name 'Integrator'
git -C "$consumer/modules/engine" config user.email 'integrator@example.invalid'
printf 'integration=v3\n' >> "$consumer/modules/engine/engine.conf"
git -C "$consumer/modules/engine" add engine.conf
git -C "$consumer/modules/engine" commit --quiet -m 'engine: add application integration'
dependency_v3="$(git -C "$consumer/modules/engine" rev-parse HEAD)"

submodule_diff="$lab_root/submodule.diff"
git -C "$consumer" diff --submodule=log -- modules/engine > "$submodule_diff"
grep -q "Submodule modules/engine ${dependency_v1:0:7}..${dependency_v3:0:7}" \
  "$submodule_diff"
git -C "$consumer" add modules/engine
git -C "$consumer" commit --quiet -m 'build: advance engine gitlink to v3'
test "$(git -C "$consumer" rev-parse 'HEAD:modules/engine')" = "$dependency_v3"

if git -C "$consumer" push --recurse-submodules=check origin main \
  >/dev/null 2>&1; then
  printf 'Expected recursive push check to reject an unpublished submodule commit.\n' >&2
  exit 1
fi

git -C "$consumer" push --quiet origin HEAD:refs/heads/unsafe
broken_clone="$lab_root/broken-clone"
git clone --quiet --branch unsafe --no-recurse-submodules \
  "$super_remote" "$broken_clone"
if git -C "$broken_clone" -c protocol.file.allow=always \
  submodule update --init --recursive >/dev/null 2>&1; then
  printf 'Expected submodule update to fail while the pinned commit is absent remotely.\n' >&2
  exit 1
fi

git -C "$consumer/modules/engine" push --quiet origin HEAD:refs/heads/main
git -C "$broken_clone" -c protocol.file.allow=always \
  submodule update --quiet --init --recursive
test "$(git -C "$broken_clone/modules/engine" rev-parse HEAD)" = "$dependency_v3"
git -C "$consumer" push --quiet --recurse-submodules=check origin main

release_clone="$lab_root/release-clone"
git -c protocol.file.allow=always clone --quiet --recurse-submodules \
  "$super_remote" "$release_clone"
test "$(git -C "$release_clone/modules/engine" rev-parse HEAD)" = "$dependency_v3"
printf '%s\n' "$(git -C "$release_clone" submodule status --recursive)" | \
  grep -Eq "^ ${dependency_v3}[[:space:]]+modules/engine"

git -C "$release_clone" submodule deinit --quiet --force -- modules/engine
test ! -e "$release_clone/modules/engine/engine.conf"
test "$(git -C "$release_clone" rev-parse 'HEAD:modules/engine')" = "$dependency_v3"
git -C "$release_clone" -c protocol.file.allow=always \
  submodule update --quiet --init --recursive
test "$(git -C "$release_clone/modules/engine" rev-parse HEAD)" = "$dependency_v3"

subtree_repo="$lab_root/subtree-application"
git init --quiet --initial-branch=main "$subtree_repo"
git -C "$subtree_repo" config user.name 'Subtree Integrator'
git -C "$subtree_repo" config user.email 'subtree@example.invalid'
printf 'application=subtree-v1\n' > "$subtree_repo/application.conf"
git -C "$subtree_repo" add application.conf
git -C "$subtree_repo" commit --quiet -m 'app: initialize subtree application'
git -C "$subtree_repo" -c protocol.file.allow=always subtree add \
  --quiet --prefix=vendor/engine "$dependency_remote" main --squash \
  >/dev/null 2>&1

test ! -e "$subtree_repo/.gitmodules"
printf '%s\n' "$(git -C "$subtree_repo" ls-tree HEAD -- vendor/engine)" | \
  grep -Eq '^040000 tree [0-9a-f]+[[:space:]]+vendor/engine$'
grep -q '^integration=v3$' "$subtree_repo/vendor/engine/engine.conf"

subtree_clone="$lab_root/subtree-clone"
git clone --quiet --no-local "$subtree_repo" "$subtree_clone"
cmp "$subtree_clone/vendor/engine/engine.conf" \
  "$subtree_repo/vendor/engine/engine.conf"

git -C "$dependency_author" -c protocol.file.allow=always fetch --quiet origin
git -C "$dependency_author" merge --quiet --ff-only origin/main
printf 'release=v4\n' >> "$dependency_author/engine.conf"
git -C "$dependency_author" add engine.conf
git -C "$dependency_author" commit --quiet -m 'engine: publish v4'
dependency_v4="$(git -C "$dependency_author" rev-parse HEAD)"
git -C "$dependency_author" push --quiet origin main

git -C "$subtree_repo" -c protocol.file.allow=always subtree pull \
  --quiet --prefix=vendor/engine "$dependency_remote" main --squash \
  >/dev/null 2>&1
grep -q '^release=v4$' "$subtree_repo/vendor/engine/engine.conf"
test "$(git -C "$subtree_repo" rev-parse HEAD)" != "$dependency_v4"

printf 'application-patch=true\n' >> "$subtree_repo/vendor/engine/engine.conf"
git -C "$subtree_repo" add vendor/engine/engine.conf
git -C "$subtree_repo" commit --quiet -m 'engine: carry application-specific patch'

split_v1="$(git -C "$subtree_repo" subtree split --prefix=vendor/engine 2>/dev/null)"
split_v2="$(git -C "$subtree_repo" subtree split --prefix=vendor/engine 2>/dev/null)"
test "$split_v1" = "$split_v2"
test "$(git -C "$subtree_repo" show "$split_v1:engine.conf")" = \
  "$(printf 'api=v1\nfeature=v2\nintegration=v3\nrelease=v4\napplication-patch=true')"
if git -C "$subtree_repo" cat-file -e "$split_v1:vendor/engine/engine.conf" \
  2>/dev/null; then
  printf 'Expected split history to place the subtree prefix at its root.\n' >&2
  exit 1
fi

git -C "$consumer" fsck --full --no-progress >/dev/null
git -C "$subtree_repo" fsck --full --no-progress >/dev/null

printf 'Submodule gitlink, recursive checkout, publication ordering, and subtree copy/split passed.\n'
