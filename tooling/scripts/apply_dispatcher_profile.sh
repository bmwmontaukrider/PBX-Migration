#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  apply_dispatcher_profile.sh --profile FILE [--target /etc/kamailio/dispatcher.list] [--reload-cmd 'kamcmd dispatcher.reload']

Description:
  Backs up existing dispatcher file, applies a generated profile, and reloads dispatcher.

Example:
  sudo apply_dispatcher_profile.sh --profile ./dispatcher.profile.new.list --target /etc/kamailio/dispatcher.list
USAGE
}

PROFILE=""
TARGET="/etc/kamailio/dispatcher.list"
RELOAD_CMD="kamcmd dispatcher.reload"
BACKUP_DIR="/var/backups/kamailio-dispatcher"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --reload-cmd) RELOAD_CMD="${2:-}"; shift 2 ;;
    --backup-dir) BACKUP_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$PROFILE" ]]; then
  echo "Profile does not exist: $PROFILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
TS="$(date +%Y%m%d_%H%M%S)"

if [[ -f "$TARGET" ]]; then
  cp -a "$TARGET" "$BACKUP_DIR/dispatcher.list.${TS}.bak"
  echo "Backup created: $BACKUP_DIR/dispatcher.list.${TS}.bak"
fi

cp "$PROFILE" "$TARGET"
echo "Applied profile to: $TARGET"

bash -lc "$RELOAD_CMD"
echo "Reload command executed: $RELOAD_CMD"
