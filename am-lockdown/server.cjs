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
