# Financial

> Snapshot of revenue + cost per project. Update monthly.
>
> Last updated: <DATE>

---

## Headline

- **Monthly recurring revenue:** _<amount>_ €/mo  (was _<amount>_ last month)
- **Monthly recurring cost:** _<amount>_ €/mo
- **Net per month:** _<amount>_ €/mo
- **Runway** (if pre-revenue): _<months>_ months at current burn

---

## By project

| Project | Revenue | Cost | Net | Notes |
|---|---|---|---|---|
| <project-1> | _<amount>_ | _<amount>_ | _<amount>_ | |
| <project-2> | | | | |
| <project-3> | | | | |
| **Shared infra** | — | _<amount>_ | (_<amount>_) | _hosting, APIs, etc._ |

---

## Cost breakdown (shared infra)

| Item | Monthly | Annual | Provider | Notes |
|---|---|---|---|---|
| _e.g. Cloudflare Workers_ | | | | |
| _e.g. Anthropic API_ | | | | |
| _e.g. domain renewals_ | | | | |

---

## How to use this file

- Update monthly during review. Don't fudge — `<verify>` is fine when you don't know.
- If "Shared infra" cost grows faster than per-project net for 3 months in a row, take it seriously and write an EXEC.
- Past months are archived as `reviews/<YYYY-MM>-financial.md`.
