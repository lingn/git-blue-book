#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-refspec-clone.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS GIT_CONFIG_COUNT SSH_ASKPASS

mkdir -p "$lab_dir/seed/app" "$lab_dir/seed/docs" "$lab_dir/seed/assets"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"

printf 'refspec and clone laboratory\n' > "$lab_dir/seed/README.md"
printf 'guide version 1\n' > "$lab_dir/seed/docs/guide.md"
printf 'binary-placeholder-v1\n' > "$lab_dir/seed/assets/archive.bin"
for version in 1 2 3 4 5 6; do
  printf 'service version %s\n' "$version" > "$lab_dir/seed/app/service.txt"
  git -C "$lab_dir/seed" add README.md app/service.txt docs/guide.md assets/archive.bin
  git -C "$lab_dir/seed" commit --quiet -m "feat: record service version $version"
done

main_count="$(git -C "$lab_dir/seed" rev-list --count main)"
main_tip="$(git -C "$lab_dir/seed" rev-parse main)"
target_blob="$(git -C "$lab_dir/seed" rev-parse main~3:app/service.txt)"

git -C "$lab_dir/seed" switch --quiet --create release/1.x main~2
printf 'release maintenance\n' > "$lab_dir/seed/RELEASE.md"
git -C "$lab_dir/seed" add RELEASE.md
git -C "$lab_dir/seed" commit --quiet -m "docs: add maintenance branch"
release_tip="$(git -C "$lab_dir/seed" rev-parse HEAD)"

git -C "$lab_dir/seed" switch --quiet --create wip/private main
printf 'private experiment\n' > "$lab_dir/seed/PRIVATE.md"
git -C "$lab_dir/seed" add PRIVATE.md
git -C "$lab_dir/seed" commit --quiet -m "test: add excluded branch"
wip_tip="$(git -C "$lab_dir/seed" rev-parse HEAD)"
git -C "$lab_dir/seed" switch --quiet main
git -C "$lab_dir/seed" tag -a v1.0.0 -m "Refspec lab release" main~1

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
git --git-dir="$lab_dir/server.git" config uploadpack.allowFilter true
server_url="file://$lab_dir/server.git"

git -C "$lab_dir" init --quiet --initial-branch=main refspec-client
git -C "$lab_dir/refspec-client" remote add origin "$server_url"
git -C "$lab_dir/refspec-client" config --unset-all remote.origin.fetch
git -C "$lab_dir/refspec-client" config --add remote.origin.fetch \
  '+refs/heads/*:refs/remotes/origin/*'
git -C "$lab_dir/refspec-client" config --add remote.origin.fetch \
  '^refs/heads/wip/*'
git -C "$lab_dir/refspec-client" fetch --quiet origin

test -s "$lab_dir/refspec-client/.git/FETCH_HEAD"
test "$(git -C "$lab_dir/refspec-client" rev-parse origin/main)" = "$main_tip"
test "$(git -C "$lab_dir/refspec-client" rev-parse origin/release/1.x)" = "$release_tip"
if git -C "$lab_dir/refspec-client" show-ref --verify --quiet refs/remotes/origin/wip/private; then
  printf 'Negative refspec unexpectedly created origin/wip/private.\n' >&2
  exit 1
fi
if git -C "$lab_dir/refspec-client" cat-file -e "$wip_tip" 2>/dev/null; then
  printf 'Negative refspec unexpectedly fetched the excluded branch tip.\n' >&2
  exit 1
fi

git -C "$lab_dir/refspec-client" config user.name "Refspec Author"
git -C "$lab_dir/refspec-client" config user.email "refspec@example.invalid"
git -C "$lab_dir/refspec-client" switch --quiet --create publish origin/main
printf 'review branch\n' > "$lab_dir/refspec-client/REVIEW.md"
git -C "$lab_dir/refspec-client" add REVIEW.md
git -C "$lab_dir/refspec-client" commit --quiet -m "docs: add review branch"
published_tip="$(git -C "$lab_dir/refspec-client" rev-parse HEAD)"
git -C "$lab_dir/refspec-client" push --quiet \
  origin HEAD:refs/heads/review/refspec-lab
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/review/refspec-lab)" = "$published_tip"
git -C "$lab_dir/refspec-client" push --quiet \
  origin :refs/heads/review/refspec-lab
if git --git-dir="$lab_dir/server.git" show-ref --verify --quiet refs/heads/review/refspec-lab; then
  printf 'Empty-source push refspec did not delete the temporary remote branch.\n' >&2
  exit 1
fi

git clone --quiet --depth=2 --branch=main "$server_url" "$lab_dir/shallow"
test "$(git -C "$lab_dir/shallow" rev-parse --is-shallow-repository)" = "true"
test "$(git -C "$lab_dir/shallow" rev-list --count main)" = "2"
test -s "$lab_dir/shallow/.git/shallow"
if git -C "$lab_dir/shallow" show-ref --verify --quiet refs/remotes/origin/release/1.x; then
  printf 'Depth clone unexpectedly fetched another remote-tracking branch.\n' >&2
  exit 1
fi

git -C "$lab_dir/shallow" fetch --quiet --deepen=2 origin main
test "$(git -C "$lab_dir/shallow" rev-list --count main)" = "4"
git -C "$lab_dir/shallow" fetch --quiet --unshallow origin
test "$(git -C "$lab_dir/shallow" rev-parse --is-shallow-repository)" = "false"
test "$(git -C "$lab_dir/shallow" rev-list --count main)" = "$main_count"

git clone --quiet --filter=blob:none \
  "$server_url" "$lab_dir/partial"
test "$(git -C "$lab_dir/partial" config --get remote.origin.promisor)" = "true"
test "$(git -C "$lab_dir/partial" config --get remote.origin.partialclonefilter)" = "blob:none"
test "$(git -C "$lab_dir/partial" rev-parse --is-shallow-repository)" = "false"

git -C "$lab_dir/partial" rev-list --objects --all --missing=print \
  > "$lab_dir/partial-missing-before.out"
grep -Fqx "?$target_blob" "$lab_dir/partial-missing-before.out"

git -C "$lab_dir/partial" show main~3:app/service.txt \
  > "$lab_dir/hydrated-service.txt"
test "$(sed -n '1p' "$lab_dir/hydrated-service.txt")" = "service version 3"
git -C "$lab_dir/partial" cat-file -e "$target_blob"

git -C "$lab_dir/partial" sparse-checkout set app
test -f "$lab_dir/partial/app/service.txt"
test ! -e "$lab_dir/partial/docs/guide.md"
git -C "$lab_dir/partial" sparse-checkout disable
test -f "$lab_dir/partial/docs/guide.md"
test "$(sed -n '1p' "$lab_dir/partial/docs/guide.md")" = "guide version 1"

printf 'Refspec, shallow-clone, partial-clone, and sparse-checkout experiments passed.\n'
