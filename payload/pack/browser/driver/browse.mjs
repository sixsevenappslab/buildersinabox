#!/usr/bin/env node
// Builders in a Box browser pack — Node driver (FEAT-017).
//
// Deliberately does NOT use playwright-core's chromium.launch() /
// launchPersistentContext() convenience launchers. Those were found (real
// testing on Ubuntu 24.04, see FEAT-017 implementation notes) to silently
// append `--no-sandbox` to the spawned Chromium process on hosts where the
// sandbox can't initialise — with no code of ours requesting it, and with no
// literal "--no-sandbox" string anywhere for a static grep to catch. That is
// exactly the silent-degrade failure mode this pack must never have.
//
// Instead this driver spawns the browser binary itself with a fully
// self-authored argument list (audited below, never containing
// --no-sandbox unless the operator has set BIAB_UNSAFE_NO_SANDBOX=1), and
// attaches to it over CDP. If the sandbox fails to initialise, Chromium
// exits non-zero before the DevTools port comes up and this driver ABORTS
// — it never retries with a relaxed sandbox. Fail closed, not fail open.
//
// Usage: node browse.mjs <url> <verb> [verb-args...]
//   verbs: read_text | click <selector> | fill <selector> <value> | screenshot <path>
//
// Env:
//   BIAB_PROFILE_DIR        required. --user-data-dir for the browser.
//   BIAB_CHROME_EXE         required. Path to the Chromium `chrome` binary.
//   BIAB_SANDBOX_HELPER     optional. Path to Chromium's setuid sandbox
//                           helper (chrome_sandbox); mapped to
//                           CHROME_DEVEL_SANDBOX below.
//   BIAB_HEADFUL            "1" for the --headful-xvfb fallback (real X display via Xvfb).
//   BIAB_UNSAFE_NO_SANDBOX  "1" to explicitly accept an unsandboxed browser (never default,
//                           never silent — prints a loud warning on every use).
//   BIAB_NAV_TIMEOUT_MS     navigation/action timeout, default 20000.
//   BIAB_LAUNCH_TIMEOUT_MS  time to wait for the DevTools port to come up, default 15000.

import { spawn } from "node:child_process";
import { readFileSync, existsSync, mkdirSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { chromium } from "playwright-core";

const EXIT_USAGE = 2;
const EXIT_SANDBOX = 3;
const EXIT_LAUNCH = 4;
const EXIT_ACTION = 5;

function fail(code, msg) {
    process.stderr.write(`biab-browse: ${msg}\n`);
    process.exit(code);
}

const [, , url, verb, ...verbArgs] = process.argv;
if (!url || !verb) {
    fail(EXIT_USAGE, "usage: browse.mjs <url> <read_text|click|fill|screenshot> [args...]");
}
if (!/^https?:\/\//i.test(url)) {
    fail(EXIT_USAGE, `invalid URL (must start with http:// or https://): ${url}`);
}

const profileDir = process.env.BIAB_PROFILE_DIR;
const exe = process.env.BIAB_CHROME_EXE;
if (!profileDir) fail(EXIT_USAGE, "BIAB_PROFILE_DIR is not set");
if (!exe || !existsSync(exe)) fail(EXIT_USAGE, `BIAB_CHROME_EXE not found: ${exe}`);
mkdirSync(profileDir, { recursive: true });

const headful = process.env.BIAB_HEADFUL === "1";
const unsafeNoSandbox = process.env.BIAB_UNSAFE_NO_SANDBOX === "1";
const navTimeout = Number(process.env.BIAB_NAV_TIMEOUT_MS || 20000);
const launchTimeout = Number(process.env.BIAB_LAUNCH_TIMEOUT_MS || 15000);

if (unsafeNoSandbox) {
    process.stderr.write(
        "biab-browse: WARNING — BIAB_UNSAFE_NO_SANDBOX=1 set. Launching WITHOUT a sandbox. " +
        "This is an explicit, non-default, Ask-First override (FEAT-017 §1 Boundaries). " +
        "Do not enable this unless you understand and accept the risk.\n"
    );
}

// ---------------------------------------------------------------------------
// Self-authored argument list. Audited: no --no-sandbox, no
// --disable-setuid-sandbox, no --disable-namespace-sandbox, ever, unless the
// explicit unsafe override above is set. This is what AC-S4's static grep
// (payload/pack/browser/**) checks for; keeping the sandbox-affecting flags
// centralised here (instead of relying on a library default) is what makes
// that grep meaningful instead of a false-positive PASS.
// ---------------------------------------------------------------------------
const args = [
    `--user-data-dir=${profileDir}`,
    "--remote-debugging-port=0",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-breakpad",
    "--disable-client-side-phishing-detection",
    "--disable-component-update",
    "--disable-default-apps",
    "--disable-dev-shm-usage",
    "--disable-extensions",
    "--disable-sync",
    "--mute-audio",
    "--hide-scrollbars",
    "--metrics-recording-only",
    "--password-store=basic",
    "--use-mock-keychain",
];
if (!headful) {
    // Full Chromium supports both modes from the same binary; this flag is
    // what actually switches it into headless mode for the default path.
    args.unshift("--headless=new");
}
if (unsafeNoSandbox) {
    args.push("--no-sandbox"); // allowlisted-no-sandbox-reference: gated above by BIAB_UNSAFE_NO_SANDBOX=1, never the default
}

const devtoolsPortFile = `${profileDir}/DevToolsActivePort`;

// install.sh sets up Chromium's own bundled setuid sandbox helper
// (chrome_sandbox, chown root + chmod 4755) for both the default and
// --headful-xvfb paths (same engine, same cache) and biab-browse points us
// at it here. This is what lets the sandbox initialise on Ubuntu 24.04's
// AppArmor-restricted userns — see SKILL.md's threat model section. The
// fail-closed abort below stays as defense in depth regardless of engine.
const childEnv = { ...process.env };
if (process.env.BIAB_SANDBOX_HELPER) {
    childEnv.CHROME_DEVEL_SANDBOX = process.env.BIAB_SANDBOX_HELPER;
}

const child = spawn(exe, args, {
    stdio: ["ignore", "ignore", "pipe"],
    env: childEnv,
});

let stderrBuf = "";
child.stderr.on("data", (d) => {
    stderrBuf += d.toString();
});

let childExited = false;
let childExitInfo = null;
child.on("exit", (code, signal) => {
    childExited = true;
    childExitInfo = { code, signal };
});

// Wait for either the DevTools port file to appear (launch succeeded) or the
// child to exit first (launch failed — most commonly a sandbox failure on
// this OS/kernel combination). No retry, no flag relaxation: fail closed.
async function waitForDevtoolsPortOrExit() {
    const deadline = Date.now() + launchTimeout;
    while (Date.now() < deadline) {
        if (childExited) return { ok: false };
        if (existsSync(devtoolsPortFile)) {
            try {
                const contents = readFileSync(devtoolsPortFile, "utf8").trim().split("\n");
                const port = contents[0];
                const wsPath = contents[1];
                if (port && wsPath) return { ok: true, port, wsPath };
            } catch {
                // file mid-write, keep polling
            }
        }
        await sleep(100);
    }
    return { ok: false, timedOut: true };
}

const launchResult = await waitForDevtoolsPortOrExit();

if (!launchResult.ok) {
    const sandboxy = /sandbox|userns|apparmor/i.test(stderrBuf);
    try { child.kill("SIGKILL"); } catch { /* already gone */ }
    if (sandboxy) {
        fail(
            EXIT_SANDBOX,
            "Chromium sandbox failed to initialise (fail-closed: refusing to fall back to " +
            "the unsandboxed mode). This is the FEAT-017 §2.9/§4.12 sandbox conflict — see " +
            "payload/pack/browser/skill/browser/SKILL.md and the FEAT-017 implementation " +
            "notes. Raw engine output:\n" + stderrBuf.split("\n").slice(0, 5).join("\n")
        );
    }
    fail(
        EXIT_LAUNCH,
        `browser process ${launchResult.timedOut ? "did not become ready in time" : "exited before startup completed"} ` +
        `(exit=${childExitInfo ? childExitInfo.code : "n/a"}). stderr:\n` +
        stderrBuf.split("\n").slice(0, 10).join("\n")
    );
}

// Defence-in-depth: verify the flag we constructed above truly landed as the
// running process's argv (catches any future accidental edit of the args
// list above, not just a hypothetical library default).
try {
    const cmdline = readFileSync(`/proc/${child.pid}/cmdline`, "utf8").split("\0");
    const hasNoSandbox = cmdline.includes("--no-sandbox"); // allowlisted-no-sandbox-reference: detection only, never sets the flag
    if (hasNoSandbox && !unsafeNoSandbox) {
        try { child.kill("SIGKILL"); } catch { /* ignore */ }
        fail(EXIT_SANDBOX, "internal error: unexpected unsandboxed launch without an explicit override — aborting (fail-closed)."); // allowlisted-no-sandbox-reference
    }
} catch {
    // /proc not readable (e.g. non-Linux) — best-effort check only.
}

const wsEndpoint = `ws://127.0.0.1:${launchResult.port}${launchResult.wsPath}`;

let exitCode = 0;
try {
    const browser = await chromium.connectOverCDP(wsEndpoint, { timeout: navTimeout });
    const context = browser.contexts()[0] ?? (await browser.newContext());
    const page = context.pages()[0] ?? (await context.newPage());
    page.setDefaultTimeout(navTimeout);

    await page.goto(url, { waitUntil: "load", timeout: navTimeout });

    switch (verb) {
        case "read_text": {
            const text = await page.evaluate(() => document.body?.innerText ?? "");
            process.stdout.write(text + "\n");
            break;
        }
        case "click": {
            const [selector] = verbArgs;
            if (!selector) fail(EXIT_USAGE, "usage: browse.mjs <url> click <selector>");
            await page.click(selector, { timeout: navTimeout });
            process.stdout.write(JSON.stringify({ ok: true, action: "click", selector }) + "\n");
            break;
        }
        case "fill": {
            const [selector, value] = verbArgs;
            if (!selector || value === undefined) fail(EXIT_USAGE, "usage: browse.mjs <url> fill <selector> <value>");
            await page.fill(selector, value, { timeout: navTimeout });
            process.stdout.write(JSON.stringify({ ok: true, action: "fill", selector }) + "\n");
            break;
        }
        case "screenshot": {
            const [outPath] = verbArgs;
            if (!outPath) fail(EXIT_USAGE, "usage: browse.mjs <url> screenshot <path>");
            await page.screenshot({ path: outPath });
            process.stdout.write(JSON.stringify({ ok: true, action: "screenshot", path: outPath }) + "\n");
            break;
        }
        default:
            fail(EXIT_USAGE, `unknown verb: ${verb} (expected read_text|click|fill|screenshot)`);
    }

    // Disconnect (not close — the real browser process is killed below,
    // owned by us since we spawned it, not by playwright).
    await browser.close().catch(() => {});
} catch (e) {
    exitCode = EXIT_ACTION;
    process.stderr.write(`biab-browse: action failed: ${e?.message ?? e}\n`);
} finally {
    try { child.kill("SIGTERM"); } catch { /* ignore */ }
    await sleep(200);
    try { child.kill("SIGKILL"); } catch { /* already gone */ }
}

process.exit(exitCode);
