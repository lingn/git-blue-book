#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-transport-auth.XXXXXX")"
trap 'rm -rf -- "$lab_dir"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_dir/gitconfig"
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS GIT_CONFIG_COUNT SSH_ASKPASS

mkdir "$lab_dir/seed"
git -C "$lab_dir/seed" init --quiet --initial-branch=main
git -C "$lab_dir/seed" config user.name "Seed Author"
git -C "$lab_dir/seed" config user.email "seed@example.invalid"
printf 'transport and authentication lab\n' > "$lab_dir/seed/README.md"
git -C "$lab_dir/seed" add README.md
git -C "$lab_dir/seed" commit --quiet -m "docs: initialize transport lab"

git clone --quiet --bare "$lab_dir/seed" "$lab_dir/server.git"
server_url="file://$lab_dir/server.git"
git clone --quiet "$server_url" "$lab_dir/alice"
git clone --quiet "$server_url" "$lab_dir/bob"

git -C "$lab_dir/alice" config user.name "Alice"
git -C "$lab_dir/alice" config user.email "alice@example.invalid"
git -C "$lab_dir/bob" config user.name "Bob"
git -C "$lab_dir/bob" config user.email "bob@example.invalid"

bob_main_before="$(git -C "$lab_dir/bob" rev-parse main)"
printf 'fetched through file transport\n' > "$lab_dir/alice/transport.txt"
git -C "$lab_dir/alice" add transport.txt
git -C "$lab_dir/alice" commit --quiet -m "docs: record file transport"
alice_commit="$(git -C "$lab_dir/alice" rev-parse HEAD)"
git -C "$lab_dir/alice" push --quiet origin main
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/main)" = "$alice_commit"

git -C "$lab_dir/bob" fetch --quiet origin
test "$(git -C "$lab_dir/bob" rev-parse main)" = "$bob_main_before"
test "$(git -C "$lab_dir/bob" rev-parse origin/main)" = "$alice_commit"
test "$(git -C "$lab_dir/bob" show origin/main:transport.txt)" = "fetched through file transport"

git -C "$lab_dir/bob" switch --quiet --create feature/file-transport origin/main
printf 'objects and references still move without network authentication\n' > "$lab_dir/bob/protocol.txt"
git -C "$lab_dir/bob" add protocol.txt
git -C "$lab_dir/bob" commit --quiet -m "docs: separate transport from authentication"
bob_commit="$(git -C "$lab_dir/bob" rev-parse HEAD)"
git -C "$lab_dir/bob" push --quiet origin HEAD:refs/heads/feature/file-transport
test "$(git --git-dir="$lab_dir/server.git" rev-parse refs/heads/feature/file-transport)" = "$bob_commit"

credential_store="$lab_dir/credentials"
git config --global credential.helper "store --file=$credential_store"
git config --global credential.useHttpPath true

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/repository.git' \
  'username=lab-user' \
  'password=lab-token' \
  '' | git credential approve

test -f "$credential_store"
grep -Fq 'lab-token' "$credential_store"

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/repository.git' \
  '' | git credential fill > "$lab_dir/credential-fill.out"

grep -Fqx 'protocol=https' "$lab_dir/credential-fill.out"
grep -Fqx 'host=git.example.invalid' "$lab_dir/credential-fill.out"
grep -Fqx 'path=team/repository.git' "$lab_dir/credential-fill.out"
grep -Fqx 'username=lab-user' "$lab_dir/credential-fill.out"
grep -Fqx 'password=lab-token' "$lab_dir/credential-fill.out"

if printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/other.git' \
  '' | git credential fill > "$lab_dir/other-path.out" 2> "$lab_dir/other-path.err"; then
  printf 'Expected useHttpPath to keep the credential from another repository path.\n' >&2
  exit 1
fi

printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/repository.git' \
  'username=lab-user' \
  '' | git credential reject

if printf '%s\n' \
  'protocol=https' \
  'host=git.example.invalid' \
  'path=team/repository.git' \
  '' | git credential fill > "$lab_dir/rejected-fill.out" 2> "$lab_dir/rejected-fill.err"; then
  printf 'Expected rejected credentials to be erased from the helper.\n' >&2
  exit 1
fi

if test -e "$credential_store" && grep -Fq 'lab-token' "$credential_store"; then
  printf 'Credential helper retained the rejected test token.\n' >&2
  exit 1
fi

printf 'File transport and isolated credential-helper experiments passed.\n'
