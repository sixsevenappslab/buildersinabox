#!/usr/bin/env bash
# Unit driver for the FEAT-029 cloud renderer and first-boot bootstrap.
#
# Two things are under test and they fail in different ways:
#
#   installer/cloud/render.sh    runs on the operator's laptop. Its job is to
#                                emit text and change nothing. The interesting
#                                failure is a bad value reaching the generated
#                                file, where a root shell later reads it.
#   installer/cloud/bootstrap.sh runs as root on an unattended public-IP box.
#                                The interesting failure is installing
#                                something other than the reviewed commit, or
#                                reporting success before one exists.
#
# Hermetic: git, apt-get and getent are mocked through PATH, every absolute
# path is redirected at a mktemp -d, and nothing here reaches the network.
#
# NEVER run this with sudo — see the guard below.

set -euo pipefail

EXPECTED_ASSERTIONS=50

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RENDER="${REPO_ROOT}/installer/cloud/render.sh"
BOOTSTRAP="${REPO_ROOT}/installer/cloud/bootstrap.sh"
GOOD_SHA="0123456789abcdef0123456789abcdef01234567"
OTHER_SHA="fedcba9876543210fedcba9876543210fedcba98"

pass=0
fail=0
ok()  { echo "cloud-bootstrap: ok: $*"; pass=$((pass + 1)); }
bad() { echo "cloud-bootstrap: FAIL: $*" >&2; fail=$((fail + 1)); }

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "cloud-bootstrap: REFUSING to run as root (EUID=0)." >&2
    echo "cloud-bootstrap: this driver executes bootstrap stages that write to" >&2
    echo "cloud-bootstrap: /opt and /var/lib; as root a missed override would" >&2
    echo "cloud-bootstrap: install over the development machine." >&2
    exit 2
fi

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"; echo "cloud-bootstrap: ${pass} passed, ${fail} failed"' EXIT

# ---------------------------------------------------------------------------
# Mocks
# ---------------------------------------------------------------------------
# The mock git is programmable through two files: MOCK_GIT_FETCH_RC decides
# whether the fetch succeeds (an unreachable or private source is rc != 0), and
# MOCK_GIT_HEAD is what rev-parse reports (so we can hand back a DIFFERENT
# commit from the one that was asked for, which is the attack the verification
# step exists to catch).

MOCK_BIN="${SANDBOX}/bin"
mkdir -p "$MOCK_BIN"
GIT_LOG="${SANDBOX}/git.log"
MOCK_GIT_FETCH_RC="${SANDBOX}/fetch_rc"
MOCK_GIT_HEAD="${SANDBOX}/git_head"

cat > "${MOCK_BIN}/git" <<MOCK
#!/usr/bin/env bash
echo "git \$*" >> "${GIT_LOG}"
for a in "\$@"; do
    if [ "\$a" = "fetch" ]; then exit "\$(cat "${MOCK_GIT_FETCH_RC}")"; fi
    if [ "\$a" = "rev-parse" ]; then cat "${MOCK_GIT_HEAD}"; exit 0; fi
done
exit 0
MOCK

cat > "${MOCK_BIN}/getent" <<MOCK
#!/usr/bin/env bash
# Only the users listed in ${SANDBOX}/users exist.
grep -qx "\$2" "${SANDBOX}/users" 2>/dev/null || exit 2
echo "\$2:x:1000:1000::/home/\$2:/bin/bash"
MOCK

cat > "${MOCK_BIN}/apt-get" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod +x "${MOCK_BIN}"/*
export PATH="${MOCK_BIN}:${PATH}"
printf 'ubuntu\n' > "${SANDBOX}/users"
printf '0\n' > "$MOCK_GIT_FETCH_RC"
printf '%s\n' "$GOOD_SHA" > "$MOCK_GIT_HEAD"

# ---------------------------------------------------------------------------
# 1. Renderer — the happy path
# ---------------------------------------------------------------------------

render_out="${SANDBOX}/user-data.yaml"
if "$RENDER" --user ubuntu --commit "$GOOD_SHA" --name "Test Owner" --ai-cli claude > "$render_out" 2>"${SANDBOX}/render.err"; then
    ok "render.sh emits user-data for valid inputs"
else
    bad "render.sh failed on valid inputs: $(cat "${SANDBOX}/render.err")"
fi

head -1 "$render_out" | grep -qx '#cloud-config' \
    && ok "output starts with the #cloud-config header cloud-init requires" \
    || bad "output is missing the #cloud-config header"

if python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$render_out" 2>/dev/null; then
    ok "output parses as YAML"
elif ! python3 -c 'import yaml' 2>/dev/null; then
    ok "output YAML parse skipped (no PyYAML here); structure covered by the grep assertions below"
else
    bad "output is not parseable YAML"
fi

grep -q "BIB_CLOUD_COMMIT='${GOOD_SHA}'" "$render_out" \
    && ok "the requested commit reaches the generated env file" \
    || bad "the commit is missing from the generated env file"
grep -q "BIB_CLOUD_USER='ubuntu'" "$render_out" \
    && ok "the target user reaches the generated env file" \
    || bad "the target user is missing from the generated env file"

# The bootstrap must be embedded, not downloaded: it is the thing that
# verifies the source, so it cannot arrive from the source it checks.
sed -n '/path: \/opt\/biab-cloud\/bootstrap.sh/,/path: \/opt\/biab-cloud\/bootstrap.env/p' "$render_out" \
    | sed -n 's/^      //p' > "${SANDBOX}/embedded.sh"
if diff -q <(sed -e 's/[[:space:]]*$//' "$BOOTSTRAP") <(sed -e 's/[[:space:]]*$//' "${SANDBOX}/embedded.sh") >/dev/null 2>&1; then
    ok "the embedded bootstrap is byte-identical to installer/cloud/bootstrap.sh"
else
    bad "the embedded bootstrap differs from the file on disk"
fi

# Nothing that looks like a credential may appear in a file the provider keeps
# in instance metadata, readable by anyone with project access.
# Comment lines are stripped first: the embedded bootstrap explains its own
# security model in prose, and "must stay non-secret:" is not a leaked secret.
if sed -e 's/^[[:space:]]*//' "$render_out" | grep -v '^#' \
    | grep -qiE '(password|secret|token|api[_-]?key|BEGIN [A-Z ]*PRIVATE KEY)[[:space:]]*[:=]'; then
    bad "the rendered user-data contains something credential-shaped"
else
    ok "the rendered user-data carries no credential-shaped value"
fi

# The rendered env file is read with `. bootstrap.env` by a ROOT shell. An
# unquoted value containing a space parses as "run the second word as a
# command": --name 'John Doe' both lost the name and executed `Doe`, and
# --name 'x poweroff' would have powered the instance off.
"$RENDER" --user ubuntu --commit "$GOOD_SHA" --name "John Doe" 2>/dev/null \
    | sed -n 's/^      BIB_CLOUD_/BIB_CLOUD_/p' > "${SANDBOX}/round.env"
roundtrip="$(bash -c 'set -a; . "$1"; set +a; printf "%s" "${BIB_CLOUD_NAME:-__UNSET__}"' _ "${SANDBOX}/round.env" 2>"${SANDBOX}/round.err")"
[[ "$roundtrip" == "John Doe" ]] \
    && ok "a multi-word --name survives being sourced from the rendered env file" \
    || bad "sourcing the rendered env file yielded '${roundtrip}' instead of 'John Doe'"
[[ ! -s "${SANDBOX}/round.err" ]] \
    && ok "sourcing the rendered env file executes nothing and prints no error" \
    || bad "sourcing the rendered env file produced: $(cat "${SANDBOX}/round.err")"

# The whole quoting scheme rests on no value ever containing a single quote.
if grep -q "BIB_CLOUD_NAME='John Doe'" "${SANDBOX}/round.env"; then
    ok "values are emitted single-quoted"
else
    bad "the env file does not single-quote its values: $(cat "${SANDBOX}/round.env")"
fi

# cloud-init must see a failed bootstrap as failed. Without pipefail the exit
# status is tee's, so `cloud-init status` would report done on a box that
# prepared nothing.
"$RENDER" --user ubuntu --commit "$GOOD_SHA" 2>/dev/null | grep -q 'set -o pipefail' \
    && ok "the runcmd sets pipefail, so a failed bootstrap is not reported as done" \
    || bad "the runcmd pipeline swallows the bootstrap's exit status"

# RF-1: the renderer changes nothing on the operator's machine.
probe="${SANDBOX}/probe"; mkdir -p "$probe"
before="$(find "$probe" | sort)"
( cd "$probe" && "$RENDER" --user ubuntu --commit "$GOOD_SHA" >/dev/null 2>&1 )
after="$(find "$probe" | sort)"
[[ "$before" == "$after" ]] \
    && ok "render.sh writes nothing into the directory it runs from" \
    || bad "render.sh created files on the operator's machine"

: > "$GIT_LOG"
"$RENDER" --user ubuntu --commit "$GOOD_SHA" >/dev/null 2>&1
[[ ! -s "$GIT_LOG" ]] \
    && ok "render.sh invokes no git (and so reaches no network)" \
    || bad "render.sh shelled out to git: $(cat "$GIT_LOG")"

# ---------------------------------------------------------------------------
# 2. Renderer — hostile and malformed input (RF-2)
# ---------------------------------------------------------------------------
# Each of these must be REFUSED. Refusing beats escaping: the values below are
# interpolated into a file a root shell later sources.

reject() {
    local label="$1"; shift
    local out
    if out="$("$RENDER" "$@" 2>&1)"; then
        bad "render.sh accepted ${label}"
    else
        ok "render.sh refuses ${label}"
    fi
}

reject "a username with a shell metacharacter" --user 'ubuntu;id' --commit "$GOOD_SHA"
reject "a username with command substitution"  --user 'ubuntu$(id)' --commit "$GOOD_SHA"
reject "root as the target user"               --user root --commit "$GOOD_SHA"
reject "a branch name where a commit belongs"  --user ubuntu --commit main
reject "a short (39-character) sha"            --user ubuntu --commit "${GOOD_SHA:0:39}"
reject "an uppercase sha"                      --user ubuntu --commit "$(tr 'a-f' 'A-F' <<<"$GOOD_SHA")"
reject "a non-https repository URL"            --user ubuntu --commit "$GOOD_SHA" --repo 'http://example.com/x'
reject "a repository URL with a substitution"  --user ubuntu --commit "$GOOD_SHA" --repo 'https://example.com/$(id)'
reject "an unknown AI CLI"                     --user ubuntu --commit "$GOOD_SHA" --ai-cli hermes
reject "a display name with a newline"         --user ubuntu --commit "$GOOD_SHA" --name $'a\nruncmd: [id]'
reject "a missing --commit"                    --user ubuntu
reject "a missing --user"                      --commit "$GOOD_SHA"

# The refusal must actually be a refusal, not a silent empty file.
out="$("$RENDER" --user root --commit "$GOOD_SHA" 2>&1 || true)"
grep -q "must not be root" <<<"$out" \
    && ok "the refusal explains why, rather than failing blank" \
    || bad "refusing root produced no useful message: ${out}"

# ---------------------------------------------------------------------------
# 3. Bootstrap — source verification (RF-2)
# ---------------------------------------------------------------------------

new_boot_env() {
    local root
    root="$(mktemp -d --tmpdir="$SANDBOX" boot.XXXXXX)"
    mkdir -p "${root}/state" "${root}/dest/.git"
    printf '%s\n' "$root"
}

run_stage() {
    # Sources the bootstrap as a library and runs one function in a subshell,
    # so a cloud_die (which exits) cannot take the driver with it.
    local root="$1" fn="$2"; shift 2
    (
        export BIB_CLOUD_BOOTSTRAP_LIB=1
        export BIB_CLOUD_STATE_DIR="${root}/state"
        export BIB_CLOUD_DEST="${root}/dest"
        # shellcheck source=/dev/null
        source "$BOOTSTRAP"
        "$fn" "$@"
    ) 2>&1
}

# Verified source: fetch succeeds AND HEAD is the commit we asked for.
B="$(new_boot_env)"
printf '0\n' > "$MOCK_GIT_FETCH_RC"; printf '%s\n' "$GOOD_SHA" > "$MOCK_GIT_HEAD"
out="$(run_stage "$B" cloud_fetch_source "https://github.com/x/y" "$GOOD_SHA" || echo "__FAILED__")"
if grep -q "__FAILED__" <<<"$out"; then
    bad "a matching commit was rejected: ${out}"
else
    grep -q "source verified at ${GOOD_SHA}" <<<"$out" \
        && ok "a fetch whose HEAD matches the requested commit is accepted" \
        || bad "the verified-source path printed no confirmation: ${out}"
fi

# The attack this check exists for: the fetch succeeds but the tree is a
# different commit. Must fail, and must NOT fall back to anything.
B="$(new_boot_env)"
printf '%s\n' "$OTHER_SHA" > "$MOCK_GIT_HEAD"
out="$(run_stage "$B" cloud_fetch_source "https://github.com/x/y" "$GOOD_SHA" || true)"
grep -q "source verification failed" <<<"$out" \
    && ok "a checkout that is NOT the requested commit is refused" \
    || bad "a mismatched commit was accepted: ${out}"
grep -qi "main" <<<"$out" \
    && bad "the failure path mentions main — there must be no fallback" \
    || ok "the failure path offers no fallback to main"

# Unavailable or private source: the fetch itself fails.
B="$(new_boot_env)"
printf '1\n' > "$MOCK_GIT_FETCH_RC"; printf '%s\n' "$GOOD_SHA" > "$MOCK_GIT_HEAD"
out="$(run_stage "$B" cloud_fetch_source "https://github.com/x/y" "$GOOD_SHA" || true)"
grep -q "could not fetch" <<<"$out" \
    && ok "an unreachable or private source fails with a clear, non-secret message" \
    || bad "an unreachable source did not fail cleanly: ${out}"
printf '0\n' > "$MOCK_GIT_FETCH_RC"

# Hostile values must be refused BEFORE git is invoked at all.
B="$(new_boot_env)"; : > "$GIT_LOG"
out="$(run_stage "$B" cloud_fetch_source 'https://x.com/$(id)' "$GOOD_SHA" || true)"
grep -q "invalid source repository URL" <<<"$out" \
    && ok "the bootstrap refuses a repository URL with a substitution" \
    || bad "a hostile repository URL was not refused: ${out}"
[[ ! -s "$GIT_LOG" ]] \
    && ok "the hostile URL was refused before git was invoked" \
    || bad "git ran with a hostile URL: $(cat "$GIT_LOG")"

B="$(new_boot_env)"
out="$(run_stage "$B" cloud_fetch_source "https://github.com/x/y" "main" || true)"
grep -q "40-character sha" <<<"$out" \
    && ok "the bootstrap refuses a branch name where a commit belongs" \
    || bad "a branch name was accepted as a commit: ${out}"

# ---------------------------------------------------------------------------
# 4. Bootstrap — target user (RF-2)
# ---------------------------------------------------------------------------

B="$(new_boot_env)"
out="$(run_stage "$B" cloud_check_user ubuntu || echo "__FAILED__")"
grep -q "__FAILED__" <<<"$out" \
    && bad "an existing user was rejected: ${out}" \
    || ok "an existing non-root target user is accepted"

B="$(new_boot_env)"
out="$(run_stage "$B" cloud_check_user nosuchuser || true)"
grep -q "does not exist" <<<"$out" \
    && ok "a missing target user fails with an actionable message" \
    || bad "a missing user did not fail clearly: ${out}"

B="$(new_boot_env)"
out="$(run_stage "$B" cloud_check_user root || true)"
grep -q "invalid target user" <<<"$out" \
    && ok "root is refused as the target user" \
    || bad "root was accepted as the target user: ${out}"

# ---------------------------------------------------------------------------
# 5. Bootstrap — status never claims more than it did (RF-4)
# ---------------------------------------------------------------------------

B="$(new_boot_env)"
run_stage "$B" cloud_status "awaiting-owner-setup" >/dev/null
got="$(cat "${B}/state/cloud-bootstrap.status")"
[[ "$got" == "awaiting-owner-setup" ]] \
    && ok "the status file records awaiting-owner-setup" \
    || bad "status file holds '${got}'"

# The word 'ready' must not be reachable as a terminal status: the box has a
# stack and no identity, and nothing has been run on the owner's behalf.
if grep -qE 'cloud_status[[:space:]]+"ready"' "$BOOTSTRAP"; then
    bad "the bootstrap can report 'ready' — it must stop at awaiting-owner-setup"
else
    ok "the bootstrap has no path that reports 'ready'"
fi

# RF-4: no login and no agent invocation anywhere in the unattended path.
if grep -nE '(tailscale[[:space:]]+up|gh[[:space:]]+auth[[:space:]]+login|claude[[:space:]]+(-p|login)|codex[[:space:]]+(exec|login))' "$BOOTSTRAP" | grep -q .; then
    bad "the unattended bootstrap performs a login or starts an agent"
else
    ok "the unattended bootstrap performs no login and starts no agent"
fi

# Missing required values must fail rather than guess.
B="$(new_boot_env)"
out="$(
    env BIB_CLOUD_BOOTSTRAP_LIB=1 BIB_CLOUD_STATE_DIR="${B}/state" BIB_CLOUD_DEST="${B}/dest" \
        BIB_CLOUD_REPO="" BIB_CLOUD_COMMIT="" BIB_CLOUD_USER="" \
        bash -c 'source "'"$BOOTSTRAP"'"; cloud_bootstrap_main' 2>&1 || true
)"
grep -q "missing required values" <<<"$out" \
    && ok "user-data with missing values fails instead of assuming defaults" \
    || bad "an empty user-data did not fail clearly: ${out}"
[[ "$(cat "${B}/state/cloud-bootstrap.status" 2>/dev/null)" == "failed" ]] \
    && ok "a failed run leaves a 'failed' status behind, not a stale success" \
    || bad "a failed run did not record the failure"

# ---------------------------------------------------------------------------
# 6. Bootstrap — restartability (RF-6)
# ---------------------------------------------------------------------------

B="$(new_boot_env)"
run_stage "$B" stage_done platform "id-1" >/dev/null
out="$(run_stage "$B" stage_check platform "id-1" && echo YES || echo NO)"
grep -q YES <<<"$out" \
    && ok "a stage completed with the same inputs is remembered across runs" \
    || bad "stage stamps do not persist"
out="$(run_stage "$B" stage_check stack "id-1" && echo YES || echo NO)"
grep -q NO <<<"$out" \
    && ok "an unreached stage is not falsely marked complete" \
    || bad "an unreached stage reported as done"

# A stage completed with DIFFERENT inputs must not be skipped. This is the
# retry path: re-running with a new commit would otherwise skip the fetch —
# and with it the commit verification — and still report success.
out="$(run_stage "$B" stage_check platform "id-2" || true)"
grep -q "already completed with different inputs" <<<"$out" \
    && ok "a stage completed with different inputs is refused, not skipped" \
    || bad "a changed stage identity was silently adopted: ${out}"

# An interrupted run must not redo the stages that already succeeded. Drive
# main() with platform+user+source already stamped and a mocked installer, and
# assert git is never re-invoked.
B="$(new_boot_env)"
mkdir -p "${B}/state/cloud-stages" "${B}/dest/payload"
printf 'ubuntu-24.04-x86_64\n' > "${B}/state/cloud-stages/platform"
printf 'ubuntu\n'                   > "${B}/state/cloud-stages/user"
printf 'https://github.com/x/y@%s\n' "$GOOD_SHA" > "${B}/state/cloud-stages/source"
cat > "${B}/dest/payload/install.sh" <<'FAKE'
#!/usr/bin/env bash
echo "installer ran: $*"
FAKE
chmod +x "${B}/dest/payload/install.sh"
: > "$GIT_LOG"
out="$(
    env BIB_CLOUD_BOOTSTRAP_LIB=1 BIB_CLOUD_STATE_DIR="${B}/state" BIB_CLOUD_DEST="${B}/dest" \
        BIB_CLOUD_REPO="https://github.com/x/y" BIB_CLOUD_COMMIT="$GOOD_SHA" BIB_CLOUD_USER=ubuntu \
        BIB_CLOUD_NAME="Test" BIB_CLOUD_AI_CLI=claude \
        bash -c 'source "'"$BOOTSTRAP"'"; cloud_bootstrap_main' 2>&1 || true
)"
[[ ! -s "$GIT_LOG" ]] \
    && ok "a resumed run does not re-fetch a source it already verified" \
    || bad "a resumed run re-ran git: $(cat "$GIT_LOG")"
grep -q -- "--profile=cloud" <<<"$out" \
    && ok "the bootstrap installs with --profile=cloud" \
    || bad "the bootstrap did not pass --profile=cloud: ${out}"
grep -q -- "--skip-wizard" <<<"$out" \
    && ok "the bootstrap installs with --skip-wizard, so no OAuth step runs unattended" \
    || bad "the bootstrap did not pass --skip-wizard: ${out}"
[[ "$(cat "${B}/state/cloud-bootstrap.status" 2>/dev/null)" == "awaiting-owner-setup" ]] \
    && ok "a complete unattended run ends at awaiting-owner-setup, not ready" \
    || bad "final status was '$(cat "${B}/state/cloud-bootstrap.status" 2>/dev/null)'"

# The same fixture, re-run with a DIFFERENT commit. It must refuse rather than
# skip the already-stamped source stage and claim the new commit is installed.
: > "$GIT_LOG"
out="$(
    env BIB_CLOUD_BOOTSTRAP_LIB=1 BIB_CLOUD_STATE_DIR="${B}/state" BIB_CLOUD_DEST="${B}/dest" \
        BIB_CLOUD_REPO="https://github.com/x/y" BIB_CLOUD_COMMIT="$OTHER_SHA" BIB_CLOUD_USER=ubuntu \
        BIB_CLOUD_NAME="Test" BIB_CLOUD_AI_CLI=claude \
        bash -c 'source "'"$BOOTSTRAP"'"; cloud_bootstrap_main' 2>&1 || true
)"
grep -q "already completed with different inputs" <<<"$out" \
    && ok "a retry with a different commit is refused instead of silently skipped" \
    || bad "a retry with a different commit was accepted: ${out}"
[[ "$(cat "${B}/state/cloud-bootstrap.status" 2>/dev/null)" == "failed" ]] \
    && ok "the refused retry leaves a failed status, not a stale awaiting-owner-setup" \
    || bad "the refused retry left status '$(cat "${B}/state/cloud-bootstrap.status" 2>/dev/null)'"

# ---------------------------------------------------------------------------
if [[ $((pass + fail)) -ne "$EXPECTED_ASSERTIONS" ]]; then
    echo "cloud-bootstrap: FAIL: ran $((pass + fail)) assertions, expected ${EXPECTED_ASSERTIONS}" >&2
    exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
