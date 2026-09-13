#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-ownership-approvals.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
export GIT_PAGER=cat
export LC_ALL=C
unset GIT_CONFIG_COUNT

repo="$lab_root/repository"
owners="$lab_root/trusted-owners.tsv"
approvals_f1="$lab_root/approvals-f1.tsv"
approvals_f2_missing="$lab_root/approvals-f2-missing.tsv"
approvals_f2_complete="$lab_root/approvals-f2-complete.tsv"
owners_without_security="$lab_root/trusted-owners-without-security.tsv"

git -C "$lab_root" init --quiet --initial-branch=main repository
git -C "$repo" config user.name 'Ownership Approval Fixture'
git -C "$repo" config user.email 'ownership-approval@example.invalid'
mkdir -p "$repo/services/payments" "$repo/security" "$repo/.review"
printf 'payment=v1\n' > "$repo/services/payments/app.txt"
printf 'security=v1\n' > "$repo/security/policy.yml"
printf 'policy-version=v1\n' > "$repo/.review/owners.tsv"
git -C "$repo" add .
GIT_AUTHOR_DATE='2026-09-14T02:00:00+00:00' \
GIT_COMMITTER_DATE='2026-09-14T02:00:00+00:00' \
  git -C "$repo" commit --quiet -m 'fixture: establish ownership baseline'
base_commit="$(git -C "$repo" rev-parse HEAD)"

{
  printf 'path_prefix\trole\tprincipal\n'
  printf 'services/payments/\tcode\tpayments-owner\n'
  printf 'security/\tsecurity\tsecurity-owner\n'
  printf '.review/owners.tsv\tpolicy\tpolicy-owner\n'
} > "$owners"

evaluate_candidate() {
  local candidate="$1"
  local target="$2"
  local author="$3"
  local approvals_path="$4"
  local owners_path="$5"
  local required_roles="$lab_root/required-roles.tsv"
  local changed_paths="$lab_root/changed-paths.txt"

  if ! git -C "$repo" cat-file -e "$candidate^{commit}"; then
    printf 'inconclusive reason=candidate-missing candidate=%s\n' "$candidate"
    return 3
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$target" "$candidate"; then
    printf 'deny reason=candidate-stale target=%s candidate=%s\n' \
      "$target" "$candidate"
    return 2
  fi

  git -C "$repo" diff --name-only "$target" "$candidate" > "$changed_paths"
  if test ! -s "$changed_paths"; then
    printf 'inconclusive reason=no-changed-paths candidate=%s\n' "$candidate"
    return 3
  fi

  : > "$required_roles"
  while IFS= read -r changed_path; do
    matched=0
    while IFS=$'\t' read -r path_prefix role principal; do
      if test "$path_prefix" = path_prefix; then
        continue
      fi
      case "$changed_path" in
        "$path_prefix"*)
          matched=1
          printf '%s\t%s\n' "$role" "$principal" >> "$required_roles"
          ;;
      esac
    done < "$owners_path"
    if test "$matched" -eq 0; then
      printf 'inconclusive reason=unowned-path path=%s candidate=%s\n' \
        "$changed_path" "$candidate"
      return 3
    fi
  done < "$changed_paths"

  while IFS=$'\t' read -r role allowed_principal; do
    test -n "$role"
    if awk -F '\t' -v candidate="$candidate" -v role="$role" \
      -v principal="$allowed_principal" \
      'NR > 1 && $1 == candidate && $2 == role && $3 == principal &&
       $4 == "approve" && $5 == "policy-v1" { found = 1 }
       END { exit(found ? 0 : 1) }' "$approvals_path"; then
      continue
    fi

    if awk -F '\t' -v candidate="$candidate" -v role="$role" \
      -v author="$author" \
      'NR > 1 && $1 == candidate && $2 == role && $3 == author &&
       $4 == "approve" { found = 1 }
       END { exit(found ? 0 : 1) }' "$approvals_path"; then
      printf 'deny reason=self-approval role=%s principal=%s candidate=%s\n' \
        "$role" "$author" "$candidate"
      return 2
    fi

    printf 'deny reason=missing-owner-approval role=%s principal=%s candidate=%s\n' \
      "$role" "$allowed_principal" "$candidate"
    return 2
  done < <(sort -u "$required_roles")

  printf 'allow candidate=%s target=%s policy=policy-v1\n' "$candidate" "$target"
}

printf 'payment=v2\n' > "$repo/services/payments/app.txt"
git -C "$repo" add services/payments/app.txt
GIT_AUTHOR_DATE='2026-09-14T02:05:00+00:00' \
GIT_COMMITTER_DATE='2026-09-14T02:05:00+00:00' \
  git -C "$repo" commit --quiet -m 'feat: update payment service'
f1_commit="$(git -C "$repo" rev-parse HEAD)"

{
  printf 'candidate\trole\tprincipal\tdecision\tpolicy_version\n'
  printf '%s\tcode\tdeveloper-alice\tapprove\tpolicy-v1\n' "$f1_commit"
} > "$approvals_f1"
f1_self_status=0
evaluate_candidate "$f1_commit" "$base_commit" developer-alice \
  "$approvals_f1" "$owners" > "$lab_root/f1-self.txt" || f1_self_status=$?
test "$f1_self_status" -eq 2
grep -F 'deny reason=self-approval role=code principal=developer-alice' \
  "$lab_root/f1-self.txt" >/dev/null

{
  printf 'candidate\trole\tprincipal\tdecision\tpolicy_version\n'
  printf '%s\tcode\tpayments-owner\tapprove\tpolicy-v1\n' "$f1_commit"
} > "$approvals_f1"
evaluate_candidate "$f1_commit" "$base_commit" developer-alice \
  "$approvals_f1" "$owners" > "$lab_root/f1-approved.txt"
grep -F "allow candidate=$f1_commit target=$base_commit" \
  "$lab_root/f1-approved.txt" >/dev/null

printf 'security=v2\n' > "$repo/security/policy.yml"
printf 'services/payments/\tcode\tdeveloper-alice\n' > "$repo/.review/owners.tsv"
git -C "$repo" add security/policy.yml .review/owners.tsv
GIT_AUTHOR_DATE='2026-09-14T02:10:00+00:00' \
GIT_COMMITTER_DATE='2026-09-14T02:10:00+00:00' \
  git -C "$repo" commit --quiet -m 'feat: update security policy and candidate ownership file'
f2_commit="$(git -C "$repo" rev-parse HEAD)"

{
  printf 'candidate\trole\tprincipal\tdecision\tpolicy_version\n'
  printf '%s\tcode\tpayments-owner\tapprove\tpolicy-v1\n' "$f1_commit"
  printf '%s\tpolicy\tpolicy-owner\tapprove\tpolicy-v1\n' "$f2_commit"
} > "$approvals_f2_missing"
f2_missing_status=0
evaluate_candidate "$f2_commit" "$base_commit" developer-alice \
  "$approvals_f2_missing" "$owners" > "$lab_root/f2-missing.txt" || f2_missing_status=$?
test "$f2_missing_status" -eq 2
grep -F 'deny reason=missing-owner-approval role=code principal=payments-owner' \
  "$lab_root/f2-missing.txt" >/dev/null

{
  printf 'candidate\trole\tprincipal\tdecision\tpolicy_version\n'
  printf '%s\tcode\tpayments-owner\tapprove\tpolicy-v1\n' "$f2_commit"
  printf '%s\tsecurity\tsecurity-owner\tapprove\tpolicy-v1\n' "$f2_commit"
  printf '%s\tpolicy\tpolicy-owner\tapprove\tpolicy-v1\n' "$f2_commit"
} > "$approvals_f2_complete"
evaluate_candidate "$f2_commit" "$base_commit" developer-alice \
  "$approvals_f2_complete" "$owners" > "$lab_root/f2-approved.txt"
grep -F "allow candidate=$f2_commit target=$base_commit" \
  "$lab_root/f2-approved.txt" >/dev/null

git -C "$repo" switch --quiet main
printf 'unrelated=true\n' > "$repo/README.md"
git -C "$repo" add README.md
GIT_AUTHOR_DATE='2026-09-14T02:15:00+00:00' \
GIT_COMMITTER_DATE='2026-09-14T02:15:00+00:00' \
  git -C "$repo" commit --quiet -m 'fix: advance target branch'
target_advanced="$(git -C "$repo" rev-parse HEAD)"
stale_status=0
evaluate_candidate "$f2_commit" "$target_advanced" developer-alice \
  "$approvals_f2_complete" "$owners" > "$lab_root/f2-stale.txt" || stale_status=$?
test "$stale_status" -eq 2
grep -F 'deny reason=candidate-stale' "$lab_root/f2-stale.txt" >/dev/null

awk -F '\t' 'NR == 1 || $2 != "security"' "$owners" > "$owners_without_security"
inconclusive_status=0
evaluate_candidate "$f2_commit" "$base_commit" developer-alice \
  "$approvals_f2_complete" "$owners_without_security" > \
  "$lab_root/f2-owner-outage.txt" || inconclusive_status=$?
test "$inconclusive_status" -eq 3
grep -F 'inconclusive reason=unowned-path path=security/policy.yml' \
  "$lab_root/f2-owner-outage.txt" >/dev/null

printf 'Ownership snapshot, independent approvals, candidate binding, stale decisions, and owner outage boundaries passed.\n'
