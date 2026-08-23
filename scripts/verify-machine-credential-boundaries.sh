#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-machine-identity.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS GIT_CONFIG_COUNT

credential_store="$lab_dir/credentials"
git config --global credential.helper "store --file=$credential_store"

# Without path matching, Git intentionally drops the path before asking helpers.
git config --global credential.useHttpPath false
printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/source.git' \
  'username=shared-machine' \
  'password=SYNTHETIC-HOST-WIDE-TOKEN' \
  '' | git credential approve

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/release.git' \
  '' | git credential fill > "$lab_dir/host-wide.out"

grep -Fqx 'username=shared-machine' "$lab_dir/host-wide.out"
grep -Fqx 'password=SYNTHETIC-HOST-WIDE-TOKEN' "$lab_dir/host-wide.out"
if grep -Fq 'path=' "$credential_store"; then
  printf 'Expected credential.useHttpPath=false to omit the repository path.\n' >&2
  exit 1
fi

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'username=shared-machine' \
  '' | git credential reject

if test -e "$credential_store" && grep -Fq 'SYNTHETIC-HOST-WIDE-TOKEN' "$credential_store"; then
  printf 'Host-wide synthetic credential survived rejection.\n' >&2
  exit 1
fi

# With path matching, two repository contexts can select different credentials.
git config --global credential.useHttpPath true
printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/source.git' \
  'username=source-reader' \
  'password=SYNTHETIC-SOURCE-READ-TOKEN' \
  '' | git credential approve

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/release.git' \
  'username=release-publisher' \
  'password=SYNTHETIC-RELEASE-WRITE-TOKEN' \
  '' | git credential approve

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/source.git' \
  '' | git credential fill > "$lab_dir/source.out"

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/release.git' \
  '' | git credential fill > "$lab_dir/release.out"

grep -Fqx 'path=team/source.git' "$lab_dir/source.out"
grep -Fqx 'username=source-reader' "$lab_dir/source.out"
grep -Fqx 'password=SYNTHETIC-SOURCE-READ-TOKEN' "$lab_dir/source.out"
grep -Fqx 'path=team/release.git' "$lab_dir/release.out"
grep -Fqx 'username=release-publisher' "$lab_dir/release.out"
grep -Fqx 'password=SYNTHETIC-RELEASE-WRITE-TOKEN' "$lab_dir/release.out"

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/source.git' \
  'username=source-reader' \
  '' | git credential reject

if printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/source.git' \
  '' | git credential fill > "$lab_dir/source-rejected.out" 2> "$lab_dir/source-rejected.err"; then
  printf 'Expected the source-path synthetic credential to be rejected.\n' >&2
  exit 1
fi

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/release.git' \
  '' | git credential fill > "$lab_dir/release-retained.out"
grep -Fqx 'password=SYNTHETIC-RELEASE-WRITE-TOKEN' "$lab_dir/release-retained.out"

# Deliberately create unsafe local fixtures, detect them, and remove them.
mkdir "$lab_dir/repository"
git -C "$lab_dir/repository" init --quiet --initial-branch=main
unsafe_url='https://machine:SYNTHETIC-URL-TOKEN@git.example.invalid/team/repository.git'
safe_url='https://git.example.invalid/team/repository.git'
git -C "$lab_dir/repository" remote add origin "$unsafe_url"
grep -Fq 'SYNTHETIC-URL-TOKEN' "$lab_dir/repository/.git/config"
test "$(git -C "$lab_dir/repository" remote get-url origin)" = "$unsafe_url"

git -C "$lab_dir/repository" remote set-url origin "$safe_url"
if grep -Fq 'SYNTHETIC-URL-TOKEN' "$lab_dir/repository/.git/config"; then
  printf 'Synthetic URL token remained in local repository config.\n' >&2
  exit 1
fi

header_key='http.https://git.example.invalid/.extraHeader'
git -C "$lab_dir/repository" config --local "$header_key" \
  'Authorization: Bearer SYNTHETIC-HEADER-TOKEN'
grep -Fq 'SYNTHETIC-HEADER-TOKEN' "$lab_dir/repository/.git/config"
git -C "$lab_dir/repository" config --local --unset-all "$header_key"
if grep -Fq 'SYNTHETIC-HEADER-TOKEN' "$lab_dir/repository/.git/config"; then
  printf 'Synthetic Authorization header remained in local repository config.\n' >&2
  exit 1
fi

printf 'Git credential context and local persistence boundaries passed.\n'
