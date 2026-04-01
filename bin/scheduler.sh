#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${ENV_FILE:-./config/snapshot-system.env}"

source "$ENV_FILE"

log() {
  echo "[$(date '+%F %T')] $*"
}

run_snapshot() {
  log "Running snapshot..."
  ./bin/snapshot-system.sh
}

wait_until_time() {
  local target="$1"
  while true; do
    now=$(date +%H:%M)
    if [[ "$now" == "$target" ]]; then
      break
    fi
    sleep 30
  done
}

case "$SCHEDULE_MODE" in
  off)
    log "Scheduler disabled"
    exit 0
    ;;

  interval)
    log "Interval mode: $INTERVAL_SECONDS seconds"
    while true; do
      run_snapshot
      sleep "$INTERVAL_SECONDS"
    done
    ;;

  daily)
    log "Daily at $START_TIME"
    while true; do
      wait_until_time "$START_TIME"
      run_snapshot
      sleep 60
    done
    ;;

  weekly)
    log "Weekly: day=$WEEKDAY time=$START_TIME"
    while true; do
      if [[ "$(date +%u)" == "$WEEKDAY" ]]; then
        wait_until_time "$START_TIME"
        run_snapshot
        sleep 86400
      fi
      sleep 300
    done
    ;;

  monthly)
    log "Monthly: day=$MONTHDAY time=$START_TIME"
    while true; do
      if [[ "$(date +%d)" == "$MONTHDAY" ]]; then
        wait_until_time "$START_TIME"
        run_snapshot
        sleep 86400
      fi
      sleep 600
    done
    ;;

  *)
    echo "Unknown SCHEDULE_MODE"
    exit 1
    ;;
esac
