#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------------------------------------------------------
#   All timer parameters are configured via env file (timers.env).
#   You can override the default path using ENV_FILE variable:
#
#     sudo ENV_FILE=/path/to/timers.env ./apply-timers.sh
#
#   After applying, timers are managed via systemd:
#
#     systemctl status snapshot-system.timer
#     systemctl list-timers
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_ENV_FILE="${PROJECT_ROOT}/config/timers.env"
ENV_FILE="${ENV_FILE:-$DEFAULT_ENV_FILE}"

SYSTEM_SERVICE_PATH="/etc/systemd/system/snapshot-system.service"
SYSTEM_TIMER_PATH="/etc/systemd/system/snapshot-system.timer"

DOCKER_SERVICE_PATH="/etc/systemd/system/snapshot-docker.service"
DOCKER_TIMER_PATH="/etc/systemd/system/snapshot-docker.timer"

SNAPSHOT_SYSTEM_SCRIPT="${PROJECT_ROOT}/bin/snapshot-system.sh"
SNAPSHOT_DOCKER_SCRIPT="${PROJECT_ROOT}/bin/snapshot-docker.sh"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run as root"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found"
}

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "env file not found: ${ENV_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
}

require_var() {
  [[ -n "${!1:-}" ]] || die "required variable is empty: $1"
}

validate_config() {
  require_var SYSTEM_ON_CALENDAR
  require_var DOCKER_ON_CALENDAR
}

write_system_service() {
  cat > "${SYSTEM_SERVICE_PATH}" <<EOF
[Unit]
Description=${SYSTEM_TIMER_DESCRIPTION:-System snapshot}
After=network.target

[Service]
Type=oneshot
ExecStart=${SNAPSHOT_SYSTEM_SCRIPT}
WorkingDirectory=${PROJECT_ROOT}
EnvironmentFile=${PROJECT_ROOT}/config/snapshot-system.env
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

# prevent parallel runs
ExecStartPre=/usr/bin/flock -n /tmp/snapshot-system.lock -c true

[Install]
WantedBy=multi-user.target
EOF
}

write_docker_service() {
  cat > "${DOCKER_SERVICE_PATH}" <<EOF
[Unit]
Description=${DOCKER_TIMER_DESCRIPTION:-Docker snapshot}
After=network.target

[Service]
Type=oneshot
ExecStart=${SNAPSHOT_DOCKER_SCRIPT}
WorkingDirectory=${PROJECT_ROOT}
EnvironmentFile=${PROJECT_ROOT}/config/snapshot-docker.env
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

ExecStartPre=/usr/bin/flock -n /tmp/snapshot-docker.lock -c true

[Install]
WantedBy=multi-user.target
EOF
}

write_system_timer() {
  cat > "${SYSTEM_TIMER_PATH}" <<EOF
[Unit]
Description=${SYSTEM_TIMER_DESCRIPTION:-System snapshot timer}

[Timer]
OnCalendar=${SYSTEM_ON_CALENDAR}
Persistent=${SYSTEM_PERSISTENT:-true}
RandomizedDelaySec=${SYSTEM_RANDOMIZED_DELAY_SEC:-5m}

[Install]
WantedBy=timers.target
EOF
}

write_docker_timer() {
  cat > "${DOCKER_TIMER_PATH}" <<EOF
[Unit]
Description=${DOCKER_TIMER_DESCRIPTION:-Docker snapshot timer}

[Timer]
OnCalendar=${DOCKER_ON_CALENDAR}
Persistent=${DOCKER_PERSISTENT:-true}
RandomizedDelaySec=${DOCKER_RANDOMIZED_DELAY_SEC:-5m}

[Install]
WantedBy=timers.target
EOF
}

main() {
  require_root
  require_cmd systemctl
  require_cmd flock

  load_env
  validate_config

  echo "Applying systemd units..."

  write_system_service
  write_docker_service

  write_system_timer
  write_docker_timer

  systemctl daemon-reload

  systemctl enable snapshot-system.timer snapshot-docker.timer
  systemctl restart snapshot-system.timer snapshot-docker.timer

  echo "Done."

  echo
  systemctl list-timers | grep snapshot || true
}

main "$@"
