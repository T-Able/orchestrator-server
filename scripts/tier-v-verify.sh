#!/usr/bin/env bash
set -euo pipefail

root="${ROOT:-$PWD}"
cfg="$root/config"
am_host="http://localhost:9093"
ok()  { printf "✅ %s\n" "$*"; }
bad() { printf "❌ %s\n" "$*" >&2; }
say() { printf "\n▶ %s\n" "$*"; }

# ---------- helpers ----------
wait_for_file() {
  local path="$1" want="$2" timeout="${3:-10}"
  local t=0
  while (( t < timeout )); do
    if [[ "$want" == "present"  && -f "$path" ]]; then return 0; fi
    if [[ "$want" == "absent"   && ! -f "$path" ]]; then return 0; fi
    sleep 1; ((t++))
  done
  return 1
}

post_alert() {
  # First try host-exposed 9093. If closed, post from inside the container.
  local payload="$1"
  if curl -fsS -X POST -H 'Content-Type: application/json' -d "$payload" "$am_host/api/v2/alerts" >/dev/null 2>&1; then
    return 0
  fi
  docker compose exec -T alertmanager sh -lc \
    'payload='"'"$payload"'"'; wget -qO- --header "Content-Type: application/json" --post-data "$payload" http://localhost:9093/api/v2/alerts >/dev/null'
}

# ---------- prechecks ----------
say "Prechecks"
[[ -d "$cfg" ]] || mkdir -p "$cfg"
rm -f "$cfg/LOCKDOWN" "$cfg/REARMED"

# Is Alertmanager up (from Prom point of view this is already working)?
if docker compose exec -T alertmanager sh -lc 'wget -qO- http://localhost:9093/api/v2/status >/dev/null'; then
  ok "Alertmanager API reachable"
else
  bad "Alertmanager not reachable"; exit 2
fi

# Can AM reach the lockdown webhook?
if docker compose exec -T alertmanager sh -lc 'wget -qS --spider http://am-lockdown:8090/healthz 2>&1 | head -1 | grep -q "200 OK"'; then
  ok "Alertmanager → am-lockdown connectivity OK"
else
  bad "am-lockdown health check failed"; exit 3
fi

# Is am-lockdown writing into /shared?
docker compose exec -T am-lockdown sh -lc 'test -w /shared' \
  && ok "am-lockdown /shared is writable" || { bad "/shared not writable"; exit 4; }

# ---------- fire ----------
say "FIRE tripwire → expect LOCKDOWN"
now="$(date -Iseconds)"
payload_firing="$(printf '[{"labels":{"alertname":"LoyaltyTripwire","severity":"critical"},"annotations":{"summary":"tier-v verify"},"startsAt":"%s"}]' "$now")"
post_alert "$payload_firing"

if wait_for_file "$cfg/LOCKDOWN" present 10; then
  ok "LOCKDOWN engaged ($cfg/LOCKDOWN present)"
else
  bad "LOCKDOWN did not engage"; exit 10
fi

# ---------- resolve (re-arm) ----------
say "RESOLVE tripwire → expect LOCKDOWN cleared + REARMED"
end="$(date -Iseconds)"
payload_resolved="$(printf '[{"labels":{"alertname":"LoyaltyTripwire","severity":"critical"},"annotations":{"summary":"tier-v verify"},"startsAt":"%s","endsAt":"%s"}]' "$now" "$end")"
post_alert "$payload_resolved"

# give AM a moment to group/dispatch
sleep 6

if wait_for_file "$cfg/LOCKDOWN" absent 10 && wait_for_file "$cfg/REARMED" present 10; then
  ok "Pressure-lock recalibrated (LOCKDOWN cleared, REARMED stamped)"
  echo
  echo "PASS: Tier-V pressure-lock e2e verified."
  exit 0
else
  bad "Re-arm failed (LOCKDOWN still present or REARMED missing)"
  echo "FAIL"
  exit 11
fi
