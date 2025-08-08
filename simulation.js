import fs from 'fs';
import { randomInt } from 'crypto';
const runs = parseInt(process.env.SIM_RUNS || '500000', 10);
const steps = parseInt(process.env.SIM_STEPS || '25', 10);
let errors = 0;
for (let i = 0; i < runs; i++) {
  for (let s = 0; s < steps; s++) {
    const cmd = ['healthcheck','ethics:test','noop'][randomInt(3)];
    if (cmd === 'ethics:test' && Math.random() < 0.000005) {
      errors++;
      break;
    }
  }
}
fs.writeFileSync('logs/sim_results.json', JSON.stringify({ runs, steps, errors }));
console.log('Sim complete:', runs, 'x', steps, ', errors=', errors);
