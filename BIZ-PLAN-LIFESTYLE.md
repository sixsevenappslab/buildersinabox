# BIAB — Lifestyle Business Plan

> Owner: Jesus (solo). Drafted 2026-05-31 after multi-agent research + portfolio audit.
> Target: 5–10 k EUR MRR within 18-24 months, working ≤15 h/week on BIAB.
> Status: planning. Not yet committed.

---

## 0. TL;DR (read this if nothing else)

**What the market says (validated):** the BIAB thesis is real and the audience is loud. Eight Show HN launches in 12 months attack the "Claude Code from phone" problem; none ship hardware or zero-touch setup. Hardware consensus is forming around €400-700 mini PCs (Beelink SER, GMKtec EVO-X2) and the workaround everyone uses is a brittle Tailscale + tmux + Termius stack that takes ~1 hour to set up. **Real gap, real demand, narrow window** (Replit could pivot to BYOH; Anthropic could partner with a hardware OEM).

**What the math says (sobering):** €10 k MRR solo in <24 months is a stretch. Plausible took 2 years with **two** founders to hit $10 k MRR. Realistic for BIAB: **€2-5 k MRR in 18 months, €5-10 k in 24-36** if execution is sharp.

**What Jesus's capacity says (constraining):** real productive time is ~10-15 h/week across the entire portfolio. Adding BIAB requires killing or starving something. Most plausible candidates to downgrade: Chordna (3% → 0%, archive), Ganga24 (20% → 5%, maintenance only), SOFI (already 0%). Hezu stays the caballo principal but drops 60% → 45%.

**What to do:** ship BIAB OSS in 4 weeks (no commitments yet). After 6 weeks measure: ≥500 GitHub stars + ≥10 paying beta users. If yes → commit to subscription tier. If no → keep as portfolio asset + LinkedIn authority play, no business.

**The non-obvious insight:** Jesus's biggest underutilized asset is his 8 k LinkedIn following in marketing/analytics. Hezu deliberately doesn't leverage it (separate brand). BIAB is the project that **could** leverage it — same audience persona (mid-senior tech professionals with money + curiosity). The biz plan only works if this asset gets unlocked.

---

## 1. Market reality (condensed from research agents)

### 1.1 The pain is real and the workaround is the same everywhere
Every guide to "Claude Code from the phone" converges on the same stack: Tailscale + tmux + Termius/Mosh + ntfy + brittle keychain workarounds. Average setup time: ~1 hour for an experienced dev. Average maintenance pain: laptop sleeping, keychain breaking, firewall blocking SSH. Top quote (kareemf.com): *"if I'm nap-trapped by my sleeping infant, sending commands from my phone doesn't disrupt her."*

### 1.2 The audience is vocal and the segment is identifiable
- HN "Local AI needs to be the norm": **1,340 points / 323 comments**.
- 8+ Show HN launches in 12 months in adjacent space (Omnara, Happy Coder, Catnip, Sled, Claude Remote, etc.) — **none bundle hardware or zero-touch setup**.
- Hardware consensus forming on r/LocalLLaMA + r/selfhosted: GMKtec EVO-X2, Beelink SER10 MAX at €400-€1500.

### 1.3 Competitive map (May 2026)
| Product | Mobile/RC story | Pricing | Hardware bundled? |
|---|---|---|---|
| Claude Code + Remote Control | Native (Feb 25, 2026) | $20-200/mo | No — your machine |
| Replit Agent + Mobile | Cloud-native | $25-100/mo | No — cloud |
| Cursor + Remote Agents | Cloud agents (April 2026) | $20-200/mo | No — cloud |
| Codex CLI + ChatGPT Mobile | Cloud (May 2026) | $20-200/mo | No — cloud |
| OpenHands self-host | Web UI, DIY | Free | No — DIY |
| Coder Agents | Enterprise self-hosted | Sales-led | No — your infra |
| Tabby | Self-host code completion | Free | No — DIY |
| **BIAB v0.1 → OSS** | **CLI + Remote Control via own box** | **Free + cloud SaaS €12-29** | **Optional bundle** |

**Nobody combines (a) hardware-ready zero-touch + (b) own-your-stack runtime + (c) mobile-first access** for individuals/prosumers.

### 1.4 The narratives alive on X/social
- **DO use:** "Anthropic shipped the phone client. We shipped the server." Frame as **craft, control, ownership** (Framework laptop vibe).
- **DON'T use:** "anti-Anthropic", "sovereignty/privacy", "vibe coding" — all are landmines in dev influencer circles in 2026.
- The dominant flex on dev X: *"I run N Claude Code sessions from my phone"* — BIAB's exact UX.

### 1.5 Anthropic ships Remote Control for free — what's BIAB's wedge?
Three things, ordered by how marketable each is:
1. **Your laptop shouldn't be the always-on server.** (sleeps, battery, portability, noise) — strongest emotional sell
2. **Provisioning is the gap.** ~1 hour of yak-shaving → 15 min plug-and-play with USB
3. **Future model agnosticism.** Same box can run local LLMs (Qwen, Llama) when you want privacy — hedge for r/LocalLLaMA purists

---

## 2. Jesus's actual capacity (from local audit)

### 2.1 Last 90 days
- **965 total commits** across ai-platform (10.7/day average, but lumpy)
- Weekly cadence: 9-180 commits/week, average ~70-90 when active
- **70% weekdays, 29% weekends** — works regularly through the week (mostly late nights)
- Peak hours: 22:00-01:00 (post-family-bedtime) + lunch slots
- **~50% commits under Jesus name** (rest under AI agents he orchestrates)

### 2.2 Stated tesis vs reality (from `stratops/PORTFOLIO.md` + May review)
| Project | Tesis 12m | Actual May | Status |
|---|---|---|---|
| Hezu-es (caballo) | 60% | **~25%** | Underweight (FEAT-026 blocker) |
| Ganga24 (cash cow) | 20% | ~15% | Close |
| Conerator (infra) | 8-10% | ~5% | Underweight |
| Observio (infra) | 5% | **~40%** | **Way overweight** (eating Hezu time) |
| SixSeven (brand) | 4% | ~1% | Coherent |
| Chordna (sandbox) | 3% | ~5% | Slightly high |
| SOFI | 0% | ~5% | Slightly high |
| **BIAB** | **0%** | **N/A** | **Not in plan** |

### 2.3 Operating constraints (from `stratops/OPERATING-MODEL.md` §0.5)
- **Day job: Head of Data + Measurement at Google España & Portugal.** Full-time. Covers €100k/yr family expenses.
- **Time available: ~10-15 h/week realistic for the ENTIRE portfolio.** Nights + weekends. No "deep morning."
- **No financial runway pressure** — but coste de oportunidad por hora alto.
- **Underutilized professional assets:** 8k LinkedIn in marketing/analytics; public authority on data privacy + AI; access to measurement/paid acquisition best-practice.
- **Explicit decision: LinkedIn personal NOT used for side projects.** Documented in EXEC-004.

### 2.4 FEAT throughput
- ~108 completed FEATs across 12-18 months of portfolio activity
- Average **6-9 FEATs/month total** across the whole portfolio (with Claude Code doing 50%+ of the typing)

### 2.5 Capacity verdict
**BIAB at ~15h/week (consistent) = 30-50% of total portfolio capacity.** This is non-trivial. Cannot be added on top; must displace.

---

## 3. Strategic fit: BIAB vs existing portfolio

### 3.1 The honest conflicts
- **Time:** BIAB at 25-35% time forces another project below its tesis target.
- **Tesis:** Existing tesis is "Jesús es la persona que mejor entiende crianza positiva con IA en España e Iberoamérica." BIAB is a developer-tools play. **Two tesis-es is one too many for a solopreneur.**
- **Distribution:** Already "día 0 de distribución" on Hezu (per May review). BIAB starts at día -1 (zero brand in the dev-tools space).
- **LinkedIn rule:** "no apalancar LinkedIn personal en side projects" actively prevents the highest-leverage acquisition channel for BIAB.

### 3.2 The honest synergies
- **Asset fit:** BIAB target audience (mid-senior tech devs) overlaps 70%+ with Jesus's LinkedIn following (marketing/analytics — many are tech-adjacent).
- **Existing skill set:** SDD workflow, agent orchestration, multi-project ops — all directly transferrable to BIAB's value prop.
- **Existing infra:** Conerator (content generation engine) could produce BIAB marketing content at low marginal cost.
- **Existing community:** stratops + sdd skills are already documented and demoable.

### 3.3 Recommended portfolio rebalance (if BIAB goes ahead)
This requires a new **EXEC-NNN** decision. Proposed:

| Project | Current tesis | Proposed | Action |
|---|---|---|---|
| Hezu-es | 60% | 45% | Stays caballo. Less new feature work, more measurement + content (Conerator-fed) |
| **BIAB** | **0%** | **25%** | **New** — promoted to second pillar |
| Ganga24 | 20% | 10% | Downgrade — maintenance + monetization measurement only, no new features |
| Conerator | 8-10% | 8% | Stable |
| Observio | 5% | 5% | Stable (Q3 down from current 40%) |
| SixSeven | 4% | 2% | Maintenance only |
| Chordna | 3% | 0% | **Sunset active dev.** Documented learnings → archive. |
| SOFI | 0% | 0% | Already done |

**Total = 95%. Reserve 5% for life/emergencies.**

### 3.4 The tesis upgrade
Current: *"Jesús es la persona que mejor entiende crianza positiva con IA en España e Iberoamérica."*

Proposed: *"Jesús construye productos y herramientas para dos audiencias subatendidas: (1) padres hispanohablantes que quieren IA en su crianza; (2) developers indie que quieren su propio entorno AI de desarrollo, en su hardware, accesible desde el móvil."*

This explicitly licenses the LinkedIn-for-BIAB channel (separate brand framing: same Jesús, two distinct audiences).

### 3.5 The fail-safe
If after 12 months BIAB is below the "go" thresholds (see §7), **archive it as a portfolio asset (GitHub stars + LinkedIn authority + portfolio piece) without continued investment**. Cost of failure: 12 months of 25% allocation = ~150-200 h. Not catastrophic if Hezu doesn't regress (the bigger risk).

---

## 4. Product positioning

### 4.1 The one-liner
*"Plug in a USB. 15 minutes later you're coding from your phone — on a mini PC that's yours, with Claude (or any AI CLI) ready to ship products."*

### 4.2 Three tagline variants for testing
- **Craft:** *"Your AI dev box. Plug in, ship from anywhere."*
- **Control:** *"Anthropic shipped the phone client. We shipped the server."*
- **Outcome:** *"Hammock-driven development, in 15 minutes."*

### 4.3 ICP (Ideal Customer Profile)
**Primary:** Mid-senior dev (5+ years), indie hacker or side-project founder, has a Claude Max/Pro subscription, frustrated with laptop-as-server, lives in CET/UTC/PST. Spends €20-30/mo on dev tools easily. Has phone-first life realities (kids, travel, etc.).

**Secondary:** Tech-curious non-devs in adjacent fields (analytics, PM, data) who want to learn agent-orchestration on their own setup. Jesus's LinkedIn following maps to this.

**NOT the buyer:**
- r/LocalLLaMA privacy purists (they want local models, BIAB v1 is Claude-bound)
- Enterprise teams (different sale, different product)
- Total beginners (BIAB assumes basic Linux + git literacy)

### 4.4 What BIAB is NOT
- Not an IDE (Cursor, Windsurf, Antigravity)
- Not a cloud dev environment (Replit, Codespaces)
- Not anti-Anthropic (we run their tools beautifully)
- Not a hardware company (yet)
- Not enterprise (yet)

---

## 5. Pricing model

### 5.1 Three tiers, BYO-key by default
| Tier | Price | Who | What they get |
|---|---|---|---|
| **OSS / Self-hosted** | Free | Tinkerers, privacy max | Full agent, all skills, AGPL relay code, community Discord |
| **Cloud** | **€12/mo** or €108/yr (25% off) | Solo devs who want zero-ops | Hosted pairing relay, OTA skill updates, mobile dashboard, BYO API key, email support 48h |
| **Pro** | **€29/mo** or €290/yr | Pro devs, freelancers, founders | Cloud + premium skill packs (deploy-ops, sdd-suite, security-review), priority support 24h, multi-device sync, early access |
| **Team** (defer to month 9+) | €19/user/mo (min 3) | Small studios | Shared skills + audit log + SSO |

### 5.2 Why BYO-key
The math: AI infra cost = €0.05-0.30 per "coding session." If BIAB bundles credits, every active user eats 60-100% of their MRR contribution. **Never become Anthropic's reseller.** BYO-key keeps gross margin >85% (relay infra ~€0.50/user/mo Cloudflare + DB).

### 5.3 The "100 customer" model
| Tier | Customers | ARPU | MRR |
|---|---|---|---|
| Cloud €12 | 65 | €12 | €780 |
| Pro €29 | 30 | €29 | €870 |
| Team €19/seat (3-seat avg) | 5 × 3 | €19 | €285 |
| **Total** | **100 paying** | €19.35 blended | **€1,935 MRR** |

**€5k MRR target ≈ 260 paid (~25-50k OSS funnel). €10k MRR ≈ 520 paid (~50-100k OSS funnel).**

### 5.4 Hardware bundle (defer to month 9+)
- **"Convenience pack":** preflashed mini PC + USB + welcome card, €450-650
- Margin: 5-15% on hardware (don't make this a profit center)
- Logistics: dropship via partner (no inventory) or batch-fulfill 20/month max
- Only viable once Cloud/Pro is humming (else returns + RMA bury you)

### 5.5 B2B services angle — implementation + retainer (added 2026-07-08, post-gate)
Idea from Jesús: small businesses as buyers of *outcomes*, not boxes. ~1 month of implementation
(automating one painful process on a BIAB box installed on-premise) + monthly retainer ("iguala").

- **Why it's interesting:** fixes the buyer problem of the hardware play — the SMB pays for the
  result (€1,500-3,000 setup + €150-400/mo retainer), the mini PC becomes the delivery vehicle
  ("your server, your office, your data never leaves"). Hardware on-demand, never inventory
  (council decision 2026-07-07).
- **Why it's dangerous:** the retainer is a perpetual manual obligation. Only compatible with the
  operating model if priced for near-zero maintenance (robust automations + observio-style
  monitoring + ≤2h/mo per client assumed in the fee). Otherwise it's a second job.
- **Status:** NOT for v1 launch — this is a separate business (automation agency using BIAB as
  infra) competing for the same hours. Validation first, zero build: Jesús sounds out 2-3 SMBs
  from his network (July 2026). Needs a named business with a named process willing to pay
  before designing anything. Evaluate against the 6-week gate outcome.

---

## 6. Go-to-market sequence

### 6.1 Pre-launch (4 weeks)

**Week 1 — Decide & name**
- [ ] Confirm "Builders in a Box" is available (search USPTO, EUIPO, domains: buildersinabox.dev/.com/.org)
- [ ] If taken → alternatives: "BIAB", "Build Box", "Build Server", "Pocket Dev", "Sidekick Box"
- [ ] Squat GitHub org + buy domain
- [ ] Write `VISION.md`, `ROADMAP.md`
- [ ] EXEC-NNN: portfolio rebalance (tesis upgrade)

**Week 2 — De-personalize codebase**
- [ ] `paco` → `${BIB_USER}` (default: current user)
- [ ] "Paco" → `${BIB_NAME}` (default: empty → "builder")
- [ ] All Spanish copy → English (Spanish becomes future i18n)
- [ ] Replace gift-specific copy with generic
- [ ] `gift/` → `flavors/gift/` (opt-in build flag)
- [ ] Inversión arquitectural: `bootstrap.sh` se vuelve `install.sh` (installer-first; ISO-builder queda como flavor opcional)
- [ ] Add `--non-interactive`, `--uninstall`, `--update` flags
- [ ] User detection (no asume paco)
- [ ] Idempotency hardening for "running on existing Ubuntu"

**Week 3 — Polish + first artifacts**
- [ ] Test install on 2-3 different Ubuntu setups (fresh, existing, VM, VPS)
- [ ] Record demo: 60-second screencast of `curl | bash` → 15 min later attached from phone
- [ ] Write the README (1-page hook + quickstart + "what you need")
- [ ] CONTRIBUTING.md, CODE_OF_CONDUCT.md, LICENSE confirm MIT
- [ ] Issue/PR templates
- [ ] `biab diagnostic` command for bundling logs

**Week 4 — Build in public**
- [ ] First X/LinkedIn posts: "I'm shipping in 2 weeks. Here's what I'm building." Daily progress screenshots.
- [ ] Pre-line up 30 Product Hunt hunters from your network
- [ ] DM Tier 1 influencers (@bcherny, @simonw, @apenwarr, @dhh) — NOT pitch, just "you write about X, curious what you'd break in this"
- [ ] Open Discord/Discussions
- [ ] Build email waitlist (500+ target)

### 6.2 Launch (Day 0)
**09:00 ET** — Show HN: *"Builders in a Box – plug in a USB, get Claude Code on a mini PC reachable from your phone in 15 min"*
**09:05 ET** — X thread (Template A: 9-tweet setup show-and-tell, screenshots only)
**09:30 ET** — Product Hunt launch with founder comment hour 1
**Throughout day** — respond to every HN comment in <20 min. Quote-tweet every X reply.
**17:00 ET** — "What didn't work" thread (vulnerability template, 2x first-day numbers historically)
**21:00 ET** — LinkedIn post (test the channel for the first time — separate brand framing per the new tesis)

### 6.3 First 30 days (post-launch)
**Daily:** ship-log tweet ("Day N: fixed UEFI boot on Beelink, added Qwen Code option")
**3x/week:** Template C (mobile coding from somewhere — recruit early users to post)
**1x/week:** Template B (productivity claim with receipts — needs real numbers)
**Weekly:** recap thread (stars, users, MRR, lessons)
**Week 2:** YouTube long-form, pitch Fireship for 100s video
**Week 3:** hardware partner outreach (Beelink, GEEKOM — they want indie-dev halo)
**Week 4:** AMA on r/selfhosted + r/homelab, "30 days in" relaunch on PH

### 6.4 Months 2-6 (consolidation)
- Weekly cadence: 1 ship, 1 write, 1 engage (depth)
- Month 2-3: build the Cloud relay tier (the SaaS layer)
- Month 4: launch Cloud tier publicly. Target 20-40 paid in 30 days.
- Month 5-6: launch Pro tier with premium skills. Target additional 10-20 Pro.
- Continuous: engage every Tailscale, opencode, Aider thread on X with substantive replies (not links)
- Content engine: 1 long-form article/month + Conerator-generated social variants

---

## 7. Year 1 milestones & go/no-go gates

### Month 1 (Launch)
- ✅ 500+ GitHub stars
- ✅ 1,000+ HN points (any post)
- ✅ Featured on Product Hunt (top 5 of day)
- ✅ 50+ Discord members
- ✅ 500+ email waitlist (built pre-launch)
- 🟡 First 100 self-installs (proxy via diagnostic ping if opt-in)

### Month 3 (early product-market signal)
- 1,500+ GitHub stars
- 200+ active installs (diagnostic ping)
- 20+ "I love this" community testimonials
- Cloud tier built, in private beta with 20 testers

### Month 6 (the GO/NO-GO gate)
**Continue if all three:**
1. ≥3,000 GitHub stars
2. ≥40 paying customers (€700+ MRR)
3. Positive net adds 3 months in a row

**Kill / pivot if:**
- <1,500 stars AND <15 paying customers → wedge isn't sharp; pivot or stop
- Churn >10%/mo after month 4 → product doesn't stick

### Month 12 (lifestyle viability gate)
- ≥10,000 GitHub stars
- ≥200 paying customers (~€4,000 MRR)
- Pro tier validated (premium skills working)
- Stripe/Lemon Squeezy revenue clean
- **If <€2,000 MRR by month 12: this is a hobby, not a business**

### Month 18 (the realistic €5k target)
- ≥250 paying customers (~€5,000 MRR)
- Healthy churn (<5%)
- 2-3 premium skill packs selling
- Hardware convenience pack in private beta

### Month 24 (the stretch €10k target)
- ≥520 paying customers (~€10,000 MRR)
- Team tier launched
- Hardware bundle delivering 10-20 units/month
- Possible co-founder conversation (if growth >€1k MRR new/month)

---

## 8. Revenue projection — three scenarios

### Base case (realistic execution, no virality)
| Month | OSS users | Paying | MRR |
|---|---|---|---|
| 1 | 1,000 | 5 | €70 |
| 3 | 3,000 | 25 | €450 |
| 6 | 6,000 | 60 | €1,200 |
| 12 | 12,000 | 180 | €3,500 |
| 18 | 20,000 | 280 | €5,500 |
| 24 | 30,000 | 400 | €8,000 |

### Upside case (HN front page hit + Fireship video)
| Month | OSS users | Paying | MRR |
|---|---|---|---|
| 1 | 5,000 | 30 | €450 |
| 3 | 12,000 | 120 | €2,200 |
| 6 | 20,000 | 250 | €4,800 |
| 12 | 40,000 | 500 | €9,800 |
| 18 | 60,000 | 700 | €14,000 |

### Downside case (slow burn, no viral moment)
| Month | OSS users | Paying | MRR |
|---|---|---|---|
| 6 | 2,000 | 15 | €300 |
| 12 | 5,000 | 60 | €1,200 |
| 18 | 8,000 | 120 | €2,300 |
| 24 | 12,000 | 180 | €3,500 |

**Downside case is below "kill" threshold by month 18. Plan to accept that risk or have an alternate use for BIAB (portfolio asset, personal brand vehicle).**

---

## 9. Cost structure & profitability

### 9.1 Monthly operating cost (steady state)
| Item | Cost |
|---|---|
| Spain autónomo cuota (year 1 tarifa plana) | €88 |
| Gestor (accounting) | €100 |
| Cloudflare R2 + Workers + DNS | €20 |
| Database (Supabase Free tier → Pro) | €0-25 |
| Lemon Squeezy MoR fees (5% + $0.50/tx) | ~5-8% of revenue |
| Domain + SSL | €1 |
| Email (Resend, transactional) | €20 |
| Monitoring (Better Stack) | €0-29 |
| **Fixed monthly floor** | **~€260** |
| **Variable (5-8% of revenue for MoR)** | proportional |

### 9.2 Break-even points
- **Cover costs only:** ~€280/mo MRR
- **Replace mid-tier dev consulting income** (€2.5k/mo take-home, after Spain tax ~50% on autónomo profits): ~€5k MRR
- **Replace Google day-job salary** (Head of role probably €80-120k base): ~€20-30k MRR — **not the goal**

### 9.3 What success looks like (lifestyle definition)
- €5k MRR sustained = ~€2.5k/mo personal income after Spain tax/cuota
- ~10-12 h/week sustained on BIAB (down from launch sprint)
- Compound: keeps growing 3-5% MoM organically without effort
- Position: "Jesús es el indie que construyó BIAB" enters his professional identity
- Optionality: if Google day-job changes, this is real income to fall back on
- Identity: provides the "build something of yours" satisfaction that's hard to get at Google

---

## 10. Risks & mitigations

| Risk | Probability | Mitigation |
|---|---|---|
| Anthropic deprecates `--remote-control` flag | Medium | Pin claude-code version. CI canary tests daily. Multi-CLI bet (Gemini, Codex) as hedge. |
| Replit pivots to "BYO hardware" (kills BIAB wedge) | Medium-Low | Move fast. Build community moat. Hardware bundle creates physical brand. |
| HN launch flops (no virality) | Medium | Build email waitlist of 500+ pre-launch. PH backup channel. Reddit/IH compounding. |
| Time conflict eats Hezu (existing caballo) | High | EXEC document rebalance BEFORE launching. Hezu kill criteria already exists; don't blur it. |
| Churn higher than expected (>10%/mo) | Medium | Annual plans aggressive (25% off → effective halving of churn math). Build switching cost via stored skills/configs. |
| BYO-key UX is too friction-y | Medium | Onboarding wizard handles key collection. Test with 10 real users in private beta. |
| Solo founder burnout at 18 months | High | Set hard cadence (no work after 23:00). Sunday off. Quarterly review against this doc — kill or rebalance. |
| LinkedIn channel doesn't activate | Medium | Test with 3 careful posts in week 4 pre-launch. If <100 reactions, plan B = pure HN/X reliance. |
| Spain VAT / autónomo legal headaches | Low | Lemon Squeezy MoR handles VAT. Gestor handles tax. €100/mo well spent. |

---

## 11. The hard question: what to do if BIAB succeeds beyond plan?

**If at month 18 you're at €8-10k MRR and growing 5-10% MoM**, the lifestyle business is doing its job. But that growth rate naturally pushes toward "real business" territory — which conflicts with the Google day job + the parenting reality + the family-time priority.

**Pre-commit now to the decision criteria for that fork:**
- **If €10k MRR + 100h/mo demand → reduce Google to 80% or part-time.** Negotiate or leave.
- **If €15k MRR + 150h/mo demand → take a co-founder OR raise capital OR keep capped.** Don't accept the "accidental startup" trap.
- **If anything pulls you below 50% Hezu time for 3+ months → renegotiate tesis again.** Hezu must remain the caballo until its kill criteria fires (or BIAB explicitly replaces it as caballo via EXEC).

**Default decision: cap BIAB at €10k MRR scope and keep it lifestyle.** Hire help at €5k+ MRR if needed (VA for support, maybe a part-time engineer for skill packs).

---

## 12. Next 7 days — concrete actions

If you decide to commit, here's what week 1 looks like:

### Day 1 (Sunday)
- [ ] Read this plan. Sleep on it. Decide go/no-go.
- [ ] If go: open `EXEC-005-biab-portfolio-rebalance.md` in stratops/decisions/. Draft.

### Day 2 (Monday — evening 1h)
- [ ] Name + domain search:
  - GitHub: `github.com/builders-in-a-box` (free?)
  - Domains: `buildersinabox.dev`, `.com`, `.org`, `.io`
  - Trademark search USPTO + EUIPO
- [ ] If "Builders in a Box" is clear → squat. If not → brainstorm 5 alternatives, sleep on it.

### Day 3 (Tuesday — evening 1h)
- [ ] Write `VISION.md` (what is BIAB, what it isn't, who it's for)
- [ ] Write the FIRST tweet of build-in-public (don't publish yet)
- [ ] Draft EXEC-005 portfolio rebalance

### Day 4-5 (Wed-Thu — 2h)
- [ ] Start the de-personalization refactor:
  - `paco` → `${BIB_USER}`
  - "Paco" → `${BIB_NAME}` (with default empty)
  - Spanish → English in wizard
- [ ] First clean install test on a fresh Ubuntu VM or Multipass

### Day 6-7 (Weekend — 4-6h)
- [ ] Finish de-personalization
- [ ] Inversión arquitectural: `bootstrap.sh` deja de asumir firstboot.pending y se vuelve installer-first
- [ ] Public-ready repo (private still, but as if public): README, LICENSE, CONTRIBUTING

By next Sunday: BIAB OSS-ready in a private repo, ready for week 2 (polish + first public artifact).

---

## 13. The one thing this plan is honest about that hurts

You already have a `caballo principal` (Hezu) that you decided is your big bet. The kill criteria for Hezu is *"if after 12 months with funnel measuring + Meta Ads active there's NO >100 MAU sustained nor paywall conversion signal → replantear tesis solopreneur entera."* That kill criteria fires around **May 2027**.

**Starting BIAB now means competing with Hezu for time precisely in the window where Hezu most needs focus to hit its kill criteria fairly.** If Hezu fails by May 2027 *because BIAB stole its momentum*, you'll never know if Hezu would have made it.

The clean answer: **don't start BIAB seriously until Hezu either (a) hits >100 MAU sustained + paywall signal (success — Hezu is on rails, BIAB becomes the second pillar), or (b) fails the kill criteria (BIAB becomes the new caballo)**. Both scenarios resolve in 12 months.

The "have your cake" answer: **do BIAB OSS only (no SaaS) for the next 12 months while Hezu plays out**. Ship Phase 0-2 of BIAB. Generate stars + LinkedIn authority. Don't build the Cloud tier yet. If Hezu wins, BIAB stays an OSS asset. If Hezu loses, BIAB pivots to SaaS at month 12 with a 12-month head start in audience.

**This is probably the right answer.** It accepts the 18-24 month timeline to €5k MRR but doesn't risk Hezu. And it's honest about the constraint: you cannot run two new SaaS plays simultaneously with 10-15h/week.

---

## Appendix: research sources

- Market research agent report (Reddit, HN, IH): 28 sources
- Competitor landscape agent report: 36 sources
- Pricing benchmarks agent report: 23 sources
- X/Twitter discourse agent report: 32 sources
- Local audit: `~/ai-platform/stratops/OPERATING-MODEL.md`, `PORTFOLIO.md`, `reviews/2026-05.md`, git logs across 8 projects, 90-day commit analysis

(Full agent reports archived in `~/.claude/projects/-home-jesus-ai-platform-projects-buildersinabox/tasks/*` for reference.)
