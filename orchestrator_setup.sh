set -euo pipefail

echo "[1/9] Installing Node.js & npm..."
sudo apt update
sudo apt install -y nodejs npm

echo "[2/9] Creating project directory..."
mkdir -p "$HOME/projects/orchestrator-server"
cd "$HOME/projects/orchestrator-server"

echo "[3/9] Writing Orchestrator server code..."
cat > orchestrator_server.js << 'EOF'
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const FORBIDDEN = ['rm', 'shutdown', 'reboot', 'drop'];
const ETHICS_KEYWORDS = ['ethics', 'loyalty', 'honor'];

function guardCommand(cmd) {
  for (const term of FORBIDDEN) {
    if (cmd.includes(term)) return `Forbidden term detected: "${term}"`;
  }
  if (!ETHICS_KEYWORDS.some(k => cmd.includes(k))) {
    return 'Command must include a reference to ethics or loyalty';
  }
  return null;
}

io.on('connection', socket => {
  console.log('🟢 Client connected:', socket.id);
  socket.emit('log', '[Orchestrator] Connection established.');

  socket.on('orchestrator:command', ({ cmd }) => {
    console.log('➡️ Received command:', cmd);
    const error = guardCommand(cmd);
    if (error) {
      socket.emit('log', `[Orchestrator] Command rejected: ${error}`);
    } else {
      socket.emit('log', `[Orchestrator] Dispatching to Number One: ${cmd}`);
      setTimeout(() => {
        socket.emit('log', `[NumberOne ✅] Completed: ${cmd}`);
      }, 1000);
    }
  });

  socket.on('disconnect', () => console.log('🔴 Client disconnected:', socket.id));
});

server.listen(4000, () => {
  console.log('🚀 Orchestrator listening on http://localhost:4000');
});
EOF

echo "[4/9] Initializing npm & enabling ESM..."
npm init -y >/dev/null
npm pkg set type=module >/dev/null

echo "[5/9] Installing dependencies..."
npm install express socket.io >/dev/null

echo "[6/9] Adding npm start script..."
npm set-script start "node orchestrator_server.js" >/dev/null

echo "[7/9] Starting Orchestrator (background)..."
# Use nohup to detach the process and avoid terminal closure
nohup npm start > orchestrator.log 2>&1 &
disown

echo "[8/9] Verifying server process..."
sleep 2
if pgrep -f orchestrator_server.js >/dev/null; then
  echo "[✓] Server process is running"
else
  echo "[✗] Server failed to start, see orchestrator.log for errors"
fi

echo "[9/9] Setup complete. Logs: $PWD/orchestrator.log"
