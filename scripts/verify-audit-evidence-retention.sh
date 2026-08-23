#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-audit-evidence.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

event_header=$'sequence\tprovider_event_id\trepository_id\tactor\trequest_id\taction\tref_name\told_oid\tnew_oid\tobject_format\tresult\treason\trule_id\tpolicy_digest\tprovider_time\tcollector_time'

hash_file() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    sha256sum "$file_path" | awk '{print $1}'
  fi
}

collect_new_events() {
  local source_path="$1"
  local cursor_path="$2"
  local destination_path="$3"
  local current_cursor next_cursor batch_path

  test "$(sed -n '1p' "$source_path")" = "$event_header" || return 4
  current_cursor="$(sed -n '1p' "$cursor_path")"
  batch_path="$lab_root/collector-batch.tsv"

  awk -F '\t' -v cursor="$current_cursor" '
    NR > 1 && $1 + 0 > cursor + 0 { print }
  ' "$source_path" > "$batch_path"

  if test -s "$batch_path"; then
    cat "$batch_path" >> "$destination_path"
  fi

  next_cursor="$({
    printf '%s\n' "$current_cursor"
    awk -F '\t' 'NR > 1 { print $1 + 0 }' "$source_path"
  } | LC_ALL=C sort -n | tail -n 1)"
  printf '%s\n' "$next_cursor" > "$cursor_path"
}

validate_export() {
  local source_status="$1"
  local events_path="$2"

  if test "$source_status" != available; then
    return 3
  fi

  awk -F '\t' -v expected_header="$event_header" '
    NR == 1 {
      if ($0 != expected_header) {
        exit 4
      }
      next
    }
    {
      rows++
      if (NF != 16) {
        invalid = 1
      }
      if ($1 + 0 != rows) {
        invalid = 1
      }
      if ($2 == "" || seen_event[$2]++) {
        invalid = 1
      }
      if ($3 == "" || $4 == "" || $5 == "" ||
          $6 == "" || $7 == "") {
        invalid = 1
      }
      if ($10 != "sha1" || length($8) != 40 || length($9) != 40 ||
          $8 !~ /^[0-9a-f]+$/ || $9 !~ /^[0-9a-f]+$/) {
        invalid = 1
      }
      if ($11 != "accepted" && $11 != "denied") {
        invalid = 1
      }
      if ($14 == "" || $15 == "" || $16 == "") {
        invalid = 1
      }
    }
    END {
      if (rows == 0 || invalid) {
        exit 2
      }
      exit 0
    }
  ' "$events_path"
}

write_manifest() {
  local package_path="$1"

  (
    cd "$package_path"
    find . -type f ! -name MANIFEST.sha256 -print |
      LC_ALL=C sort |
      while IFS= read -r relative_path; do
        digest="$(hash_file "$relative_path")"
        size="$(wc -c < "$relative_path" | tr -d ' ')"
        printf '%s\t%s\t%s\n' "$digest" "$size" "$relative_path"
      done
  ) > "$package_path/MANIFEST.sha256"
}

verify_manifest() {
  local package_path="$1"
  local expected_digest expected_size relative_path
  local actual_digest actual_size

  while IFS=$'\t' read -r expected_digest expected_size relative_path
  do
    test -n "$relative_path" || return 1
    test -f "$package_path/$relative_path" || return 1
    actual_digest="$(hash_file "$package_path/$relative_path")"
    actual_size="$(wc -c < "$package_path/$relative_path" | tr -d ' ')"
    test "$actual_digest" = "$expected_digest" || return 1
    test "$actual_size" = "$expected_size" || return 1
  done < "$package_path/MANIFEST.sha256"
}

work_repo="$lab_root/work"
service_repo="$lab_root/service.git"
source_log="$lab_root/provider-events.tsv"
policy_file="$lab_root/policy.txt"

printf 'rule=ORG-NONFF\nmode=enforce\n' > "$policy_file"
policy_digest="$(hash_file "$policy_file")"
printf '%s\n' "$event_header" > "$source_log"

git init --quiet --initial-branch=main "$work_repo"
git -C "$work_repo" config user.name 'Audit Evidence Fixture'
git -C "$work_repo" config user.email 'audit-evidence@example.invalid'
printf 'version=1\n' > "$work_repo/service.conf"
git -C "$work_repo" add service.conf
GIT_AUTHOR_DATE='2040-01-01T00:00:00+00:00' \
GIT_COMMITTER_DATE='2040-01-01T00:00:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: future object clock'
base_commit="$(git -C "$work_repo" rev-parse HEAD)"
base_tree="$(git -C "$work_repo" rev-parse HEAD^{tree})"
object_format="$(git -C "$work_repo" rev-parse --show-object-format)"
test "$object_format" = sha1

rewritten_commit="$({
  printf 'fixture: unrelated root for denied update\n'
} | GIT_AUTHOR_NAME='Audit Evidence Fixture' \
  GIT_AUTHOR_EMAIL='audit-evidence@example.invalid' \
  GIT_COMMITTER_NAME='Audit Evidence Fixture' \
  GIT_COMMITTER_EMAIL='audit-evidence@example.invalid' \
  GIT_AUTHOR_DATE='2041-01-01T00:00:00+00:00' \
  GIT_COMMITTER_DATE='2041-01-01T00:00:00+00:00' \
  git -C "$work_repo" commit-tree "$base_tree")"

git init --quiet --bare --initial-branch=main "$service_repo"
git -C "$work_repo" remote add origin "$service_repo"

pre_receive="$service_repo/hooks/pre-receive"
post_receive="$service_repo/hooks/post-receive"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -eu'
  printf 'source_log=%q\n' "$source_log"
  printf '%s\n' 'zero_oid=0000000000000000000000000000000000000000'
  printf '%s\n' 'while read -r old_oid new_oid ref_name; do'
  printf '%s\n' '  if test "$ref_name" = refs/heads/main &&'
  printf '%s\n' '     test "$old_oid" != "$zero_oid" &&'
  printf '%s\n' '     test "$new_oid" != "$zero_oid" &&'
  printf '%s\n' '     ! git merge-base --is-ancestor "$old_oid" "$new_oid"; then'
  printf '%s\n' '    printf "%s\t%s\t%s\t%s\t%s\tpush\t%s\t%s\t%s\t%s\tdenied\tnon-fast-forward\tORG-NONFF\t%s\t%s\t%s\n" "$AUDIT_SEQUENCE" "$AUDIT_EVENT_ID" repository-payments "$AUDIT_ACTOR" "$AUDIT_REQUEST_ID" "$ref_name" "$old_oid" "$new_oid" "$AUDIT_OBJECT_FORMAT" "$AUDIT_POLICY_DIGEST" "$AUDIT_PROVIDER_TIME" "$AUDIT_COLLECTOR_TIME" >> "$source_log"'
  printf '%s\n' '    printf "audit fixture rejects non-fast-forward update\n" >&2'
  printf '%s\n' '    exit 1'
  printf '%s\n' '  fi'
  printf '%s\n' 'done'
} > "$pre_receive"

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -eu'
  printf 'source_log=%q\n' "$source_log"
  printf '%s\n' 'while read -r old_oid new_oid ref_name; do'
  printf '%s\n' '  printf "%s\t%s\t%s\t%s\t%s\tpush\t%s\t%s\t%s\t%s\taccepted\t-\t-\t%s\t%s\t%s\n" "$AUDIT_SEQUENCE" "$AUDIT_EVENT_ID" repository-payments "$AUDIT_ACTOR" "$AUDIT_REQUEST_ID" "$ref_name" "$old_oid" "$new_oid" "$AUDIT_OBJECT_FORMAT" "$AUDIT_POLICY_DIGEST" "$AUDIT_PROVIDER_TIME" "$AUDIT_COLLECTOR_TIME" >> "$source_log"'
  printf '%s\n' 'done'
} > "$post_receive"
chmod +x "$pre_receive" "$post_receive"

AUDIT_SEQUENCE=1 \
AUDIT_EVENT_ID=provider-event-001 \
AUDIT_ACTOR=developer-alice \
AUDIT_REQUEST_ID=request-001 \
AUDIT_OBJECT_FORMAT="$object_format" \
AUDIT_POLICY_DIGEST="$policy_digest" \
AUDIT_PROVIDER_TIME=2000000010 \
AUDIT_COLLECTOR_TIME=2000000020 \
  git -C "$work_repo" push --quiet origin main
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"

collector_dir="$lab_root/collector"
mkdir -p "$collector_dir"
events_export="$collector_dir/events.tsv"
cursor_path="$collector_dir/cursor"
printf '%s\n' "$event_header" > "$events_export"
printf '0\n' > "$cursor_path"
collect_new_events "$source_log" "$cursor_path" "$events_export"
test "$(sed -n '1p' "$cursor_path")" = 1
test "$(wc -l < "$events_export" | tr -d ' ')" = 2

if AUDIT_SEQUENCE=2 \
  AUDIT_EVENT_ID=provider-event-002 \
  AUDIT_ACTOR=automation-compromised \
  AUDIT_REQUEST_ID=request-002 \
  AUDIT_OBJECT_FORMAT="$object_format" \
  AUDIT_POLICY_DIGEST="$policy_digest" \
  AUDIT_PROVIDER_TIME=2000000030 \
  AUDIT_COLLECTOR_TIME=2000000040 \
  git -C "$work_repo" push --force origin \
    "$rewritten_commit:refs/heads/main" \
    > "$lab_root/denied.out" 2> "$lab_root/denied.err"; then
  printf 'Expected non-fast-forward fixture update to be rejected.\n' >&2
  exit 1
fi
grep -F 'audit fixture rejects non-fast-forward update' \
  "$lab_root/denied.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"

collect_new_events "$source_log" "$cursor_path" "$events_export"
test "$(sed -n '1p' "$cursor_path")" = 2
test "$(wc -l < "$events_export" | tr -d ' ')" = 3
events_digest_before="$(hash_file "$events_export")"
collect_new_events "$source_log" "$cursor_path" "$events_export"
test "$(hash_file "$events_export")" = "$events_digest_before"

validate_export available "$events_export"
awk -F '\t' -v base="$base_commit" -v rewritten="$rewritten_commit" \
  -v digest="$policy_digest" '
  NR == 2 {
    if ($2 != "provider-event-001" || $4 != "developer-alice" ||
        $5 != "request-001" || $8 != "0000000000000000000000000000000000000000" ||
        $9 != base || $11 != "accepted" || $14 != digest) {
      exit 1
    }
  }
  NR == 3 {
    if ($2 != "provider-event-002" || $4 != "automation-compromised" ||
        $5 != "request-002" || $8 != base || $9 != rewritten ||
        $11 != "denied" || $12 != "non-fast-forward" ||
        $13 != "ORG-NONFF" || $14 != digest) {
      exit 1
    }
  }
' "$events_export"

commit_time="$(git -C "$work_repo" show -s --format=%ct "$base_commit")"
test "$commit_time" -gt 2000000010

gap_export="$lab_root/events-with-gap.tsv"
awk -F '\t' 'BEGIN { OFS = "\t" }
  NR == 3 { $1 = 3 }
  { print }
' "$events_export" > "$gap_export"
gap_status=0
validate_export available "$gap_export" || gap_status=$?
if test "$gap_status" -ne 2; then
  printf 'Expected sequence gap to return fail status 2, got %s.\n' \
    "$gap_status" >&2
  exit 1
fi

unavailable_status=0
validate_export unavailable "$events_export" || unavailable_status=$?
if test "$unavailable_status" -ne 3; then
  printf 'Expected unavailable source to return inconclusive status 3, got %s.\n' \
    "$unavailable_status" >&2
  exit 1
fi

package="$lab_root/investigation-package"
mkdir -p "$package/raw" "$package/normalized" "$package/schema"
cp "$source_log" "$package/raw/provider-events.tsv"
cp "$events_export" "$package/normalized/events.tsv"
{
  printf 'case_id=INC-AUDIT-2026-0042\n'
  printf 'repository_id=repository-payments\n'
  printf 'export_status=complete\n'
  printf 'exported_at=2000000100\n'
} > "$package/case.txt"
{
  printf 'query.repository_id=repository-payments\n'
  printf 'query.provider_time=[2000000000,2000000100)\n'
  printf 'query.event_type=git.push\n'
  printf 'query.timezone=UTC\n'
  printf 'query.cursor_start=0\n'
  printf 'query.cursor_end=2\n'
} > "$package/scope-and-query.txt"
{
  printf 'source\tinstance\tstatus\tfirst_sequence\tlast_sequence\n'
  printf 'local-git-fixture\tservice.git\tavailable\t1\t2\n'
} > "$package/source-inventory.tsv"
{
  printf '%s\n' "$event_header"
  printf 'schema_version=fixture-v1\n'
  printf 'parser=verify-audit-evidence-retention.sh\n'
} > "$package/schema/events-schema.txt"
{
  printf 'source\tstatus\tdetail\n'
  printf 'local-git-fixture\tcomplete\tsequence 1 through 2 present\n'
  printf 'platform-api\tnot_applicable\tlocal experiment does not call a platform\n'
} > "$package/gaps-and-unknowns.tsv"
{
  printf 'collector=fixture-collector-v1\n'
  printf 'parser=fixture-parser-v1\n'
  printf 'git=%s\n' "$(git --version)"
} > "$package/collector-and-parser-versions.txt"
write_manifest "$package"
verify_manifest "$package"

tampered_package="$lab_root/tampered-package"
cp -R "$package" "$tampered_package"
printf 'tampered\n' >> "$tampered_package/normalized/events.tsv"
if verify_manifest "$tampered_package"; then
  printf 'Expected manifest verification to reject tampered events.\n' >&2
  exit 1
fi

git -C "$service_repo" fsck --full --strict --no-progress \
  > "$lab_root/service.fsck" 2>&1

printf 'Audit accept/deny events, cursor idempotence, sequence gaps, clock boundaries, and investigation manifest passed.\n'
