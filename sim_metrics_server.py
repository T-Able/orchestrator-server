#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
METRICS_FILE = os.environ.get("METRICS_FILE", "/var/lib/sim_metrics/metrics.prom")
PORT = int(os.environ.get("PORT", "9108"))
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404); self.end_headers(); return
        try:
            with open(METRICS_FILE, "r") as f: data = f.read().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.end_headers(); self.wfile.write(data)
        except Exception as e:
            self.send_response(200); self.end_headers()
            self.wfile.write(f"# exporter_error 1\n# {e}\n".encode())
if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), H).serve_forever()
