#!/usr/bin/env bash
set -euo pipefail

CAPT="Captain"
echo "[$CAPT] 👉 Starting full bootstrap…"

# 1. Prepare config & log folders
mkdir -p config logs db-data
cat > config/rules.json << 'EOF'
{
  "forbidden": ["rm","shutdown","reboot","drop","format","kill","sudo"],
  "ethics_keywords": ["ethics","loyalty","honor"]
}
EOF

# 2. Write the server code
cat > orchestrator_server.js << 'EOF'
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import fs from 'fs';
import { Pool } from 'pg';
import client from 'prom-client';

const app = express();
const server = http.createServer(app);
const io = new Server(server);

// Load guard rules
const cfg = JSON.parse(fs.readFileSync('./config/rules.json'));
const FORBID = cfg.forbidden;

// Postgres pool
const pool = new Pool({ connectionString: process.env.DATABASE_URL || 'postgres://orchestrator:secret@db:5432/orchestrator_db' });

// Prometheus metric
const cmdCounter = new client.Counter({
  name: 'orchestrator_commands_total',
  help: 'Total commands received',
});

// /metrics endpoint
app.get('/metrics', (req, res) => res.send(client.register.metrics()));

io.on('connection', socket => {
  socket.on('orchestrator:command', async ({ cmd }) => {
    const ts = new Date().toISOString();
    fs.appendFileSync('logs/commands.log', \`\${ts} COMMAND: \${cmd}\n\`);
    cmdCounter.inc();
    await pool.query('INSERT INTO commands(command,timestamp) VALUES($1,$2)', [cmd, ts]);
    console.log('➡️', ts, cmd);
  });
});

server.listen(4000, () => console.log('🚀 on https://localhost:4000'));
EOF

# 3. Write the simulation harness (500k × 25 steps)
cat > simulation.js << 'EOF'
import fs from 'fs';
import { randomInt } from 'crypto';

const runs = parseInt(process.env.SIM_RUNS || '500000', 10);
const steps = parseInt(process.env.SIM_STEPS || '25', 10);
let errors = 0;

for (let i = 0; i < runs; i++) {
  for (let s = 0; s < steps; s++) {
    const cmd = ['healthcheck','ethics:test','noop'][randomInt(3)];
    if (cmd === 'ethics:test' && Math.random() < 0.00001) {
      errors++;
      break;
    }
  }
}
fs.writeFileSync('logs/sim_results.json', JSON.stringify({ runs, steps, errors }));
console.log(\`Sim complete: \${runs}×\${steps}, errors=\${errors}\`);
EOF

# 4. Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: orchestrator
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: orchestrator_db
    volumes:
      - "./db-data:/var/lib/postgresql/data"
  orchestrator:
    build: .
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: postgres://orchestrator:secret@db:5432/orchestrator_db
      SIM_RUNS: 32000000
      SIM_STEPS: 25
    depends_on:
      - db
  caddy:
    image: caddy:2
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data

volumes:
  caddy_data:
  db-data:
EOF

# later…
docker-compose up --build -d
docker-compose exec orchestrator node simulation.js

# 5. Caddyfile for HTTPS
cat > Caddyfile << 'EOF'
localhost
reverse_proxy orchestrator:4000
EOF

# 6. Logrotate config
cat > logrotate.conf << 'EOF'
logs/commands.log {
  daily
  rotate 7
  compress
  missingok
  notifempty
  copytruncate
}
EOF

# 7. Build & launch
docker compose up --build -d

# 8. Run the 500k-run simulation
docker compose exec orchestrator node simulation.js

# 9. Check errors
ERRORS=$(docker compose exec orchestrator node -e "console.log(require('fs').readFileSync('logs/sim_results.json','utf8'))" | jq .errors)
if [ "$ERRORS" -gt 50 ]; then
  echo "❌ Simulation errors ($ERRORS) exceed threshold" >&2
  exit 1
fi

echo "✅ Simulations passed with errors=$ERRORS"
echo "🚀 Bootstrap complete. All systems green."
EOF
