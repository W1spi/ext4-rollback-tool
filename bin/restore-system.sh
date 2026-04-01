#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# restore-system.sh
#
# ВНИМАНИЕ: восстанавливает систему в /
#
# Особенности:
#   - всегда строит план (dry-run)
#   - показывает summary + опасные удаления
#   - двойное подтверждение: "yes" + точное имя снапшота
#   - проверяет целостность снапшота (критические директории/файлы)
#   - "двойной замок": restore НЕ трогает mountpoints и docker-контур
#   - логирование (кто/когда/какой снапшот/режим)
#   - базовые пути можно переопределить через env-файл
#
# Пример:
#   sudo ENV_FILE=/etc/ext4-rollback-tool/restore-system.env ./restore-system.sh
# -----------------------------------------------------------------------------

# ---------- env loading ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/restore-system.env"
ENV_FILE="${ENV_FILE:-$DEFAULT_ENV_FILE}"

load_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
}

load_env_file

# ---------- config ----------
SNAP_BASE="${SNAP_BASE:-/mnt/nextcloud_data/.infra_snapshots/system}"
LOG_DIR="${LOG_DIR:-/mnt/nextcloud_data/.infra_snapshots/_logs}"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

logc() { echo -e "$*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || {
    echo "ERROR: run as root" >&2
    exit 1
  }
}

now_iso() { date --iso-8601=seconds; }
actor() { echo "${SUDO_USER:-$(whoami)}"; }

ensure_log_dir() {
  mkdir -p "${LOG_DIR}"
  chmod 700 "${LOG_DIR}" || true
}

write_log() { echo "[$(now_iso)] $1" >> "${LOG_FILE}"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found" >&2
    exit 1
  }
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

# --- Restore excludes (DOUBLE LOCK) ---
# Эти exclude применяются и к dry-run плану, и к реальному apply.
# То есть даже если снапшот случайно содержит эти пути — restore НЕ будет их трогать.
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

  --exclude="/mnt/nextcloud_data/*"

  --exclude="/var/lib/docker/*"
)

fail_snapshot() {
  local msg="$1"
  logc "${RED}${BOLD}SNAPSHOT CHECK FAILED:${RESET} ${RED}${msg}${RESET}"
  write_log "SnapshotCheckFailed=${msg}"
  exit 1
}

check_exists_dir() {
  local path="$1"
  [[ -d "${SNAP}${path}" ]] || fail_snapshot "Missing directory in snapshot: ${path}"
}

check_exists_file() {
  local path="$1"
  [[ -f "${SNAP}${path}" ]] || fail_snapshot "Missing file in snapshot: ${path}"
}

check_exists_dir_any() {
  local ok="false"
  for p in "$@"; do
    if [[ -d "${SNAP}${p}" ]]; then
      ok="true"
      break
    fi
  done
  [[ "${ok}" == "true" ]] || fail_snapshot "None of required directories exist: $*"
}

snapshot_sanity_checks() {
  [[ -d "${SNAP}" ]] || fail_snapshot "Snapshot path is not a directory: ${SNAP}"

  if [[ "${SNAP_NAME}" == "LATEST" ]] || [[ "${SNAP_NAME}" == .tmp-* ]]; then
    fail_snapshot "Refusing to restore from '${SNAP_NAME}' (must be a finalized snapshot dir)"
  fi

  local entries
  entries="$(find "${SNAP}" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  if [[ "${entries}" =~ ^[0-9]+$ ]] && (( entries < 5 )); then
    fail_snapshot "Snapshot root looks too small (${entries} entries). Refusing."
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

  local rsync_args=(
    -aHAX --numeric-ids --delete
    --one-file-system
    --itemize-changes
    --dry-run
    --stats
  )

  rsync "${rsync_args[@]}" "${RESTORE_EXCLUDES[@]}" "${SNAP}/" "/" | tee "${PLAN_FILE}" > /dev/null

  if grep -E "Number of files:|Number of created files:|Number of deleted files:|Number of regular files transferred:|Total transferred file size:|Total file size:" \
    "${PLAN_FILE}" > "${STATS_FILE}"; then
    write_log "PlanStatsExtracted=true"
  else
    : > "${STATS_FILE}"
    write_log "PlanStatsExtracted=false"
  fi
}

show_plan_summary() {
  logc ""
  logc "${CYAN}${BOLD}Planned changes summary (from dry-run):${RESET}"
  if [[ -s "${STATS_FILE}" ]]; then
    while IFS= read -r line; do
      logc "${YELLOW}  ${line}${RESET}"
    done < "${STATS_FILE}"
  else
    logc "${YELLOW}  (Could not extract rsync stats, but plan exists)${RESET}"
  fi
}

show_danger_deletes() {
  local danger_regex='^\*deleting +/(etc|usr|boot|lib|lib64|bin|sbin|var/lib|root)/'
  local danger_file
  danger_file="$(mktemp /tmp/restore-danger.XXXXXX)"

  if grep -E "${danger_regex}" "${PLAN_FILE}" > "${danger_file}"; then
    :
  else
    : > "${danger_file}"
  fi

  local danger_count
  danger_count="$(wc -l < "${danger_file}" | tr -d ' ')"

  logc ""
  if (( danger_count > 0 )); then
    logc "${RED}${BOLD}DANGER:${RESET} Planned deletions in critical paths: ${RED}${BOLD}${danger_count}${RESET}"
    logc "${RED}${BOLD}Showing TOP-20 dangerous deletions:${RESET}"
    head -n 20 "${danger_file}" | sed 's/^/  /' | while IFS= read -r line; do
      logc "${RED}${line}${RESET}"
    done || true
    logc ""
    logc "${RED}${BOLD}If you do not fully understand these deletions — CANCEL NOW.${RESET}"
  else
    logc "${GREEN}${BOLD}OK:${RESET} No deletions detected in critical paths (/etc,/usr,/boot,/lib,/bin,/sbin,...)"
  fi

  DANGER_COUNT="${danger_count}"
  DANGER_FILE="${danger_file}"
}

show_recent_changes_preview() {
  logc ""
  logc "${CYAN}${BOLD}Preview (first 60 change lines):${RESET}"

  grep -vE "^Number of files:|^Total file size:|^Total transferred file size:|^sending incremental file list|^sent |^received |^total size is|^speedup is" \
    "${PLAN_FILE}" \
    | head -n 60 \
    | sed 's/^/  /' \
    | while IFS= read -r line; do
        logc "${YELLOW}${line}${RESET}"
      done || true
}

confirm_double() {
  logc ""
  logc "${RED}${BOLD}FINAL WARNING:${RESET} This will overwrite the live system '/' using snapshot:"
  logc "  ${BOLD}${SNAP_NAME}${RESET}"
  logc ""
  logc "${RED}${BOLD}Type 'yes' ONLY if you clearly know WHY and WHAT you restore.${RESET}"
  logc "${BOLD}Enter 'yes' to continue:${RESET} "
  read -r c1
  [[ "${c1}" == "yes" ]] || return 1

  logc ""
  logc "${RED}${BOLD}Second confirmation:${RESET} type the exact snapshot name to proceed:"
  logc "  ${BOLD}${SNAP_NAME}${RESET}"
  logc "${BOLD}Enter snapshot name:${RESET} "
  read -r c2
  [[ "${c2}" == "${SNAP_NAME}" ]]
}

apply_restore() {
  snapshot_sanity_checks

  local rsync_args=(
    -aHAX --numeric-ids --delete
    --one-file-system
    --info=stats2,progress2
  )

  logc ""
  logc "${CYAN}${BOLD}Applying restore now...${RESET}"
  write_log "ApplyRestore=true"
  write_log "RsyncArgs=${rsync_args[*]}"
  write_log "RestoreExcludes=${RESTORE_EXCLUDES[*]}"

  rsync "${rsync_args[@]}" "${RESTORE_EXCLUDES[@]}" "${SNAP}/" "/"
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
  write_log "Action=restore-system"
  write_log "Host=$(hostname)"
  write_log "PWD=$(pwd)"
  write_log "EnvFile=${ENV_FILE}"
  write_log "SnapBase=${SNAP_BASE}"

  select_snapshot
  write_log "SelectedSnapshot=${SNAP_NAME}"
  logc "${CYAN}${BOLD}Selected snapshot:${RESET} ${BOLD}${SNAP_NAME}${RESET}"

  snapshot_sanity_checks

  logc ""
  logc "${YELLOW}${BOLD}Building a RESTORE PLAN using rsync dry-run...${RESET}"
  plan_changes
  write_log "PlanFile=${PLAN_FILE}"

  show_plan_summary
  show_danger_deletes
  show_recent_changes_preview

  logc ""
  logc "${BOLD}Proceed to APPLY restore? (y/n):${RESET} "
  read -r proceed
  if [[ "${proceed,,}" != "y" ]]; then
    logc "${YELLOW}${BOLD}Cancelled.${RESET}"
    write_log "CancelledByUser=true"
    exit 0
  fi

  if ! confirm_double; then
    logc "${YELLOW}${BOLD}Cancelled.${RESET}"
    write_log "CancelledByUser=true"
    exit 0
  fi

  apply_restore

  logc "${GREEN}${BOLD}System restore completed.${RESET}"
  write_log "Result=success"

  logc "${YELLOW}${BOLD}Reboot is strongly recommended. Reboot now? (y/n):${RESET} "
  read -r rb
  if [[ "${rb,,}" == "y" ]]; then
    write_log "RebootRequested=true"
    reboot
  else
    write_log "RebootRequested=false"
    logc "${YELLOW}Please reboot manually when ready.${RESET}"
  fi
}

main "$@"
