#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - Supervisor Control API (GO-001 / operator decision D5)
# ==============================================================================
# The Supervisor presents Scheduler, Runner Pool and Recovery Engine through a
# single HTTP surface on faigrid_control_net:5000. This file provides the inline
# Python stdlib HTTP server, following the exact idiom from
# core/tenant/credential-mediator.sh (_cm_broker_server, _cm_mediator_server).
#
#   * Inline `python3 -c` so the test never depends on a bind-mount.
#   * stdlib-only: http.server, json, os, socketserver, pathlib.
#   * Attached ONLY to faigrid_control_net; faigrid_inference_net must NOT reach
#     it. That isolation is SEC-001 and is proven by a refused probe.
#   * recovery_history reads the journal core/tenant/recovery-journal.sh writes;
#     it does not introduce a second, parallel record. The journal path is
#     configured via SUPERVISOR_RECOVERY_JOURNAL_DIR (default /var/lib/faigrid/recovery).
#
# Sourced from supervisor.sh. Bash 3.2 compatible (macOS + Linux).
# ==============================================================================

# The Supervisor HTTP server. Prints the Python source; the caller passes it to
# `docker run ... python3 -c "$(_supervisor_server)"`.
_supervisor_server() {
    printf '%s' 'import http.server,socketserver,json,os,re
JOURNAL_DIR=os.environ.get("SUPERVISOR_RECOVERY_JOURNAL_DIR","/var/lib/faigrid/recovery")
JOURNAL_FILE=os.path.join(JOURNAL_DIR,"recovery.jsonl")
MAX_WORKERS=int(os.environ.get("SUPERVISOR_MAX_WORKERS","4"))
class H(http.server.BaseHTTPRequestHandler):
 def _json(self,code,obj):
  b=json.dumps(obj).encode()
  self.send_response(code)
  self.send_header("Content-Type","application/json")
  self.send_header("Content-Length",str(len(b)))
  self.end_headers()
  self.wfile.write(b)
 def do_GET(self):
  if self.path=="/v1/supervisor/max_workers":
   self._json(200,{"max_workers":MAX_WORKERS})
  elif self.path=="/v1/supervisor/poll":
   self._json(200,{"status":"ok","queued":0,"running":0})
  elif self.path.startswith("/v1/supervisor/recovery_history/"):
   job_id=self.path.split("/")[-1]
   self._recovery_history(job_id)
  else:
   self._json(404,{"error":"not_found"})
 def do_POST(self):
  if self.path=="/v1/supervisor/register":
   n=int(self.headers.get("Content-Length",0))
   body=self.rfile.read(n)
   try:
    d=json.loads(body)
   except Exception:
    d={}
   w=d.get("worker","unknown")
   self._json(200,{"status":"registered","worker":w})
  else:
   self._json(404,{"error":"not_found"})
 def _recovery_history(self,job_id):
  if not os.path.isfile(JOURNAL_FILE):
   self._json(200,{"worker":job_id,"entries":[]})
   return
  entries=[]
  try:
   with open(JOURNAL_FILE,"r") as f:
    for line in f:
     line=line.strip()
     if not line:
      continue
     try:
      rec=json.loads(line)
     except json.JSONDecodeError:
      continue
     if rec.get("worker")==job_id:
      entries.append(rec)
  except OSError:
   self._json(500,{"error":"cannot_read_journal"})
   return
  self._json(200,{"worker":job_id,"entries":entries})
 def log_message(self,*a):pass
socketserver.ThreadingTCPServer(("0.0.0.0",5000),H).serve_forever()'
}
