---
name: fact-checker
description: Verifies every factual claim in a draft (article, post, report, spec, or landing page) one by one against primary sources and returns a structured table with verdict, source, and minimal fix. Use when asked to fact-check, verify claims, audit numbers or sources, or before publishing data-heavy content.
---

# Fact Checker

Answers one question: **which claims in this text are backed by a primary source, and which are not?** Does not edit style, judge tone, or rewrite prose. Delivers verifiable evidence, claim by claim.

## When to Use

- The user pastes or points to a draft and asks to fact-check, verify claims, or audit numbers and citations.
- Before publishing an article, technical post, landing page, or strategy report that cites statistics, benchmarks, prices, or dates.
- `no-ai-slop` flags "weasel attribution" ("experts agree", "studies show") and you need to check whether a real primary source exists.
- A landing page or comparison table states pricing, discounts, availability, or benchmark figures.

## Procedure

1. **Extract.** List every verifiable claim: numbers, percentages, dates, names, quotes, prices, comparisons, causal claims ("X causes Y"), and superlatives ("the first", "the largest"). Author opinions are not fact-checked; mark them as opinion and leave them alone.
2. **Prioritise.** Check high-stakes claims first: money, legal/compliance, health/safety, third-party reputation, and the core figures that support the draft's thesis. If a draft has more than ~15 claims, verify the critical ones first and list the remainder as "not yet verified".
3. **Find a primary source.** In order of preference: original document (paper, official press release, statute/regulation, official report, release notes, vendor documentation), official statistics (national stats office, central bank, regulator, standards body), or a reputable primary report citing the original. Aggregators, social threads, or AI summaries are not primary sources. Use web search/browsing tools when available; if offline, check repository files and state explicitly what comes from local docs vs. unverified training memory.
4. **Compare literally.** The claim must match the source in magnitude, unit, time period, and scope. "40% of companies" and "40% of surveyed enterprises with 250+ employees" are not the same claim.
5. **Date every figure.** Record both the source publication date and the date checked. Exchange rates, pricing, and availability go stale quickly — note both dates.
6. **Never invent.** If you cannot find a primary source, the verdict is "Unsourced" — never "probably true". Do not fabricate a missing citation or suggest a guessed "approximate" number.

## Verdicts

| Verdict | Meaning |
|---|---|
| ✅ Confirmed | The primary source states exactly this claim |
| 🟡 Qualified | True only with a condition the draft omits (time period, sample size, geography, version) |
| ⚪ Unsourced | No primary source found; cannot be published as a stated fact |
| ❌ False | Contradicted by the primary source |
| 💬 Opinion | Author's judgement or value statement; not subject to fact-checking |

## Output Format

Return one table row per claim, in the order they appear in the text:

```markdown
| # | Claim (literal quote) | Verdict | Source (URL or doc + date) | Proposed fix |
```

Below the table, add at most three summary lines: count per verdict, the single riskiest claim if published as-is, and whether the draft is ready to publish. If every row is ✅ or 💬, state that in one sentence.

The "Proposed fix" is the minimal corrected phrase or qualifier needed — never a full paragraph rewrite.

## Scope Boundaries

- Does not edit style or voice — use `no-ai-slop` for prose cleanup.
- Does not decide whether to publish — delivers the evidence so the owner can decide. Exception: highlight any ❌ involving money, legal compliance, or health/safety on the very first line of the response.
- Does not verify software behaviour by executing code — use test suites and `sdd-qa` for that.
