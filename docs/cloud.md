# Running Builders in a Box on a cloud VPS

You don't need a mini PC to try this. Any Ubuntu 24.04 instance in your own
cloud account works, and the install is the same one the hardware path uses.

**This is not hosting.** The instance lives in your account, on your bill, under
your control. Nothing here creates a resource, spends money, or gives anyone
else access to your machine. You create the VPS; the tooling only writes the
startup file you hand it.

## What's different from a dedicated box

On a mini PC or a gift USB, Builders in a Box owns SSH end to end: it enables
password auth so you can reach the box while you set it up, then binds sshd to
your Tailscale address so the public listener goes away.

On a VPS, your provider already owns SSH. Applying the dedicated-box policy
there would enable password authentication on a public IP address — and then
re-enable it on the next `biab update`, because updating re-runs the installer.

So the cloud path installs under a different profile:

| | `dedicated` | `cloud` |
|---|---|---|
| sshd drop-in | written by BIAB | **none, ever** |
| Password auth | enabled during setup | **never enabled** |
| `ssh.socket` → `ssh.service` | switched | **left alone** |
| `authorized_keys` | prepared by the wizard | **left to your provider** |
| Tailscale-only bind | applied by the wizard | **never applied** |
| Closing inbound TCP/22 | automatic | **your call, in the provider console** |

The profile is persisted on first install and read back on every later run, so
`biab update` cannot quietly revert to the dedicated policy.

## Step 1 — render the startup file

On your own machine, from a checkout of this repo:

```bash
installer/cloud/render.sh \
  --user ubuntu \
  --commit <the full 40-character commit you want to install> \
  --name "Your Name" \
  --ai-cli claude \
  -o user-data.yaml
```

This writes a file and does nothing else. No network call, no cloud SDK, no
credentials read, no resource created.

It insists on a **full commit sha**, not a branch. A branch can move between
the moment you render this file and the moment the instance boots, and the
result would be an unattended machine on a public IP running something you
never reviewed.

Read `user-data.yaml` before you use it. It is meant to be read: the bootstrap
is embedded in it in full rather than downloaded at boot.

## Step 2 — create the instance (Google Cloud)

This is the path the feature was built and verified against.

```bash
gcloud compute instances create biab-1 \
  --machine-type=e2-standard-2 \
  --zone=europe-west1-b \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --metadata-from-file=user-data=user-data.yaml
```

`e2-standard-2` is 2 vCPU and 8 GB — the smallest shape the stack is comfortable
on. The `e2-micro` always-free instance has 1 GB and will not work.

**Costs**, at list price in `europe-west1` (checked 2026-09-28, 1 EUR = 1,1381 USD):
roughly **1 EUR** for a day of setting things up and trying it, or about **54 EUR
a month** if you leave it running around the clock. Stopping the instance drops
that to the disk alone, about 2,60 EUR a month. Your AI provider's own charges
are separate and unchanged.

### AWS Lightsail (second option, not yet verified end to end)

An 8 GB Lightsail instance is a flat 44 USD a month with disk, IPv4 and 5 TB of
transfer included. Create an Ubuntu 24.04 instance and paste the same
`user-data.yaml` as the launch script.

This path is **documented but untested** — nobody has run it start to finish
yet. Treat the GCP recipe above as the one with evidence behind it.

## Step 3 — wait for preparation, then finish setup yourself

```bash
cloud-init status --wait
cat /var/lib/buildersinabox/cloud-bootstrap.status
```

The status you want is `awaiting-owner-setup`. That is deliberately **not**
"ready": the machine has the stack installed and no identity at all. Nothing is
logged into Tailscale, GitHub or your AI CLI, and no agent has run.

It stops there because the alternative is baking credentials into a startup file
your provider stores as instance metadata.

Finish it yourself, from an SSH session or the provider's console:

```bash
sudo biab
```

That runs the normal wizard: your logins, your workspace, your first project.

## Step 4 — close the door (optional, and yours to do)

While you do nothing, your provider's SSH listener stays reachable from the
internet. Key-only, as the Ubuntu cloud images ship it — Builders in a Box never
enables password authentication under this profile — but reachable.

To reduce that to your tailnet only:

1. Finish setup and confirm Tailscale is up.
2. **Verify you can SSH over the tailnet address.** Do this first.
3. Only then remove the inbound TCP/22 rule in your provider's firewall
   (GCP: the `default-allow-ssh` rule or your instance's network tags).
4. Confirm: a connection from outside the tailnet fails, one from inside works.

Builders in a Box will not do step 3 for you. It manages no firewall on any
platform, and a tool that closes your only way in before you've proved the other
way works is a tool that locks you out of your own machine.

Until you do it, the honest description is "provider-managed SSH, still
reachable" — which is what `biab status` reports.

## Updating, retrying and removing

- **Retry:** re-running the bootstrap with the same values resumes from the last
  completed stage. Changing the commit or the profile is refused rather than
  applied on top of an existing install — reconcile it deliberately.
- **Update:** `biab update` works normally and keeps the cloud profile.
- **Remove:** `sudo /opt/buildersinabox/payload/install.sh --uninstall` removes
  BIAB-owned state only. It never touches your provider's SSH configuration,
  your repositories, or the instance itself. Deleting the VPS is a separate
  action in your own console.

## Recovery

The cloud profile never changes sshd, so the provider's own recovery paths all
still work: the serial console, the browser SSH window, and adding a key through
the provider's metadata. That is the main practical benefit of not owning SSH on
a machine you reach over the internet.
