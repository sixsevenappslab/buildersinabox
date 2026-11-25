#!/usr/bin/env python3
"""A local stand-in for the Responses API, for FEAT-043 T1 measurements.

No model, no login, no network beyond 127.0.0.1. It speaks just enough of the
streaming protocol for `codex exec` to run a scripted sequence of tool calls and
then finish. Every request body goes to --log (one JSON object per line), so a
measurement can read what Codex sent (the tool list, the tool outputs).

Usage: fake-responses.py --port-file F --log F --steps F

The steps file is a JSON list. Each step is one tool call the "model" makes:
  {"cmd": "git status"}                       a shell command
  {"cmd": "...", "escalate": true}            ask for sandbox_permissions=require_escalated
  {"hang": true}                              never answer (a hung provider)
After the last step the stub answers with a plain message, which ends the turn.
The shell tool is whichever the request offers (exec_command, shell_command,
shell); when the request offers none, the stub says so in its message and logs
`no_shell_tool`.
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ARGS = None
STEPS = []
LOCK = threading.Lock()


def log(obj):
    with LOCK, open(ARGS.log, "a") as f:
        f.write(json.dumps(obj) + "\n")


def pick_tool(tools):
    names = [t.get("name") for t in tools if isinstance(t, dict)]
    for want in ("exec_command", "shell_command", "shell"):
        if want in names:
            return want
    return None


def call_args(tool, step):
    cmd = step["cmd"]
    if tool == "exec_command":
        a = {"cmd": cmd, "login": False, "yield_time_ms": 10000}
        if step.get("escalate"):
            a["sandbox_permissions"] = "require_escalated"
            a["justification"] = "measurement"
        return a
    if tool == "shell_command":
        a = {"command": cmd, "login": False, "timeout_ms": 10000}
        if step.get("escalate"):
            a["sandbox_permissions"] = "require_escalated"
            a["justification"] = "measurement"
        return a
    return {"command": ["bash", "-lc", cmd], "timeout_ms": 10000}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        log({"method": "GET", "path": self.path})
        self._json(200, {"models": []})

    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(n)
        try:
            body = json.loads(raw)
        except Exception:
            body = {"raw": raw.decode("latin1")}
        outputs = [i for i in body.get("input", []) if isinstance(i, dict) and i.get("type") == "function_call_output"]
        idx = len(outputs)
        tool = pick_tool(body.get("tools", []))
        log({"method": "POST", "path": self.path, "step": idx, "tool": tool,
             "tools": [t.get("name") or t.get("type") for t in body.get("tools", [])],
             "outputs": [o.get("output") for o in outputs]})
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("connection", "close")
        self.end_headers()
        self.close_connection = True

        def ev(t, d):
            self.wfile.write(f"event: {t}\ndata: {json.dumps(d)}\n\n".encode())
            self.wfile.flush()

        ev("response.created", {"type": "response.created", "response": {"id": f"resp_{idx}"}})
        step = STEPS[idx] if idx < len(STEPS) else None
        if step and step.get("hang"):
            time.sleep(3600)
            return
        if step and tool:
            item = {"type": "function_call", "id": f"fc_{idx}", "call_id": f"call_{idx}",
                    "name": tool, "arguments": json.dumps(call_args(tool, step))}
        else:
            text = "done" if not step else "no_shell_tool"
            if step:
                log({"event": "no_shell_tool", "step": idx})
            item = {"type": "message", "role": "assistant", "id": f"msg_{idx}",
                    "content": [{"type": "output_text", "text": text}]}
        ev("response.output_item.done", {"type": "response.output_item.done", "item": item})
        ev("response.completed", {"type": "response.completed", "response": {
            "id": f"resp_{idx}",
            "usage": {"input_tokens": 1, "input_tokens_details": None,
                      "output_tokens": 1, "output_tokens_details": None, "total_tokens": 2}}})


def main():
    global ARGS, STEPS
    p = argparse.ArgumentParser()
    p.add_argument("--port-file", required=True)
    p.add_argument("--log", required=True)
    p.add_argument("--steps", required=True)
    ARGS = p.parse_args()
    with open(ARGS.steps) as f:
        STEPS = json.load(f)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    srv.daemon_threads = True
    with open(ARGS.port_file, "w") as f:
        f.write(str(srv.server_address[1]))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
