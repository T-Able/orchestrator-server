import React, { useState, useEffect } from 'react';
import { Button, Input, Card, CardContent, CardHeader } from '@/components/ui';
import { io } from 'socket.io-client';

export default function OrchestratorDashboard() {
  const [socket, setSocket] = useState(null);
  const [status, setStatus] = useState('Disconnected');
  const [logs, setLogs] = useState([]);
  const [command, setCommand] = useState('');

  useEffect(() => {
    const s = io('http://localhost:4000', { transports: ['websocket'] });
    s.on('connect', () => setStatus('Connected'));
    s.on('disconnect', () => setStatus('Disconnected'));
    s.on('log', (msg) => setLogs((prev) => [msg, ...prev]));
    setSocket(s);
    return () => s.disconnect();
  }, []);

  function sendCommand() {
    if (socket && command.trim()) {
      socket.emit('orchestrator:command', { cmd: command });
      setCommand('');
    }
  }

  return (
    <div className="p-4 grid gap-4">
      <Card>
        <CardHeader>
          <h2 className="text-xl">Orchestrator Dashboard</h2>
          <p>Status: {status}</p>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2 mb-4">
            <Input
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              placeholder="Enter Number One directive"
            />
            <Button onClick={sendCommand}>Send</Button>
          </div>
          <div className="h-64 overflow-auto bg-gray-50 p-2 rounded">
            {logs.map((line, idx) => (
              <div key={idx} className="text-sm font-mono">{line}</div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
