import express from 'express'; import fs from 'fs';
const app = express(); app.use(express.json({limit:'1mb'}));

function stamp(p){ fs.writeFileSync(p, new Date().toISOString()+"\n"); }

app.post('/lockdown',(req,res)=>{
  try{
    fs.writeFileSync('/shared/last_alert.json', JSON.stringify(req.body,null,2));

    const alerts = Array.isArray(req.body.alerts) ? req.body.alerts : [];
    const anyFiring  = alerts.some(a => a.status === 'firing');
    const allResolved = alerts.length > 0 && alerts.every(a => a.status === 'resolved');

    if (anyFiring) {
      stamp('/shared/LOCKDOWN');
      console.log('LOCKDOWN engaged.');
    } else if (allResolved) {
      fs.rmSync('/shared/LOCKDOWN', { force: true });
      stamp('/shared/REARMED');
      console.log('LOCKDOWN cleared, pressure-lock re-armed.');
    }

    res.json({ok:true});
  } catch (e) { console.error(e); res.status(500).json({ok:false,error:String(e)}) }
});

app.get('/healthz',(_req,res)=>res.json({ok:true}));
app.listen(8090,()=>console.log('am-lockdown listening on :8090'));
