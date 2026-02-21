#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  orchestrate_migration_over_ssh.sh \
    --mode old|both|new \
    --kamailio-host HOST \
    --old-pbx-ip IP \
    --new-pbx-ip IP \
    [options]

Required:
  --mode MODE                  Dispatcher mode to apply: old, both, or new.
  --kamailio-host HOST         SSH hostname/IP for Kamailio.
  --old-pbx-ip IP              Old PBX signaling IP/FQDN used in dispatcher URI.
  --new-pbx-ip IP              New PBX signaling IP/FQDN used in dispatcher URI.

Core options:
  --kamailio-user USER         SSH user for Kamailio. Default: root
  --kamailio-ssh-port PORT     SSH port for Kamailio. Default: 22
  --old-pbx-host HOST          SSH host for old PBX evidence/drain. Default: --old-pbx-ip
  --old-pbx-user USER          SSH user for old PBX. Default: root
  --old-pbx-ssh-port PORT      SSH port for old PBX. Default: 22
  --new-pbx-host HOST          SSH host for new PBX evidence. Default: --new-pbx-ip
  --new-pbx-user USER          SSH user for new PBX. Default: root
  --new-pbx-ssh-port PORT      SSH port for new PBX. Default: 22
  --ssh-key PATH               Private key path used for SSH/SCP.
  --sip-port PORT              SIP port for URIs. Default: 5060
  --sip-scheme sip|sips        URI scheme. Default: sip
  --set-id N                   Dispatcher set id. Default: 1
  --dispatcher-target PATH     Kamailio dispatcher file. Default: /etc/kamailio/dispatcher.list
  --reload-cmd CMD             Reload command on Kamailio. Default: kamcmd dispatcher.reload

Safety and behavior:
  --capture-snapshots          Capture pre/post snapshots from old/new PBX.
  --wait-for-drain             Wait for old PBX channel drain after apply (use with --mode new).
  --drain-threshold N          Drain threshold. Default: 0
  --drain-interval SEC         Drain poll interval. Default: 15
  --drain-timeout SEC          Drain timeout. Default: 14400
  --auto-rollback              On failure after apply attempt, revert dispatcher to old profile.
  --dry-run                    Print actions without making changes.
  --confirm                    Required for non-dry-run execution.

Path options:
  --remote-script-dir PATH     Directory on Kamailio containing apply script.
                               Default: /opt/pbx-migration/scripts
  --remote-profile-dir PATH    Directory on Kamailio for uploaded profiles.
                               Default: /tmp/pbx-migration
  --local-artifacts-dir PATH   Local output directory for generated artifacts.
                               Default: ./artifacts/orchestration

Examples:
  orchestrate_migration_over_ssh.sh \
    --mode both \
    --kamailio-host 198.51.100.30 \
    --kamailio-user admin \
    --old-pbx-ip 198.51.100.10 \
    --new-pbx-ip 198.51.100.20 \
    --capture-snapshots \
    --confirm

  orchestrate_migration_over_ssh.sh \
    --mode new \
    --kamailio-host 198.51.100.30 \
    --old-pbx-ip 198.51.100.10 \
    --new-pbx-ip 198.51.100.20 \
    --wait-for-drain \
    --auto-rollback \
    --confirm
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_dispatcher_list.sh"
APPLY_SCRIPT_NAME="apply_dispatcher_profile.sh"
SNAPSHOT_SCRIPT="${SCRIPT_DIR}/discovery_snapshot.sh"
DRAIN_SCRIPT="${SCRIPT_DIR}/wait_for_channel_drain.sh"

MODE=""
KAMAILIO_HOST=""
KAMAILIO_USER="root"
KAMAILIO_SSH_PORT="22"
OLD_PBX_IP=""
NEW_PBX_IP=""
OLD_PBX_HOST=""
OLD_PBX_USER="root"
OLD_PBX_SSH_PORT="22"
NEW_PBX_HOST=""
NEW_PBX_USER="root"
NEW_PBX_SSH_PORT="22"
SSH_KEY=""
SIP_PORT="5060"
SIP_SCHEME="sip"
SET_ID="1"
DISPATCHER_TARGET="/etc/kamailio/dispatcher.list"
RELOAD_CMD="kamcmd dispatcher.reload"
REMOTE_SCRIPT_DIR="/opt/pbx-migration/scripts"
REMOTE_PROFILE_DIR="/tmp/pbx-migration"
LOCAL_ARTIFACTS_DIR="./artifacts/orchestration"

CAPTURE_SNAPSHOTS="false"
WAIT_FOR_DRAIN="false"
DRAIN_THRESHOLD="0"
DRAIN_INTERVAL="15"
DRAIN_TIMEOUT="14400"
AUTO_ROLLBACK="false"
DRY_RUN="false"
CONFIRM="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --kamailio-host) KAMAILIO_HOST="${2:-}"; shift 2 ;;
    --kamailio-user) KAMAILIO_USER="${2:-}"; shift 2 ;;
    --kamailio-ssh-port) KAMAILIO_SSH_PORT="${2:-}"; shift 2 ;;
    --old-pbx-ip) OLD_PBX_IP="${2:-}"; shift 2 ;;
    --new-pbx-ip) NEW_PBX_IP="${2:-}"; shift 2 ;;
    --old-pbx-host) OLD_PBX_HOST="${2:-}"; shift 2 ;;
    --old-pbx-user) OLD_PBX_USER="${2:-}"; shift 2 ;;
    --old-pbx-ssh-port) OLD_PBX_SSH_PORT="${2:-}"; shift 2 ;;
    --new-pbx-host) NEW_PBX_HOST="${2:-}"; shift 2 ;;
    --new-pbx-user) NEW_PBX_USER="${2:-}"; shift 2 ;;
    --new-pbx-ssh-port) NEW_PBX_SSH_PORT="${2:-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --sip-port) SIP_PORT="${2:-}"; shift 2 ;;
    --sip-scheme) SIP_SCHEME="${2:-}"; shift 2 ;;
    --set-id) SET_ID="${2:-}"; shift 2 ;;
    --dispatcher-target) DISPATCHER_TARGET="${2:-}"; shift 2 ;;
    --reload-cmd) RELOAD_CMD="${2:-}"; shift 2 ;;
    --remote-script-dir) REMOTE_SCRIPT_DIR="${2:-}"; shift 2 ;;
    --remote-profile-dir) REMOTE_PROFILE_DIR="${2:-}"; shift 2 ;;
    --local-artifacts-dir) LOCAL_ARTIFACTS_DIR="${2:-}"; shift 2 ;;
    --capture-snapshots) CAPTURE_SNAPSHOTS="true"; shift ;;
    --wait-for-drain) WAIT_FOR_DRAIN="true"; shift ;;
    --drain-threshold) DRAIN_THRESHOLD="${2:-}"; shift 2 ;;
    --drain-interval) DRAIN_INTERVAL="${2:-}"; shift 2 ;;
    --drain-timeout) DRAIN_TIMEOUT="${2:-}"; shift 2 ;;
    --auto-rollback) AUTO_ROLLBACK="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --confirm) CONFIRM="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

is_valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

is_valid_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

if [[ -z "$MODE" || -z "$KAMAILIO_HOST" || -z "$OLD_PBX_IP" || -z "$NEW_PBX_IP" ]]; then
  usage
  exit 1
fi

[[ "$MODE" == "old" || "$MODE" == "both" || "$MODE" == "new" ]] || die "--mode must be old, both, or new"
[[ "$SIP_SCHEME" == "sip" || "$SIP_SCHEME" == "sips" ]] || die "--sip-scheme must be sip or sips"
is_valid_port "$SIP_PORT" || die "--sip-port must be a valid port number"
is_valid_port "$KAMAILIO_SSH_PORT" || die "--kamailio-ssh-port must be a valid port number"
is_valid_port "$OLD_PBX_SSH_PORT" || die "--old-pbx-ssh-port must be a valid port number"
is_valid_port "$NEW_PBX_SSH_PORT" || die "--new-pbx-ssh-port must be a valid port number"
is_valid_int "$SET_ID" || die "--set-id must be a non-negative integer"
is_valid_int "$DRAIN_THRESHOLD" || die "--drain-threshold must be a non-negative integer"
is_valid_int "$DRAIN_INTERVAL" || die "--drain-interval must be a non-negative integer"
is_valid_int "$DRAIN_TIMEOUT" || die "--drain-timeout must be a non-negative integer"

[[ -x "$BUILD_SCRIPT" ]] || die "Missing executable build script: $BUILD_SCRIPT"
[[ -x "$SNAPSHOT_SCRIPT" ]] || die "Missing executable snapshot script: $SNAPSHOT_SCRIPT"
[[ -x "$DRAIN_SCRIPT" ]] || die "Missing executable drain script: $DRAIN_SCRIPT"

require_cmd ssh
require_cmd scp
require_cmd mktemp

if [[ "$DRY_RUN" == "false" && "$CONFIRM" == "false" ]]; then
  die "Refusing to run without --confirm. Use --dry-run to preview."
fi

if [[ -z "$OLD_PBX_HOST" ]]; then OLD_PBX_HOST="$OLD_PBX_IP"; fi
if [[ -z "$NEW_PBX_HOST" ]]; then NEW_PBX_HOST="$NEW_PBX_IP"; fi

if [[ "$WAIT_FOR_DRAIN" == "true" && "$MODE" != "new" ]]; then
  die "--wait-for-drain is only valid with --mode new"
fi

RUN_TS="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${LOCAL_ARTIFACTS_DIR%/}/run-${RUN_TS}"
mkdir -p "$RUN_DIR"

OLD_URI="${SIP_SCHEME}:${OLD_PBX_IP}:${SIP_PORT}"
NEW_URI="${SIP_SCHEME}:${NEW_PBX_IP}:${SIP_PORT}"
PROFILE_SELECTED="${RUN_DIR}/dispatcher.profile.${MODE}.list"
PROFILE_OLD="${RUN_DIR}/dispatcher.profile.old.list"
REMOTE_SELECTED="${REMOTE_PROFILE_DIR%/}/dispatcher.profile.${MODE}.${RUN_TS}.list"
REMOTE_OLD="${REMOTE_PROFILE_DIR%/}/dispatcher.profile.old.${RUN_TS}.list"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

remote_kam() {
  local cmd="$1"
  ssh "${SSH_OPTS[@]}" -p "$KAMAILIO_SSH_PORT" "${KAMAILIO_USER}@${KAMAILIO_HOST}" "$cmd"
}

kam_sudo_prefix=""
if [[ "$KAMAILIO_USER" != "root" ]]; then
  kam_sudo_prefix="sudo "
fi

applied="false"

rollback_if_needed() {
  if [[ "$AUTO_ROLLBACK" == "true" && "$MODE" != "old" && "$applied" == "true" ]]; then
    echo "Attempting auto-rollback to old dispatcher profile..."
    set +e
    remote_kam "${kam_sudo_prefix}${REMOTE_SCRIPT_DIR%/}/${APPLY_SCRIPT_NAME} --profile '${REMOTE_OLD}' --target '${DISPATCHER_TARGET}' --reload-cmd '${RELOAD_CMD}'"
    local rc=$?
    set -e
    if (( rc == 0 )); then
      echo "Auto-rollback succeeded."
    else
      echo "Auto-rollback failed. Manual intervention required." >&2
    fi
  fi
}

trap rollback_if_needed ERR

echo "Run directory: ${RUN_DIR}"
echo "Generating dispatcher profiles..."
"$BUILD_SCRIPT" --mode "$MODE" --old "$OLD_URI" --new "$NEW_URI" --set-id "$SET_ID" --output "$PROFILE_SELECTED"
"$BUILD_SCRIPT" --mode "old" --old "$OLD_URI" --new "$NEW_URI" --set-id "$SET_ID" --output "$PROFILE_OLD"

if [[ "$CAPTURE_SNAPSHOTS" == "true" ]]; then
  echo "Capturing pre-change snapshots..."
  "$SNAPSHOT_SCRIPT" --host "$OLD_PBX_HOST" --ssh-user "$OLD_PBX_USER" --ssh-port "$OLD_PBX_SSH_PORT" --ssh-key "$SSH_KEY" --label "old-pre-${MODE}" --output-dir "$RUN_DIR"
  "$SNAPSHOT_SCRIPT" --host "$NEW_PBX_HOST" --ssh-user "$NEW_PBX_USER" --ssh-port "$NEW_PBX_SSH_PORT" --ssh-key "$SSH_KEY" --label "new-pre-${MODE}" --output-dir "$RUN_DIR"
fi

echo "Planned apply target: ${KAMAILIO_USER}@${KAMAILIO_HOST}:${DISPATCHER_TARGET}"
echo "Selected profile: $PROFILE_SELECTED"
echo "Rollback profile: $PROFILE_OLD"

if [[ "$DRY_RUN" == "true" ]]; then
  cat <<EOF
DRY RUN ONLY - no changes applied.
Would execute:
  1) ssh ${KAMAILIO_USER}@${KAMAILIO_HOST} "mkdir -p '${REMOTE_PROFILE_DIR}'"
  2) scp -P ${KAMAILIO_SSH_PORT} ${PROFILE_SELECTED} ${KAMAILIO_USER}@${KAMAILIO_HOST}:${REMOTE_SELECTED}
  3) scp -P ${KAMAILIO_SSH_PORT} ${PROFILE_OLD} ${KAMAILIO_USER}@${KAMAILIO_HOST}:${REMOTE_OLD}
  4) ssh ${KAMAILIO_USER}@${KAMAILIO_HOST} "${kam_sudo_prefix}${REMOTE_SCRIPT_DIR%/}/${APPLY_SCRIPT_NAME} --profile '${REMOTE_SELECTED}' --target '${DISPATCHER_TARGET}' --reload-cmd '${RELOAD_CMD}'"
EOF
  if [[ "$WAIT_FOR_DRAIN" == "true" ]]; then
    cat <<EOF
  5) ${DRAIN_SCRIPT} --host ${OLD_PBX_HOST} --ssh-user ${OLD_PBX_USER} --ssh-port ${OLD_PBX_SSH_PORT} --ssh-key ${SSH_KEY} --threshold ${DRAIN_THRESHOLD} --interval ${DRAIN_INTERVAL} --timeout ${DRAIN_TIMEOUT}
EOF
  fi
  exit 0
fi

echo "Running connectivity prechecks..."
remote_kam "echo ok >/dev/null"
ssh "${SSH_OPTS[@]}" -p "$OLD_PBX_SSH_PORT" "${OLD_PBX_USER}@${OLD_PBX_HOST}" "echo ok >/dev/null"
if [[ "$CAPTURE_SNAPSHOTS" == "true" ]]; then
  ssh "${SSH_OPTS[@]}" -p "$NEW_PBX_SSH_PORT" "${NEW_PBX_USER}@${NEW_PBX_HOST}" "echo ok >/dev/null"
fi

echo "Uploading profiles to Kamailio..."
remote_kam "mkdir -p '${REMOTE_PROFILE_DIR}'"
scp "${SSH_OPTS[@]}" -P "$KAMAILIO_SSH_PORT" "$PROFILE_SELECTED" "${KAMAILIO_USER}@${KAMAILIO_HOST}:${REMOTE_SELECTED}"
scp "${SSH_OPTS[@]}" -P "$KAMAILIO_SSH_PORT" "$PROFILE_OLD" "${KAMAILIO_USER}@${KAMAILIO_HOST}:${REMOTE_OLD}"

echo "Applying dispatcher profile on Kamailio..."
applied="true"
remote_kam "${kam_sudo_prefix}${REMOTE_SCRIPT_DIR%/}/${APPLY_SCRIPT_NAME} --profile '${REMOTE_SELECTED}' --target '${DISPATCHER_TARGET}' --reload-cmd '${RELOAD_CMD}'"
applied="false"

if [[ "$WAIT_FOR_DRAIN" == "true" ]]; then
  echo "Waiting for old PBX channel drain..."
  "$DRAIN_SCRIPT" \
    --host "$OLD_PBX_HOST" \
    --ssh-user "$OLD_PBX_USER" \
    --ssh-port "$OLD_PBX_SSH_PORT" \
    --ssh-key "$SSH_KEY" \
    --threshold "$DRAIN_THRESHOLD" \
    --interval "$DRAIN_INTERVAL" \
    --timeout "$DRAIN_TIMEOUT"
fi

if [[ "$CAPTURE_SNAPSHOTS" == "true" ]]; then
  echo "Capturing post-change snapshots..."
  "$SNAPSHOT_SCRIPT" --host "$OLD_PBX_HOST" --ssh-user "$OLD_PBX_USER" --ssh-port "$OLD_PBX_SSH_PORT" --ssh-key "$SSH_KEY" --label "old-post-${MODE}" --output-dir "$RUN_DIR"
  "$SNAPSHOT_SCRIPT" --host "$NEW_PBX_HOST" --ssh-user "$NEW_PBX_USER" --ssh-port "$NEW_PBX_SSH_PORT" --ssh-key "$SSH_KEY" --label "new-post-${MODE}" --output-dir "$RUN_DIR"
fi

echo "Migration orchestration completed successfully."
echo "Artifacts: ${RUN_DIR}"
