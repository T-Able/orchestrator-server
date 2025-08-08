#!/usr/bin/env bash
set -euo pipefail

APP="/usr/src/app"
cd "$APP"

# belts and suspenders: ensure dirs exist at runtime too
mkdir -p "$APP/config" "$APP/logs"

# run sim then server
node "$APP/simulation.js"
npm start & SERVER_PID=$!

# watch loop: if inotify fails, just sleep and retry
while true; do
  inotifywait -e modify,create,delete -r "$APP/config" "$APP/simulation.js" || sleep 1
  kill $SERVER_PID 2>/dev/null || true
  node "$APP/simulation.js"
  npm start & SERVER_PID=$!
done
