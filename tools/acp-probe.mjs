// Minimal ACP (Agent Client Protocol) client for maintainers: does an ACP agent
// ask permission before it runs a tool, and what happens after allow / reject?
//
// Usage: node tools/acp-probe.mjs <workdir> [--command "<argv>"] [--decision reject|allow]
//                                 [--prompt "<text>"] [--timeout <seconds>]
//   <workdir>   directory the agent session starts in (use a scratch directory)
//   --command   the ACP server argv, split on spaces (default: "agy acp")
//   --decision  answer every permission request with the first option whose kind is
//               exactly this value, else the first starting with it: "reject"
//               (default), "allow", or an exact kind such as "allow_always"
//   --prompt    text sent to the agent (default: ask it to run `touch acp-probe-marker.txt`)
//   --timeout   give up after this many seconds (default 150)
//
// Prints one line per event: INIT, SESSION, TOOL_CALL, PERMISSION_REQUEST (with the
// option kinds offered), STOP, PERMISSION_REQUESTS (count). Node built-ins only.
import { spawn } from "node:child_process";
import readline from "node:readline";

const argv = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = argv.indexOf(name);
  if (i === -1) return dflt;
  const v = argv[i + 1];
  argv.splice(i, 2);
  return v ?? dflt;
};
const commandStr = opt("--command", "agy acp");
const decision = opt("--decision", "reject");
const prompt = opt(
  "--prompt",
  "Run this exact shell command in the terminal: touch acp-probe-marker.txt . Do not use any file-writing tool, only the shell.",
);
const timeoutS = Number(opt("--timeout", "150"));
const work = argv[0];
if (!work || !decision) {
  console.error('usage: node acp-probe.mjs <workdir> [--command "agy acp"] [--decision reject|allow|<option kind>] [--prompt "..."] [--timeout 150]');
  process.exit(2);
}
const [cmd, ...cmdArgs] = commandStr.split(/\s+/).filter(Boolean);

const agent = spawn(cmd, cmdArgs, { stdio: ["pipe", "pipe", "pipe"] });
agent.stderr.on("data", () => {});
agent.on("error", (e) => { console.log("SPAWN_ERROR:", e.message); process.exit(1); });
let id = 0;
const pending = new Map();
const send = (msg) => agent.stdin.write(JSON.stringify(msg) + "\n");
const call = (method, params) => new Promise((res, rej) => {
  const i = ++id;
  pending.set(i, { res, rej });
  send({ jsonrpc: "2.0", id: i, method, params });
});
const rl = readline.createInterface({ input: agent.stdout });
let asked = 0;
rl.on("line", (line) => {
  let m;
  try { m = JSON.parse(line); } catch { return; }
  if (m.id !== undefined && !m.method) {
    const p = pending.get(m.id);
    if (p) { pending.delete(m.id); m.error ? p.rej(m.error) : p.res(m.result); }
    return;
  }
  if (m.method === "session/request_permission") {
    asked++;
    console.log("PERMISSION_REQUEST:", JSON.stringify({
      title: m.params.toolCall?.title,
      kind: m.params.toolCall?.kind,
      options: m.params.options?.map((o) => o.kind),
    }));
    const opts = m.params.options ?? [];
    const pick = opts.find((o) => o.kind === decision) ?? opts.find((o) => o.kind?.startsWith(decision));
    send({
      jsonrpc: "2.0",
      id: m.id,
      result: { outcome: pick ? { outcome: "selected", optionId: pick.optionId } : { outcome: "cancelled" } },
    });
    return;
  }
  if (m.method === "session/update") {
    const u = m.params.update;
    if (u.sessionUpdate === "tool_call") console.log("TOOL_CALL:", u.title, u.status ?? "");
    return;
  }
  if (m.id !== undefined && m.method) {
    send({ jsonrpc: "2.0", id: m.id, error: { code: -32601, message: "not supported" } });
  }
});
const timer = setTimeout(() => { console.log("TIMEOUT"); finish(); }, timeoutS * 1000);
function finish() {
  clearTimeout(timer);
  console.log("PERMISSION_REQUESTS:", asked);
  agent.kill();
  process.exit(0);
}
try {
  const init = await call("initialize", {
    protocolVersion: 1,
    clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false },
  });
  console.log("INIT:", JSON.stringify({
    protocolVersion: init.protocolVersion,
    agentInfo: init.agentInfo,
    authMethods: init.authMethods?.map((a) => a.id),
  }));
  const s = await call("session/new", { cwd: work, mcpServers: [] });
  console.log("SESSION:", s.sessionId ? "ok" : "none", JSON.stringify(s.modes ?? null).slice(0, 300));
  const r = await call("session/prompt", { sessionId: s.sessionId, prompt: [{ type: "text", text: prompt }] });
  console.log("STOP:", r.stopReason);
} catch (e) {
  console.log("ERROR:", JSON.stringify(e));
}
finish();
