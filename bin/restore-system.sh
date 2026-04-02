#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# restore-system.sh
#
# WARNING: restores the system to /
#
# Features:
#   - always builds a plan (dry-run)
#   - shows summary + dangerous deletions
#   - double confirmation: "yes" + exact snapshot name
#   - verifies snapshot integrity (critical directories/files)
#   - "double lock": restore does NOT touch mountpoints or Docker layer
#   - logging (who/when/which snapshot/mode)
#   - base paths can be overridden via env file
# -----------------------------------------------------------------------------

# ---------- env loading ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/restore-system.env"
ENV_FILE="${ENV_FILE:-$DEFAULT_ENV_FILE}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

load_env_file() {
  [[ -f "${ENV_FILE}" ]] || die "env file not found: ${ENV_FILE}"

  set -a
  source "${ENV_FILE}"
  set +a
}

load_env_file

# ---------- config ----------
SNAP_ROOT="${SNAP_ROOT:-/var/backups/ext4-rollback}"
SNAP_BASE="${SNAP_BASE:-${SNAP_ROOT}/system}"
LOG_DIR="${LOG_DIR:-${SNAP_ROOT}/_logs}"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

logc() { echo -e "$*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root"
}

now_iso() { date --iso-8601=seconds; }
actor() { echo "${SUDO_USER:-$(whoami)}"; }

ensure_log_dir() {
  mkdir -p "${LOG_DIR}"
  chmod 700 "${LOG_DIR}" || true
}

write_log() { echo "[$(now_iso)] $1" >> "${LOG_FILE}"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found"
}

list_snapshots() {
  find "${SNAP_BASE}" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort
}

select_snapshot() {
  mapfile -t snaps < <(list_snapshots)
  (( ${#snaps[@]} > 0 )) || {
    logc "${RED}${BOLD}ERROR:${RESET} no snapshots found in ${SNAP_BASE}"
    exit 1
  }

  logc "${CYAN}${BOLD}Available SYSTEM snapshots:${RESET}"
  local i=1
  for s in "${snaps[@]}"; do
    logc "  ${BOLD}${i}${RESET}) $(basename "${s}")"
    ((i++))
  done

  logc ""
  logc "${BOLD}Select snapshot number (1-${#snaps[@]}):${RESET} "
  read -r choice

  if [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#snaps[@]} )); then
    logc "${RED}${BOLD}ERROR:${RESET} invalid choice '${choice}'"
    exit 1
  fi

  SNAP="${snaps[$((choice-1))]}"
  SNAP_NAME="$(basename "${SNAP}")"
}

RESTORE_EXCLUDES=(
  --exclude="/proc/*"
  --exclude="/sys/*"
  --exclude="/dev/*"
  --exclude="/run/*"
  --exclude="/tmp/*"
  --exclude="/var/tmp/*"
  --exclude="/swapfile"
  --exclude="/lost+found"
  --exclude="/mnt/*"
  --exclude="/media/*"
  --exclude="/srv/*"
  --exclude="${SNAP_ROOT}/*"
  --exclude="/var/lib/docker/*"
)

fail_snapshot() {
  local msg="$1"
  logc "${RED}${BOLD}SNAPSHOT CHECK FAILED:${RESET} ${RED}${msg}${RESET}"
  write_log "SnapshotCheckFailed=${msg}"
  exit 1
}

check_exists_dir() {
  [[ -d "${SNAP}$1" ]] || fail_snapshot "Missing directory in snapshot: $1"
}

check_exists_file() {
  [[ -f "${SNAP}$1" ]] || fail_snapshot "Missing file in snapshot: $1"
}

check_exists_dir_any() {
  for p in "$@"; do
    [[ -d "${SNAP}${p}" ]] && return
  done
  fail_snapshot "None of required directories exist: $*"
}

snapshot_sanity_checks() {
  [[ -d "${SNAP}" ]] || fail_snapshot "Snapshot path is not a directory: ${SNAP}"

  if [[ "${SNAP_NAME}" == "LATEST" ]] || [[ "${SNAP_NAME}" == .tmp-* ]]; then
    fail_snapshot "Refusing to restore from '${SNAP_NAME}'"
  fi

  check_exists_dir "/etc"
  check_exists_dir "/usr"
  check_exists_file "/etc/passwd"
  check_exists_file "/etc/group"
  check_exists_file "/etc/fstab"
  check_exists_dir "/usr/bin"
  check_exists_dir_any "/usr/sbin" "/sbin" "/bin"
  check_exists_dir_any "/lib" "/usr/lib" "/lib64" "/usr/lib64"

  logc "${GREEN}${BOLD}Snapshot integrity checks: OK${RESET}"
  write_log "SnapshotCheck=OK"
}

plan_changes() {
  PLAN_FILE="$(mktemp /tmp/restore-plan.XXXXXX)"
  STATS_FILE="$(mktemp /tmp/restore-stats.XXXXXX)"

  rsync -aHAX --numeric-ids --delete \
    --one-file-system \
    --itemize-changes \
    --dry-run \
    --stats \
    "${RESTORE_EXCLUDES[@]}" \
    "${SNAP}/" "/" | tee "${PLAN_FILE}" > /dev/null

  grep -E "Number of files:|Total file size:" "${PLAN_FILE}" > "${STATS_FILE}" || true
}

show_plan_summary() {
  logc ""
  logc "${CYAN}${BOLD}Planned changes summary:${RESET}"
  [[ -s "${STATS_FILE}" ]] && cat "${STATS_FILE}" || logc "No stats available"
}

show_danger_deletes() {
  logc ""
  grep -E "^\*deleting" "${PLAN_FILE}" | head -n 20 || logc "No dangerous deletes detected"
}

show_recent_changes_preview() {
  logc ""
  head -n 60 "${PLAN_FILE}"
}

confirm_double() {
  logc ""
  logc "${RED}${BOLD}FINAL WARNING${RESET}"
  read -r c1
  [[ "$c1" == "yes" ]] || return 1
  read -r c2
  [[ "$c2" == "$SNAP_NAME" ]]
}

apply_restore() {
  snapshot_sanity_checks

  rsync -aHAX --numeric-ids --delete \
    --one-file-system \
    --info=stats2,progress2 \
    "${RESTORE_EXCLUDES[@]}" \
    "${SNAP}/" "/"
}

main() {
  require_root
  require_cmd rsync
  require_cmd find
  require_cmd grep
  require_cmd sed
  require_cmd head
  require_cmd wc
  require_cmd tee
  require_cmd mktemp

  ensure_log_dir
  LOG_FILE="${LOG_DIR}/restore-system-$(date +%F).log"

  write_log "----"
  write_log "Actor=$(actor)"

  select_snapshot
  snapshot_sanity_checks

  plan_changes
  show_plan_summary
  show_danger_deletes
  show_recent_changes_preview

  read -r proceed
  [[ "${proceed,,}" == "y" ]] || exit 0

  confirm_double || exit 0

  apply_restore

  logc "${GREEN}${BOLD}System restore completed.${RESET}"
}

main "$@"
