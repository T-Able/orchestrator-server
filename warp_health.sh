#!/usr/bin/env bash
set -euo pipefail

NAMES=(
  "orchestrator-server_orchestrator_1"
  "orchestrator-server_warp-beta_1"
  "orchestrator-server_fusion-omega_1"
)

echo "=== Container status ==="
for n in "${NAMES[@]}"; do
  if docker ps --format '{{.Names}}' | grep -q "^${n}$"; then
    echo "✅ ${n}: UP"
  else
    if docker ps -a --format '{{.Names}}' | grep -q "^${n}$"; then
      state=$(docker inspect -f '{{.State.Status}}' "$n" 2>/dev/null || echo "unknown")
      echo "❌ ${n}: NOT RUNNING (state: ${state})"
    else
      echo "❌ ${n}: NOT FOUND"
    fi
  fi
done

echo
echo "=== Recent logs (last 20 lines each) ==="
for n in "${NAMES[@]}"; do
  echo
  echo "--- $n ---"
  if docker ps -a --format '{{.Names}}' | grep -q "^${n}$"; then
    docker logs --tail=20 "$n" 2>&1 || true
  else
    echo "(no container)"
  fi
done

echo
echo "=== Quick success heuristics ==="
ok=1

# Orchestrator should print its startup line and accept commands
if docker logs orchestrator-server_orchestrator_1 2>&1 | grep -Eq "on (http|https)://localhost:4000|Server running"; then
  echo "✅ Orchestrator: startup banner detected"
else
  echo "❌ Orchestrator: no startup banner"
  ok=0
fi

# Warp-Beta should show activity lines (adjust to your log phrases if different)
if docker logs orchestrator-server_warp-beta_1 2>&1 | grep -Eiq "beta|risk|simulation|impulse"; then
  echo "✅ Warp-Beta: activity detected"
else
  echo "❌ Warp-Beta: no activity"
  ok=0
fi

# Fusion-Omega should show merge/fusion messages (adjust to your phrases)
if docker logs orchestrator-server_fusion-omega_1 2>&1 | grep -Eiq "fusion|merge|fused"; then
  echo "✅ Fusion-Omega: fusion activity detected"
else
  echo "❌ Fusion-Omega: no fusion activity"
  ok=0
fi

echo
if [ "$ok" -eq 1 ]; then
  echo "🟢 HEALTH: Impulse → Warp‑Beta → Fusion‑Omega looks good."
  exit 0
else
  echo "🔴 HEALTH: one or more links are down. See logs above."
  exit 1
fi
