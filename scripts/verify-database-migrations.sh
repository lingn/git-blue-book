#!/usr/bin/env bash

set -euo pipefail

lab_dir="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-database-migrations.XXXXXX")"
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
    printf 'A SHA-256 command is required for the migration experiment.\n' >&2
    return 1
  fi
}

repo="$lab_dir/repository"
mkdir -p "$repo/db/migrations"
git -C "$repo" init --quiet --initial-branch=main
git -C "$repo" config user.name "Migration Lab"
git -C "$repo" config user.email "migration@example.invalid"

printf '%s\n' \
  'migration_id=001-expand-display-name' \
  'rollback_class=reversible-before-contract' \
  'precondition_schema=schema-v1' \
  'target_schema=schema-v2-expand' \
  > "$repo/db/migrations/001-expand.manifest"
git -C "$repo" add db/migrations/001-expand.manifest
git -C "$repo" commit --quiet -m "db: add expand migration contract"
expand_commit="$(git -C "$repo" rev-parse HEAD)"
expand_manifest_digest="$(sha256_file "$repo/db/migrations/001-expand.manifest")"

state="$lab_dir/database"
mkdir -p "$state"
printf '%s\n' 'column=id' 'column=name' > "$state/schema.tsv"
printf 'id\tname\tdisplay_name\n1\tAlpha\t\n2\tBeta\t\n' > "$state/rows.tsv"
: > "$state/applied.tsv"

grep -Fqx 'column=name' "$state/schema.tsv"
if grep -Fq 'column=display_name' "$state/schema.tsv"; then
  printf 'display_name unexpectedly existed before expand.\n' >&2
  exit 1
fi

printf '%s\n' 'column=display_name' >> "$state/schema.tsv"
printf '001-expand-display-name\t%s\n' "$expand_commit" >> "$state/applied.tsv"
printf 'schema_version=schema-v2-expand\n' > "$state/schema.version"
grep -Fqx 'column=display_name' "$state/schema.tsv"
grep -Fqx "001-expand-display-name	$expand_commit" "$state/applied.tsv"

rows_before="$(sha256_file "$state/rows.tsv")"
awk -F '\t' 'BEGIN {OFS="\t"} NR == 1 {print; next} NR == 2 {$3 = $2} {print}' \
  "$state/rows.tsv" > "$state/rows.partial"
mv "$state/rows.partial" "$state/rows.tsv"
printf 'checkpoint=1\nstatus=paused\n' > "$state/backfill.env"
grep -Fqx 'checkpoint=1' "$state/backfill.env"
grep -Fqx 'status=paused' "$state/backfill.env"
test "$(sha256_file "$state/rows.tsv")" != "$rows_before"

awk -F '\t' 'BEGIN {OFS="\t"} NR == 1 {print; next} $3 == "" {$3 = $2} {print}' \
  "$state/rows.tsv" > "$state/rows.complete"
mv "$state/rows.complete" "$state/rows.tsv"
printf 'checkpoint=2\nstatus=complete\n' > "$state/backfill.env"
awk -F '\t' 'NR > 1 && $3 != $2 {exit 1}' "$state/rows.tsv"
grep -Fqx 'status=complete' "$state/backfill.env"

printf '3\tGamma\tGamma\n' >> "$state/rows.tsv"
awk -F '\t' 'NR > 1 && ($2 == "" || $3 == "") {exit 1}' "$state/rows.tsv"
printf 'dual_write=enabled\n' > "$state/write-policy.env"

if grep -Fq 'old_app_fenced=true' "$state/guards.env" 2>/dev/null; then
  printf 'old app was fenced before the contract gate.\n' >&2
  exit 1
fi
if grep -Fq 'column=name' "$state/schema.tsv" && \
  test ! -f "$state/guards.env"; then
  contract_without_fence=0
else
  contract_without_fence=1
fi
test "$contract_without_fence" -eq 0

printf 'old_app_fenced=true\nold_consumer_fenced=true\n' > "$state/guards.env"
grep -Fqx 'old_app_fenced=true' "$state/guards.env"
grep -Fqx 'old_consumer_fenced=true' "$state/guards.env"

awk -F '\t' 'BEGIN {OFS="\t"} $1 != "column=name" {print}' \
  "$state/schema.tsv" > "$state/schema.contract"
mv "$state/schema.contract" "$state/schema.tsv"
awk -F '\t' 'BEGIN {OFS="\t"} NR == 1 {print; next} {print $1, $3}' \
  "$state/rows.tsv" > "$state/rows.contract"
mv "$state/rows.contract" "$state/rows.tsv"
printf 'schema_version=schema-v3-contract\n' > "$state/schema.version"
printf '002-contract-display-name\tstatus=complete\n' >> "$state/applied.tsv"
if grep -Fq 'column=name' "$state/schema.tsv"; then
  printf 'contract did not remove the fenced column.\n' >&2
  exit 1
fi
awk -F '\t' 'NR > 1 && NF != 2 {exit 1}' "$state/rows.tsv"

printf '%s\n' \
  "migration_code_digest=$expand_manifest_digest" \
  "source_commit=$expand_commit" \
  'database_schema=schema-v3-contract' \
  'backfill_status=complete' \
  'rollback_class=forward-fix-required-after-contract' \
  > "$state/migration-record.env"
grep -Fqx 'rollback_class=forward-fix-required-after-contract' \
  "$state/migration-record.env"

git -C "$repo" switch --quiet --create main-after-migration
printf 'post-migration application change\n' > "$repo/app.txt"
git -C "$repo" add app.txt
git -C "$repo" commit --quiet -m "app: advance after migration"
new_commit="$(git -C "$repo" rev-parse HEAD)"
test "$new_commit" != "$expand_commit"
grep -Fqx 'schema_version=schema-v3-contract' "$state/schema.version"
grep -Fqx 'rollback_class=forward-fix-required-after-contract' \
  "$state/migration-record.env"

printf 'Expand/contract fixture, resumable backfill, compatibility gate, and forward-fix boundary passed.\n'
