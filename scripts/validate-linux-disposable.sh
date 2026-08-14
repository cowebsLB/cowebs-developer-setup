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
session_root="$(mktemp -d)"
trap 'rm -rf "$session_root"' EXIT

case "$platform" in ubuntu|fedora) ;; *) echo "unsupported platform: $platform" >&2; exit 2 ;; esac
case "$mode" in dry-run|real) ;; *) echo "unsupported validation mode: $mode" >&2; exit 2 ;; esac

"$cowebs_binary" doctor dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --json
"$cowebs_binary" plan dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --profile game --essentials-only --platform "$platform" --architecture x64 --json > "$session_root/plan.json"

install_arguments=(install dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --profile game --essentials-only --platform "$platform" --architecture x64 --non-interactive --no-config --no-restart --journal "$session_root/session.jsonl" --state "$session_root/state.json" --plan-out "$session_root/canonical-plan.json")
if [[ "$mode" == 'dry-run' ]]; then
  install_arguments+=(--dry-run)
fi
"$cowebs_binary" "${install_arguments[@]}"
"$cowebs_binary" status dev-setup --journal "$session_root/session.jsonl" --state "$session_root/state.json" --json

if [[ "$mode" == 'real' ]]; then
  cmp "$session_root/plan.json" "$session_root/canonical-plan.json"
  for state_file in "$session_root/session.jsonl" "$session_root/state.json" "$session_root/canonical-plan.json"; do
    if [[ "$(stat -c '%u' "$state_file")" != "$(id -u)" ]]; then
      echo "validation state is not owned by the initiating user: $state_file" >&2
      exit 1
    fi
  done
  "$cowebs_binary" resume dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --plan "$session_root/canonical-plan.json" --journal "$session_root/session.jsonl" --state "$session_root/state.json" --non-interactive --no-config --no-restart

  second_root="$session_root/idempotency"
  mkdir -p "$second_root"
  "$cowebs_binary" install dev-setup --packages "$package_catalog" --profiles "$profile_catalog" --profile game --essentials-only --platform "$platform" --architecture x64 --non-interactive --no-config --no-restart --journal "$second_root/session.jsonl" --state "$second_root/state.json" --plan-out "$second_root/canonical-plan.json"
  cmp "$session_root/canonical-plan.json" "$second_root/canonical-plan.json"
  "$cowebs_binary" status dev-setup --journal "$second_root/session.jsonl" --state "$second_root/state.json" --json
fi

echo "Disposable $platform $mode validation completed."
