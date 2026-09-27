---
name: whats-ahead
description: Narrative overview of how a Builders in a Box devbox is meant to be used day-to-day. Useful for a user who has completed setup, has tmux + Claude Code running, and wants to understand the shape of the system before they start working.
---

# /whats-ahead — the shape of your devbox in one walkthrough

When the user invokes this skill, you give them a 5-minute narrative tour of what they have and how to use it. Not a feature list. A story they can hold in their head.

## What to cover, in this order

### 1. Each tmux session is a context, not just a screen

Tell the user they're in a tmux session called `ai-platform`, opened in `~/ai-platform/` — the workspace root. It survives SSH disconnects, so they can leave and come back.

The model is **one session per context**, not windows inside one session:

- **`ai-platform`** — the session they start in. The workspace root: cross-cutting changes, the tutorial, deciding what to work on.
- **`<their project_name>`** — when they create their first project (via `/first-project`), it gets its **own** tmux session. The product, the code, the specs. This is where 80% of the time goes.

Each session is its own conversation with you (Claude), and each shows up as a separate remote session in the Claude Code app sidebar. Switch between them with `tmuxc <name>` (or `tmuxa` to jump back to `ai-platform`). It's like having a colleague per context, each remembering different threads.

### 2. The way work happens here is spec-driven (SDD)

Open a real description, not jargon:

> *The convention this device is opinionated about is: before writing code, write a short doc that says what you want and why. Then implement against the doc. The doc lives in the project's `specs/` folder.*
>
> *You don't have to write the doc alone. There are skills that play different roles to help you:*
>
> - `/sdd-coordinator` plays the Product Lead — helps you describe what you want
> - `/sdd-spec-writer` plays the Tech Lead — turns it into a technical plan
> - `/sdd-qa` plays QA — turns it into tests
> - `/sdd-growth` plays Growth — only when the feature is user-facing/marketing-relevant
> - `/sdd-docs` plans the docs you'll need to write after shipping
> - `/sdd-base` is the overview if any of this confuses you

Tell them they don't have to use these for tiny changes — a one-line bug fix doesn't need a spec. SDD is for features that take more than a couple hours.

### 3. Expert consultants on tap

> *When you have a real question — "is this the right architecture", "is this UI confusing", "how should we charge for this feature" — there are consultants you can call.*
>
> - `/backend-engineer` — Senior Backend perspective
> - `/ui-ux-consultant` — UI/UX advice
> - `/executive` — strategy, prioritization, hard trade-offs
> - `/product-marketing` — positioning, conversion, growth
>
> *They're not better than asking me directly. But they have a specific voice and lens, and sometimes that helps you see something you'd miss otherwise.*

### 4. Code-level tools

Light touch:

> *And for day-to-day code work:*
>
> - `/code-review` — pass me a diff or branch, get a structured review
> - `/code-simplifier` — refactors recent code for clarity
> - `/qa-testing` — generates test plans from specs
> - `/documentator` — generates technical docs

### 5. What's literally next on your plate

Direct them at the bundled spec:

> *In `~/ai-platform/projects/<their project>/specs/draft/` there's already one FEAT waiting: a Slack coach. The whole spec is written. You haven't decided to build it — that's up to you. But it's there as a starter project that shows the system end-to-end.*
>
> *If you want to walk through it, run `/first-project` (if you haven't already) or just say "show me the coach FEAT" and we'll go through it.*

### 6. Where to get help

On a **Claude Code** box:

> *If you ever feel stuck, type `/remote-control` in any of these tmux windows. It generates a link you can share — the other person sees your screen live and can take over. Useful for pair programming or when something's broken and "let me show you" beats explaining.*

On an **`agy`** or **codex** box there's no Remote Control link — pairing is plain tmux: a second person SSHes into the box and runs `tmux attach -t <name>`, and you both drive the same screen. (Read the box's CLI with `jq -r '.ai_cli // "claude"' /var/lib/buildersinabox/state.json`; on codex, invoke every skill named here as `$name` rather than `/name`.)

End there. Don't list every skill in the bundle — they can `/help` or just type `/` to discover.

## Tone

Narrative, not bullet-listy. The user wants to feel oriented, not briefed. Use "you", be direct, don't oversell.

## Length

Aim for ~400 words total when you say this out loud. If they ask follow-ups, expand. If not, stop talking.
