#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# restore-docker.sh
#
# Откатывает Docker-инфру (без volumes):
#   - /opt/devteam/docker
#   - /etc/docker
#
# Особенности:
#   - список снапшотов с номерами (1..N) от самого раннего к последнему
#   - выбор снапшота по номеру
#   - dry-run (rsync -n) перед применением
#   - обязательное подтверждение вводом "yes"
#   - логирование (кто/когда/что/куда)
#   - цветные предупреждения
#   - пути можно переопределить через env-файл
#
# Пример:
#   sudo ENV_FILE=/etc/ext4-rollback-tool/restore-docker.env ./restore-docker.sh
# -----------------------------------------------------------------------------

# ---------- env loading ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/restore-docker.env"
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
SNAP_BASE="${SNAP_BASE:-/mnt/nextcloud_data/.infra_snapshots/docker}"
LOG_DIR="${LOG_DIR:-/mnt/nextcloud_data/.infra_snapshots/_logs}"

PROJECTS_DST="${PROJECTS_DST:-/opt/devteam/docker}"
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
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root" >&2
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "ERROR: '${cmd}' not found" >&2
    exit 1
  }
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
