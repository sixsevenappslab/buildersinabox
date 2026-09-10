# FEAT-029: User-owned cloud bootstrap, preserving provider access

## Metadata

- **Proyecto:** buildersinabox
- **Prioridad:** alta
- **Complejidad:** media
- **Presupuesto de ejecucion:** max_turns=90 timeout=3600
- **E2E mode:** curl (real Ubuntu 24.04 x86-64 VPS, human OAuth, second SSH session and reboot)
- **Reconciliation owner:** sdd-coordinator
- **Fase:** requisitos
- **Creado:** 2026-09-05
- **Actualizado:** 2026-09-05
- **Validado por Jesus:** [ ] Implementation intent authorized on 2026-09-05; the concrete cloud SSH policy below requires explicit review before implementation.
- **Agent scope decision:** Confirmed by Jesus on 2026-09-05: do not introduce Hermes in BIAB. Use the official coding CLIs; existing adapters remain unchanged.

## Definition of Ready (DoR)

- [x] Explicit problem, intent, observable user story and EARS requirements.
- [x] Existing paths inspected; installation, update and uninstall included.
- [x] Bounded tasks, risks, QA and delivery gates defined.
- [x] Growth and documentation impact defined.
- [x] Hermes excluded from BIAB by the owner; no Hermes installation, adapter, optional pack or dependency in this cloud path.
- [ ] Explicit review of the proposed persisted cloud profile: preserve provider SSH, socket activation, authorized keys and firewall; do not enable passwords or automatically bind SSH to Tailscale.
- [ ] Confirm initial target/policy before the real delivery test: user-owned AWS Lightsail, Ubuntu 24.04 x86-64, 8 GB target; no resource creation or spending is authorized by this spec alone.

Proposed initial mobile path: Claude Code Remote Control after native authentication. Using SSH from the phone, including for Codex, requires the owner to have a usable SSH key on the phone; this feature must not restore password auth as a shortcut. After verifying tailnet access, the owner may explicitly remove the public TCP/22 rule in the provider console. That action is manual and must be tested before claiming private-only access.

This draft is not an implementation-ready spec. Do not infer security approval from the request to implement the overall vision.

## 1. Requisitos

### Problema

A user who wants an always-on coding agent currently has to prepare hardware or provision Ubuntu and drive the installer manually. A cloud instance removes the USB/display/firmware work, but simply running the existing installer in cloud-init is unsafe: `install/50-ssh.sh` enables password authentication and changes SSH activation even with `--skip-wizard`.

### Intent (why)

Validate BIAB independently of acquiring a mini PC. Keep the machine, billing and provider account under the user's control, with one BIAB codebase for dedicated hardware and an explicitly supported cloud path. This is not a managed hosting business.

### Historias de usuario

- As an existing coding-agent user, I can provision an Ubuntu VPS with a reviewed startup payload, finish my own logins, and start a useful task from my phone without preparing physical media.
- As the machine owner, I can retry, update or remove BIAB without losing the provider's SSH recovery access or enabling password login on its public interface.

### Requisitos funcionales (EARS)

- [ ] **RF-1:** When the operator supplies the source release, expected source commit and existing target username, the renderer shall emit cloud-init user-data offline; it shall not invoke AWS/GCP APIs, install tools locally or read local credentials.
- [ ] **RF-2:** When the cloud instance first boots, the bootstrap shall verify Ubuntu 24.04 x86-64, an existing non-root target user and the requested source identity before invoking BIAB. Mutable/unverified source, malformed values or unavailable source shall fail with a non-secret diagnostic, not fall back to `main`.
- [ ] **RF-3:** While the persisted install profile is `cloud`, install, wizard, update and uninstall shall preserve provider-owned SSH configuration, authorized keys and SSH activation. They shall never enable password authentication, install console autologin, introduce firewall management (the payload has none today) or silently apply the dedicated-box network policy.
- [ ] **RF-4:** When unattended preparation completes, the instance shall report `awaiting-owner-setup`, not `ready`. It shall perform no Tailscale login, AI login, GitHub login or unattended agent invocation; no auth keys, passwords or credentials may be included in user-data or a reusable image.
- [ ] **RF-5:** When the owner resumes setup from an authenticated terminal, the wizard shall reuse valid existing identity and authentication, guide the necessary provider-native logins, and report success only after the selected CLI and workspace are usable. Existing FEAT-028 pause semantics remain compatible; a URL alone is not successful login.
- [ ] **RF-6:** If bootstrap/setup is interrupted, re-running the same reviewed inputs shall preserve successful steps and provider access. A mismatched installation profile/source shall require explicit reconciliation rather than silently overwrite an existing installation.
- [ ] **RF-7:** When the owner updates or removes a cloud install, the persisted cloud profile shall remain effective and cleanup shall remove only BIAB-owned state, never the VPS itself, provider credentials or user repositories.
- [ ] **RF-8:** While provider SSH remains externally reachable, the system shall report provider-managed access and shall not stamp the existing dedicated-box `ssh_finalized` flag or claim nothing is exposed. A documented optional human closure check requires working tailnet access first, then a failing non-tailnet connection and a successful tailnet connection after the owner closes public TCP/22.

### Requisitos no funcionales

- English public-facing output; no private infrastructure names or personal identifiers.
- Single existing BIAB payload and adapter registry; no forked installer per provider.
- Official coding CLIs only in this feature; no Hermes-based orchestration or provider fallback. This does not remove any existing BIAB adapter.
- Ubuntu 24.04 x86-64 first; 8 GB is the pilot target, not a measured universal capacity promise. No GPU, local inference or mandatory Docker.
- Cloud SSH remains provider-managed. The owner must restrict inbound access in their account; this feature must not claim Tailscale-only exposure when the provider listener remains public.
- Normal provider/model charges still apply; user-data generation is not a purchase and has no embedded pricing promise.

### Growth Notes

- Audience/channel: existing coding-agent users trying BIAB on a fresh user-owned VPS; three manually observed betas after the release gates.
- Observe: provisioned -> preparation complete -> owner logins complete -> CLI task from mobile -> repeat use at day 7; record rescue/support time and recovery failures.
- Pilot target: one internal E2E, then 2/3 external installations without operator rescue. Diagnostic observations supplement, not replace, the canonical six-week launch checkpoint.
- No analytics service, automatic telemetry, new email endpoint or external event collection in this feature.

## 2. Spec Tecnica

### Investigacion previa

- `installer/web/install.sh` supports source/ref/destination overrides but its ref may be mutable; repeated fetch can replace a checkout. The cloud wrapper needs an explicit verified source identity, not implicit trust in latest main.
- `payload/install.sh` skips the SSH-install acknowledgement for `--skip-wizard`, yet always calls `install/50-ssh.sh` while building the stack.
- `payload/install/50-ssh.sh` writes a BIAB SSH drop-in, enables password/keyboard-interactive auth and switches socket activation. It is inappropriate for silent cloud startup as-is.
- `payload/wizard/35-ssh-finalize.sh` and `payload/install.sh` teardown own SSH policy on dedicated-box installs; update calls the installer with `--skip-wizard` from `payload/install/05-biab-command.sh`.
- FEAT-027 owns the console/VM preflight route; FEAT-028 owns semi-delegated auth pauses. This feature adds cloud preparation/policy, not duplicate copies of those requirements.
- The source repository used by the published bootstrap was private in the 2026-09-05 evaluation. Generating a template does not resolve anonymous release availability.

Verified against `main` at 0c33f34 on 2026-09-10 (review of this draft, no code changed):

- `payload/install/50-ssh.sh:62-63` writes `PasswordAuthentication yes` and
  `KbdInteractiveAuthentication yes`; `:79-80` disables `ssh.socket` and enables
  `ssh.service`. Confirmed unsafe for silent cloud startup.
- `payload/install.sh:400` skips only `check_ssh_install_preflight` under
  `--skip-wizard`; `:593` still runs `install/50-ssh.sh` inside the stack block.
  Confirmed: `--skip-wizard` suppresses the acknowledgement, not the mutation.
- `payload/install/05-biab-command.sh:189` runs `install.sh --skip-wizard` from
  `do_update`, so `biab update` re-applies 50-ssh.sh. Confirmed: the cloud
  profile must survive update or it is reverted on the first bug fix.
- `installer/web/install.sh:23,62-65` defaults `BIB_REF` to `main` and does a
  forced `fetch`/`checkout -B` over an existing checkout. Confirmed: RF-2's
  explicit-source requirement is load-bearing, not defensive decoration.
- `payload/install.sh:296-315` (uninstall) only touches SSH activation when
  `removed_ssh_dropin=1`, i.e. when BIAB removed a drop-in it had written
  itself. So the teardown is already a no-op for a profile that writes no
  drop-in — see task 1's invariant.
- The payload contains **no** firewall management at all (no `ufw`, `iptables`
  or `nft` outside tests). "Preserve firewall settings" is therefore an
  absence to keep, not a call path to make profile-aware.

### Architecture and rollout

Offline renderer -> user creates VPS in their account -> cloud-init fetches/verifies an explicit release -> BIAB stack preparation under the persisted cloud profile -> owner finishes native authentication -> mobile smoke/reboot -> optional later update/removal.

Proposed initial provider recipe: AWS Lightsail. Keep the generated cloud-init payload provider-neutral where possible, but do not advertise a tested Google Cloud recipe until separately exercised. No Marketplace image, AMI publication, Terraform account management or hosted control plane in this feature.

Do not alter dedicated-box behavior by default. A cloud profile is explicit, persisted once, validated before host mutations and read again on update/uninstall. The exact propagation points must be covered by tests so `biab update` cannot revert to the password-capable base path.

### Archivos afectados

| File | Action |
|---|---|
| `installer/cloud/render.sh` | CREATE offline payload renderer with validated inputs |
| `installer/cloud/bootstrap.sh` | CREATE restartable verified cloud preparation |
| `payload/install.sh`, `payload/lib/common.sh` | MODIFY explicit profile/state/preflight and profile-aware teardown |
| `payload/install/50-ssh.sh`, `payload/wizard/35-ssh-finalize.sh` | MODIFY reviewed cloud no-mutation path only |
| `payload/install/05-biab-command.sh` | MODIFY profile-aware update if not covered by persisted state resolution |
| `payload/test/cloud-bootstrap.sh`, `payload/test/cloud-profile.sh` | CREATE hermetic tests |
| `.github/workflows/ci.yml` | MODIFY to execute new tests |
| `docs/cloud.md`, `README.md`, `docs/architecture.md` | CREATE/MODIFY only the necessary cloud contract and limitations |

### Dependencies and boundaries

Use existing Bash/Python standard-library tooling and cloud-init supplied by the image. No cloud SDK is required on the user's laptop to render user-data. Do not bake auth, copy an already-used home directory or capture an authenticated instance as a distributable image.

### Tasks

<task id="1">
<name>Persist explicit cloud profile without changing default behavior</name>
<files>payload/install.sh payload/lib/common.sh payload/install/50-ssh.sh payload/wizard/35-ssh-finalize.sh payload/install/05-biab-command.sh payload/test/cloud-profile.sh</files>
<action>After explicit security review, add the profile and prove preservation through install, wizard, update and uninstall. Reject profile changes rather than silently weaken an existing setup.</action>
<verify>bash payload/test/cloud-profile.sh && bash payload/test/uninstall-contract.sh && bash payload/test/ssh-finalize-decision.sh</verify>
<done>Provider SSH fixtures remain byte-identical and no SSH service mutation is called in cloud profile; default-path regression tests pass.</done>
<invariant>The cloud profile writes no file under `/etc/ssh/sshd_config.d/` or `/etc/systemd/system/ssh.service.d/`. That single assertion is what makes install, update AND uninstall safe: the teardown block in `payload/install.sh:296-315` is already gated on `removed_ssh_dropin`, so a profile that writes nothing needs no separate profile-aware teardown. Assert the invariant at the source; do not re-audit the teardown.</invariant>
</task>

<task id="2">
<name>Render and prepare an explicit verified source</name>
<files>installer/cloud/render.sh installer/cloud/bootstrap.sh payload/test/cloud-bootstrap.sh</files>
<action>Add offline generation, source verification, clean error states and resumable preparation. Owner credentials remain absent and unattended preparation stops before auth/agent execution.</action>
<verify>bash payload/test/cloud-bootstrap.sh && shellcheck -S warning installer/cloud/*.sh</verify>
<done>Fixtures cover success, retry, unavailable source, wrong commit, hostile input and interruption; no network or host changes occur on the renderer machine.</done>
</task>

<task id="3">
<name>Document operator-owned cloud delivery and enforce CI</name>
<files>docs/cloud.md README.md docs/architecture.md .github/workflows/ci.yml</files>
<action>Document the AWS-first path, preserved SSH responsibility, owner-native auth, recovery, charges and explicit teardown. Label unavailable/unverified paths. Add only local test jobs, not deployment jobs.</action>
<verify>bash tools/check-no-personal-refs.sh && bash payload/test/ssh-install-preflight.sh && bash payload/test/oauth-agent-pause.sh</verify>
<done>Copy matches the executable profile, no unsupported privacy/security guarantee, all relevant test jobs are wired.</done>
</task>

<task id="4">
<name>Run authorized disposable-VPS verification</name>
<files>specs/active/FEAT-029-cloud-bootstrap.tracking.json</files>
<action>Only after target/spend authorization, provision one user-owned VPS, complete real auth and mobile task, reconnect after reboot, retry/update/uninstall and verify recovery. Record source identity and observable receipts without credentials.</action>
<verify>On the authorized VPS: cloud-init status --wait; then biab and the documented two-session/reboot/update/uninstall checklist.</verify>
<done>Real receipt proves mobile use and recovery; failed/omitted tests remain pending. Cloud resources are not deleted without the owner's explicit request.</done>
</task>

### Patron de codigo

Current stack dispatch (`payload/install.sh`), the point needing profile-aware treatment:

```bash
if phase_is_done "stack_installed"; then
    log "install: stack already installed, skipping (use --force to re-run wizard, or remove state.json to fully reinstall)"
else
    run_install "install/00-base.sh"
    run_install "install/05-biab-command.sh"
    run_install "install/06-bd-cli.sh"
    run_install "install/10-tmux.sh"
    run_install "install/20-tailscale.sh"
    run_install "install/30-gh.sh"
    run_install "$(ai_cli_install_script "$CHOSEN_CLI")"
    run_install "install/50-ssh.sh"
    phase_done "stack_installed"
fi
```

### Contrato de entrega

| Gate | Required | Evidence |
|---|---|---|
| Merge | true | Reviewed implementation PR + merged commit; spec PR alone is not implementation |
| Deploy | true | Authorized VPS preparation from the reviewed release/commit |
| Verification | true | Real native logins, mobile task, reboot/retry/update/uninstall preserving provider access |
| Follow-up | false | No external queue writes needed; any incomplete gate remains in tracking |

Create adjacent tracking only when promoted to active, with `criteria`, `e2e` and structured `delivery.merge/deploy/verification/follow_up`. Nothing is completed by creating this draft.

## 3. Boundaries

### Always
- Run baseline before installer/security changes, preserve provider access and user files, use PRs/worktrees.
- Public messages in English; reject unexpected source/profile and retain useful failure status.

### Ask First
- Cloud SSH profile design above; any firewall/auth/security change; account/region/budget; real provisioning; publication/visibility changes; merge/deployment.

### Never
- Embed credentials/authenticated state; run or arm Night Shift; silently enable password login; replace provider SSH configuration; claim a VPS fixes quota/handover; spend or create resources from the renderer.
- Introduce Hermes into BIAB, including as a preinstalled runtime, adapter, optional pack or indirect dependency.

## 4. QA

| Case | Steps | Expected | State |
|---|---|---|---|
| RF-1/2 render/prepare | 1. Render with valid values. 2. Prepare against a mocked matching source. | Parseable payload, exact source verified, correct stage result; no local provider calls. | pending |
| RF-2 hostile/missing source | 1. Use shell metacharacters, invalid username/ref, wrong commit, private/unavailable repo. | Rejected without shell injection, fallback or host mutation. | pending |
| RF-3 profile lifecycle | 1. Snapshot provider fixtures. 2. Install/resume/update/remove in cloud profile. 3. Assert no file created under `sshd_config.d/` or `ssh.service.d/`. | Byte-identical configs/keys; no password enabling and no socket toggle. | pending |
| RF-3 no firewall creep | Grep the shipped tree for `ufw`/`iptables`/`nft` outside tests. | No hits — the payload still manages no firewall. | pending |
| RF-4 preparation | 1. Mock all login/agent/pack commands. 2. Run cloud preparation twice. | No invocation; status awaits owner, not ready; no secrets in output. | pending |
| RF-5 auth | 1. Run owner setup. 2. Complete/expire/decline each login. | Reuses valid auth, preserves native refresh handling, failure/pauses do not report ready. | pending |
| RF-6 interruption | 1. Stop between steps. 2. Retry identical and then conflicting inputs. | Successful steps preserved; conflicts stop before overwrite. | pending |
| RF-7 recovery | 1. Finish real install. 2. Reboot/update/remove. 3. Open second provider session. | Owner remains able to access machine and repositories survive. | pending |
| RF-8 exposure | 1. Verify tailnet SSH. 2. Owner closes provider public TCP/22. 3. Test from outside/inside tailnet. | External connection fails, tailnet connection works; no automatic firewall write or premature private-only claim. | pending |

Regression: dedicated-machine install, FEAT-027 preflight, FEAT-028 pauses, uninstall ownership and CLI wiring matrix. Never run root installers in the development host.

Baseline on 2026-09-05 at b5d19d2, non-root fixtures: uninstall 89 passed/0 failed; SSH preflight 6/0; SSH finalize 53/0; OAuth pause 5/0. These do not validate the proposed cloud profile or a real VPS.

## 5. Implementation and documentation impact

Planning only. No production changes, no new public release and no VPS created. Branch: `feat/feat-029-cloud-bootstrap`. Security approval and DoR gates remain open. Required docs are the narrow cloud recipe and existing architecture/requirements alignment; do not claim a general hosting product.

## 6. Feedback

2026-09-05 — Owner decision: Hermes will not be introduced in BIAB. This closes that scope question only; cloud security, real provisioning and spending remain subject to their existing gates.

Await explicit cloud policy review. Existing FEAT-012/025/027/028 gates remain unchanged; cloud validation can supply relevant evidence only when it actually satisfies their criteria.

2026-09-10 — Code review of this draft against `main` at 0c33f34. Every technical
claim in §2 checked and confirmed with file:line evidence (see "Investigacion
previa"). Two corrections applied, both narrowing scope rather than widening it:
the payload manages no firewall, so "preserve firewall settings" became "do not
introduce firewall management"; and the uninstall teardown needs no profile
awareness because it is already gated on BIAB having written a drop-in — task 1
now asserts the no-drop-in invariant at the source instead. No code changed and
no gate cleared: the two open DoR checkboxes (cloud SSH policy, target/spend)
are still Jesus's to decide.

Independent QA review on 2026-09-05 confirmed FEAT-029 is a separate cloud-lifecycle feature and that `--skip-wizard` alone is not cloud-safe. It added the mobile SSH-key prerequisite and external-versus-tailnet exposure test. All cloud-specific acceptance remains NOT VERIFIED.
