#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# scheduler.sh (LEGACY MODE)
#
# Simple fallback scheduler for environments without systemd.
#
# Runs snapshot scripts based on time (HH:MM), checked every minute.
#
# NOT recommended if systemd timers are available.
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/scheduler.env"
ENV_FILE="${ENV_FILE:-$DEFAULT_ENV_FILE}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "env file not found: ${ENV_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

load_env

SYSTEM_SCHEDULE="${SYSTEM_SCHEDULE:-03:00}"
DOCKER_SCHEDULE="${DOCKER_SCHEDULE:-04:00}"

SNAPSHOT_SYSTEM="${SCRIPT_DIR}/snapshot-system.sh"
SNAPSHOT_DOCKER="${SCRIPT_DIR}/snapshot-docker.sh"

log() {
  echo "[$(date --iso-8601=seconds)] $*"
}

run_if_match() {
  local schedule="$1"
  local script="$2"
  local name="$3"

  local now
  now="$(date +%H:%M)"

  if [[ "${now}" == "${schedule}" ]]; then
    log "Running ${name} snapshot..."

    if "${script}"; then
      log "${name} snapshot OK"
    else
      log "ERROR: ${name} snapshot failed"
    fi
  fi
}

log "Scheduler started"
log "System schedule: ${SYSTEM_SCHEDULE}"
log "Docker schedule: ${DOCKER_SCHEDULE}"

# Prevent multiple runs within same minute
LAST_RUN=""

while true; do
  current_minute="$(date +%Y-%m-%d_%H:%M)"

  if [[ "${current_minute}" != "${LAST_RUN}" ]]; then
    run_if_match "${SYSTEM_SCHEDULE}" "${SNAPSHOT_SYSTEM}" "system"
    run_if_match "${DOCKER_SCHEDULE}" "${SNAPSHOT_DOCKER}" "docker"

    LAST_RUN="${current_minute}"
  fi

  sleep 10
done
