#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-reproducible-build.XXXXXX")"
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
    printf 'A SHA-256 command is required for the reproducible-build experiment.\n' >&2
    return 1
  fi
}

repo="$lab_dir/repository"
mkdir -p "$repo/src"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Reproducible Build Author"
git -C "$repo" config user.email "reproducible@example.invalid"
printf 'source input v1\n' > "$repo/src/input.txt"
git -C "$repo" add src/input.txt
git -C "$repo" commit --quiet -m "build: establish reproducible source"
source_commit="$(git -C "$repo" rev-parse HEAD)"
source_tree="$(git -C "$repo" rev-parse HEAD^{tree})"

archive_a="$lab_dir/source-a.tar"
archive_b="$lab_dir/source-b.tar"
git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=source/ "$source_commit" > "$archive_a"
git -C "$repo" archive --format=tar --mtime='UTC 1970-01-01' \
  --prefix=source/ "$source_commit" > "$archive_b"

archive_digest_a="$(sha256_file "$archive_a")"
archive_digest_b="$(sha256_file "$archive_b")"
test "$archive_digest_a" = "$archive_digest_b"

printf 'external-input=v1\n' > "$lab_dir/external-input"
external_digest_a="$(sha256_file "$lab_dir/external-input")"
cat "$archive_a" "$lab_dir/external-input" > "$lab_dir/output-a.bin"
output_digest_a="$(sha256_file "$lab_dir/output-a.bin")"

printf 'external-input=v2\n' > "$lab_dir/external-input"
external_digest_b="$(sha256_file "$lab_dir/external-input")"
cat "$archive_b" "$lab_dir/external-input" > "$lab_dir/output-b.bin"
output_digest_b="$(sha256_file "$lab_dir/output-b.bin")"

test "$external_digest_a" != "$external_digest_b"
test "$output_digest_a" != "$output_digest_b"

printf '%s\n' \
  'schema_version=1' \
  "source_commit=$source_commit" \
  "source_tree=$source_tree" \
  "source_archive_digest=$archive_digest_a" \
  "external_input_digest=$external_digest_a" \
  "artifact_digest=$output_digest_a" \
  'comparison_policy=byte-for-byte' \
  > "$lab_dir/manifest.env"

grep -Fqx "source_commit=$source_commit" "$lab_dir/manifest.env"
grep -Fqx "source_tree=$source_tree" "$lab_dir/manifest.env"
grep -Fqx "source_archive_digest=$archive_digest_a" "$lab_dir/manifest.env"
grep -Fqx "artifact_digest=$output_digest_a" "$lab_dir/manifest.env"

printf 'Reproducible source archive, manifest, and nondeterministic input detection passed.\n'
