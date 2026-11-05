---
name: whats-ahead
description: Narrative overview of how a Builders in a Box devbox is meant to be used day-to-day. Useful for a user who has completed setup, has their AI agent running, and wants to understand the shape of the system before they start working.
---

# /whats-ahead — the shape of your devbox in one walkthrough

When the user invokes this skill, you give them a 5-minute narrative tour of what they have and how to use it. Not a feature list. A story they can hold in their head.

## What to cover, in this order

### 1. Each workspace is a context, not just a screen

Tell the user they're in a workspace called `ai-platform`, opened in `~/ai-platform/` — the workspace root. It keeps running on the box when they close the app, so they can leave and come back.

The model is **one workspace per context**:

- **`ai-platform`** — the one they start in. The workspace root: cross-cutting changes, the tutorial, deciding what to work on.
- **`<their project_name>`** — when they create their first project (via `/first-project`), it gets its **own** workspace. The product, the code, the specs. This is where 80% of the time goes.

Each workspace holds its own conversations with you, and each project shows up as a separate item in the Paseo app. Switching context is opening another workspace. It's like having a colleague per context, each remembering different threads.

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

Look at where their first project stands, not at a fixed answer:

```bash
BP=/opt/buildersinabox/payload/scripts/biab-project
"$BP" progress get
```

If that prints a template and project, run `"$BP" status "<project>"` and say it in plain words:

> *Your project `<project>` is at the "<step>" step: <what is next, in one line>. Say `/first-project` and I'll pick up exactly there.*

Where `status` says `complete`, the first walk is done: point at `/second-project` for the next bigger one, or at `/sdd-coordinator` to start a feature of their own.

If there is no progress yet and no project, the next thing on their plate is `/first-project`: one idea, a spec they write with you, and a pull request waiting for them.

### 6. Where to get help

If something is broken, the quickest help is to paste the error here and let you and me look at it together. Read the box's CLI with `jq -r '.ai_cli // "claude"' /var/lib/buildersinabox/state.json`; on codex, invoke every skill named here as `$name` rather than `/name`.

If the app can't reach the box, `biab status` on the box says why and prints the SSH command that still works.

End there. Don't list every skill in the bundle — they can `/help` or just type `/` to discover.

## Tone

Narrative, not bullet-listy. The user wants to feel oriented, not briefed. Use "you", be direct, don't oversell.

## Length

Aim for ~400 words total when you say this out loud. If they ask follow-ups, expand. If not, stop talking.
