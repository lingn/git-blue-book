#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-lifecycle-governance.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

hash_value() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    sha256sum "$file_path" | awk '{print $1}'
  fi
}

validate_registry() {
  local registry_path="$1"
  local line_number=0
  local registry_row normalized_row
  local repository_id repository_path lifecycle business_owner technical_owner
  local data_class default_branch backup_path backup_digest deletion_case
  local actual_default actual_digest hook_path

  while IFS= read -r registry_row
  do
    normalized_row="${registry_row//$'\t'/$'\034'}"
    IFS=$'\034' read -r \
      repository_id repository_path lifecycle business_owner technical_owner \
      data_class default_branch backup_path backup_digest deletion_case \
      <<< "$normalized_row"
    line_number=$((line_number + 1))
    if test "$line_number" -eq 1; then
      test "$repository_id" = 'repository_id' || return 11
      test "$repository_path" = 'repository_path' || return 12
      continue
    fi

    test -n "$repository_id" || return 20
    test -n "$repository_path" || return 21
    test -n "$business_owner" || return 22
    test -n "$technical_owner" || return 23
    test "$business_owner" != "$technical_owner" || return 24
    test -n "$data_class" || return 25
    test -n "$default_branch" || return 26
    test -d "$repository_path" || return 27
    git -C "$repository_path" rev-parse --is-bare-repository |
      grep -Fx 'true' >/dev/null || return 28

    case "$lifecycle" in
      active|archived|pending_delete)
        ;;
      *)
        return 29
        ;;
    esac

    actual_default="$(git -C "$repository_path" symbolic-ref HEAD)" || return 30
    test "$actual_default" = "refs/heads/$default_branch" || return 31
    git -C "$repository_path" show-ref --verify --quiet \
      "refs/heads/$default_branch" || return 32
    git -C "$repository_path" fsck --full --strict --no-progress \
      >/dev/null 2>&1 || return 33

    case "$lifecycle" in
      active)
        test "$backup_path" = '-' || return 40
        test "$backup_digest" = '-' || return 41
        test "$deletion_case" = '-' || return 42
        ;;
      archived)
        test -f "$backup_path" || return 50
        test -n "$backup_digest" || return 51
        test "$backup_digest" != '-' || return 52
        actual_digest="$(hash_value "$backup_path")"
        test "$actual_digest" = "$backup_digest" || return 53
        git -C "$repository_path" bundle verify "$backup_path" \
          >/dev/null 2>&1 || return 54
        hook_path="$repository_path/hooks/pre-receive"
        test -x "$hook_path" || return 55
        grep -F 'repository is archived and read-only' "$hook_path" \
          >/dev/null || return 56
        test "$deletion_case" = '-' || return 57
        ;;
      pending_delete)
        test -f "$backup_path" || return 60
        test -n "$backup_digest" || return 61
        test "$backup_digest" != '-' || return 62
        actual_digest="$(hash_value "$backup_path")"
        test "$actual_digest" = "$backup_digest" || return 63
        git -C "$repository_path" bundle verify "$backup_path" \
          >/dev/null 2>&1 || return 64
        test -n "$deletion_case" || return 65
        test "$deletion_case" != '-' || return 66
        hook_path="$repository_path/hooks/pre-receive"
        test -x "$hook_path" || return 67
        grep -F 'repository is archived and read-only' "$hook_path" \
          >/dev/null || return 68
        ;;
    esac
  done < "$registry_path"

  test "$line_number" -gt 1 || return 70
}

work_repo="$lab_root/work"
service_repo="$lab_root/service.git"
git init --quiet --initial-branch=main "$work_repo"
git -C "$work_repo" config user.name 'Lifecycle Governance Fixture'
git -C "$work_repo" config user.email 'lifecycle@example.invalid'
mkdir -p "$work_repo/src"
printf 'service=v1\n' > "$work_repo/src/service.conf"
git -C "$work_repo" add src/service.conf
GIT_AUTHOR_DATE='2026-08-21T01:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T01:00:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: establish governed repository'
main_commit="$(git -C "$work_repo" rev-parse HEAD)"
git -C "$work_repo" tag -a lifecycle-v1 \
  -m 'fixture: lifecycle checkpoint' "$main_commit"

git init --quiet --bare --initial-branch=main "$service_repo"
git -C "$work_repo" remote add origin "$service_repo"
git -C "$work_repo" push --quiet origin --all
git -C "$work_repo" push --quiet origin --tags
git -C "$service_repo" symbolic-ref HEAD refs/heads/main

header=$'repository_id\trepository_path\tlifecycle\tbusiness_owner\ttechnical_owner\tdata_class\tdefault_branch\tbackup_path\tbackup_digest\tdeletion_case'
active_registry="$lab_root/active.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tactive\tteam-payments-product\tteam-payments-platform\tinternal\tmain\t-\t-\t-\n' \
    "$service_repo"
} > "$active_registry"
validate_registry "$active_registry"

missing_owner_registry="$lab_root/missing-owner.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tactive\tteam-payments-product\t\tinternal\tmain\t-\t-\t-\n' \
    "$service_repo"
} > "$missing_owner_registry"
missing_owner_status=0
validate_registry "$missing_owner_registry" || missing_owner_status=$?
if test "$missing_owner_status" -ne 23; then
  printf 'Expected missing technical owner status 23, got %s.\n' \
    "$missing_owner_status" >&2
  exit 1
fi

wrong_default_registry="$lab_root/wrong-default.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tactive\tteam-payments-product\tteam-payments-platform\tinternal\ttrunk\t-\t-\t-\n' \
    "$service_repo"
} > "$wrong_default_registry"
wrong_default_status=0
validate_registry "$wrong_default_registry" || wrong_default_status=$?
if test "$wrong_default_status" -ne 31; then
  printf 'Expected default-branch mismatch status 31, got %s.\n' \
    "$wrong_default_status" >&2
  exit 1
fi

archive_dir="$lab_root/archive/2026-08-21T020000Z"
mkdir -p "$archive_dir"
refs_before_archive="$archive_dir/refs.txt"
git -C "$service_repo" for-each-ref \
  --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
  LC_ALL=C sort > "$refs_before_archive"
git -C "$service_repo" symbolic-ref HEAD > "$archive_dir/head.symref"
bundle_path="$archive_dir/repository.bundle"
git -C "$service_repo" bundle create "$bundle_path" --all
git -C "$service_repo" bundle verify "$bundle_path" \
  > "$archive_dir/bundle.verify.txt"
bundle_digest="$(hash_value "$bundle_path")"
printf '%s  %s\n' "$bundle_digest" 'repository.bundle' \
  > "$archive_dir/SHA256SUMS"

printf '#!/usr/bin/env bash\nprintf "repository is archived and read-only\\n" >&2\nexit 1\n' \
  > "$service_repo/hooks/pre-receive"
chmod +x "$service_repo/hooks/pre-receive"

archived_registry="$lab_root/archived.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tarchived\tteam-payments-product\tteam-payments-platform\tinternal\tmain\t%s\t%s\t-\n' \
    "$service_repo" "$bundle_path" "$bundle_digest"
} > "$archived_registry"
validate_registry "$archived_registry"

printf 'post-archive change\n' > "$work_repo/src/post-archive.txt"
git -C "$work_repo" add src/post-archive.txt
git -C "$work_repo" commit --quiet -m 'fixture: push should be rejected after archive'
if git -C "$work_repo" push origin main \
  > "$lab_root/archive-push.out" 2> "$lab_root/archive-push.err"; then
  printf 'Expected an archived repository to reject push.\n' >&2
  exit 1
fi
grep -F 'repository is archived and read-only' \
  "$lab_root/archive-push.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$main_commit"

tampered_registry="$lab_root/tampered-backup.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tarchived\tteam-payments-product\tteam-payments-platform\tinternal\tmain\t%s\t%s\t-\n' \
    "$service_repo" "$bundle_path" \
    '0000000000000000000000000000000000000000000000000000000000000000'
} > "$tampered_registry"
tampered_backup_status=0
validate_registry "$tampered_registry" || tampered_backup_status=$?
if test "$tampered_backup_status" -ne 53; then
  printf 'Expected backup digest mismatch status 53, got %s.\n' \
    "$tampered_backup_status" >&2
  exit 1
fi

pending_delete_registry="$lab_root/pending-delete.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tpending_delete\tteam-payments-product\tteam-payments-platform\tinternal\tmain\t%s\t%s\tCHANGE-DELETE-2026-001\n' \
    "$service_repo" "$bundle_path" "$bundle_digest"
} > "$pending_delete_registry"
validate_registry "$pending_delete_registry"

missing_case_registry="$lab_root/missing-delete-case.tsv"
{
  printf '%s\n' "$header"
  printf 'payments-api\t%s\tpending_delete\tteam-payments-product\tteam-payments-platform\tinternal\tmain\t%s\t%s\t-\n' \
    "$service_repo" "$bundle_path" "$bundle_digest"
} > "$missing_case_registry"
missing_case_status=0
validate_registry "$missing_case_registry" || missing_case_status=$?
if test "$missing_case_status" -ne 66; then
  printf 'Expected missing deletion case status 66, got %s.\n' \
    "$missing_case_status" >&2
  exit 1
fi

restore_repo="$lab_root/restore.git"
git init --quiet --bare --initial-branch=main "$restore_repo"
git -C "$restore_repo" fetch --quiet "$bundle_path" '+refs/*:refs/*'
git -C "$restore_repo" symbolic-ref HEAD refs/heads/main
git -C "$restore_repo" fsck --full --strict --no-progress \
  > "$lab_root/restore.fsck" 2>&1
restored_refs="$lab_root/restored.refs"
git -C "$restore_repo" for-each-ref \
  --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
  LC_ALL=C sort > "$restored_refs"
cmp "$refs_before_archive" "$restored_refs"

printf 'Lifecycle registry, ownership/default-branch gates, archive evidence, read-only fencing, deletion approval, and restore passed.\n'
