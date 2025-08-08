#!/usr/bin/env bash
set -euo pipefail

SIM_RUNS="${SIM_RUNS:-20}"
STATE_DIR="${STATE_DIR:-/var/lib/sim_metrics}"
METRICS_FILE="$STATE_DIR/metrics.prom"

mkdir -p "$STATE_DIR"
# if you run via cron as root, ownership is fine; if as a user, you can chown once:
# chown "$(id -u)":"$(id -g)" "$STATE_DIR" || true

ERRORS=0
for ((i=1; i<=SIM_RUNS; i++)); do
  echo "Run $i / $SIM_RUNS..."
  if [ $((RANDOM % 20)) -eq 0 ]; then
    ((ERRORS+=1))
  fi
done

if [[ "${FORCE_FAIL:-0}" -eq 1 ]]; then ERRORS=$((ERRORS+1)); fi
echo "Total errors: $ERRORS"
if (( ERRORS > 0 )); then echo "⚠ Issues detected."; else echo "✅ All clear."; fi

NOW="$(date +%s)"
TMP="${METRICS_FILE}.tmp"
cat > "$TMP" <<METRICS
# HELP simulation_errors_total Total errors observed in last run
# TYPE simulation_errors_total gauge
simulation_errors_total $ERRORS

# HELP simulation_runs_last Last run count used
# TYPE simulation_runs_last gauge
simulation_runs_last $SIM_RUNS

# HELP simulation_status 0=OK,1=ISSUES
# TYPE simulation_status gauge
simulation_status $(( ERRORS>0 ? 1 : 0 ))

# HELP simulation_last_run_unixtime Last run UNIX timestamp
# TYPE simulation_last_run_unixtime gauge
simulation_last_run_unixtime $NOW
METRICS
mv -f "$TMP" "$METRICS_FILE"
