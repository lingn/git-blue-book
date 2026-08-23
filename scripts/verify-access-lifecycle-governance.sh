#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-access-lifecycle.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

as_of=2000000000
future=2000003600

audit_snapshot() {
  local principals_path="$1"
  local memberships_path="$2"
  local grants_path="$3"

  awk -F '\t' -v now="$as_of" '
    FILENAME == ARGV[1] {
      if (FNR == 1) {
        if ($0 != "principal_id\tkind\tstatus\towner") {
          schema_error = 1
        }
        next
      }
      kind[$1] = $2
      status[$1] = $3
      owner[$1] = $4
      next
    }

    FILENAME == ARGV[2] {
      if (FNR == 1) {
        if ($0 != "principal_id\tgroup_id\tvalid_until") {
          schema_error = 1
        }
        next
      }
      principal_id = $1
      valid_until = $3 + 0
      if (!(principal_id in status)) {
        unknown = 1
        next
      }
      if (status[principal_id] != "active" &&
          (valid_until == 0 || valid_until > now)) {
        failed = 1
      }
      if (kind[principal_id] == "external" &&
          (valid_until == 0 || valid_until <= now)) {
        failed = 1
      }
      next
    }

    FILENAME == ARGV[3] {
      if (FNR == 1) {
        if ($0 != "subject_type\tsubject_id\trepository_id\taction\tvalid_until\tapproval_case") {
          schema_error = 1
        }
        next
      }
      subject_type = $1
      subject_id = $2
      valid_until = $5 + 0
      approval_case = $6

      if (subject_type != "principal" && subject_type != "group") {
        schema_error = 1
        next
      }
      if (subject_type == "group") {
        next
      }
      if (!(subject_id in status)) {
        unknown = 1
        next
      }
      if (status[subject_id] != "active" &&
          (valid_until == 0 || valid_until > now)) {
        failed = 1
      }
      if ((kind[subject_id] == "machine" ||
           kind[subject_id] == "emergency") && owner[subject_id] == "") {
        failed = 1
      }
      if (kind[subject_id] == "emergency" &&
          (valid_until == 0 || valid_until <= now ||
           approval_case == "" || approval_case == "-")) {
        failed = 1
      }
      next
    }

    END {
      if (schema_error) {
        exit 4
      }
      if (failed) {
        exit 2
      }
      if (unknown) {
        exit 3
      }
      exit 0
    }
  ' "$principals_path" "$memberships_path" "$grants_path"
}

principals="$lab_root/principals.tsv"
memberships="$lab_root/memberships.tsv"
grants="$lab_root/grants.tsv"

{
  printf 'principal_id\tkind\tstatus\towner\n'
  printf 'developer-alice\thuman\tactive\tteam-platform\n'
  printf 'former-bob\thuman\tdisabled\tteam-platform\n'
  printf 'vendor-carol\texternal\tactive\tsponsor-payments\n'
  printf 'release-bot\tmachine\tactive\tteam-release\n'
  printf 'breakglass-01\temergency\tactive\tsecurity-oncall\n'
} > "$principals"

{
  printf 'principal_id\tgroup_id\tvalid_until\n'
  printf 'developer-alice\tdevelopers\t0\n'
  printf 'vendor-carol\treviewers\t%s\n' "$future"
} > "$memberships"

{
  printf 'subject_type\tsubject_id\trepository_id\taction\tvalid_until\tapproval_case\n'
  printf 'group\tdevelopers\trepository-payments\tpush_feature\t0\t-\n'
  printf 'group\treviewers\trepository-payments\tread\t%s\t-\n' "$future"
  printf 'principal\trelease-bot\trepository-payments\tcreate_release_tag\t%s\t-\n' "$future"
  printf 'principal\tbreakglass-01\trepository-payments\tpush_main\t%s\tINC-2026-0042\n' \
    "$future"
} > "$grants"

audit_snapshot "$principals" "$memberships" "$grants"

stale_memberships="$lab_root/memberships-stale.tsv"
cp "$memberships" "$stale_memberships"
printf 'former-bob\tmaintainers\t0\n' >> "$stale_memberships"
stale_status=0
audit_snapshot "$principals" "$stale_memberships" "$grants" || stale_status=$?
if test "$stale_status" -ne 2; then
  printf 'Expected disabled principal with live membership to return fail status 2, got %s.\n' \
    "$stale_status" >&2
  exit 1
fi

unknown_grants="$lab_root/grants-unknown.tsv"
cp "$grants" "$unknown_grants"
printf 'principal\tunknown-agent\trepository-payments\tread\t%s\t-\n' \
  "$future" >> "$unknown_grants"
unknown_status=0
audit_snapshot "$principals" "$memberships" "$unknown_grants" || unknown_status=$?
if test "$unknown_status" -ne 3; then
  printf 'Expected unresolved principal to return inconclusive status 3, got %s.\n' \
    "$unknown_status" >&2
  exit 1
fi

work_repo="$lab_root/work"
service_repo="$lab_root/service.git"
git init --quiet --initial-branch=main "$work_repo"
git -C "$work_repo" config user.name 'Access Lifecycle Fixture'
git -C "$work_repo" config user.email 'access-lifecycle@example.invalid'
printf 'version=1\n' > "$work_repo/service.conf"
git -C "$work_repo" add service.conf
GIT_AUTHOR_DATE='2026-08-21T03:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T03:00:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: establish protected main'
base_commit="$(git -C "$work_repo" rev-parse HEAD)"

git init --quiet --bare --initial-branch=main "$service_repo"
git -C "$work_repo" remote add origin "$service_repo"

hook_path="$service_repo/hooks/pre-receive"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -eu'
  printf '%s\n' 'principal="${ACCESS_PRINCIPAL:-}"'
  printf '%s\n' 'approval_case="${ACCESS_CASE:-}"'
  printf '%s\n' 'as_of="${ACCESS_AS_OF:-2000000000}"'
  printf '%s\n' 'expires="${ACCESS_EXPIRES:-0}"'
  printf '%s\n' 'while read -r old_oid new_oid ref_name; do'
  printf '%s\n' '  case "$principal:$ref_name" in'
  printf '%s\n' '    developer-alice:refs/heads/feature/*)'
  printf '%s\n' '      ;;'
  printf '%s\n' '    release-bot:refs/tags/release-*)'
  printf '%s\n' '      ;;'
  printf '%s\n' '    breakglass-01:refs/heads/main)'
  printf '%s\n' '      if test "$approval_case" != "INC-2026-0042" ||'
  printf '%s\n' '         test "$expires" -le "$as_of"; then'
  printf '%s\n' '        printf "[access-denied] break-glass approval missing or expired for %s\n" "$ref_name" >&2'
  printf '%s\n' '        exit 1'
  printf '%s\n' '      fi'
  printf '%s\n' '      ;;'
  printf '%s\n' '    *)'
  printf '%s\n' '      printf "[access-denied] principal=%s ref=%s\n" "$principal" "$ref_name" >&2'
  printf '%s\n' '      exit 1'
  printf '%s\n' '      ;;'
  printf '%s\n' '  esac'
  printf '%s\n' 'done'
} > "$hook_path"
chmod +x "$hook_path"

ACCESS_PRINCIPAL=breakglass-01 \
ACCESS_CASE=INC-2026-0042 \
ACCESS_AS_OF="$as_of" \
ACCESS_EXPIRES="$future" \
  git -C "$work_repo" push --quiet origin main
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"

git -C "$work_repo" switch --quiet -c feature/access-lifecycle
printf 'feature=access-review\n' >> "$work_repo/service.conf"
git -C "$work_repo" add service.conf
GIT_AUTHOR_DATE='2026-08-21T03:05:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T03:05:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: add reviewed feature'
feature_commit="$(git -C "$work_repo" rev-parse HEAD)"

ACCESS_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --quiet origin \
    HEAD:refs/heads/feature/access-lifecycle
test "$(git -C "$service_repo" rev-parse refs/heads/feature/access-lifecycle)" = \
  "$feature_commit"

if ACCESS_PRINCIPAL=developer-alice \
  git -C "$work_repo" push origin HEAD:refs/heads/main \
    > "$lab_root/developer-main.out" 2> "$lab_root/developer-main.err"; then
  printf 'Expected ordinary developer main push to be rejected.\n' >&2
  exit 1
fi
grep -F '[access-denied] principal=developer-alice ref=refs/heads/main' \
  "$lab_root/developer-main.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"

if ACCESS_PRINCIPAL=former-bob \
  git -C "$work_repo" push origin HEAD:refs/heads/former-attempt \
    > "$lab_root/former.out" 2> "$lab_root/former.err"; then
  printf 'Expected disabled principal push to be rejected.\n' >&2
  exit 1
fi
grep -F '[access-denied] principal=former-bob ref=refs/heads/former-attempt' \
  "$lab_root/former.err" >/dev/null
if git -C "$service_repo" show-ref --verify --quiet \
  refs/heads/former-attempt; then
  printf 'Rejected former-principal ref unexpectedly exists.\n' >&2
  exit 1
fi

git -C "$work_repo" tag -a release-2026-08 "$feature_commit" \
  -m 'fixture: approved release tag'
ACCESS_PRINCIPAL=release-bot \
  git -C "$work_repo" push --quiet origin refs/tags/release-2026-08
test "$(git -C "$service_repo" rev-parse refs/tags/release-2026-08)" = \
  "$(git -C "$work_repo" rev-parse refs/tags/release-2026-08)"

if ACCESS_PRINCIPAL=release-bot \
  git -C "$work_repo" push origin HEAD:refs/heads/main \
    > "$lab_root/bot-main.out" 2> "$lab_root/bot-main.err"; then
  printf 'Expected release bot main push to be rejected.\n' >&2
  exit 1
fi
grep -F '[access-denied] principal=release-bot ref=refs/heads/main' \
  "$lab_root/bot-main.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"

ACCESS_PRINCIPAL=breakglass-01 \
ACCESS_CASE=INC-2026-0042 \
ACCESS_AS_OF="$as_of" \
ACCESS_EXPIRES="$future" \
  git -C "$work_repo" push --quiet origin HEAD:refs/heads/main
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$feature_commit"

printf 'emergency-follow-up=1\n' >> "$work_repo/service.conf"
git -C "$work_repo" add service.conf
GIT_AUTHOR_DATE='2026-08-21T03:10:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T03:10:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: attempt after emergency grant'
followup_commit="$(git -C "$work_repo" rev-parse HEAD)"
test "$followup_commit" != "$feature_commit"

if ACCESS_PRINCIPAL=breakglass-01 \
  ACCESS_AS_OF="$as_of" \
  ACCESS_EXPIRES="$future" \
  git -C "$work_repo" push origin HEAD:refs/heads/main \
    > "$lab_root/breakglass-no-case.out" \
    2> "$lab_root/breakglass-no-case.err"; then
  printf 'Expected break-glass push without approval case to be rejected.\n' >&2
  exit 1
fi
grep -F '[access-denied] break-glass approval missing or expired' \
  "$lab_root/breakglass-no-case.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$feature_commit"

if ACCESS_PRINCIPAL=breakglass-01 \
  ACCESS_CASE=INC-2026-0042 \
  ACCESS_AS_OF="$as_of" \
  ACCESS_EXPIRES="$as_of" \
  git -C "$work_repo" push origin HEAD:refs/heads/main \
    > "$lab_root/breakglass-expired.out" \
    2> "$lab_root/breakglass-expired.err"; then
  printf 'Expected expired break-glass push to be rejected.\n' >&2
  exit 1
fi
grep -F '[access-denied] break-glass approval missing or expired' \
  "$lab_root/breakglass-expired.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$feature_commit"

git -C "$service_repo" fsck --full --strict --no-progress \
  > "$lab_root/service.fsck" 2>&1

printf 'Access snapshot pass/fail/inconclusive, developer and machine scopes, leaver denial, and break-glass expiry passed.\n'
