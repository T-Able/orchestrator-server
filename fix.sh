set -euo pipefail
PROJECT=~/projects/orchestrator-server
mkdir -p "$PROJECT"/{config,public}
cd "$PROJECT"

# --- orchestrator_server.js ---
cat > orchestrator_server.js << 'JS'
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import fs from 'fs';
import client from 'prom-client';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

client.collectDefaultMetrics();
const cmdCounter = new client.Counter({ name: 'orchestrator_commands_total', help: 'Total commands received' });

let FORBID = [];
try {
  const cfg = JSON.parse(fs.readFileSync('./config/rules.json','utf8'));
  FORBID = Array.isArray(cfg.forbidden) ? cfg.forbidden : [];
} catch { FORBID = []; }

fs.mkdirSync('logs', { recursive: true });

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, role: process.env.ROLE || 'orchestrator' });
});

io.on('connection', socket => {
  socket.on('orchestrator:command', ({ cmd }) => {
    if (FORBID.some(bad => cmd.includes(bad))) return;
    const ts = new Date().toISOString();
    fs.appendFileSync('logs/commands.log', `${ts} COMMAND: ${cmd}\n`);
    cmdCounter.inc();
    console.log('➡️', ts, cmd);
  });
});

const PORT = process.env.PORT || 4000;
server.listen(PORT, '0.0.0.0', () =>
  console.log(`🟢 Server running on ${PORT} role=${process.env.ROLE || 'orchestrator'}`)
);
JS

# --- package.json ---
cat > package.json << 'JSON'
{
  "name": "orchestrator-server",
  "version": "1.0.0",
  "type": "module",
  "main": "orchestrator_server.js",
  "scripts": { "start": "node orchestrator_server.js" },
  "dependencies": {
    "express": "^4.21.2",
    "socket.io": "^4.8.1",
    "prom-client": "^15.1.3"
  }
}
JSON

# --- Dockerfile ---
cat > Dockerfile << 'DOCKER'
FROM node:18-alpine
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --production
COPY orchestrator_server.js ./ 
COPY public ./public
COPY config ./config
EXPOSE 4000
CMD ["npm","start"]
DOCKER

# --- Caddyfile (reverse proxy nice paths) ---
cat > Caddyfile << 'CADDY'
{
  auto_https off
}
:80 {
  reverse_proxy /orchestrator/* http://orchestrator:4000
  reverse_proxy /beta/*         http://warp-beta:4000
  reverse_proxy /fusion/*       http://fusion-omega:4000

  reverse_proxy /metrics        http://orchestrator:4000/metrics
  reverse_proxy /health         http://orchestrator:4000/health
}
CADDY

# --- docker-compose.yml (one image, 3 roles) ---
cat > docker-compose.yml << 'YML'
version: "3.8"
services:
  orchestrator:
    build: .
    image: orchestrator-server:latest
    environment:
      ROLE: orchestrator
    ports:
      - "4000:4000"

  warp-beta:
    image: orchestrator-server:latest
    environment:
      ROLE: beta
    ports:
      - "4002:4000"
    depends_on: [orchestrator]

  fusion-omega:
    image: orchestrator-server:latest
    environment:
      ROLE: fusion
    ports:
      - "4003:4000"
    depends_on: [orchestrator]

  caddy:
    image: caddy:2
    depends_on: [orchestrator, warp-beta, fusion-omega]
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data

volumes:
  caddy_data:
YML

# --- minimal UI page (optional) ---
cat > public/index.html << 'HTML'
<!doctype html><html><body><h1>Orchestrator up ✅</h1></body></html>
HTML

# --- guard rules ---
cat > config/rules.json << 'RULES'
{ "forbidden": ["shutdown", "rm -rf /", "DROP TABLE"] }
RULES

# --- build & run ---
docker-compose down -v || true
docker-compose up -d --build

echo "Waiting for containers..."
sleep 8

echo "== Checks =="
curl -sf http://localhost/health || true
echo
curl -sf http://localhost/orchestrator/health || true
echo
curl -sf http://localhost/beta/health || true
echo
curl -sf http://localhost/fusion/health || true
echo
curl -sf http://localhost/metrics | head -n 10 || true
