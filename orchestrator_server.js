import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import fs from 'fs';
import client from 'prom-client';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

// metrics
client.collectDefaultMetrics();
const cmdCounter = new client.Counter({
  name: 'orchestrator_commands_total',
  help: 'Total commands received',
});

// optional rules.json
let FORBID = [];
try {
  fs.mkdirSync('logs', { recursive: true });
  const cfg = JSON.parse(fs.readFileSync('./config/rules.json', 'utf8'));
  FORBID = Array.isArray(cfg.forbidden) ? cfg.forbidden : [];
} catch { /* ok if rules.json is missing */ }

// endpoints
app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, role: process.env.ROLE || 'orchestrator' });
});

// sockets (simple demo)
io.on('connection', socket => {
  socket.on('orchestrator:command', ({ cmd }) => {
    if (FORBID.some(bad => String(cmd).includes(bad))) return;
    const ts = new Date().toISOString();
    fs.appendFileSync('logs/commands.log', `${ts} COMMAND: ${cmd}\n`);
    cmdCounter.inc();
    console.log('➡️', ts, cmd);
  });
});

const PORT = process.env.PORT || 4000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🟢 Server running on ${PORT} role=${process.env.ROLE || 'orchestrator'}`);
});
