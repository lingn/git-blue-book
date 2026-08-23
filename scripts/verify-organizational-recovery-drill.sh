#!/usr/bin/env bash

set -euo pipefail

lab_root="$(mktemp -d "${TMPDIR:-/tmp}/git-blue-book-organizational-drill.XXXXXX")"
trap 'rm -rf -- "$lab_root"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$lab_root/gitconfig"
unset GIT_CONFIG_COUNT

sha256_file() {
  local file_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
  else
    sha256sum "$file_path" | awk '{print $1}'
  fi
}

verify_sha256_manifest() {
  local evidence_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    (cd "$evidence_path" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1)
  else
    (cd "$evidence_path" && sha256sum -c SHA256SUMS >/dev/null 2>&1)
  fi
}

refs_manifest() {
  local repository_path="$1"

  git -C "$repository_path" for-each-ref \
    --format='%(refname) %(objecttype) %(objectname) %(*objectname)' |
    LC_ALL=C sort
}

validate_roles() {
  local roles_path="$1"

  awk -F '\t' '
    NR == 1 {
      if ($0 != "event_id\trole\tprincipal\tbackup\tstatus") {
        exit 40
      }
      next
    }
    NF != 5 { exit 40 }
    $2 == "incident_commander" && $5 == "active" { ic++ }
    $2 == "evidence_scribe" && $5 == "active" { scribe++ }
    END {
      if (ic != 1) {
        exit 41
      }
      if (scribe != 1) {
        exit 42
      }
    }
  ' "$roles_path"
}

validate_decisions() {
  local decisions_path="$1"
  local approved_oid="$2"

  awk -F '\t' -v approved_oid="$approved_oid" '
    NR == 1 {
      if ($0 != "event_id\tdata_plane\tobjective_oid\tstatus\tapprover\tdecided_at") {
        exit 50
      }
      next
    }
    NF != 6 { exit 50 }
    $2 == "git" && $3 == approved_oid && $4 == "approved" &&
      $5 != "" && $6 != "" { matches++ }
    END {
      if (matches != 1) {
        exit 51
      }
    }
  ' "$decisions_path"
}

validate_gate_matrix() {
  local gates_path="$1"

  awk -F '\t' '
    NR == 1 {
      if ($0 != "data_plane\tstatus\tevidence") {
        exit 70
      }
      next
    }
    NF != 3 { exit 70 }
    $2 == "inconclusive" { inconclusive++ }
    $2 == "fail" { failed++ }
    $2 != "pass" && $2 != "fail" && $2 != "inconclusive" { invalid++ }
    $3 == "" { missing_evidence++ }
    { rows++ }
    END {
      if (rows < 4 || invalid > 0) {
        exit 70
      }
      if (inconclusive > 0) {
        exit 71
      }
      if (failed > 0) {
        exit 72
      }
      if (missing_evidence > 0) {
        exit 73
      }
    }
  ' "$gates_path"
}

validate_candidate() {
  local repository_path="$1"
  local approved_oid="$2"
  local gates_path="$3"
  local result_path="$4"
  local manifest_path="$5"
  local actual_oid
  local object_format
  local ref_format

  actual_oid="$(git -C "$repository_path" rev-parse refs/heads/main)" || return 60
  if test "$actual_oid" != "$approved_oid"; then
    return 61
  fi
  if test -e "$repository_path/objects/info/alternates"; then
    return 62
  fi
  if git -C "$repository_path" config --get extensions.partialClone >/dev/null; then
    return 63
  fi
  git -C "$repository_path" fsck --full --strict --no-progress \
    > "$repository_path/fsck.stdout" 2> "$repository_path/fsck.stderr" || return 64
  validate_gate_matrix "$gates_path" || return "$?"

  object_format="$(git -C "$repository_path" rev-parse --show-object-format)"
  ref_format="$(git -C "$repository_path" rev-parse --show-ref-format)"
  {
    printf 'approved_oid=%s\n' "$approved_oid"
    printf 'actual_oid=%s\n' "$actual_oid"
    printf 'object_format=%s\n' "$object_format"
    printf 'ref_format=%s\n' "$ref_format"
    printf 'connectivity=pass\n'
    printf 'external_gates=pass\n'
  } > "$manifest_path"
  printf 'pass\n' > "$result_path"
}

validate_actions() {
  local actions_path="$1"

  awk -F '\t' '
    NR == 1 {
      if ($0 != "action_id\trisk\towner\tdue_at\tacceptance_evidence\tstatus") {
        exit 80
      }
      next
    }
    NF != 6 { exit 80 }
    $3 == "" { missing_owner++ }
    $4 == "" { missing_due++ }
    $5 == "" { missing_evidence++ }
    $6 != "verified" { not_verified++ }
    { rows++ }
    END {
      if (rows == 0) {
        exit 80
      }
      if (missing_owner > 0) {
        exit 81
      }
      if (missing_due > 0) {
        exit 82
      }
      if (missing_evidence > 0 || not_verified > 0) {
        exit 83
      }
    }
  ' "$actions_path"
}

current_state() {
  sed -n '1p' "$state_path"
}

latest_authority() {
  awk -F '\t' '
    NR == 1 {
      if ($0 != "generation\tauthority\toid") {
        exit 90
      }
      next
    }
    NF != 3 { exit 90 }
    { latest = $0; rows++ }
    END {
      if (rows == 0) {
        exit 90
      }
      print latest
    }
  ' "$authority_path"
}

latest_service_mode() {
  awk -F '\t' '
    NR == 1 {
      if ($0 != "event_id\tendpoint\tmode\treason") {
        exit 90
      }
      next
    }
    NF != 4 { exit 90 }
    { latest = $0; rows++ }
    END {
      if (rows == 0) {
        exit 90
      }
      print latest
    }
  ' "$service_modes_path"
}

transition() {
  local next_state="$1"
  local current
  local gate_status
  local authority_line
  local service_line

  current="$(current_state)"
  case "$current:$next_state" in
    DETECTED:DECLARED|\
    DECLARED:WRITES_FENCED|\
    WRITES_FENCED:EVIDENCE_PRESERVED|\
    EVIDENCE_PRESERVED:RECOVERY_OBJECTIVE_APPROVED|\
    RECOVERY_OBJECTIVE_APPROVED:CANDIDATE_VALIDATED|\
    CANDIDATE_VALIDATED:PROMOTED_READ_ONLY|\
    PROMOTED_READ_ONLY:WRITES_OPEN|\
    WRITES_OPEN:STABILIZED|\
    STABILIZED:REVIEWED)
      ;;
    *)
      return 30
      ;;
  esac

  case "$next_state" in
    DECLARED)
      validate_roles "$roles_path" || {
        gate_status="$?"
        return "$gate_status"
      }
      ;;
    WRITES_FENCED)
      grep -Fx pass "$fence_status_path" >/dev/null || return 31
      ;;
    EVIDENCE_PRESERVED)
      verify_sha256_manifest "$evidence_path" || return 32
      ;;
    RECOVERY_OBJECTIVE_APPROVED)
      validate_decisions "$decisions_path" "$approved_oid" || {
        gate_status="$?"
        return "$gate_status"
      }
      ;;
    CANDIDATE_VALIDATED)
      grep -Fx pass "$candidate_result_path" >/dev/null || return 33
      ;;
    PROMOTED_READ_ONLY)
      authority_line="$(latest_authority)" || return 34
      test "$authority_line" = \
        "2"$'\t'"$candidate"$'\t'"$approved_oid" || return 34
      service_line="$(latest_service_mode)" || return 35
      test "$service_line" = \
        "$event_id"$'\t'"$candidate"$'\tread_only\trecovery acceptance' || return 35
      ;;
    WRITES_OPEN)
      service_line="$(latest_service_mode)" || return 36
      test "$service_line" = \
        "$event_id"$'\t'"$candidate"$'\tread_write\tIC approved canary' || return 36
      ;;
    STABILIZED)
      grep -Fx pass "$stability_status_path" >/dev/null || return 37
      ;;
    REVIEWED)
      validate_actions "$actions_path" || {
        gate_status="$?"
        return "$gate_status"
      }
      ;;
  esac

  printf '%s\n' "$next_state" > "$state_path"
  printf '%s\t%s\t%s\tpass\n' \
    "$event_time" "$current" "$next_state" >> "$timeline_path"
}

conditional_promote_read_only() {
  local expected_generation="$1"
  local authority_line
  local actual_generation
  local current_authority
  local current_oid
  local candidate_oid

  test "$(current_state)" = CANDIDATE_VALIDATED || return 90
  grep -Fx pass "$candidate_result_path" >/dev/null || return 90
  authority_line="$(latest_authority)" || return 90
  IFS=$'\t' read -r actual_generation current_authority current_oid \
    <<< "$authority_line"

  if test "$actual_generation" -ne "$expected_generation"; then
    return 91
  fi
  if test "$current_authority" != "$primary" || test "$current_oid" != "$approved_oid"; then
    return 92
  fi
  candidate_oid="$(git -C "$candidate" rev-parse refs/heads/main)"
  if test "$candidate_oid" != "$approved_oid"; then
    return 93
  fi

  printf '2\t%s\t%s\n' "$candidate" "$candidate_oid" >> "$authority_path"
  printf '%s\t%s\tread_only\trecovery acceptance\n' \
    "$event_id" "$candidate" >> "$service_modes_path"
  transition PROMOTED_READ_ONLY
}

open_candidate_writes() {
  local authority_line
  local service_line

  test "$(current_state)" = PROMOTED_READ_ONLY || return 100
  authority_line="$(latest_authority)" || return 100
  test "$authority_line" = \
    "2"$'\t'"$candidate"$'\t'"$approved_oid" || return 100
  service_line="$(latest_service_mode)" || return 100
  test "$service_line" = \
    "$event_id"$'\t'"$candidate"$'\tread_only\trecovery acceptance' || return 100
  test -x "$primary/hooks/pre-receive" || return 101
  test -x "$candidate/hooks/pre-receive" || return 101

  mv "$candidate/hooks/pre-receive" \
    "$candidate/hooks/pre-receive.read-only"
  printf '%s\t%s\tread_write\tIC approved canary\n' \
    "$event_id" "$candidate" >> "$service_modes_path"
  transition WRITES_OPEN
}

event_id='INC-GIT-20260821-001'
event_time='2026-08-21T06:00:00Z'
producer="$lab_root/producer"
primary="$lab_root/primary.git"
standby="$lab_root/standby.git"
candidate="$lab_root/candidate.git"
acceptance="$lab_root/acceptance"
recovery_bundle="$lab_root/approved-recovery.bundle"
roles_path="$lab_root/roles.tsv"
decisions_path="$lab_root/decisions.tsv"
actions_path="$lab_root/actions.tsv"
authority_path="$lab_root/authority.tsv"
service_modes_path="$lab_root/service-modes.tsv"
timeline_path="$lab_root/timeline.tsv"
state_path="$lab_root/state.txt"
fence_status_path="$lab_root/fence-status.txt"
candidate_result_path="$lab_root/candidate-result.txt"
candidate_manifest_path="$lab_root/candidate-manifest.txt"
stability_status_path="$lab_root/stability-status.txt"
evidence_path="$lab_root/evidence"

git init --quiet --initial-branch=main "$producer"
git -C "$producer" config user.name 'Organizational Drill Fixture'
git -C "$producer" config user.email 'organizational-drill@example.invalid'
mkdir -p "$producer/src"
printf 'version=1\n' > "$producer/src/service.conf"
git -C "$producer" add src/service.conf
GIT_AUTHOR_DATE='2026-08-21T05:00:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T05:00:00+00:00' \
  git -C "$producer" commit --quiet -m 'fixture: establish approved service'
standby_oid="$(git -C "$producer" rev-parse HEAD)"

git init --quiet --bare --initial-branch=main "$primary"
git -C "$producer" remote add primary "$primary"
git -C "$producer" push --quiet primary main
git -C "$primary" symbolic-ref HEAD refs/heads/main
git clone --quiet --mirror --no-local "$primary" "$standby"

printf 'version=2\n' > "$producer/src/service.conf"
printf 'approved incident recovery payload\n' > "$producer/src/recovery.txt"
git -C "$producer" add src/service.conf src/recovery.txt
GIT_AUTHOR_DATE='2026-08-21T05:10:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T05:10:00+00:00' \
  git -C "$producer" commit --quiet -m 'feat: approved recovery point'
approved_oid="$(git -C "$producer" rev-parse HEAD)"
git -C "$producer" tag -a recovery-v2 \
  -m 'fixture: approved recovery point' "$approved_oid"
git -C "$producer" push --quiet primary main --tags
git -C "$producer" bundle create "$recovery_bundle" --branches --tags

test "$(git -C "$primary" rev-parse refs/heads/main)" = "$approved_oid"
test "$(git -C "$standby" rev-parse refs/heads/main)" = "$standby_oid"
test "$standby_oid" != "$approved_oid"

printf 'DETECTED\n' > "$state_path"
printf 'timestamp\tfrom\tto\tresult\n' > "$timeline_path"
{
  printf 'generation\tauthority\toid\n'
  printf '1\t%s\t%s\n' "$primary" "$approved_oid"
} > "$authority_path"
{
  printf 'event_id\tendpoint\tmode\treason\n'
  printf '%s\t%s\tread_write\tnormal authority\n' "$event_id" "$primary"
} > "$service_modes_path"

jump_status=0
transition WRITES_OPEN || jump_status="$?"
if test "$jump_status" -ne 30; then
  printf 'Expected DETECTED to WRITES_OPEN jump to return 30, got %s.\n' \
    "$jump_status" >&2
  exit 1
fi
test "$(current_state)" = DETECTED

{
  printf 'event_id\trole\tprincipal\tbackup\tstatus\n'
  printf '%s\trecovery_lead\tteam-recovery\tteam-platform\tactive\n' "$event_id"
  printf '%s\tevidence_scribe\tteam-evidence\tteam-compliance\tactive\n' "$event_id"
} > "$roles_path"
missing_ic_status=0
transition DECLARED || missing_ic_status="$?"
if test "$missing_ic_status" -ne 41; then
  printf 'Expected a missing active IC to return 41, got %s.\n' \
    "$missing_ic_status" >&2
  exit 1
fi
test "$(current_state)" = DETECTED

{
  printf 'event_id\trole\tprincipal\tbackup\tstatus\n'
  printf '%s\tincident_commander\tteam-incident\tteam-platform\tactive\n' "$event_id"
  printf '%s\trecovery_lead\tteam-recovery\tteam-platform\tactive\n' "$event_id"
} > "$roles_path"
missing_scribe_status=0
transition DECLARED || missing_scribe_status="$?"
if test "$missing_scribe_status" -ne 42; then
  printf 'Expected a missing active scribe to return 42, got %s.\n' \
    "$missing_scribe_status" >&2
  exit 1
fi
test "$(current_state)" = DETECTED

{
  printf 'event_id\trole\tprincipal\tbackup\tstatus\n'
  printf '%s\tincident_commander\tteam-incident\tteam-platform\tactive\n' "$event_id"
  printf '%s\trecovery_lead\tteam-recovery\tteam-platform\tactive\n' "$event_id"
  printf '%s\tevidence_scribe\tteam-evidence\tteam-compliance\tactive\n' "$event_id"
  printf '%s\tbusiness_owner\tteam-payments\tteam-finance\tactive\n' "$event_id"
} > "$roles_path"
transition DECLARED

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "primary fenced by INC-GIT-20260821-001\n" >&2' \
  'exit 1' > "$primary/hooks/pre-receive"
chmod +x "$primary/hooks/pre-receive"
primary_oid_before_reject="$(git -C "$primary" rev-parse refs/heads/main)"
printf 'must not reach fenced primary\n' > "$producer/src/after-fence.txt"
git -C "$producer" add src/after-fence.txt
GIT_AUTHOR_DATE='2026-08-21T06:05:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T06:05:00+00:00' \
  git -C "$producer" commit --quiet -m 'fixture: rejected after fence'
if git -C "$producer" push primary main \
  > "$lab_root/primary-fence.stdout" \
  2> "$lab_root/primary-fence.stderr"; then
  printf 'Expected the fenced primary to reject a push.\n' >&2
  exit 1
fi
grep -F 'primary fenced by INC-GIT-20260821-001' \
  "$lab_root/primary-fence.stderr" >/dev/null
test "$(git -C "$primary" rev-parse refs/heads/main)" = \
  "$primary_oid_before_reject"
test "$primary_oid_before_reject" = "$approved_oid"
printf 'pass\n' > "$fence_status_path"
transition WRITES_FENCED

mkdir "$evidence_path"
refs_manifest "$primary" > "$evidence_path/primary.refs"
refs_manifest "$standby" > "$evidence_path/standby.refs"
cp "$roles_path" "$evidence_path/roles-at-declaration.tsv"
cp "$recovery_bundle" "$evidence_path/approved-recovery.bundle"
{
  printf 'event_id=%s\n' "$event_id"
  printf 'primary_oid=%s\n' "$approved_oid"
  printf 'standby_oid=%s\n' "$standby_oid"
  printf 'primary_write_test=rejected\n'
  printf 'platform_control_plane=fixture\n'
} > "$evidence_path/acquisition-manifest.txt"
{
  for evidence_file in \
    acquisition-manifest.txt \
    approved-recovery.bundle \
    primary.refs \
    roles-at-declaration.tsv \
    standby.refs
  do
    printf '%s  %s\n' \
      "$(sha256_file "$evidence_path/$evidence_file")" "$evidence_file"
  done
} > "$evidence_path/SHA256SUMS"
verify_sha256_manifest "$evidence_path"
transition EVIDENCE_PRESERVED

{
  printf 'event_id\tdata_plane\tobjective_oid\tstatus\tapprover\tdecided_at\n'
  printf '%s\tgit\t%s\tapproved\tteam-payments\t2026-08-21T06:10:00Z\n' \
    "$event_id" "$approved_oid"
} > "$decisions_path"
transition RECOVERY_OBJECTIVE_APPROVED

{
  printf 'data_plane\tstatus\tevidence\n'
  printf 'git\tpass\tlocal fsck and refs fixture\n'
  printf 'audit\tpass\tsynthetic checkpoint AUDIT-42\n'
  printf 'external\tpass\tsynthetic LFS CI and artifact gate\n'
  printf 'capacity\tpass\tsynthetic scratch and headroom gate\n'
} > "$lab_root/candidate-gates.tsv"

stale_candidate_status=0
validate_candidate "$standby" "$approved_oid" \
  "$lab_root/candidate-gates.tsv" \
  "$candidate_result_path" "$candidate_manifest_path" || \
  stale_candidate_status="$?"
if test "$stale_candidate_status" -ne 61; then
  printf 'Expected the lagging standby to return OID mismatch 61, got %s.\n' \
    "$stale_candidate_status" >&2
  exit 1
fi
test "$(current_state)" = RECOVERY_OBJECTIVE_APPROVED
test ! -e "$candidate_result_path"

git init --quiet --bare --initial-branch=main "$candidate"
git -C "$candidate" bundle verify "$recovery_bundle" \
  > "$lab_root/recovery-bundle.verify"
git -C "$candidate" fetch --quiet "$recovery_bundle" \
  '+refs/heads/*:refs/heads/*' \
  '+refs/tags/*:refs/tags/*'
git -C "$candidate" symbolic-ref HEAD refs/heads/main
test "$(git -C "$candidate" rev-parse refs/heads/main)" = "$approved_oid"

{
  printf 'data_plane\tstatus\tevidence\n'
  printf 'git\tpass\tlocal fsck and refs fixture\n'
  printf 'audit\tinconclusive\tsynthetic collector gap\n'
  printf 'external\tpass\tsynthetic LFS CI and artifact gate\n'
  printf 'capacity\tpass\tsynthetic scratch and headroom gate\n'
} > "$lab_root/candidate-gates.tsv"
audit_gap_status=0
validate_candidate "$candidate" "$approved_oid" \
  "$lab_root/candidate-gates.tsv" \
  "$candidate_result_path" "$candidate_manifest_path" || \
  audit_gap_status="$?"
if test "$audit_gap_status" -ne 71; then
  printf 'Expected an inconclusive audit gate to return 71, got %s.\n' \
    "$audit_gap_status" >&2
  exit 1
fi
test "$(current_state)" = RECOVERY_OBJECTIVE_APPROVED
test ! -e "$candidate_result_path"

{
  printf 'data_plane\tstatus\tevidence\n'
  printf 'git\tpass\tlocal fsck and refs fixture\n'
  printf 'audit\tpass\tsynthetic checkpoint AUDIT-42\n'
  printf 'external\tpass\tsynthetic LFS CI and artifact gate\n'
  printf 'capacity\tpass\tsynthetic scratch and headroom gate\n'
} > "$lab_root/candidate-gates.tsv"
validate_candidate "$candidate" "$approved_oid" \
  "$lab_root/candidate-gates.tsv" \
  "$candidate_result_path" "$candidate_manifest_path"
grep -F "actual_oid=$approved_oid" "$candidate_manifest_path" >/dev/null
transition CANDIDATE_VALIDATED

cp "$authority_path" "$lab_root/authority-before-stale.tsv"
stale_generation_status=0
conditional_promote_read_only 0 || stale_generation_status="$?"
if test "$stale_generation_status" -ne 91; then
  printf 'Expected a stale authority generation to return 91, got %s.\n' \
    "$stale_generation_status" >&2
  exit 1
fi
cmp "$lab_root/authority-before-stale.tsv" "$authority_path"
test "$(current_state)" = CANDIDATE_VALIDATED

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "candidate remains read-only during acceptance\n" >&2' \
  'exit 1' > "$candidate/hooks/pre-receive"
chmod +x "$candidate/hooks/pre-receive"
conditional_promote_read_only 1
test "$(current_state)" = PROMOTED_READ_ONLY

git clone --quiet --no-local "$candidate" "$acceptance"
git -C "$acceptance" config user.name 'Recovery Acceptance Fixture'
git -C "$acceptance" config user.email 'recovery-acceptance@example.invalid'
test "$(git -C "$acceptance" rev-parse HEAD)" = "$approved_oid"
test "$(cat "$acceptance/src/service.conf")" = 'version=2'
printf 'accepted canary write\n' > "$acceptance/src/canary.txt"
git -C "$acceptance" add src/canary.txt
GIT_AUTHOR_DATE='2026-08-21T06:20:00+00:00' \
GIT_COMMITTER_DATE='2026-08-21T06:20:00+00:00' \
  git -C "$acceptance" commit --quiet -m 'fixture: recovery canary'
canary_oid="$(git -C "$acceptance" rev-parse HEAD)"
if git -C "$acceptance" push origin main \
  > "$lab_root/read-only.stdout" \
  2> "$lab_root/read-only.stderr"; then
  printf 'Expected the promoted candidate to remain read-only before approval.\n' >&2
  exit 1
fi
grep -F 'candidate remains read-only during acceptance' \
  "$lab_root/read-only.stderr" >/dev/null
test "$(git -C "$candidate" rev-parse refs/heads/main)" = "$approved_oid"

open_candidate_writes
git -C "$acceptance" push --quiet origin main
test "$(git -C "$candidate" rev-parse refs/heads/main)" = "$canary_oid"

git -C "$acceptance" remote add old-primary "$primary"
if git -C "$acceptance" push old-primary main \
  > "$lab_root/old-primary.stdout" \
  2> "$lab_root/old-primary.stderr"; then
  printf 'Expected the old primary to remain fenced after failover.\n' >&2
  exit 1
fi
grep -F 'primary fenced by INC-GIT-20260821-001' \
  "$lab_root/old-primary.stderr" >/dev/null
test "$(git -C "$primary" rev-parse refs/heads/main)" = "$approved_oid"
test "$(git -C "$candidate" rev-parse refs/heads/main)" = "$canary_oid"

git -C "$candidate" fsck --full --strict --no-progress \
  > "$lab_root/stabilized.fsck" 2>&1
test "$(latest_authority)" = \
  "2"$'\t'"$candidate"$'\t'"$approved_oid"
test -x "$primary/hooks/pre-receive"
printf 'pass\n' > "$stability_status_path"
transition STABILIZED

{
  printf 'action_id\trisk\towner\tdue_at\tacceptance_evidence\tstatus\n'
  printf 'ACT-001\tstandby replication lag\t\t\tdrill replay DR-2\tverified\n'
} > "$actions_path"
incomplete_action_status=0
transition REVIEWED || incomplete_action_status="$?"
if test "$incomplete_action_status" -ne 81; then
  printf 'Expected a missing action owner to return 81, got %s.\n' \
    "$incomplete_action_status" >&2
  exit 1
fi
test "$(current_state)" = STABILIZED

{
  printf 'action_id\trisk\towner\tdue_at\tacceptance_evidence\tstatus\n'
  printf 'ACT-001\tstandby replication lag\tteam-platform\t2026-09-21\tdrill replay DR-2\tverified\n'
} > "$actions_path"
transition REVIEWED
test "$(current_state)" = REVIEWED
test "$(awk 'END {print NR}' "$timeline_path")" -eq 10

{
  printf 'event_id=%s\n' "$event_id"
  printf 'approved_oid=%s\n' "$approved_oid"
  printf 'standby_oid=%s\n' "$standby_oid"
  printf 'canary_oid=%s\n' "$canary_oid"
  printf 'authority_generation=2\n'
  printf 'old_primary_fenced=true\n'
  printf 'final_state=REVIEWED\n'
  printf 'organizational_controls=fixture\n'
} > "$lab_root/drill-result.txt"
grep -F 'old_primary_fenced=true' "$lab_root/drill-result.txt" >/dev/null
grep -F 'final_state=REVIEWED' "$lab_root/drill-result.txt" >/dev/null

printf 'Organizational recovery gates, bundle restore, conditional promotion, single-authority writes, and action closure passed.\n'
