#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-signatures.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
release_key="$lab_root/release-signing"
attacker_key="$lab_root/untrusted-signing"
external_policy="$lab_root/trusted-allowed-signers"
authorization_policy="$lab_root/release-authorization.tsv"

ssh-keygen -q -t ed25519 -N '' -C 'release signing lab' -f "$release_key"
ssh-keygen -q -t ed25519 -N '' -C 'untrusted signing lab' -f "$attacker_key"

release_public="$(awk '{print $1 " " $2}' "$release_key.pub")"
attacker_public="$(awk '{print $1 " " $2}' "$attacker_key.pub")"
printf 'release@example.invalid %s\n' "$release_public" > "$external_policy"

git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Release Maintainer'
git -C "$repo" config user.email 'release@example.invalid'
git -C "$repo" config gpg.format ssh
git -C "$repo" config user.signingKey "$release_key"
git -C "$repo" config gpg.ssh.allowedSignersFile "$external_policy"

mkdir -p "$repo/ci"
printf 'release@example.invalid %s\n' "$release_public" > "$repo/ci/allowed_signers"
printf 'service version 1\n' > "$repo/service.txt"
git -C "$repo" add ci/allowed_signers service.txt
git -C "$repo" commit --quiet -S -m 'feat: add signed release candidate'
signed_commit="$(git -C "$repo" rev-parse HEAD)"

test "$(git -C "$repo" show --no-patch --format='%G?' "$signed_commit")" = 'G'
test "$(git -C "$repo" show --no-patch --format='%GS' "$signed_commit")" = 'release@example.invalid'
test -n "$(git -C "$repo" show --no-patch --format='%GF' "$signed_commit")"
git -C "$repo" verify-commit "$signed_commit" >/dev/null 2>&1

release_fingerprint="$(git -C "$repo" show --no-patch --format='%GF' "$signed_commit")"
printf '%s\t%s\t%s\t%s\t%s\n' \
  "$signed_commit" \
  "$release_fingerprint" \
  'release@example.invalid' \
  'release' \
  'allow' > "$authorization_policy"

authorize_release() {
  local candidate_oid="$1"
  local fingerprint="$2"
  local principal="$3"

  awk -F '\t' \
    -v candidate_oid="$candidate_oid" \
    -v fingerprint="$fingerprint" \
    -v principal="$principal" \
    '$1 == candidate_oid && $2 == fingerprint && $3 == principal && $4 == "release" && $5 == "allow" { found = 1 } END { exit found ? 0 : 1 }' \
    "$authorization_policy"
}

authorize_release "$signed_commit" "$release_fingerprint" 'release@example.invalid'

git -C "$repo" tag -s -m 'Release 1.0.0' v1.0.0 "$signed_commit"
test "$(git -C "$repo" cat-file -t v1.0.0)" = 'tag'
test "$(git -C "$repo" rev-parse 'v1.0.0^{}')" = "$signed_commit"
git -C "$repo" verify-tag v1.0.0 >/dev/null 2>&1

git -C "$repo" switch --quiet --create unsigned-history "$signed_commit"
printf 'unsigned maintenance change\n' >> "$repo/service.txt"
git -C "$repo" add service.txt
git -C "$repo" commit --quiet --no-gpg-sign -m 'test: create unsigned commit'
unsigned_commit="$(git -C "$repo" rev-parse HEAD)"
test "$(git -C "$repo" show --no-patch --format='%G?' "$unsigned_commit")" = 'N'
if git -C "$repo" verify-commit "$unsigned_commit" >/dev/null 2>&1; then
  printf 'Expected verification of an unsigned commit to fail.\n' >&2
  exit 1
fi

git -C "$repo" switch --quiet main
git -C "$repo" config user.name 'Untrusted Contributor'
git -C "$repo" config user.email 'attacker@example.invalid'
git -C "$repo" config user.signingKey "$attacker_key"
printf 'attacker@example.invalid %s\n' "$attacker_public" > "$repo/ci/allowed_signers"
printf 'untrusted candidate change\n' >> "$repo/service.txt"
git -C "$repo" add ci/allowed_signers service.txt
git -C "$repo" commit --quiet -S -m 'test: candidate changes its own trust policy'
untrusted_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" config gpg.ssh.allowedSignersFile "$repo/ci/allowed_signers"
git -C "$repo" verify-commit "$untrusted_commit" >/dev/null 2>&1
test "$(git -C "$repo" show --no-patch --format='%GS' "$untrusted_commit")" = 'attacker@example.invalid'

git -C "$repo" config gpg.ssh.allowedSignersFile "$external_policy"
if git -C "$repo" verify-commit "$untrusted_commit" >/dev/null 2>&1; then
  printf 'Expected the external trust policy to reject the untrusted signing key.\n' >&2
  exit 1
fi
git -C "$repo" verify-commit "$signed_commit" >/dev/null 2>&1
git -C "$repo" verify-tag v1.0.0 >/dev/null 2>&1

untrusted_fingerprint="$(git -C "$repo" show --no-patch --format='%GF' "$untrusted_commit")"
if authorize_release "$untrusted_commit" "$untrusted_fingerprint" 'attacker@example.invalid'; then
  printf 'Expected the untrusted candidate to fail the external release authorization policy.\n' >&2
  exit 1
fi

test "$(git -C "$repo" rev-parse HEAD^)" = "$signed_commit"
test "$untrusted_commit" != "$signed_commit"

printf 'SSH commit/tag signing, unsigned rejection, external trust, and release authorization passed.\n'
