#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# snapshot-docker.sh
#
# Docker infra snapshot (WITHOUT volumes) + atomic commit
#
# We store:
#   1) /opt/docker        — compose/yml/env/config (infrastructure)
#   2) /etc/docker        — Docker daemon configuration
#
# We DO NOT store:
#   - /var/lib/docker/volumes (volumes are intentionally excluded)
#
# Space efficiency (ext4):
#   - rsync --link-dest to previous snapshot (hardlink deduplication)
#
# Reliability:
#   - write to .tmp-<timestamp> first, then atomically mv -> <timestamp>
#   - update LATEST only after successful mv
#   - clean up stale .tmp-* directories
#
# Paths and retention can be overridden via env file.
# -----------------------------------------------------------------------------

umask 077

# ---------- env loading ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/snapshot-docker.env"
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
SNAP_ROOT="${SNAP_ROOT:-/var/backups/ext4-rollback}"

DEST_BASE="${DEST_BASE:-${SNAP_ROOT}/docker}"
LOG_DIR="${LOG_DIR:-${SNAP_ROOT}/_logs}"

KEEP_COUNT="${KEEP_COUNT:-28}"

DOCKER_PROJECTS_DIR="${DOCKER_PROJECTS_DIR:-/opt/docker}"
DOCKER_ETC_DIR="${DOCKER_ETC_DIR:-/etc/docker}"

# ---------- computed ----------
TS="$(date +%F_%H-%M-%S)"
FINAL_DEST="${DEST_BASE}/${TS}"
TMP_DEST="${DEST_BASE}/.tmp-${TS}"
LATEST_LINK="${DEST_BASE}/LATEST"

LOG_FILE="${LOG_DIR}/snapshot-docker-$(date +%F).log"

log() {
  local msg="[$(date --iso-8601=seconds)] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

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

cleanup_old() {
  mapfile -t snaps < <(find "${DEST_BASE}" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort)
  local count="${#snaps[@]}"

  if (( count <= KEEP_COUNT )); then
    log "Cleanup: nothing to delete (have ${count}, keep ${KEEP_COUNT})"
    return 0
  fi

  local to_delete=$((count - KEEP_COUNT))
  log "Cleanup: deleting ${to_delete} old snapshots..."

  local i
  for ((i=0; i<to_delete; i++)); do
    log "Deleting: ${snaps[$i]}"
    rm -rf --one-file-system "${snaps[$i]}"
  done
}

cleanup_tmp() {
  log "Cleanup: removing stale temp snapshots (.tmp-*)..."
  find "${DEST_BASE}" -mindepth 1 -maxdepth 1 -type d -name ".tmp-20*" ! -path "${TMP_DEST}" -exec rm -rf --one-file-system {} + 2>/dev/null || true
}

on_error() {
  log "ERROR: snapshot failed. Temp dir kept: ${TMP_DEST}"
}
trap on_error ERR

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
mkdir -p "${LOG_DIR}"

cleanup_tmp

PREV=""
if [[ -L "${LATEST_LINK}" ]]; then
  PREV="$(readlink -f "${LATEST_LINK}")"
fi

log "Docker snapshot start: ${TS}"
log "Env file: ${ENV_FILE}"
log "Temp destination:  ${TMP_DEST}"
log "Final destination: ${FINAL_DEST}"
log "Projects dir: ${DOCKER_PROJECTS_DIR}"
log "Docker etc dir: ${DOCKER_ETC_DIR}"
log "Keep count: ${KEEP_COUNT}"

if [[ -n "${PREV}" && -d "${PREV}" ]]; then
  log "Previous snapshot: ${PREV}"
else
  log "No previous snapshot found — first snapshot will be full"
fi

mkdir -p "${TMP_DEST}/projects"
mkdir -p "${TMP_DEST}/etc-docker"

NICE_CMD=(nice -n 10 ionice -c2 -n7)

RSYNC_BASE_ARGS=(
  -aHAX --numeric-ids
  --delete --delete-excluded
  --info=stats2,progress2
)

if [[ -d "${DOCKER_PROJECTS_DIR}" ]]; then
  log "Sync projects: ${DOCKER_PROJECTS_DIR} -> ${TMP_DEST}/projects/"

  RSYNC_ARGS=("${RSYNC_BASE_ARGS[@]}")

  if [[ -n "${PREV}" && -d "${PREV}/projects" ]]; then
    RSYNC_ARGS+=(--link-dest="${PREV}/projects")
    log "Dedup link-dest for projects: ${PREV}/projects"
  fi

  "${NICE_CMD[@]}" rsync "${RSYNC_ARGS[@]}" \
    "${DOCKER_PROJECTS_DIR}/" \
    "${TMP_DEST}/projects/"
else
  log "WARN: projects dir not found: ${DOCKER_PROJECTS_DIR}"
fi

if [[ -d "${DOCKER_ETC_DIR}" ]]; then
  log "Sync docker daemon config: ${DOCKER_ETC_DIR} -> ${TMP_DEST}/etc-docker/"

  RSYNC_ARGS=("${RSYNC_BASE_ARGS[@]}")

  if [[ -n "${PREV}" && -d "${PREV}/etc-docker" ]]; then
    RSYNC_ARGS+=(--link-dest="${PREV}/etc-docker")
    log "Dedup link-dest for etc-docker: ${PREV}/etc-docker"
  fi

  "${NICE_CMD[@]}" rsync "${RSYNC_ARGS[@]}" \
    "${DOCKER_ETC_DIR}/" \
    "${TMP_DEST}/etc-docker/"
else
  log "WARN: docker etc dir not found: ${DOCKER_ETC_DIR}"
fi

log "Committing snapshot atomically (mv temp -> final)..."
mv -T "${TMP_DEST}" "${FINAL_DEST}"

ln -sfn "${FINAL_DEST}" "${LATEST_LINK}"

log "Snapshot done: ${FINAL_DEST}"

cleanup_old

log "Snapshot finished OK"
