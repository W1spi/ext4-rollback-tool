#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# apply-timers.sh
#
# Generates systemd timer files from config/timers.env:
#   - /etc/systemd/system/snapshot-system.timer
#   - /etc/systemd/system/snapshot-docker.timer
#
# Then reloads systemd and restarts/enables timers.
#
# Usage:
#   sudo ./bin/apply-timers.sh
#   sudo ENV_FILE=/path/to/timers.env ./bin/apply-timers.sh
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="${SCRIPT_DIR}/../config/timers.env"
ENV_FILE="${ENV_FILE:-$DEFAULT_ENV_FILE}"

SYSTEM_TIMER_PATH="/etc/systemd/system/snapshot-system.timer"
DOCKER_TIMER_PATH="/etc/systemd/system/snapshot-docker.timer"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

log() {
  echo -e "[$(date --iso-8601=seconds)] $*"
}

die() {
  echo -e "${RED}${BOLD}ERROR:${RESET} $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found"
}

load_env_file() {
  [[ -f "${ENV_FILE}" ]] || die "env file not found: ${ENV_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "required variable is empty: ${name}"
}

validate_config() {
  require_var SYSTEM_TIMER_DESCRIPTION
  require_var SYSTEM_ON_CALENDAR
  require_var SYSTEM_PERSISTENT
  require_var SYSTEM_RANDOMIZED_DELAY_SEC

  require_var DOCKER_TIMER_DESCRIPTION
  require_var DOCKER_ON_CALENDAR
  require_var DOCKER_PERSISTENT
  require_var DOCKER_RANDOMIZED_DELAY_SEC
}

write_system_timer() {
  cat > "${SYSTEM_TIMER_PATH}" <<EOF
[Unit]
Description=${SYSTEM_TIMER_DESCRIPTION}

[Timer]
OnCalendar=${SYSTEM_ON_CALENDAR}
Persistent=${SYSTEM_PERSISTENT}
RandomizedDelaySec=${SYSTEM_RANDOMIZED_DELAY_SEC}

[Install]
WantedBy=timers.target
EOF
}

write_docker_timer() {
  cat > "${DOCKER_TIMER_PATH}" <<EOF
[Unit]
Description=${DOCKER_TIMER_DESCRIPTION}

[Timer]
OnCalendar=${DOCKER_ON_CALENDAR}
Persistent=${DOCKER_PERSISTENT}
RandomizedDelaySec=${DOCKER_RANDOMIZED_DELAY_SEC}

[Install]
WantedBy=timers.target
EOF
}

main() {
  require_root
  require_cmd systemctl
  require_cmd cat

  load_env_file
  validate_config

  log "${CYAN}${BOLD}Using env file:${RESET} ${ENV_FILE}"

  log "${CYAN}${BOLD}Writing system timer:${RESET} ${SYSTEM_TIMER_PATH}"
  write_system_timer

  log "${CYAN}${BOLD}Writing docker timer:${RESET} ${DOCKER_TIMER_PATH}"
  write_docker_timer

  log "${CYAN}${BOLD}Reloading systemd daemon...${RESET}"
  systemctl daemon-reload

  log "${CYAN}${BOLD}Enabling timers...${RESET}"
  systemctl enable snapshot-system.timer snapshot-docker.timer

  log "${CYAN}${BOLD}Restarting timers...${RESET}"
  systemctl restart snapshot-system.timer snapshot-docker.timer

  log "${GREEN}${BOLD}Timers applied successfully.${RESET}"

  echo
  echo "Current timers:"
  systemctl list-timers --all | grep -E 'snapshot-(system|docker)\.timer' || true
}

main "$@"
