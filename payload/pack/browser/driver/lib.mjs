// Builders in a Box browser pack — pure driver helpers (FEAT-030).
//
// Everything here is deliberately free of playwright, CDP and process state so
// the test harness can exercise it with plain `node` on any runner. browse.mjs
// owns the side effects (exit codes, stderr); this module only decides.

export const MAX_ACTIONS = 20;

// The maximum workflow we accept, in bytes. The wrapper reads one byte more
// than this so it can tell "exactly at the limit" from "over the limit".
export const MAX_WORKFLOW_BYTES = 65536;

export class WorkflowError extends Error {}

function requireString(value, label) {
    if (typeof value !== "string" || value.length === 0) {
        throw new WorkflowError(`workflow field '${label}' must be a non-empty string`);
    }
}

function rejectUnknownFields(step, allowed, index) {
    const unknown = Object.keys(step).filter((key) => !allowed.includes(key));
    if (unknown.length > 0) {
        throw new WorkflowError(`workflow action ${index} has unknown field '${unknown[0]}'`);
    }
}

// Validate the whole workflow before navigating anywhere (FEAT-030 R5). A
// workflow that is going to be rejected must be rejected without a browser
// ever starting — a half-run sequence of fills and clicks is exactly the
// failure this feature exists to avoid.
export function parseWorkflow(text) {
    let workflow;
    try {
        workflow = JSON.parse(text);
    } catch (error) {
        throw new WorkflowError(`invalid workflow JSON: ${error?.message ?? error}`);
    }
    if (!workflow || typeof workflow !== "object" || Array.isArray(workflow)) {
        throw new WorkflowError("workflow must be a JSON object");
    }
    const rootUnknown = Object.keys(workflow).filter((key) => key !== "actions");
    if (rootUnknown.length > 0) {
        throw new WorkflowError(`workflow has unknown field '${rootUnknown[0]}'`);
    }
    if (!Array.isArray(workflow.actions) || workflow.actions.length === 0) {
        throw new WorkflowError("workflow.actions must be a non-empty array");
    }
    if (workflow.actions.length > MAX_ACTIONS) {
        throw new WorkflowError(`workflow may contain at most ${MAX_ACTIONS} actions`);
    }

    workflow.actions.forEach((step, index) => {
        if (!step || typeof step !== "object" || Array.isArray(step)) {
            throw new WorkflowError(`workflow action ${index} must be an object`);
        }
        requireString(step.action, `actions[${index}].action`);
        switch (step.action) {
            case "fill":
                rejectUnknownFields(step, ["action", "selector", "value"], index);
                requireString(step.selector, `actions[${index}].selector`);
                if (typeof step.value !== "string") {
                    throw new WorkflowError(`workflow field 'actions[${index}].value' must be a string`);
                }
                break;
            case "click":
            case "wait_for":
                rejectUnknownFields(step, ["action", "selector"], index);
                requireString(step.selector, `actions[${index}].selector`);
                break;
            case "select":
                rejectUnknownFields(step, ["action", "selector", "value"], index);
                requireString(step.selector, `actions[${index}].selector`);
                requireString(step.value, `actions[${index}].value`);
                break;
            case "read_text":
                rejectUnknownFields(step, ["action", "selector"], index);
                if (step.selector !== undefined) requireString(step.selector, `actions[${index}].selector`);
                break;
            default:
                throw new WorkflowError(`unknown workflow action '${step.action}'`);
        }
    });
    return workflow.actions;
}

// Deliberately narrow (FEAT-030 R3). Returns a reason string only for an
// unambiguous interstitial served INSTEAD of the page, and null for everything
// else — including every case where trying another mode would be dishonest:
//
//   - A CAPTCHA is not a fallback trigger: an iPhone user agent does not solve
//     a challenge, and silently re-requesting it is the "keep hammering until
//     something works" behaviour this pack must not have.
//   - DNS, TLS, timeouts, 401/404/429/5xx are real answers from the site. They
//     are reported as themselves, never retried behind the user's back.
//   - An article containing the words "Access denied" is a page that loaded
//     fine. Hence the anchored title test below rather than a body search:
//     the title must be essentially nothing BUT the refusal.
export function initialBlockReason(status, title, body) {
    const sample = (body ?? "").slice(0, 12000);
    if (/captcha|verify you are human|challenge-platform/i.test(sample)) return null;
    if (/you(?:'|’)ve been blocked by network security|pardon our interruption|the requested url was rejected|this request has been blocked/i.test(sample)) {
        return "known block page";
    }
    const trimmedTitle = (title ?? "").trim();
    if (status === 403 && /^(access denied|forbidden)[.!\s-]*$/i.test(trimmedTitle)) {
        return `HTTP ${status} ${trimmedTitle}`;
    }
    return null;
}
