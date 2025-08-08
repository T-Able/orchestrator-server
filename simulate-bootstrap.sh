#!/usr/bin/env bash
set -u

cd ~/projects/orchestrator-server
LOGDIR=logs
mkdir -p "$LOGDIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$LOGDIR/sim_${TS}.log"
ERRORS=0

note() { echo "[$(date -u '+%F %T UTC')] $*" | tee -a "$LOG"; }

for i in $(seq 1 20); do
  note "---- Run $i/20: starting bootstrap-monitoring.sh ----"
  bash -x ./bootstrap-monitoring.sh >>"$LOG" 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then
    note "bootstrap-monitoring.sh exited with $rc"
    ERRORS=$((ERRORS+1))
  fi

  # Basic container health snapshot
  note "docker compose ps"
  docker compose ps >>"$LOG" 2>&1 || true

  # App health
  if ! curl -fsS --max-time 5 http://localhost:4000/healthz >>"$LOG" 2>&1; then
    note "[run $i] orchestrator /healthz FAILED"
    ERRORS=$((ERRORS+1))
  fi

  # Metrics format sanity (should be text/plain exposition)
  if ! curl -fsS --max-time 5 http://localhost:4000/metrics | head -n 3 >>"$LOG" 2>&1; then
    note "[run $i] orchestrator /metrics FAILED"
    ERRORS=$((ERRORS+1))
  fi

  # Prometheus readiness
  if ! curl -fsS --max-time 5 http://localhost:9090/-/ready >>"$LOG" 2>&1; then
    note "[run $i] Prometheus not ready"
    ERRORS=$((ERRORS+1))
  fi

  # Target health (expects '"health":"up"' in JSON)
  if ! curl -fsS --max-time 5 http://localhost:9090/api/v1/targets | grep -q '"health":"up"'; then
    note "[run $i] Prometheus target for orchestrator is NOT up"
    ERRORS=$((ERRORS+1))
  fi

  sleep 2
  note "---- Run $i/20: complete ----"
  echo >>"$LOG"

done

note "==== Simulation finished. Errors: $ERRORS ===="
if [ $ERRORS -eq 0 ]; then
  note "ALL GOOD. Log: $LOG"
else
  note "See $LOG for details (search for 'FAILED' or 'exited')."
  exit 1
fi
