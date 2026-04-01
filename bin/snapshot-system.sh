#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# snapshot-system.sh
#
# SYSTEM ONLY snapshot (Docker root excluded)
#
# Цель:
#   - сохранить "всю систему" в рамках системного диска (root FS)
#   - НЕ залезать в другие примонтированные диски (за это отвечает --one-file-system)
#   - НЕ пересекаться с docker-контуром (исключаем Docker Root Dir)
#   - дедупликация через --link-dest
#   - атомарная запись через .tmp-* (защита от внезапного выключения)
#   - ротация: KEEP_COUNT самых свежих
#
# Пути и retention можно переопределить через env-файл.
# -----------------------------------------------------------------------------

# ---------- env loading ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/snapshot-system.env"
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
DEST_BASE="${DEST_BASE:-/mnt/nextcloud_data/.infra_snapshots/system}"
KEEP_COUNT="${KEEP_COUNT:-8}"
SRC="${SRC:-/}"

TS="$(date +%F_%H-%M-%S)"
DEST_FINAL="${DEST_BASE}/${TS}"
DEST_TMP="${DEST_BASE}/.tmp-${TS}"
LATEST_LINK="${DEST_BASE}/LATEST"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

logc() { echo -e "[$(date --iso-8601=seconds)] $*"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || {
    echo "ERROR: run as root" >&2
    exit 1
  }
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found" >&2
    exit 1
  }
}

cleanup_old() {
  mapfile -t snaps < <(find "${DEST_BASE}" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort)
  local count="${#snaps[@]}"
  if (( count <= KEEP_COUNT )); then
    logc "${CYAN}Cleanup:${RESET} nothing to delete (have ${count}, keep ${KEEP_COUNT})"
    return 0
  fi

  local to_delete=$((count - KEEP_COUNT))
  logc "${YELLOW}Cleanup:${RESET} deleting ${to_delete} old snapshots..."

  local i
  for ((i=0; i<to_delete; i++)); do
    logc "${YELLOW}Deleting:${RESET} ${snaps[$i]}"
    rm -rf --one-file-system "${snaps[$i]}"
  done
}

rollback_tmp() {
  if [[ -d "${DEST_TMP}" ]]; then
    logc "${YELLOW}Abort:${RESET} removing tmp snapshot dir: ${DEST_TMP}"
    rm -rf --one-file-system "${DEST_TMP}" || true
  fi
}

main() {
  require_root
  require_cmd rsync
  require_cmd find
  require_cmd readlink
  require_cmd nice
  require_cmd ionice
  require_cmd mv
  require_cmd ln
  require_cmd sort

  mkdir -p "${DEST_BASE}"

  trap rollback_tmp EXIT INT TERM

  local PREV=""
  if [[ -L "${LATEST_LINK}" ]]; then
    PREV="$(readlink -f "${LATEST_LINK}" || true)"
  fi

  logc "${CYAN}${BOLD}System snapshot start${RESET}: ${TS}"
  logc "${CYAN}Env file:${RESET} ${ENV_FILE}"
  logc "${CYAN}Source:${RESET} ${SRC}"
  logc "${CYAN}Destination (tmp):${RESET} ${DEST_TMP}"
  logc "${CYAN}Destination (final):${RESET} ${DEST_FINAL}"
  logc "${CYAN}Keep count:${RESET} ${KEEP_COUNT}"
  if [[ -n "${PREV}" && -d "${PREV}" ]]; then
    logc "${CYAN}Using link-dest:${RESET} ${PREV}"
  fi

  mkdir -p "${DEST_TMP}"

  local EXCLUDES=(
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

    --exclude="${DEST_BASE}/*"
    --exclude="/mnt/nextcloud_data/.infra_snapshots/*"
    --exclude="/mnt/nextcloud_data/*"

    --exclude="/var/lib/docker/*"
  )

  local NICE_CMD=(nice -n 10 ionice -c2 -n7)

  local RSYNC_ARGS=(
    -aHAX --numeric-ids
    --delete --delete-excluded
    --info=stats2,progress2
    --one-file-system
  )

  if [[ -n "${PREV}" && -d "${PREV}" ]]; then
    RSYNC_ARGS+=(--link-dest="${PREV}")
  fi

  logc "${CYAN}Rsync:${RESET} syncing..."
  "${NICE_CMD[@]}" rsync "${RSYNC_ARGS[@]}" "${EXCLUDES[@]}" "${SRC}" "${DEST_TMP}/"

  mv -T "${DEST_TMP}" "${DEST_FINAL}"
  ln -sfn "${DEST_FINAL}" "${LATEST_LINK}"

  trap - EXIT INT TERM

  logc "${GREEN}${BOLD}System snapshot done${RESET}: ${DEST_FINAL}"
  cleanup_old
  logc "${GREEN}${BOLD}System snapshot finished OK${RESET}"
}

main "$@"
