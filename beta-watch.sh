#!/usr/bin/env bash
set -euo pipefail

# 1) Run 500 000 sims
node simulation.js

# 2) Re-run on simulation.js change
while inotifywait -e modify simulation.js; do
  node simulation.js
done
