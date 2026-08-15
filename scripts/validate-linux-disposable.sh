#!/usr/bin/env bash
set -euo pipefail

if [[ "${COWEBS_DISPOSABLE:-}" != '1' ]]; then
  echo 'Refusing validation: set COWEBS_DISPOSABLE=1 only inside a disposable VM, container, or ephemeral CI runner.' >&2
  exit 2
fi

if [[ "${CI:-}" != 'true' ]]; then
  virtualization="$(systemd-detect-virt 2>/dev/null || true)"
  if [[ -z "$virtualization" || "$virtualization" == 'none' ]]; then
    echo 'Refusing real-host validation because no disposable virtualization boundary was detected.' >&2
    exit 2
  fi
fi

if [[ $# -lt 5 ]]; then
  echo 'usage: validate-linux-disposable.sh PLATFORM MODE COWEBS_BINARY PACKAGE_CATALOG PROFILE_CATALOG' >&2
  exit 2
fi

platform="$1"
mode="$2"
cowebs_binary="$(realpath "$3")"
package_catalog="$(realpath "$4")"
profile_catalog="$(realpath "$5")"
session_root="$(mktemp -d -t cowebs-disposable.XXXXXXXX)"
plan_files_before="$session_root/plan-files-before.txt"
find /tmp -maxdepth 1 -type f -name 'cowebs-plan-*.json' -print | sort > "$plan_files_before"
trap 'rm -rf "$session_root"' EXIT HUP INT TERM

case "$platform" in ubuntu|fedora) ;; *) echo "unsupported platform: $platform" >&2; exit 2 ;; esac
case "$mode" in dry-run|real|matrix) ;; *) echo "unsupported validation mode: $mode" >&2; exit 2 ;; esac

profile='game'
common_plan_arguments=(--packages "$package_catalog" --profiles "$profile_catalog" --profile "$profile" --essentials-only --platform "$platform" --architecture x64)

write_expected_plan() {
  local destination="$1"
  "$cowebs_binary" plan dev-setup "${common_plan_arguments[@]}" --json > "$destination"
}

run_new_install() {
  local root="$1"
  local run_mode="${2:-real}"
  mkdir -p "$root"
  local arguments=(install dev-setup "${common_plan_arguments[@]}" --non-interactive --no-config --no-restart --journal "$root/session.jsonl" --state "$root/state.json" --plan-out "$root/canonical-plan.json")
  if [[ "$run_mode" == 'dry-run' ]]; then
    arguments+=(--dry-run)
  fi
  "$cowebs_binary" "${arguments[@]}"
}

resume_install() {
  local root="$1"
  "$cowebs_binary" resume dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --plan "$root/canonical-plan.json" --journal "$root/session.jsonl" --state "$root/state.json" --non-interactive --no-config --no-restart
}

assert_owned_files() {
  local root="$1"
  for state_file in "$root/session.jsonl" "$root/state.json" "$root/canonical-plan.json"; do
    if [[ "$(stat -c '%u' "$state_file")" != "$(id -u)" ]]; then
      echo "validation state is not owned by the initiating user: $state_file" >&2
      exit 1
    fi
  done
}

assert_journal_redacted() {
  local journal_path="$1"
  python3 - "$journal_path" <<'PY'
import json
import re
import sys

allowed = {
    "schemaVersion", "sessionId", "sequence", "timestamp", "type", "status",
    "operationId", "logicalPackageId", "provider", "exitCode", "message",
    "rebootRequired", "retryable",
}
sensitive = re.compile(r"(?i)(authorization|bearer|cookie|password|private[ -]?key|secret|access[ -]?token)")
with open(sys.argv[1], encoding="utf-8") as stream:
    rows = [line.strip() for line in stream if line.strip()]
if not rows:
    raise SystemExit("execution journal is empty")
last_sequence = 0
for row in rows:
    event = json.loads(row)
    unknown = set(event) - allowed
    if unknown:
        raise SystemExit(f"journal contains unknown/raw fields: {sorted(unknown)}")
    sequence = event.get("sequence", 0)
    if sequence <= last_sequence:
        raise SystemExit("journal sequence is not strictly increasing")
    last_sequence = sequence
    if sensitive.search(str(event.get("message", ""))):
        raise SystemExit("journal contains credential-shaped message content")
PY
}

assert_failed_state() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    state = json.load(stream)
if not state.get("failedOperations"):
    raise SystemExit("expected at least one persisted failed operation")
PY
}

assert_complete_state() {
  local state_path="$1"
  local require_git_skip="${2:-false}"
  python3 - "$state_path" "$require_git_skip" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    state = json.load(stream)
completed = state.get("completedOperations", [])
skipped = state.get("skippedOperations", [])
failed = state.get("failedOperations", [])
if failed:
    raise SystemExit(f"completed state retains failures: {failed}")
if len(completed) + len(skipped) != state.get("totalOperations"):
    raise SystemExit("not every operation reached a terminal success/skip state")
if sys.argv[2] == "true" and "install:git" not in skipped:
    raise SystemExit("partial-host validation did not skip preinstalled Git")
PY
}

assert_no_temporary_plan_leak() {
  local after="$session_root/plan-files-after.txt"
  find /tmp -maxdepth 1 -type f -name 'cowebs-plan-*.json' -print | sort > "$after"
  if ! cmp -s "$plan_files_before" "$after"; then
    echo 'temporary canonical plan leaked after failure or interruption' >&2
    diff -u "$plan_files_before" "$after" >&2 || true
    exit 1
  fi
}

wait_for_native_manager_idle() {
  if ! command -v snap >/dev/null; then
    return
  fi
  for _ in {1..180}; do
    local changes
    if changes="$(snap changes 2>/dev/null)"; then
      if ! printf '%s\n' "$changes" | awk 'NR > 1 && $2 == "Doing" { found = 1 } END { exit !found }'; then
        return 0
      fi
    fi
    sleep 1
  done
  echo 'Snap did not finish native recovery within three minutes' >&2
  snap changes >&2 || true
  return 1
}

resume_after_native_recovery() {
  local root="$1"
  local deadline=$((SECONDS + 300))
  while (( SECONDS < deadline )); do
    wait_for_native_manager_idle || return 1
    if resume_install "$root"; then
      return 0
    fi
    sleep 5
  done
  echo 'resume did not succeed within the five-minute native-recovery bound' >&2
  snap changes >&2 || true
  return 1
}

run_core_story() {
  local root="$session_root/core"
  mkdir -p "$root"
  "$cowebs_binary" doctor dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --json
  write_expected_plan "$root/plan.json"
  run_new_install "$root" "$mode"
  "$cowebs_binary" status dev-setup --journal "$root/session.jsonl" --state "$root/state.json" --json

  if [[ "$mode" == 'real' ]]; then
    cmp "$root/plan.json" "$root/canonical-plan.json"
    assert_owned_files "$root"
    assert_journal_redacted "$root/session.jsonl"
    resume_install "$root"
    assert_complete_state "$root/state.json"

    local second="$session_root/idempotency"
    run_new_install "$second"
    cmp "$root/canonical-plan.json" "$second/canonical-plan.json"
    assert_complete_state "$second/state.json"
    "$cowebs_binary" status dev-setup --journal "$second/session.jsonl" --state "$second/state.json" --json
  fi
}

run_matrix_story() {
  command -v setsid >/dev/null
  command -v unshare >/dev/null
  command -v python3 >/dev/null
  "$cowebs_binary" doctor dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --json

  case "$platform" in
    ubuntu) sudo apt-get install -y git ;;
    fedora) sudo dnf -y install git ;;
  esac

  local interrupted="$session_root/interrupted"
  mkdir -p "$interrupted"
  write_expected_plan "$interrupted/expected-plan.json"
  setsid "$cowebs_binary" install dev-setup "${common_plan_arguments[@]}" --non-interactive --no-config --no-restart --journal "$interrupted/session.jsonl" --state "$interrupted/state.json" --plan-out "$interrupted/canonical-plan.json" >"$interrupted/stdout.log" 2>"$interrupted/stderr.log" &
  local process_id=$!
  local observed_started=0
  for _ in {1..300}; do
    if [[ -f "$interrupted/session.jsonl" ]] && grep -q '"status":"started"' "$interrupted/session.jsonl"; then
      observed_started=1
      break
    fi
    if ! kill -0 "$process_id" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if [[ "$observed_started" != '1' ]]; then
    wait "$process_id" || true
    echo 'installation exited before an interruptible operation started' >&2
    exit 1
  fi
  kill -INT -- "-$process_id" 2>/dev/null || kill -INT "$process_id" 2>/dev/null || true
  for _ in {1..200}; do
    if ! kill -0 "$process_id" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if kill -0 "$process_id" 2>/dev/null; then
    kill -KILL -- "-$process_id" 2>/dev/null || true
  fi
  set +e
  wait "$process_id"
  local interrupted_exit=$?
  set -e
  if [[ "$interrupted_exit" == '0' ]]; then
    echo 'interrupted installation unexpectedly succeeded' >&2
    exit 1
  fi
  assert_owned_files "$interrupted"
  assert_journal_redacted "$interrupted/session.jsonl"
  assert_no_temporary_plan_leak
  resume_after_native_recovery "$interrupted"
  cmp "$interrupted/expected-plan.json" "$interrupted/canonical-plan.json"
  assert_complete_state "$interrupted/state.json" true
  assert_journal_redacted "$interrupted/session.jsonl"

  if command -v snap >/dev/null && snap list powershell >/dev/null 2>&1; then
    sudo snap remove powershell
  fi
  if command -v pwsh >/dev/null 2>&1; then
    echo 'failed to remove PowerShell before the isolated-network scenario' >&2
    exit 1
  fi

  local network="$session_root/network-failure"
  mkdir -p "$network"
  set +e
  sudo unshare --net --mount-proc sudo -u "$(id -un)" -H "$cowebs_binary" install dev-setup "${common_plan_arguments[@]}" --non-interactive --no-config --no-restart --journal "$network/session.jsonl" --state "$network/state.json" --plan-out "$network/canonical-plan.json" >"$network/stdout.log" 2>"$network/stderr.log"
  local network_exit=$?
  set -e
  if [[ "$network_exit" == '0' ]]; then
    echo 'network-isolated installation unexpectedly succeeded' >&2
    exit 1
  fi
  assert_owned_files "$network"
  assert_failed_state "$network/state.json"
  assert_journal_redacted "$network/session.jsonl"
  resume_install "$network"
  assert_complete_state "$network/state.json" true
  assert_journal_redacted "$network/session.jsonl"

  local repeated="$session_root/idempotency"
  run_new_install "$repeated"
  cmp "$interrupted/canonical-plan.json" "$repeated/canonical-plan.json"
  assert_complete_state "$repeated/state.json" true
  assert_owned_files "$repeated"
  assert_journal_redacted "$repeated/session.jsonl"

  if ! bash -lc 'command -v cowebs >/dev/null && cowebs --version >/dev/null'; then
    echo 'cowebs is unavailable from a fresh login-shell PATH' >&2
    exit 1
  fi
  assert_no_temporary_plan_leak
  "$cowebs_binary" status dev-setup --journal "$repeated/session.jsonl" --state "$repeated/state.json" --json
}

if [[ "$mode" == 'matrix' ]]; then
  run_matrix_story
else
  run_core_story
fi

echo "Disposable $platform $mode validation completed."
