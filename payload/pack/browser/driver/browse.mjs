#!/usr/bin/env node
// Builders in a Box browser pack — Node driver (FEAT-017, FEAT-030).
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
//   verbs: read_text | click <selector> | fill <selector> <value>
//        | screenshot <path> | run <workflow-file>
//
// Env:
//   BIAB_PROFILE_DIR             required. --user-data-dir for the browser.
//   BIAB_CHROME_EXE              required. Path to the Chromium `chrome` binary.
//   BIAB_SANDBOX_HELPER          optional. Path to Chromium's setuid sandbox
//                                helper (chrome_sandbox); mapped to
//                                CHROME_DEVEL_SANDBOX below.
//   BIAB_HEADFUL                 "1" for the headful/Xvfb mode (real X display).
//   BIAB_DEVICE                  "iphone" to emulate an iPhone over CDP (FEAT-030).
//                                Chromium emulation, not Safari/iOS.
//   BIAB_DETECT_INITIAL_BLOCK    "1" to report a recognised block page as exit 6
//                                instead of continuing. Only the wrapper decides
//                                whether that becomes a retry in another mode.
//   BIAB_UNSAFE_NO_SANDBOX       "1" to explicitly accept an unsandboxed browser
//                                (never default, never silent — prints a loud
//                                warning on every use).
//   BIAB_NAV_TIMEOUT_MS          navigation/action timeout, default 20000.
//   BIAB_LAUNCH_TIMEOUT_MS       time to wait for the DevTools port, default 15000.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { chromium, devices } from "playwright-core";
import { WorkflowError, initialBlockReason, parseWorkflow } from "./lib.mjs";

const EXIT_USAGE = 2;
const EXIT_SANDBOX = 3;
const EXIT_LAUNCH = 4;
const EXIT_ACTION = 5;
const EXIT_BLOCKED = 6;

function fail(code, message) {
    process.stderr.write(`biab-browse: ${message}\n`);
    process.exit(code);
}

// Thin wrapper: lib.mjs decides, this turns a rejection into the reserved
// usage exit code. Reading the file (rather than stdin) is what keeps workflow
// values out of argv — biab-browse has already copied stdin into a private
// 0600 file owned by the browser user.
function loadWorkflow(path) {
    let text;
    try {
        text = readFileSync(path, "utf8");
    } catch (error) {
        fail(EXIT_USAGE, `cannot read workflow file: ${error?.message ?? error}`);
    }
    try {
        return parseWorkflow(text);
    } catch (error) {
        if (error instanceof WorkflowError) fail(EXIT_USAGE, error.message);
        throw error;
    }
}

const [, , url, verb, ...verbArgs] = process.argv;
if (!url || !verb) fail(EXIT_USAGE, "usage: browse.mjs <url> <read_text|click|fill|screenshot|run> [args...]");
if (!/^https?:\/\//i.test(url)) fail(EXIT_USAGE, `invalid URL (must start with http:// or https://): ${url}`);

let workflowActions = null;
switch (verb) {
    case "read_text":
        if (verbArgs.length !== 0) fail(EXIT_USAGE, "usage: browse.mjs <url> read_text");
        break;
    case "click":
        if (verbArgs.length !== 1) fail(EXIT_USAGE, "usage: browse.mjs <url> click <selector>");
        break;
    case "fill":
        if (verbArgs.length !== 2) fail(EXIT_USAGE, "usage: browse.mjs <url> fill <selector> <value>");
        break;
    case "screenshot":
        if (verbArgs.length !== 1) fail(EXIT_USAGE, "usage: browse.mjs <url> screenshot <path>");
        break;
    case "run":
        if (verbArgs.length !== 1) fail(EXIT_USAGE, "usage: browse.mjs <url> run <workflow-file>");
        workflowActions = loadWorkflow(verbArgs[0]);
        break;
    default:
        fail(EXIT_USAGE, `unknown verb: ${verb}`);
}

const profileDir = process.env.BIAB_PROFILE_DIR;
const exe = process.env.BIAB_CHROME_EXE;
if (!profileDir) fail(EXIT_USAGE, "BIAB_PROFILE_DIR is not set");
if (!exe || !existsSync(exe)) fail(EXIT_USAGE, `BIAB_CHROME_EXE not found: ${exe}`);
mkdirSync(profileDir, { recursive: true });

const headful = process.env.BIAB_HEADFUL === "1";
const emulateIphone = process.env.BIAB_DEVICE === "iphone";
const unsafeNoSandbox = process.env.BIAB_UNSAFE_NO_SANDBOX === "1";
const detectBlock = process.env.BIAB_DETECT_INITIAL_BLOCK === "1";
const navTimeout = Number(process.env.BIAB_NAV_TIMEOUT_MS || 20000);
const launchTimeout = Number(process.env.BIAB_LAUNCH_TIMEOUT_MS || 15000);

if (unsafeNoSandbox) {
    process.stderr.write("biab-browse: WARNING — BIAB_UNSAFE_NO_SANDBOX=1 set. Launching WITHOUT a sandbox. This is an explicit, non-default, Ask-First override.\n");
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
// Full Chromium supports both modes from the same binary; this flag is what
// actually switches it into headless mode for the default path.
if (!headful) args.unshift("--headless=new");
if (unsafeNoSandbox) args.push("--no-sandbox"); // allowlisted-no-sandbox-reference: explicit gated override only

const devtoolsPortFile = `${profileDir}/DevToolsActivePort`;

// install.sh sets up Chromium's own bundled setuid sandbox helper
// (chrome_sandbox, chown root + chmod 4755) for every mode (same engine, same
// cache) and biab-browse points us at it here. This is what lets the sandbox
// initialise on Ubuntu 24.04's AppArmor-restricted userns — see SKILL.md's
// threat model section. The fail-closed abort below stays as defense in depth
// regardless of engine.
const childEnv = { ...process.env };
if (process.env.BIAB_SANDBOX_HELPER) childEnv.CHROME_DEVEL_SANDBOX = process.env.BIAB_SANDBOX_HELPER;

const child = spawn(exe, args, { stdio: ["ignore", "ignore", "pipe"], env: childEnv });
let stderrBuf = "";
child.stderr.on("data", (data) => { stderrBuf += data.toString(); });
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
                const [port, wsPath] = readFileSync(devtoolsPortFile, "utf8").trim().split("\n");
                if (port && wsPath) return { ok: true, port, wsPath };
            } catch {
                // The file can be observed mid-write; keep polling.
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
    fail(EXIT_LAUNCH, `browser process ${launchResult.timedOut ? "did not become ready in time" : "exited before startup completed"} ` +
        `(exit=${childExitInfo ? childExitInfo.code : "n/a"}). stderr:\n` + stderrBuf.split("\n").slice(0, 10).join("\n"));
}

// Defence-in-depth: verify the flag we constructed above truly landed as the
// running process's argv (catches any future accidental edit of the args
// list above, not just a hypothetical library default).
try {
    const cmdline = readFileSync(`/proc/${child.pid}/cmdline`, "utf8").split("\0");
    const hasNoSandbox = cmdline.includes("--no-sandbox"); // allowlisted-no-sandbox-reference: detection only
    if (hasNoSandbox && !unsafeNoSandbox) {
        try { child.kill("SIGKILL"); } catch { /* ignore */ }
        fail(EXIT_SANDBOX, "internal error: unexpected unsandboxed launch without an explicit override — aborting (fail-closed)."); // allowlisted-no-sandbox-reference
    }
} catch {
    // /proc is Linux-specific; the launch still remains fail-closed without it.
}

// Chromium's iPhone emulation, applied over CDP before the first navigation:
// user agent, viewport, device scale and touch. This is NOT Safari and NOT
// iOS — it changes what the page is told about the device, nothing more, and
// the docs say so in those words.
async function configureIphone(page, context) {
    if (!emulateIphone) return;
    const iphone = devices["iPhone 13"];
    const session = await context.newCDPSession(page);
    await session.send("Network.setUserAgentOverride", {
        userAgent: iphone.userAgent,
        acceptLanguage: "en-US,en;q=0.9",
        platform: "iPhone",
    });
    await session.send("Emulation.setDeviceMetricsOverride", {
        width: iphone.viewport.width,
        height: iphone.viewport.height,
        deviceScaleFactor: iphone.deviceScaleFactor,
        mobile: true,
        screenWidth: iphone.screen.width,
        screenHeight: iphone.screen.height,
    });
    await session.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
}

// One page, one browser, actions in order, stop at the first failure. Mutating
// actions confirm themselves without echoing `value`, so a filled password
// never reaches stdout; only read_text returns page content.
async function runWorkflow(page, actions) {
    for (let index = 0; index < actions.length; index += 1) {
        const step = actions[index];
        switch (step.action) {
            case "fill":
                await page.fill(step.selector, step.value, { timeout: navTimeout });
                process.stdout.write(JSON.stringify({ ok: true, index, action: "fill", selector: step.selector }) + "\n");
                break;
            case "click":
                await page.click(step.selector, { timeout: navTimeout });
                process.stdout.write(JSON.stringify({ ok: true, index, action: "click", selector: step.selector }) + "\n");
                break;
            case "select":
                await page.selectOption(step.selector, step.value, { timeout: navTimeout });
                process.stdout.write(JSON.stringify({ ok: true, index, action: "select", selector: step.selector }) + "\n");
                break;
            case "wait_for":
                await page.waitForSelector(step.selector, { state: "visible", timeout: navTimeout });
                process.stdout.write(JSON.stringify({ ok: true, index, action: "wait_for", selector: step.selector }) + "\n");
                break;
            case "read_text": {
                const text = step.selector
                    ? await page.locator(step.selector).innerText({ timeout: navTimeout })
                    : await page.evaluate(() => document.body?.innerText ?? "");
                process.stdout.write(JSON.stringify({ ok: true, index, action: "read_text", text }) + "\n");
                break;
            }
        }
    }
}

const wsEndpoint = `ws://127.0.0.1:${launchResult.port}${launchResult.wsPath}`;
let exitCode = 0;
let browser;
try {
    browser = await chromium.connectOverCDP(wsEndpoint, { timeout: navTimeout });
    const context = browser.contexts()[0] ?? (await browser.newContext());
    const page = context.pages()[0] ?? (await context.newPage());
    page.setDefaultTimeout(navTimeout);
    await configureIphone(page, context);

    const response = await page.goto(url, { waitUntil: "load", timeout: navTimeout });
    if (detectBlock) {
        const status = response?.status() ?? 0;
        const title = await page.title().catch(() => "");
        const body = await page.evaluate(() => document.body?.innerText ?? "").catch(() => "");
        const reason = initialBlockReason(status, title, body);
        if (reason) {
            exitCode = EXIT_BLOCKED;
            process.stderr.write(`biab-browse: initial navigation appears blocked (${reason}); no actions were executed\n`);
        }
    }

    if (exitCode === 0) {
        switch (verb) {
            case "read_text":
                process.stdout.write(await page.evaluate(() => document.body?.innerText ?? "") + "\n");
                break;
            case "click":
                await page.click(verbArgs[0], { timeout: navTimeout });
                process.stdout.write(JSON.stringify({ ok: true, action: "click", selector: verbArgs[0] }) + "\n");
                break;
            case "fill":
                await page.fill(verbArgs[0], verbArgs[1], { timeout: navTimeout });
                process.stdout.write(JSON.stringify({ ok: true, action: "fill", selector: verbArgs[0] }) + "\n");
                break;
            case "screenshot":
                await page.screenshot({ path: verbArgs[0] });
                process.stdout.write(JSON.stringify({ ok: true, action: "screenshot", path: verbArgs[0] }) + "\n");
                break;
            case "run":
                await runWorkflow(page, workflowActions);
                break;
        }
    }
} catch (error) {
    exitCode = EXIT_ACTION;
    process.stderr.write(`biab-browse: action failed: ${error?.message ?? error}\n`);
} finally {
    await browser?.close().catch(() => {});
    try { child.kill("SIGTERM"); } catch { /* ignore */ }
    await sleep(200);
    try { child.kill("SIGKILL"); } catch { /* already gone */ }
}

process.exit(exitCode);
