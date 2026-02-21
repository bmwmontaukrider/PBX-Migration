#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  discovery_snapshot.sh [--host HOST] [--ssh-user USER] [--ssh-port PORT] [--ssh-key PATH] [--label LABEL] [--output-dir DIR]

Description:
  Captures a migration evidence snapshot from local host or remote host over SSH.

Examples:
  discovery_snapshot.sh --label pre-cutover --output-dir ./artifacts
  discovery_snapshot.sh --host 10.10.10.20 --ssh-user root --ssh-port 2222 --ssh-key ~/.ssh/id_ed25519 --label post-shift --output-dir ./artifacts
USAGE
}

HOST=""
SSH_USER="root"
SSH_PORT="22"
SSH_KEY=""
LABEL="snapshot"
OUTPUT_DIR="./artifacts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ssh-user) SSH_USER="${2:-}"; shift 2 ;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$LABEL" ]]; then
  echo "--label cannot be empty" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
SNAP_DIR="${OUTPUT_DIR%/}/${LABEL}-${TS}"
mkdir -p "$SNAP_DIR"

run_cmd() {
  local cmd="$1"
  if [[ -n "$HOST" ]]; then
    local ssh_args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -p "$SSH_PORT")
    if [[ -n "$SSH_KEY" ]]; then
      ssh_args+=(-i "$SSH_KEY")
    fi
    ssh "${ssh_args[@]}" "${SSH_USER}@${HOST}" "$cmd"
  else
    bash -lc "$cmd"
  fi
}

capture() {
  local name="$1"
  local cmd="$2"
  {
    echo "# Command"
    echo "$cmd"
    echo
    echo "# Output"
    run_cmd "$cmd"
  } > "${SNAP_DIR}/${name}.txt" 2>&1 || true
}

capture "00_meta" "date -u; hostname; uname -a"
capture "01_network" "ip -brief addr 2>/dev/null || ifconfig"
capture "02_sockets" "ss -lntu"
capture "03_freeswitch_service" "systemctl status freeswitch --no-pager"
capture "04_sofia_status" "fs_cli -x 'sofia status'"
capture "05_registrations" "fs_cli -x 'show registrations'"
capture "06_channels" "fs_cli -x 'show channels'"
capture "07_channels_count" "fs_cli -x 'show channels count'"

printf 'Snapshot written to: %s\n' "$SNAP_DIR"
