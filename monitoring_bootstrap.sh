#!/usr/bin/env bash
set -euo pipefail

echo "[1/5] Installing dependencies..."
sudo apt update
sudo apt install -y curl wget jq

echo "[2/5] Creating simulation script..."
cat << 'SIM' > simulate_runs.sh
#!/usr/bin/env bash
set -euo pipefail

SIM_RUNS=20
ERRORS=0

for ((i=1; i<=SIM_RUNS; i++)); do
  echo "Run \$i / \$SIM_RUNS..."
  # Example simulated check
  if [ $((RANDOM % 20)) -eq 0 ]; then
    ((ERRORS++))
  fi
done

echo "Total errors: \$ERRORS"
if (( ERRORS > 0 )); then
  echo "⚠ Issues detected."
else
  echo "✅ All clear."
fi
SIM
chmod +x simulate_runs.sh

echo "[3/5] Running first 20× simulation..."
./simulate_runs.sh

echo "[4/5] Setting up cron job for hourly runs..."
( crontab -l 2>/dev/null; echo "0 * * * * cd ~/projects/orchestrator-server && ./simulate_runs.sh >> simulation.log 2>&1" ) | crontab -

echo "[5/5] Done. Check simulation.log for results."
