#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d /tmp/git-blue-book-signature-troubleshooting.XXXXXX)"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
release_key="$lab_root/release-signing"
attacker_key="$lab_root/untrusted-signing"
external_policy="$lab_root/external-allowed-signers"

ssh-keygen -q -t ed25519 -N '' -C 'release troubleshooting lab' -f "$release_key"
ssh-keygen -q -t ed25519 -N '' -C 'untrusted troubleshooting lab' -f "$attacker_key"
release_public="$(awk '{print $1 " " $2}' "$release_key.pub")"
attacker_public="$(awk '{print $1 " " $2}' "$attacker_key.pub")"
printf 'release@example.invalid %s\n' "$release_public" > "$external_policy"

git init --quiet --initial-branch=main "$repo"
git -C "$repo" config user.name 'Release Maintainer'
git -C "$repo" config user.email 'release@example.invalid'
git -C "$repo" config gpg.format ssh
git -C "$repo" config user.signingKey "$release_key"
git -C "$repo" config gpg.ssh.allowedSignersFile "$external_policy"
printf 'release=v1\n' > "$repo/release.txt"
git -C "$repo" add release.txt
git -C "$repo" commit --quiet -S -m 'release: signed candidate'
signed_commit="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag -s -m 'Release 1.0.0' v1.0.0 "$signed_commit"
tag_object="$(git -C "$repo" rev-parse --verify 'v1.0.0^{tag}')"
test "$(git -C "$repo" rev-parse 'v1.0.0^{}')" = "$signed_commit"

refs_before="$(git -C "$repo" show-ref | LC_ALL=C sort)"
head_before="$(git -C "$repo" rev-parse HEAD)"
index_before="$(git -C "$repo" ls-files --stage)"
status_before="$(git -C "$repo" status --porcelain=v1)"
git -C "$repo" verify-commit "$signed_commit" >/dev/null 2>&1
git -C "$repo" verify-tag "$tag_object" >/dev/null 2>&1
test "$(git -C "$repo" show --no-patch --format='%G?' "$signed_commit")" = G
test "$(git -C "$repo" show --no-patch --format='%GS' "$signed_commit")" = release@example.invalid
test "$(git -C "$repo" show --no-patch --format='%GF' "$signed_commit")" != ''
test "$(git -C "$repo" show-ref | LC_ALL=C sort)" = "$refs_before"
test "$(git -C "$repo" rev-parse HEAD)" = "$head_before"
test "$(git -C "$repo" ls-files --stage)" = "$index_before"
test "$(git -C "$repo" status --porcelain=v1)" = "$status_before"

git -C "$repo" switch --quiet --create unsigned "$signed_commit"
printf 'unsigned=true\n' >> "$repo/release.txt"
git -C "$repo" add release.txt
git -C "$repo" commit --quiet --no-gpg-sign -m 'test: unsigned candidate'
unsigned_commit="$(git -C "$repo" rev-parse HEAD)"
test "$(git -C "$repo" show --no-patch --format='%G?' "$unsigned_commit")" = N
if git -C "$repo" verify-commit "$unsigned_commit" >/dev/null 2>&1; then
  printf 'Expected strict verification of an unsigned commit to fail.\n' >&2
  exit 1
fi
test "$(git -C "$repo" rev-parse HEAD)" = "$unsigned_commit"

git -C "$repo" tag -s -m 'Signed tag with wrong release target' v1.0.0-test \
  "$unsigned_commit"
wrong_target_tag="$(git -C "$repo" rev-parse --verify 'v1.0.0-test^{tag}')"
git -C "$repo" verify-tag "$wrong_target_tag" >/dev/null 2>&1
test "$(git -C "$repo" rev-parse 'v1.0.0-test^{}')" = "$unsigned_commit"
test "$unsigned_commit" != "$signed_commit"

git -C "$repo" switch --quiet main
git -C "$repo" config user.name 'Untrusted Contributor'
git -C "$repo" config user.email 'attacker@example.invalid'
git -C "$repo" config user.signingKey "$attacker_key"
mkdir -p "$repo/ci"
printf 'attacker@example.invalid %s\n' "$attacker_public" > "$repo/ci/allowed_signers"
printf 'candidate=untrusted\n' >> "$repo/release.txt"
git -C "$repo" add ci/allowed_signers release.txt
git -C "$repo" commit --quiet -S -m 'test: candidate changes trust policy'
self_authorized_commit="$(git -C "$repo" rev-parse HEAD)"

git -C "$repo" config gpg.ssh.allowedSignersFile "$repo/ci/allowed_signers"
git -C "$repo" verify-commit "$self_authorized_commit" >/dev/null 2>&1
test "$(git -C "$repo" show --no-patch --format='%GS' "$self_authorized_commit")" = attacker@example.invalid

git -C "$repo" config gpg.ssh.allowedSignersFile "$external_policy"
if git -C "$repo" verify-commit "$self_authorized_commit" >/dev/null 2>&1; then
  printf 'Expected external trust policy to reject the candidate signing key.\n' >&2
  exit 1
fi
git -C "$repo" verify-commit "$signed_commit" >/dev/null 2>&1
git -C "$repo" verify-tag "$tag_object" >/dev/null 2>&1

git -C "$repo" switch --quiet --create rewritten "$signed_commit"
git -C "$repo" config user.name 'Release Maintainer'
git -C "$repo" config user.email 'release@example.invalid'
git -C "$repo" config user.signingKey "$release_key"
printf 'rewritten=true\n' >> "$repo/release.txt"
git -C "$repo" add release.txt
git -C "$repo" commit --quiet -S -m 'rewrite: signed intermediate'
rewrite_parent="$(git -C "$repo" rev-parse HEAD)"
printf 'amended=true\n' >> "$repo/release.txt"
git -C "$repo" add release.txt
git -C "$repo" commit --quiet --amend --no-gpg-sign -m 'rewrite: unsigned replacement'
rewritten_commit="$(git -C "$repo" rev-parse HEAD)"
test "$rewritten_commit" != "$rewrite_parent"
test "$(git -C "$repo" show --no-patch --format='%G?' "$rewrite_parent")" = G
test "$(git -C "$repo" show --no-patch --format='%G?' "$rewritten_commit")" = N
git -C "$repo" verify-commit "$signed_commit" >/dev/null 2>&1
git -C "$repo" cat-file -e "$signed_commit^{commit}"
test "$(git -C "$repo" rev-parse 'v1.0.0^{}')" = "$signed_commit"

printf 'Signature failure classification, external trust policy, tag target, and rewrite boundaries passed.\n'
