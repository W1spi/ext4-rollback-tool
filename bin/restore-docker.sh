#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# restore-docker.sh
#
# Restores Docker infrastructure (WITHOUT volumes):
#   - /opt/docker
#   - /etc/docker
#
# Features:
#   - snapshot list with indices (1..N) from oldest to latest
#   - snapshot selection by index
#   - dry-run (rsync -n) before applying changes
#   - mandatory confirmation by typing "yes"
#   - logging (who/when/what/where)
#   - colored warnings
#   - paths can be overridden via env file
#
# Example:
#   sudo ENV_FILE=/etc/ext4-rollback-tool/restore-docker.env ./restore-docker.sh
# -----------------------------------------------------------------------------

# ---------- env loading ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/restore-docker.env"
ENV_FILE="${ENV_FILE:-$DEFAULT_ENV_FILE}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

load_env_file() {
  [[ -f "${ENV_FILE}" ]] || die "env file not found: ${ENV_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

load_env_file

# ---------- config ----------
SNAP_ROOT="${SNAP_ROOT:-/var/backups/ext4-rollback}"

SNAP_BASE="${SNAP_BASE:-${SNAP_ROOT}/docker}"
LOG_DIR="${LOG_DIR:-${SNAP_ROOT}/_logs}"

PROJECTS_DST="${PROJECTS_DST:-/opt/docker}"
ETC_DOCKER_DST="${ETC_DOCKER_DST:-/etc/docker}"

# ---------- colors ----------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

log_console() { echo -e "$*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found"
}

now_iso() { date --iso-8601=seconds; }

get_actor() {
  echo "${SUDO_USER:-$(whoami)}"
}

ensure_log_dir() {
  mkdir -p "${LOG_DIR}"
  chmod 700 "${LOG_DIR}" || true
}

write_log() {
  local msg="$1"
  echo "[$(now_iso)] ${msg}" >> "${LOG_FILE}"
}

list_snapshots() {
  find "${SNAP_BASE}" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort
}

select_snapshot() {
  mapfile -t snaps < <(list_snapshots)

  if (( ${#snaps[@]} == 0 )); then
    log_console "${RED}${BOLD}ERROR:${RESET} no snapshots found in ${SNAP_BASE}"
    exit 1
  fi

  log_console "${CYAN}${BOLD}Available snapshots:${RESET}"
  local i=1
  for s in "${snaps[@]}"; do
    log_console "  ${BOLD}${i}${RESET}) $(basename "${s}")"
    ((i++))
  done

  log_console ""
  log_console "${BOLD}Select snapshot number (1-${#snaps[@]}):${RESET} "
  read -r choice

  if [[ ! "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#snaps[@]} )); then
    log_console "${RED}${BOLD}ERROR:${RESET} invalid choice '${choice}'"
    exit 1
  fi

  SNAP="${snaps[$((choice-1))]}"
}

ask_dry_run() {
  log_console ""
  log_console "${YELLOW}${BOLD}Dry-run recommendation:${RESET} run a preview first to see what will change."
  log_console "${BOLD}Run dry-run first? (yes/no):${RESET} "
  read -r ans
  [[ "${ans,,}" == "yes" ]]
}

ask_yes_confirm() {
  log_console ""
  log_console "${RED}${BOLD}WARNING:${RESET} You are about to restore infrastructure from:"
  log_console "  ${BOLD}Snapshot:${RESET} $(basename "${SNAP}")"
  log_console ""
  log_console "${RED}${BOLD}Type 'yes' ONLY if you clearly understand what you are doing.${RESET}"
  log_console "${BOLD}Enter 'yes' to continue:${RESET} "
  read -r confirm
  [[ "${confirm}" == "yes" ]]
}

run_rsync() {
  local mode="$1" # "dry-run" | "apply"
  local dry_flag=()
  if [[ "${mode}" == "dry-run" ]]; then
    dry_flag=(--dry-run)
  fi

  local rsync_args=(
    -aHAX --numeric-ids --delete
    --info=stats2,progress2
  )

  if [[ -d "${SNAP}/projects" ]]; then
    log_console "${CYAN}Rsync projects (${mode})...${RESET}"
    write_log "rsync projects (${mode}) from ${SNAP}/projects/ to ${PROJECTS_DST}/"
    rsync "${rsync_args[@]}" "${dry_flag[@]}" "${SNAP}/projects/" "${PROJECTS_DST}/"
  else
    log_console "${YELLOW}WARN:${RESET} ${SNAP}/projects not found, skipping"
    write_log "WARN: ${SNAP}/projects not found, skipping"
  fi

  if [[ -d "${SNAP}/etc-docker" ]]; then
    log_console "${CYAN}Rsync /etc/docker (${mode})...${RESET}"
    write_log "rsync etc-docker (${mode}) from ${SNAP}/etc-docker/ to ${ETC_DOCKER_DST}/"
    rsync "${rsync_args[@]}" "${dry_flag[@]}" "${SNAP}/etc-docker/" "${ETC_DOCKER_DST}/"
  else
    log_console "${YELLOW}WARN:${RESET} ${SNAP}/etc-docker not found, skipping"
    write_log "WARN: ${SNAP}/etc-docker not found, skipping"
  fi
}

main() {
  require_root
  require_cmd rsync
  require_cmd find
  require_cmd sort
  require_cmd systemctl

  ensure_log_dir

  ACTOR="$(get_actor)"
  LOG_FILE="${LOG_DIR}/restore-docker-$(date +%F).log"

  write_log "----"
  write_log "Actor=${ACTOR}"
  write_log "Action=restore-docker"
  write_log "Host=$(hostname)"
  write_log "PWD=$(pwd)"
  write_log "EnvFile=${ENV_FILE}"
  write_log "SnapBase=${SNAP_BASE}"
  write_log "ProjectsDst=${PROJECTS_DST}"
  write_log "EtcDockerDst=${ETC_DOCKER_DST}"

  select_snapshot
  write_log "SelectedSnapshot=$(basename "${SNAP}")"

  if ask_dry_run; then
    write_log "Mode=dry-run"
    log_console "${YELLOW}${BOLD}DRY-RUN:${RESET} preview mode, no changes will be made."
    run_rsync "dry-run"
    log_console "${GREEN}${BOLD}Dry-run complete.${RESET}"
  else
    log_console "${YELLOW}Dry-run skipped.${RESET}"
    write_log "Mode=dry-run skipped"
  fi

  if ! ask_yes_confirm; then
    log_console "${YELLOW}${BOLD}Cancelled.${RESET}"
    write_log "CancelledByUser=true"
    exit 0
  fi

  write_log "Mode=apply"
  log_console ""
  log_console "${CYAN}${BOLD}Stopping Docker...${RESET}"
  write_log "systemctl stop docker"
  systemctl stop docker

  run_rsync "apply"

  log_console "${CYAN}${BOLD}Starting Docker...${RESET}"
  write_log "systemctl start docker"
  systemctl start docker

  log_console "${GREEN}${BOLD}Restore completed successfully.${RESET}"
  write_log "Result=success"
}

main "$@"
