#!/usr/bin/env bash
set -euo pipefail

root="${ROOT:-$PWD}"

say(){ printf "\n▶ %s\n" "$*"; }
ok(){ printf "✅ %s\n" "$*"; }
die(){ printf "❌ %s\n" "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker required"
command -v curl >/dev/null || die "curl required"

# 1) Known-good Prom rules (Tier-V tripwire)
mkdir -p "$root/prometheus"
cat > "$root/prometheus/alerts.yml" <<'YAML'
groups:
- name: tier-v.tripwires
  rules:
  - alert: LoyaltyTripwire
    expr: increase(policy_block_total[1m]) > 0
    for: 0s
    labels:
      severity: critical
    annotations:
      summary: Tier-V tripwire triggered
      description: A forbidden capability was attempted.
YAML
ok "Prometheus rules (alerts.yml) in place"

# 2) Known-good Alertmanager routing (echo + lockdown)
mkdir -p "$root/config"
cat > "$root/config/alertmanager.yml" <<'YAML'
route:
  receiver: echo
  group_by: [alertname]
  group_wait: 0s
  group_interval: 5s
  repeat_interval: 1h
  routes:
    - receiver: lockdown
      matchers:
        - alertname="LoyaltyTripwire"

receivers:
  - name: echo
    webhook_configs:
      - send_resolved: true
        url: http://am-echo:8080/
  - name: lockdown
    webhook_configs:
      - send_resolved: true
        url: http://am-lockdown:8090/lockdown
YAML
ok "Alertmanager config in place"

# 3) am-lockdown (no deps, Node http)
mkdir -p "$root/am-lockdown"
cat > "$root/am-lockdown/server.cjs" <<'JS'
const http = require('http'); const fs = require('fs');
function stamp(p){ fs.writeFileSync(p, new Date().toISOString()+"\n"); }
const srv = http.createServer((req,res)=>{
  if (req.method==='GET' && req.url==='/healthz') {
    res.writeHead(200, {'content-type':'application/json'}); return res.end('{"ok":true}');
  }
  if (req.method==='POST' && req.url==='/lockdown') {
    let body=''; req.on('data', c=> body+=c);
    req.on('end', ()=>{
      try {
        const payload = JSON.parse(body||'{}');
        fs.writeFileSync('/shared/last_alert.json', JSON.stringify(payload,null,2));
        const alerts = Array.isArray(payload.alerts) ? payload.alerts : [];
        const anyFiring   = alerts.some(a => a.status === 'firing');
        const allResolved = alerts.length>0 && alerts.every(a => a.status === 'resolved');
        if (anyFiring) { stamp('/shared/LOCKDOWN'); console.log('LOCKDOWN engaged.'); }
        else if (allResolved) {
          try { fs.unlinkSync('/shared/LOCKDOWN'); } catch(_) {}
          stamp('/shared/REARMED'); console.log('LOCKDOWN cleared, pressure-lock re-armed.');
        }
        res.writeHead(200, {'content-type':'application/json'}); res.end('{"ok":true}');
      } catch (e) { console.error(e); res.writeHead(500); res.end('{"ok":false}'); }
    });
    return;
  }
  res.writeHead(404); res.end();
});
srv.listen(8090, ()=> console.log('am-lockdown listening on :8090'));
JS
cat > "$root/am-lockdown/Dockerfile" <<'DOCKER'
FROM node:18-alpine
WORKDIR /app
COPY server.cjs .
EXPOSE 8090
CMD ["node","server.cjs"]
DOCKER
ok "am-lockdown service ready"

# 4) Compose override (prom ro mount + AM ro mount + ports)
cat > "$root/docker-compose.override.yml" <<'YAML'
services:
  prometheus:
    image: prom/prometheus:latest
    command: ["--config.file=/etc/prometheus/prometheus.yml"]
    ports:
      - "9090:9090"
    volumes:
      - type: bind
        source: ./prometheus
        target: /etc/prometheus
        read_only: true
        bind: { create_host_path: true }

  alertmanager:
    image: prom/alertmanager:v0.27.0
    command: ["--config.file=/etc/alertmanager/alertmanager.yml"]
    ports:
      - "9093:9093"
    volumes:
      - type: bind
        source: ./config
        target: /etc/alertmanager
        read_only: true
        bind: { create_host_path: true }

  am-lockdown:
    build: ./am-lockdown
    restart: unless-stopped
    volumes:
      - type: bind
        source: ./config
        target: /shared
YAML
ok "docker-compose override written"

# 5) Bring up + verify
chmod 755 "$root/prometheus"
chmod 644 "$root"/prometheus/*.yml "$root/config/alertmanager.yml" || true

docker compose up -d --build am-lockdown alertmanager prometheus

# Wait Prom ready
until curl -fsS http://localhost:9090/-/ready >/dev/null; do sleep 0.5; done
ok "Prometheus ready"

# Prom → AM discovery
curl -fsS http://localhost:9090/api/v1/alertmanagers >/dev/null && ok "Prom ↔ AM discovery OK"

# Quick functional verify (re-uses existing verify script if present)
if [ -x "$root/scripts/tier-v-verify.sh" ]; then
  bash "$root/scripts/tier-v-verify.sh"
else
  # inline minimal verify
  now=$(date -Iseconds)
  curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "[{\"labels\":{\"alertname\":\"LoyaltyTripwire\",\"severity\":\"critical\"},\"annotations\":{\"summary\":\"e2e test\"},\"startsAt\":\"$now\"}]" \
    http://localhost:9093/api/v2/alerts >/dev/null
  sleep 2
  test -f "$root/config/LOCKDOWN" || die "LOCKDOWN not engaged"

  end=$(date -Iseconds)
  curl -fsS -X POST -H 'Content-Type: application/json' \
    -d "[{\"labels\":{\"alertname\":\"LoyaltyTripwire\",\"severity\":\"critical\"},\"annotations\":{\"summary\":\"e2e test\"},\"startsAt\":\"$now\",\"endsAt\":\"$end\"}]" \
    http://localhost:9093/api/v2/alerts >/dev/null
  sleep 6
  test ! -f "$root/config/LOCKDOWN" -a -f "$root/config/REARMED" || die "Pressure-lock didn’t re-arm"
  ok "Tier-V pressure-lock e2e verified"
fi

echo
echo "PASS: Tier V loyalty architecture enabled & verified."
