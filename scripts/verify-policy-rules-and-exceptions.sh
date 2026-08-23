#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-policy-rules.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

as_of=2000000000
future=2000003600

hash_file() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    sha256sum "$file_path" | awk '{print $1}'
  fi
}

evaluate_policy() {
  local repositories_path="$1"
  local exceptions_path="$2"
  local rules_path="$3"
  local repository_id="$4"
  local principal_id="$5"
  local action="$6"
  local approval_count="$7"
  local ci_result="$8"
  local signed_state="$9"
  local exception_id="${10}"
  local evaluation_time="${11}"

  awk -F '\t' \
    -v repository_id="$repository_id" \
    -v principal_id="$principal_id" \
    -v requested_action="$action" \
    -v approval_count="$approval_count" \
    -v ci_result="$ci_result" \
    -v signed_state="$signed_state" \
    -v claimed_exception="$exception_id" \
    -v now="$evaluation_time" '
    FILENAME == ARGV[1] {
      if (FNR == 1) {
        if ($0 != "repository_id\tdata_class\tcohort") {
          schema_error = 1
        }
        next
      }
      if ($1 == repository_id) {
        repository_matches++
        data_class = $2
        cohort = $3
      }
      next
    }

    FILENAME == ARGV[2] {
      if (FNR == 1) {
        if ($0 != "exception_id\trule_id\trepository_id\tprincipal_id\taction\tvalid_from\tvalid_until\tapproval_case\tcompensating_control") {
          schema_error = 1
        }
        next
      }
      if ($1 in exception_rule) {
        schema_error = 1
        next
      }
      exception_rule[$1] = $2
      exception_repository[$1] = $3
      exception_principal[$1] = $4
      exception_action[$1] = $5
      exception_from[$1] = $6 + 0
      exception_until[$1] = $7 + 0
      exception_case[$1] = $8
      exception_control[$1] = $9
      next
    }

    FILENAME == ARGV[3] {
      if (FNR == 1) {
        if ($0 != "rule_id\tversion\tpriority\tscope_type\tscope_value\taction\trequirement\tmode") {
          schema_error = 1
        }
        next
      }
      if ($1 in rule_seen) {
        schema_error = 1
        next
      }
      rule_seen[$1] = 1
      rule_count++
      rule_id[rule_count] = $1
      rule_scope_type[rule_count] = $4
      rule_scope_value[rule_count] = $5
      rule_action[rule_count] = $6
      rule_requirement[rule_count] = $7
      rule_mode[rule_count] = $8

      if ($4 != "all" && $4 != "repository" &&
          $4 != "data_class" && $4 != "cohort") {
        schema_error = 1
      }
      if ($7 != "approval" && $7 != "ci_success" &&
          $7 != "signature") {
        schema_error = 1
      }
      if ($8 != "audit" && $8 != "enforce") {
        schema_error = 1
      }
      next
    }

    function exception_matches(current_rule, id) {
      return id != "-" &&
        (id in exception_rule) &&
        exception_rule[id] == current_rule &&
        exception_repository[id] == repository_id &&
        exception_principal[id] == principal_id &&
        exception_action[id] == requested_action &&
        exception_from[id] <= now && now < exception_until[id] &&
        exception_case[id] != "" && exception_case[id] != "-" &&
        exception_control[id] != "" && exception_control[id] != "-"
    }

    END {
      if (schema_error) {
        exit 4
      }
      if (repository_matches != 1) {
        exit 3
      }

      for (i = 1; i <= rule_count; i++) {
        applies = 0
        if (rule_action[i] != requested_action) {
          continue
        }
        if (rule_scope_type[i] == "all") {
          applies = 1
        } else if (rule_scope_type[i] == "repository" &&
                   rule_scope_value[i] == repository_id) {
          applies = 1
        } else if (rule_scope_type[i] == "data_class" &&
                   rule_scope_value[i] == data_class) {
          applies = 1
        } else if (rule_scope_type[i] == "cohort" &&
                   rule_scope_value[i] == cohort) {
          applies = 1
        }
        if (!applies) {
          continue
        }

        applicable_rules++
        satisfied = 0
        if (rule_requirement[i] == "approval" && approval_count + 0 >= 1) {
          satisfied = 1
        } else if (rule_requirement[i] == "ci_success" &&
                   ci_result == "success") {
          satisfied = 1
        } else if (rule_requirement[i] == "signature" &&
                   signed_state == "yes") {
          satisfied = 1
        }
        if (satisfied) {
          continue
        }

        if (exception_matches(rule_id[i], claimed_exception)) {
          printf "exception-used rule=%s exception=%s\n", \
            rule_id[i], claimed_exception
          continue
        }
        if (rule_mode[i] == "audit") {
          printf "would-deny rule=%s\n", rule_id[i]
        } else {
          printf "deny rule=%s\n", rule_id[i]
          enforce_failed = 1
        }
      }

      if (applicable_rules == 0) {
        exit 3
      }
      if (enforce_failed) {
        exit 2
      }
      exit 0
    }
  ' "$repositories_path" "$exceptions_path" "$rules_path"
}

verify_policy_observation() {
  local repository_id="$1"
  local desired_digest="$2"
  local observations_path="$3"

  awk -F '\t' \
    -v repository_id="$repository_id" \
    -v desired_digest="$desired_digest" '
    NR == 1 {
      if ($0 != "repository_id\tstate\tobserved_digest") {
        exit 4
      }
      next
    }
    $1 == repository_id {
      matches++
      state = $2
      observed_digest = $3
    }
    END {
      if (matches != 1 || state == "unavailable") {
        exit 3
      }
      if (state != "applied") {
        exit 4
      }
      if (observed_digest != desired_digest) {
        exit 2
      }
      exit 0
    }
  ' "$observations_path"
}

repositories="$lab_root/repositories.tsv"
exceptions="$lab_root/exceptions.tsv"
rules_audit="$lab_root/rules-audit.tsv"
rules_enforce="$lab_root/rules-enforce.tsv"

{
  printf 'repository_id\tdata_class\tcohort\n'
  printf 'repository-payments\tregulated\tcanary\n'
  printf 'repository-docs\tinternal\tbroad\n'
} > "$repositories"

{
  printf 'exception_id\trule_id\trepository_id\tprincipal_id\taction\tvalid_from\tvalid_until\tapproval_case\tcompensating_control\n'
  printf 'EX-CI-2026-0042\tORG-CI\trepository-payments\tbreakglass-01\tupdate_main\t1999999000\t%s\tINC-2026-0042\tmanual-test-pass\n' \
    "$future"
} > "$exceptions"

{
  printf 'rule_id\tversion\tpriority\tscope_type\tscope_value\taction\trequirement\tmode\n'
  printf 'ORG-APPROVAL\tv1\t100\tall\t*\tupdate_main\tapproval\tenforce\n'
  printf 'ORG-CI\tv1\t110\tall\t*\tupdate_main\tci_success\tenforce\n'
  printf 'CLASS-SIGN\tv1\t200\tdata_class\tregulated\tupdate_main\tsignature\taudit\n'
} > "$rules_audit"

awk -F '\t' 'BEGIN { OFS = "\t" }
  NR == 1 { print; next }
  $1 == "CLASS-SIGN" { $8 = "enforce" }
  { print }
' "$rules_audit" > "$rules_enforce"

audit_result="$lab_root/audit-result.txt"
evaluate_policy \
  "$repositories" "$exceptions" "$rules_audit" \
  repository-payments developer-alice update_main \
  1 success no - "$as_of" > "$audit_result"
grep -Fx 'would-deny rule=CLASS-SIGN' "$audit_result" >/dev/null

promoted_status=0
evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-payments developer-alice update_main \
  1 success no - "$as_of" > "$lab_root/promoted-result.txt" || \
  promoted_status=$?
if test "$promoted_status" -ne 2; then
  printf 'Expected promoted signature rule to deny with status 2, got %s.\n' \
    "$promoted_status" >&2
  exit 1
fi
grep -Fx 'deny rule=CLASS-SIGN' "$lab_root/promoted-result.txt" >/dev/null

evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-payments developer-alice update_main \
  1 success yes - "$as_of" > "$lab_root/all-evidence-result.txt"

evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-docs developer-alice update_main \
  1 success no - "$as_of" > "$lab_root/internal-scope-result.txt"
test ! -s "$lab_root/internal-scope-result.txt"

narrow_exception_status=0
evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-payments breakglass-01 update_main \
  0 failure yes EX-CI-2026-0042 "$as_of" \
  > "$lab_root/narrow-exception-result.txt" || narrow_exception_status=$?
if test "$narrow_exception_status" -ne 2; then
  printf 'Expected CI-only exception to leave approval denial active, got %s.\n' \
    "$narrow_exception_status" >&2
  exit 1
fi
grep -Fx 'deny rule=ORG-APPROVAL' \
  "$lab_root/narrow-exception-result.txt" >/dev/null
grep -Fx 'exception-used rule=ORG-CI exception=EX-CI-2026-0042' \
  "$lab_root/narrow-exception-result.txt" >/dev/null

evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-payments breakglass-01 update_main \
  1 failure yes EX-CI-2026-0042 "$as_of" \
  > "$lab_root/valid-exception-result.txt"
grep -Fx 'exception-used rule=ORG-CI exception=EX-CI-2026-0042' \
  "$lab_root/valid-exception-result.txt" >/dev/null

expired_exception_status=0
evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-payments breakglass-01 update_main \
  1 failure yes EX-CI-2026-0042 "$future" \
  > "$lab_root/expired-exception-result.txt" || expired_exception_status=$?
if test "$expired_exception_status" -ne 2; then
  printf 'Expected expired exception to deny with status 2, got %s.\n' \
    "$expired_exception_status" >&2
  exit 1
fi
grep -Fx 'deny rule=ORG-CI' "$lab_root/expired-exception-result.txt" >/dev/null

unknown_repository_status=0
evaluate_policy \
  "$repositories" "$exceptions" "$rules_enforce" \
  repository-unknown developer-alice update_main \
  1 success yes - "$as_of" > "$lab_root/unknown-repository-result.txt" || \
  unknown_repository_status=$?
if test "$unknown_repository_status" -ne 3; then
  printf 'Expected unknown repository to return inconclusive status 3, got %s.\n' \
    "$unknown_repository_status" >&2
  exit 1
fi

desired_digest="$(hash_file "$rules_enforce")"
observations="$lab_root/observations.tsv"
{
  printf 'repository_id\tstate\tobserved_digest\n'
  printf 'repository-payments\tapplied\t%s\n' "$desired_digest"
  printf 'repository-docs\tapplied\t%s\n' \
    '0000000000000000000000000000000000000000000000000000000000000000'
  printf 'repository-hidden\tunavailable\t-\n'
} > "$observations"

verify_policy_observation repository-payments "$desired_digest" "$observations"

drift_status=0
verify_policy_observation repository-docs "$desired_digest" "$observations" || \
  drift_status=$?
if test "$drift_status" -ne 2; then
  printf 'Expected observed policy drift to return fail status 2, got %s.\n' \
    "$drift_status" >&2
  exit 1
fi

unavailable_status=0
verify_policy_observation repository-hidden "$desired_digest" "$observations" || \
  unavailable_status=$?
if test "$unavailable_status" -ne 3; then
  printf 'Expected unavailable observation to return inconclusive status 3, got %s.\n' \
    "$unavailable_status" >&2
  exit 1
fi

work_repo="$lab_root/work"
service_repo="$lab_root/service.git"
mode_path="$lab_root/policy-mode"
audit_log="$lab_root/policy-audit.log"

git init --quiet --initial-branch=main "$work_repo"
git -C "$work_repo" config user.name 'Policy Rules Fixture'
git -C "$work_repo" config user.email 'policy-rules@example.invalid'
printf 'version=1\n' > "$work_repo/service.conf"
git -C "$work_repo" add service.conf
GIT_AUTHOR_DATE='2026-08-21T04:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T04:00:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: policy baseline'
base_commit="$(git -C "$work_repo" rev-parse HEAD)"

git init --quiet --bare --initial-branch=main "$service_repo"
git -C "$work_repo" remote add origin "$service_repo"
printf 'audit\n' > "$mode_path"
: > "$audit_log"

hook_path="$service_repo/hooks/pre-receive"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -eu'
  printf 'mode_path=%q\n' "$mode_path"
  printf 'audit_log=%q\n' "$audit_log"
  printf '%s\n' 'zero_oid=0000000000000000000000000000000000000000'
  printf '%s\n' 'principal="${POLICY_PRINCIPAL:-unknown}"'
  printf '%s\n' 'exception_id="${POLICY_EXCEPTION:-}"'
  printf '%s\n' 'approval_case="${POLICY_CASE:-}"'
  printf '%s\n' 'as_of="${POLICY_AS_OF:-2000000000}"'
  printf '%s\n' 'expires="${POLICY_EXPIRES:-0}"'
  printf '%s\n' 'mode="$(sed -n "1p" "$mode_path")"'
  printf '%s\n' 'while read -r old_oid new_oid ref_name; do'
  printf '%s\n' '  violation=0'
  printf '%s\n' '  if test "$ref_name" = refs/heads/main &&'
  printf '%s\n' '     test "$old_oid" != "$zero_oid" &&'
  printf '%s\n' '     test "$new_oid" != "$zero_oid" &&'
  printf '%s\n' '     ! git merge-base --is-ancestor "$old_oid" "$new_oid"; then'
  printf '%s\n' '    violation=1'
  printf '%s\n' '  fi'
  printf '%s\n' '  if test "$violation" -eq 0; then'
  printf '%s\n' '    continue'
  printf '%s\n' '  fi'
  printf '%s\n' '  if test "$principal" = breakglass-01 &&'
  printf '%s\n' '     test "$exception_id" = EX-NONFF-2026-0042 &&'
  printf '%s\n' '     test "$approval_case" = INC-POLICY-0042 &&'
  printf '%s\n' '     test "$expires" -gt "$as_of"; then'
  printf '%s\n' '    printf "exception-used rule=ORG-NONFF principal=%s ref=%s old=%s new=%s\n" "$principal" "$ref_name" "$old_oid" "$new_oid" >> "$audit_log"'
  printf '%s\n' '    continue'
  printf '%s\n' '  fi'
  printf '%s\n' '  if test "$mode" = audit; then'
  printf '%s\n' '    printf "would-deny rule=ORG-NONFF principal=%s ref=%s old=%s new=%s\n" "$principal" "$ref_name" "$old_oid" "$new_oid" >> "$audit_log"'
  printf '%s\n' '    continue'
  printf '%s\n' '  fi'
  printf '%s\n' '  printf "[policy-denied] rule=ORG-NONFF ref=%s\n" "$ref_name" >&2'
  printf '%s\n' '  exit 1'
  printf '%s\n' 'done'
} > "$hook_path"
chmod +x "$hook_path"

POLICY_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --quiet origin main

printf 'version=2\n' > "$work_repo/service.conf"
git -C "$work_repo" add service.conf
GIT_AUTHOR_DATE='2026-08-21T04:05:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T04:05:00+00:00' \
  git -C "$work_repo" commit --quiet -m 'fixture: advance protected main'
head_commit="$(git -C "$work_repo" rev-parse HEAD)"
POLICY_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --quiet origin main

POLICY_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --quiet --force origin \
    "$base_commit:refs/heads/main"
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"
grep -F 'would-deny rule=ORG-NONFF principal=developer-alice ref=refs/heads/main' \
  "$audit_log" >/dev/null

POLICY_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --quiet origin "$head_commit:refs/heads/main"
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$head_commit"

printf 'enforce\n' > "$mode_path"
if POLICY_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --force origin "$base_commit:refs/heads/main" \
    > "$lab_root/enforce.out" 2> "$lab_root/enforce.err"; then
  printf 'Expected enforced non-fast-forward rule to reject push.\n' >&2
  exit 1
fi
grep -F '[policy-denied] rule=ORG-NONFF ref=refs/heads/main' \
  "$lab_root/enforce.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$head_commit"

POLICY_PRINCIPAL=breakglass-01 \
POLICY_EXCEPTION=EX-NONFF-2026-0042 \
POLICY_CASE=INC-POLICY-0042 \
POLICY_AS_OF="$as_of" \
POLICY_EXPIRES="$future" \
  git -C "$work_repo" push --quiet --force origin \
    "$base_commit:refs/heads/main"
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$base_commit"
grep -F 'exception-used rule=ORG-NONFF principal=breakglass-01 ref=refs/heads/main' \
  "$audit_log" >/dev/null

POLICY_PRINCIPAL=developer-alice \
  git -C "$work_repo" push --quiet origin "$head_commit:refs/heads/main"
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$head_commit"

if POLICY_PRINCIPAL=breakglass-01 \
  POLICY_EXCEPTION=EX-NONFF-2026-0042 \
  POLICY_AS_OF="$as_of" \
  POLICY_EXPIRES="$future" \
  git -C "$work_repo" push --force origin "$base_commit:refs/heads/main" \
    > "$lab_root/missing-case.out" 2> "$lab_root/missing-case.err"; then
  printf 'Expected exception without approval case to reject push.\n' >&2
  exit 1
fi
grep -F '[policy-denied] rule=ORG-NONFF ref=refs/heads/main' \
  "$lab_root/missing-case.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$head_commit"

if POLICY_PRINCIPAL=breakglass-01 \
  POLICY_EXCEPTION=EX-NONFF-2026-0042 \
  POLICY_CASE=INC-POLICY-0042 \
  POLICY_AS_OF="$as_of" \
  POLICY_EXPIRES="$as_of" \
  git -C "$work_repo" push --force origin "$base_commit:refs/heads/main" \
    > "$lab_root/expired.out" 2> "$lab_root/expired.err"; then
  printf 'Expected expired exception to reject push.\n' >&2
  exit 1
fi
grep -F '[policy-denied] rule=ORG-NONFF ref=refs/heads/main' \
  "$lab_root/expired.err" >/dev/null
test "$(git -C "$service_repo" rev-parse refs/heads/main)" = "$head_commit"

git -C "$service_repo" fsck --full --strict --no-progress \
  > "$lab_root/service.fsck" 2>&1

printf 'Policy scope composition, audit/enforce rollout, narrow exceptions, drift states, and receive enforcement passed.\n'
