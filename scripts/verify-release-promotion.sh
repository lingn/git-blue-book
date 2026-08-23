#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-release-promotion.XXXXXX")"
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
    printf 'A SHA-256 command is required for the release experiment.\n' >&2
    return 1
  fi
}

repo="$lab_dir/publisher"
server="$lab_dir/server.git"
staging="$lab_dir/staging"
mkdir -p "$repo/service" "$staging"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Release Publisher"
git -C "$repo" config user.email "release@example.invalid"
git init --bare --quiet "$server"
git -C "$server" symbolic-ref HEAD refs/heads/main
server_url="file://$server"
git -C "$repo" remote add origin "$server_url"

printf 'service version 1\n' > "$repo/service/version.txt"
git -C "$repo" add service/version.txt
git -C "$repo" commit --quiet -m "release: establish source"
source_commit="$(git -C "$repo" rev-parse HEAD)"
source_tree="$(git -C "$repo" rev-parse HEAD^{tree})"

git -C "$repo" push --quiet origin \
  "refs/heads/main:refs/heads/main"

release_tag="v1.4.2"
git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=application/ "$source_commit" > "$lab_dir/application.tar"
artifact_digest="$(sha256_file "$lab_dir/application.tar")"

git -C "$repo" tag -a "$release_tag" "$source_commit" \
  -m "Release $release_tag"
tag_object="$(git -C "$repo" rev-parse --verify "$release_tag^{tag}")"
tag_target="$(git -C "$repo" rev-parse --verify "$release_tag^{}")"
test "$tag_target" = "$source_commit"
test "$(git -C "$repo" cat-file -t "$release_tag")" = tag

printf '%s\n' \
  'schema_version=1' \
  "release_tag=$release_tag" \
  "tag_object=$tag_object" \
  "source_commit=$source_commit" \
  "source_tree=$source_tree" \
  "artifact_digest=$artifact_digest" \
  'approval_id=approval-release-001' \
  > "$lab_dir/manifest.env"

git -C "$repo" push --quiet origin \
  "refs/tags/$release_tag:refs/tags/$release_tag"

remote_tag="$(git ls-remote --tags "$server_url" \
  "refs/tags/$release_tag" | awk 'NR == 1 {print $1}')"
remote_target="$(git ls-remote --tags "$server_url" \
  "refs/tags/$release_tag^{}" | awk 'NR == 1 {print $1}')"
test "$remote_tag" = "$tag_object"
test "$remote_target" = "$source_commit"

cp "$lab_dir/application.tar" "$staging/application.tar"
cp "$lab_dir/manifest.env" "$staging/manifest.env"
test "$(sha256_file "$staging/application.tar")" = "$artifact_digest"
grep -Fqx "source_commit=$source_commit" "$staging/manifest.env"
grep -Fqx "artifact_digest=$artifact_digest" "$staging/manifest.env"

printf 'tampered staging bytes\n' >> "$staging/application.tar"
if test "$(sha256_file "$staging/application.tar")" = "$artifact_digest"; then
  printf 'tampered staging artifact unexpectedly matched the release digest.\n' >&2
  exit 1
fi
cp "$lab_dir/application.tar" "$staging/application.tar"
test "$(sha256_file "$staging/application.tar")" = "$artifact_digest"

git clone --quiet "$server_url" "$lab_dir/challenger"
git -C "$lab_dir/challenger" config user.name "Second Publisher"
git -C "$lab_dir/challenger" config user.email "second@example.invalid"
git -C "$lab_dir/challenger" tag -d "$release_tag" >/dev/null
git -C "$lab_dir/challenger" switch --quiet --create candidate-two
printf 'service version 2\n' > "$lab_dir/challenger/service/version.txt"
git -C "$lab_dir/challenger" add service/version.txt
git -C "$lab_dir/challenger" commit --quiet -m "release: second candidate"
second_commit="$(git -C "$lab_dir/challenger" rev-parse HEAD)"
git -C "$lab_dir/challenger" tag -a "$release_tag" "$second_commit" \
  -m "Release $release_tag from second candidate"

if git -C "$lab_dir/challenger" push --quiet origin \
  "refs/tags/$release_tag:refs/tags/$release_tag" >/dev/null 2>&1; then
  printf 'same release tag unexpectedly overwrote the first candidate.\n' >&2
  exit 1
fi
test "$(git ls-remote --tags "$server_url" \
  "refs/tags/$release_tag^{}" | awk 'NR == 1 {print $1}')" = "$source_commit"
test "$second_commit" != "$source_commit"

printf 'Release tag, immutable promotion, artifact digest, and tag-race protection passed.\n'
