#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  wait_for_channel_drain.sh [--host HOST] [--ssh-user USER] [--ssh-port PORT] [--ssh-key PATH] [--threshold N] [--interval SEC] [--timeout SEC]

Description:
  Polls FreeSWITCH channel count until it falls to threshold (default: 0).

Examples:
  wait_for_channel_drain.sh --threshold 0 --interval 15 --timeout 14400
  wait_for_channel_drain.sh --host 10.10.10.20 --ssh-user root --ssh-port 2222 --ssh-key ~/.ssh/id_ed25519 --threshold 0
USAGE
}

HOST=""
SSH_USER="root"
SSH_PORT="22"
SSH_KEY=""
THRESHOLD=0
INTERVAL=15
TIMEOUT=14400

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ssh-user) SSH_USER="${2:-}"; shift 2 ;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

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

channel_count() {
  local out
  out="$(run_cmd "fs_cli -x 'show channels count'" 2>/dev/null || true)"
  local n
  n="$(echo "$out" | grep -Eo '[0-9]+' | head -n 1 || true)"
  if [[ -z "$n" ]]; then
    echo "-1"
  else
    echo "$n"
  fi
}

start_ts=$(date +%s)

echo "Waiting for channels <= ${THRESHOLD} (interval=${INTERVAL}s timeout=${TIMEOUT}s)"

while true; do
  now_ts=$(date +%s)
  elapsed=$((now_ts - start_ts))

  if (( elapsed > TIMEOUT )); then
    echo "Timeout after ${TIMEOUT}s; channel drain not complete" >&2
    exit 1
  fi

  current="$(channel_count)"
  stamp="$(date +'%Y-%m-%d %H:%M:%S')"

  if [[ "$current" == "-1" ]]; then
    echo "${stamp} channels=unknown (fs_cli parse failed), retrying..."
  else
    echo "${stamp} channels=${current}"
    if (( current <= THRESHOLD )); then
      echo "Drain complete: channels=${current} <= threshold=${THRESHOLD}"
      exit 0
    fi
  fi

  sleep "$INTERVAL"
done
