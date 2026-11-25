#!/usr/bin/env bash
# Unit driver for tools/bump-pins.sh (FEAT-038 T3).
#
# Hermetic: no network, no root, no real npm. The script runs against a copy of
# the repo in a mktemp -d (never the working tree), a local fixture server that
# plays both the npm registry and the GitHub API (and logs every path it is asked
# for), and a fake `npm` that rewrites package.json and the lockfile the way
# `npm install --package-lock-only` would.
#
# What it does NOT cover: a real lockfile regeneration (the live dry run and the
# weekly job do that) and the CI result of a bump (pins-smoke does that).

set -euo pipefail

EXPECTED_ASSERTIONS=30

PAYLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${PAYLOAD_DIR}/.." && pwd)"

pass=0
fail=0
ok()  { echo "bump-pins: ok: $*"; pass=$((pass + 1)); }
bad() { echo "bump-pins: FAIL: $*" >&2; fail=$((fail + 1)); }

SANDBOX="$(mktemp -d)"
SERVER_PID=""
_finish() {
    local rc=$?
    [[ -z "$SERVER_PID" ]] || kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "${SANDBOX:?}"
    printf 'bump-pins: %d passed, %d failed\n' "$pass" "$fail"
    local total=$((pass + fail))
    if [[ "$total" -ne "$EXPECTED_ASSERTIONS" ]]; then
        printf 'bump-pins: FAIL: ran %d assertions, expected %d (aborted early, or a case was added without updating EXPECTED_ASSERTIONS)\n' "$total" "$EXPECTED_ASSERTIONS" >&2
        exit 1
    fi
    [[ "$fail" -eq 0 ]] || exit 1
    exit "$rc"
}
trap _finish EXIT

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "bump-pins: REFUSING to run as root; this driver needs no privileges." >&2
    exit 2
fi

# --- Fixture server -------------------------------------------------------------
FIX="${SANDBOX}/fix"; mkdir -p "$FIX"
cat > "${SANDBOX}/server.py" <<'PY'
import http.server, os, sys
root, logf, portf = sys.argv[1:4]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(logf, 'a') as f:
            f.write(self.path + '\n')
        p = os.path.join(root, self.path.lstrip('/'))
        if os.path.exists(p + '.status'):
            code = int(open(p + '.status').read().strip())
            self.send_response(code); self.end_headers(); self.wfile.write(b'oops'); return
        if os.path.isfile(p):
            data = open(p, 'rb').read()
            self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a):
        pass
s = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
open(portf, 'w').write(str(s.server_address[1]))
s.serve_forever()
PY
REQLOG="${SANDBOX}/requests.log"; : > "$REQLOG"
python3 -I "${SANDBOX}/server.py" "$FIX" "$REQLOG" "${SANDBOX}/port" &
SERVER_PID=$!
for _ in $(seq 1 50); do [[ -s "${SANDBOX}/port" ]] && break; sleep 0.1; done
[[ -s "${SANDBOX}/port" ]] || { echo "bump-pins: fixture server did not start" >&2; exit 2; }
PORT="$(cat "${SANDBOX}/port")"

reg() { # reg <escaped-pkg> <version> [repo-url|-]   (a .status file or garbage content = unreachable/malformed)
    local pkg="${1:?}"
    mkdir -p "${FIX}/${pkg}"
    if [[ "${3:--}" == "-" ]]; then
        jq -n --arg v "$2" '{version:$v, repository:null}' > "${FIX}/${pkg}/latest"
    else
        jq -n --arg v "$2" --arg u "$3" '{version:$v, repository:{type:"git", url:$u}}' > "${FIX}/${pkg}/latest"
    fi
    rm -f "${FIX:?}/${pkg}/latest.status"
}
GH_DIR="${FIX}/gh/repos/google-antigravity/antigravity-cli/releases"
agy_rel() { # agy_rel <tag> <prerelease> <draft> <digest|computed|none>
    mkdir -p "$GH_DIR" "${FIX}/dl"
    printf 'agy-asset-%s' "$1" > "${FIX}/dl/agy-$1.tgz"
    local d="$4"
    [[ "$d" != computed ]] || d="$(sha256sum "${FIX}/dl/agy-$1.tgz" | cut -d' ' -f1)"
    jq -n --arg t "$1" --argjson pre "$2" --argjson dr "$3" --arg d "$d" --arg u "http://127.0.0.1:${PORT}/dl/agy-$1.tgz" \
       '{tag_name:$t, prerelease:$pre, draft:$dr, html_url:("https://example.test/agy/" + $t),
         assets:[{name:"agy_cli_linux_x64.tar.gz", browser_download_url:$u} + (if $d == "none" then {} else {digest:("sha256:" + $d)} end)]}' > "${GH_DIR}/latest"
    rm -f "${GH_DIR:?}/latest.status"
}

# --- Fake npm: what `npm install --package-lock-only --save-exact pkg@ver` does ----
FAKEBIN="${SANDBOX}/fakebin"; mkdir -p "$FAKEBIN"
cat > "${FAKEBIN}/npm" <<'FAKE'
#!/usr/bin/env bash
if [[ "${1:-}" == ci ]]; then
    mkdir -p node_modules/.bin
    cp "$(dirname "$0")/../evil-paseo" node_modules/.bin/paseo   # the sandbox keeps one stand-in "paseo" (the run is env -i: nothing is passed by variable)
    chmod +x node_modules/.bin/paseo
    exit 0
fi
[[ "${1:-}" == install ]] || exit 0
spec="${*: -1}"; pkg="${spec%@*}"; ver="${spec##*@}"
[[ "$pkg" != "${FAKE_NPM_FAIL_PKG:-}" ]] || exit 1
integ="sha512-$(printf '%s' "$ver" | base64)"
tmp="$(mktemp)"
jq --arg p "$pkg" --arg v "$ver" '.dependencies[$p] = $v' package.json > "$tmp" && mv "$tmp" package.json
jq --arg p "$pkg" --arg v "$ver" --arg i "$integ" \
   '.packages[""].dependencies[$p] = $v | .packages["node_modules/" + $p].version = $v | .packages["node_modules/" + $p].integrity = $i' package-lock.json > "$tmp" && mv "$tmp" package-lock.json
FAKE
chmod +x "${FAKEBIN}/npm"
# What `paseo run --help` prints: the fixture of the version the repo has today.
HELPCMD="${SANDBOX}/helpcmd"
cat > "$HELPCMD" <<EOF
#!/usr/bin/env bash
printf '%s/%s' "\${GH_TOKEN:-unset}" "\${GITHUB_TOKEN:-unset}" > "${SANDBOX}/helpenv"
cat "${PAYLOAD_DIR}/test/fixtures/paseo-\$(sed -n 's/^PASEO_PIN="\\(.*\\)"\$/\\1/p' "${PAYLOAD_DIR}/lib/paseo.sh")-run-help.txt"
EOF
chmod +x "$HELPCMD"

# --- A pristine copy of the repo to clone per case ---------------------------------
# payload/test/paseo.sh also reads the CI file and checks the installer paths it lists.
BASE="${SANDBOX}/base"; mkdir -p "$BASE"
cp -a "${PAYLOAD_DIR}" "${BASE}/payload"
cp -a "${REPO_ROOT}/tools" "${BASE}/tools"
cp -a "${REPO_ROOT}/installer" "${BASE}/installer"
cp -a "${REPO_ROOT}/.github" "${BASE}/.github"
(cd "$BASE" && git init -q -b main && git config user.email t@example.test && git config user.name tester && git config commit.gpgsign false && git add -A && git commit -q -m base)

PIN_CLAUDE="$(jq -r '.dependencies["@anthropic-ai/claude-code"]' "${BASE}/payload/pins/claude-code/package.json")"
PIN_CODEX="$(jq -r '.dependencies["@openai/codex"]' "${BASE}/payload/pins/codex/package.json")"
PIN_PASEO="$(jq -r '.dependencies["@getpaseo/cli"]' "${BASE}/payload/paseo/package.json")"
PIN_AGY="$(sed -n 's/^AGY_VERSION="\([0-9.]*\)".*/\1/p' "${BASE}/payload/install/41-antigravity-cli.sh")"

n=0
R=""
newrepo() { n=$((n + 1)); cp -a "$BASE" "${SANDBOX}/r${n}"; R="${SANDBOX}/r${n}"; }
same() { # every upstream equals the pin
    reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"; reg "@openai%2Fcodex" "$PIN_CODEX" "git+https://github.com/openai/codex.git"
    reg "@getpaseo%2Fcli" "$PIN_PASEO"; agy_rel "$PIN_AGY" false false computed
}
b_rc=0; b_out=""
bump() { # bump <repo> args... ; sets b_rc b_out
    local repo="$1"; shift
    b_rc=0
    b_out="$( (cd "$repo" && env BUMP_NPM_REGISTRY="http://127.0.0.1:${PORT}" BUMP_GH_API="http://127.0.0.1:${PORT}/gh" BUMP_AGY_DL_PREFIX="http://127.0.0.1:${PORT}/dl/" \
        GH_TOKEN=tok-gh GITHUB_TOKEN=tok-github PATH="${FAKEBIN}:${PATH}" BUMP_PASEO_HELP_CMD="$HELPCMD" bash tools/bump-pins.sh "$@") 2>&1 )" || b_rc=$?
}
head_of() { git -C "$1" rev-parse HEAD; }
clean() { [[ -z "$(git -C "$1" status --porcelain)" ]]; }
commits() { git -C "$1" rev-list --count "$2..HEAD"; }
subject() { git -C "$1" log -1 --format=%s; }

# ---- 1. Nothing newer: empty report, exit 0, no commit, clean tree (F8) ---------------
same; newrepo; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep1.json"
{ [[ "$b_rc" == 0 && "$(head_of "$R")" == "$before" ]] && clean "$R" && [[ "$(jq '.changes | length' "${SANDBOX}/rep1.json")" == 0 && "$(jq '.up_to_date | length' "${SANDBOX}/rep1.json")" == 4 ]]; } \
    && ok "same versions: exit 0, empty changes, four up_to_date, no commit, clean tree" || bad "same versions (rc=$b_rc out=$b_out)"

# ---- 2. Newer stable: claude-code bumped, lockfile + report + commit (F7) -------------
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; newrepo; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep2.json"
{ [[ "$b_rc" == 0 ]] && [[ "$(commits "$R" "$before")" == 1 && "$(subject "$R")" == "chore(deps): bump claude-code ${PIN_CLAUDE} -> 9.8.7" ]] \
  && [[ "$(jq -r '.dependencies["@anthropic-ai/claude-code"]' "$R/payload/pins/claude-code/package.json")" == 9.8.7 ]] \
  && [[ "$(jq -r '.packages["node_modules/@anthropic-ai/claude-code"].version' "$R/payload/pins/claude-code/package-lock.json")" == 9.8.7 ]] \
  && [[ "$(jq -r '.changes[0] | "\(.tool) \(.from) \(.to)"' "${SANDBOX}/rep2.json")" == "claude-code ${PIN_CLAUDE} 9.8.7" ]] \
  && jq -e '.changes[0].integrity | startswith("lockfile integrity sha512-")' "${SANDBOX}/rep2.json" >/dev/null \
  && jq -e '.changes[0].notes_url | contains("npmjs.com/package/@anthropic-ai/claude-code")' "${SANDBOX}/rep2.json" >/dev/null && clean "$R"; } \
    && ok "newer stable: package.json + lockfile rewritten, one commit, report has tool/from/to/integrity/npm-page link" || bad "claude bump (rc=$b_rc out=$b_out)"
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"

# ---- 3. A pre-release `latest` is never followed (E1, M1) -----------------------------
reg "@openai%2Fcodex" "2.0.0-rc.1" "git+https://github.com/openai/codex.git"; newrepo; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep3.json"
{ [[ "$b_rc" == 0 && "$(head_of "$R")" == "$before" ]] && clean "$R" && grep -q 'not a stable version' <<<"$b_out"; } \
    && ok "latest pointing at 2.0.0-rc.1: not picked, no commit, exit 0, reported as not stable" || bad "rc tag was followed or not reported (rc=$b_rc out=$b_out)"
odd_ok=1
for v in 1.2.3-beta.1 1.2.3+build 1.2 v1.2.3; do
    reg "@openai%2Fcodex" "$v" "git+https://github.com/openai/codex.git"; newrepo; before="$(head_of "$R")"; bump "$R"
    if [[ "$b_rc" != 0 || "$(head_of "$R")" != "$before" ]]; then odd_ok=0; echo "odd version '$v' was followed" >&2; fi
done
[[ "$odd_ok" == 1 ]] && ok "beta, build-metadata, short and v-prefixed versions are never picked" || bad "an odd version string was followed"

# ---- 4. A lower upstream is never followed (R10, E9) ----------------------------------
reg "@openai%2Fcodex" "0.0.9" "git+https://github.com/openai/codex.git"; newrepo; before="$(head_of "$R")"
bump "$R"
{ [[ "$b_rc" == 0 && "$(head_of "$R")" == "$before" ]] && clean "$R" && jq -e --arg p "$PIN_CODEX" '.dependencies["@openai/codex"] == $p' "$R/payload/pins/codex/package.json" >/dev/null; } \
    && ok "upstream lower than the pin: no downgrade, no commit" || bad "bot followed a downgrade (rc=$b_rc out=$b_out)"
reg "@openai%2Fcodex" "10.0.0" "git+https://github.com/openai/codex.git"; newrepo; bump "$R" --only codex --report "${SANDBOX}/rep4b.json"
{ [[ "$b_rc" == 0 && "$(jq -r '.changes[0].to' "${SANDBOX}/rep4b.json")" == 10.0.0 ]] && jq -e '.changes[0].notes_url == "https://github.com/openai/codex/releases"' "${SANDBOX}/rep4b.json" >/dev/null; } \
    && ok "versions compare numerically (0.166.0 -> 10.0.0) and the codex link comes from its repository field" || bad "numeric comparison or repository link (rc=$b_rc out=$b_out)"
reg "@openai%2Fcodex" "$PIN_CODEX" "git+https://github.com/openai/codex.git"

# ---- 5. Two tools bumped: two commits, two report entries (F11) -----------------------
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; reg "@openai%2Fcodex" "7.7.7" "git+https://github.com/openai/codex.git"; newrepo; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep5.json"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 2 && "$(jq '.changes | length' "${SANDBOX}/rep5.json")" == 2 ]] \
  && git -C "$R" log --format=%s "$before..HEAD" | grep -q 'bump claude-code' && git -C "$R" log --format=%s "$before..HEAD" | grep -q 'bump codex'; } \
    && ok "two tools newer: one commit each, two entries in the report" || bad "two-tool bump (rc=$b_rc commits=$(commits "$R" "$before") out=$b_out)"
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"; reg "@openai%2Fcodex" "$PIN_CODEX" "git+https://github.com/openai/codex.git"

# ---- 6. Paseo: the three edits, the help fixture, and the paseo test (F9, M3) ---------
reg "@getpaseo%2Fcli" "0.99.0"; newrepo; before="$(head_of "$R")"
bump "$R" --only paseo --report "${SANDBOX}/rep6.json"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 ]] \
  && [[ "$(jq -r '.dependencies["@getpaseo/cli"]' "$R/payload/paseo/package.json")" == 0.99.0 \
     && "$(jq -r '.packages["node_modules/@getpaseo/cli"].version' "$R/payload/paseo/package-lock.json")" == 0.99.0 ]] \
  && grep -qx 'PASEO_PIN="0.99.0"' "$R/payload/lib/paseo.sh" \
  && [[ -s "$R/payload/test/fixtures/paseo-0.99.0-run-help.txt" && ! -e "$R/payload/test/fixtures/paseo-${PIN_PASEO}-run-help.txt" ]] && clean "$R"; } \
    && ok "paseo bump: package.json, lockfile, PASEO_PIN and the run-help fixture change together in one commit" || bad "paseo bump (rc=$b_rc out=$b_out)"
if (cd "$R" && bash payload/test/paseo.sh >"${SANDBOX}/paseo-after.log" 2>&1); then
    ok "payload/test/paseo.sh still passes after the bump"
else
    bad "payload/test/paseo.sh fails after the bump: $(grep -m4 ' FAIL: \|passed,' "${SANDBOX}/paseo-after.log" | tr '\n' '|')"
fi
[[ "$(cat "${SANDBOX}/helpenv")" == "unset/unset" ]] \
    && ok "the code that runs the new Paseo tree (paseo run --help) sees neither GH_TOKEN nor GITHUB_TOKEN" || bad "a token reached the downloaded Paseo code: $(cat "${SANDBOX}/helpenv")"
reg "@getpaseo%2Fcli" "$PIN_PASEO"

# ---- 7. Paseo absent (FEAT-035 not on the branch): skipped, the rest still bumps (E7) -
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; newrepo
git -C "$R" rm -q -r payload/paseo && git -C "$R" commit -q -m "no paseo"; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep7.json"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 ]] && jq -e '.skipped[] | select(.tool == "paseo")' "${SANDBOX}/rep7.json" >/dev/null && grep -q 'Paseo is not on this branch' <<<"$b_out"; } \
    && ok "payload/paseo absent: Paseo skipped with a clear message, claude-code still bumped, exit 0" || bad "missing-paseo handling (rc=$b_rc out=$b_out)"
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"

# ---- 8. agy: a good bump, constants rewritten, both hashes printed (F10, E8) ----------
agy_rel "1.9.0" false false computed; newrepo; before="$(head_of "$R")"
bump "$R" --only agy --report "${SANDBOX}/rep8.json"
want_sha="$(sha256sum "${FIX}/dl/agy-1.9.0.tgz" | cut -d' ' -f1)"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 ]] \
  && grep -qx "AGY_SHA256_LINUX_X64=\"${want_sha}\"" "$R/payload/install/41-antigravity-cli.sh" \
  && grep -q '^AGY_VERSION="1.9.0"' "$R/payload/install/41-antigravity-cli.sh" \
  && jq -e --arg s "$want_sha" '.changes[0].integrity | contains("computed") and contains($s)' "${SANDBOX}/rep8.json" >/dev/null && clean "$R"; } \
    && ok "agy bump: AGY_VERSION and AGY_SHA256_LINUX_X64 rewritten, report prints the computed hash and the API digest" || bad "agy bump (rc=$b_rc out=$b_out)"
sed -i -E 's/^AGY_VERSION="[0-9.]+"/AGY_VERSION="1.3.0"/' "$R/payload/install/41-antigravity-cli.sh"
git -C "$R" commit -q -am "agy 1.3.0"; agy_rel "1.9.1" false false computed; bump "$R" --only agy
{ [[ "$b_rc" == 0 ]] && grep -q '^AGY_VERSION="1.9.1"' "$R/payload/install/41-antigravity-cli.sh" && ! grep -n '1\.1\.0' "${REPO_ROOT}/tools/bump-pins.sh" >/dev/null; } \
    && ok "agy: the current pin is read at run time (1.3.0 -> 1.9.1); no version is hardcoded in the script" || bad "agy pin not read at run time (rc=$b_rc out=$b_out)"

# ---- 9. agy digest mismatch: exit non-zero, NOTHING written, not even other tools (E4, M2) ----
agy_rel "1.9.0" false false "$(printf '0%.0s' $(seq 1 64))"; reg "@anthropic-ai%2Fclaude-code" "9.8.7"; newrepo; before="$(head_of "$R")"
bump "$R"
{ [[ "$b_rc" == 3 && "$(head_of "$R")" == "$before" ]] && clean "$R" && grep -q 'FATAL' <<<"$b_out"; } \
    && ok "agy sha256 != published digest: exit 3, no commit, working tree clean (claude-code's newer version was not kept either)" || bad "agy mismatch was not fatal/clean (rc=$b_rc out=$b_out)"
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"

# ---- 10. agy asset without a digest: not bumped, said so, the rest continues (R9, E5) -
agy_rel "1.9.0" false false none; reg "@anthropic-ai%2Fclaude-code" "9.8.7"; newrepo; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep10.json"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 ]] && jq -e '.skipped[] | select(.tool == "agy") | .reason | contains("no published digest")' "${SANDBOX}/rep10.json" >/dev/null \
  && grep -q "AGY_VERSION=\"${PIN_AGY}\"" "$R/payload/install/41-antigravity-cli.sh"; } \
    && ok "agy asset with no digest: agy not bumped and reported as skipped; claude-code still bumped" || bad "missing agy digest (rc=$b_rc out=$b_out)"
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"

# ---- 11. agy pre-release / draft releases are never chosen (E3) -----------------------
rel_ok=1
for pd in "true false" "false true"; do
    # shellcheck disable=SC2086
    agy_rel "1.9.0" $pd computed; newrepo; before="$(head_of "$R")"; bump "$R" --only agy
    if [[ "$(head_of "$R")" != "$before" ]]; then rel_ok=0; echo "agy release (prerelease draft = $pd) was chosen" >&2; fi
done
[[ "$rel_ok" == 1 ]] && ok "agy: a pre-release release and a draft release are never chosen" || bad "agy pre-release or draft was chosen"
agy_rel "$PIN_AGY" false false computed

# ---- 12. Unreachable / malformed upstream (R8, E6) -----------------------------------
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; echo 500 > "${FIX}/@openai%2Fcodex/latest.status"; newrepo; before="$(head_of "$R")"
bump "$R" --report "${SANDBOX}/rep12.json"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 && "$(subject "$R")" == *claude-code* ]] && jq -e '.errors[] | select(.tool == "codex")' "${SANDBOX}/rep12.json" >/dev/null \
  && jq -e --arg p "$PIN_CODEX" '.dependencies["@openai/codex"] == $p' "$R/payload/pins/codex/package.json" >/dev/null && clean "$R"; } \
    && ok "registry 500 for one tool: that pin is untouched and reported, the others still bump, exit 0" || bad "one tool down (rc=$b_rc out=$b_out)"
rm -f "${FIX:?}/@openai%2Fcodex/latest.status"
echo '{"version": ' > "${FIX}/@openai%2Fcodex/latest"; newrepo; before="$(head_of "$R")"; bump "$R" --only codex
{ [[ "$b_rc" == 1 && "$(head_of "$R")" == "$before" ]] && clean "$R"; } \
    && ok "malformed JSON and no tool checked: exit 1, nothing changed" || bad "malformed JSON (rc=$b_rc out=$b_out)"
reg "@openai%2Fcodex" "$PIN_CODEX" "git+https://github.com/openai/codex.git"
newrepo; before="$(head_of "$R")"
b_rc=0; b_out="$( (cd "$R" && env BUMP_NPM_REGISTRY="http://127.0.0.1:1" BUMP_GH_API="http://127.0.0.1:1/gh" PATH="${FAKEBIN}:${PATH}" bash tools/bump-pins.sh) 2>&1 )" || b_rc=$?
{ [[ "$b_rc" == 1 && "$(head_of "$R")" == "$before" ]] && clean "$R"; } \
    && ok "everything unreachable: exit 1 and no commit" || bad "unreachable upstream (rc=$b_rc out=$b_out)"

# ---- 13. A lockfile regeneration failure leaves that tool's files restored ----------------
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; reg "@openai%2Fcodex" "7.7.7" "git+https://github.com/openai/codex.git"; newrepo; before="$(head_of "$R")"
FAKE_NPM_FAIL_PKG="@anthropic-ai/claude-code" bump "$R" --report "${SANDBOX}/rep13.json"
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 && "$(subject "$R")" == *codex* ]] && clean "$R" && jq -e '.errors[] | select(.tool == "claude-code")' "${SANDBOX}/rep13.json" >/dev/null; } \
    && ok "npm fails for one tool: its files are restored, no partial commit, the other tool is committed" || bad "npm failure handling (rc=$b_rc out=$b_out)"
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"; reg "@openai%2Fcodex" "$PIN_CODEX" "git+https://github.com/openai/codex.git"

# ---- 14. Only /<pkg>/latest is ever requested (E10, M13) -----------------------------------
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; newrepo; : > "$REQLOG"; bump "$R" >/dev/null 2>&1 || true
reqs="$(grep -c . "$REQLOG" || true)"
if [[ "$reqs" -gt 0 ]] && ! grep -vE '/latest$|/dl/' "$REQLOG" | grep -q .; then
    ok "every request is /<pkg>/latest, the releases/latest document or the asset ($reqs requests); no packument"
else
    bad "unexpected requests: $(grep -vE '/latest$|/dl/' "$REQLOG" | tr '\n' ' ')"
fi
reg "@anthropic-ai%2Fclaude-code" "$PIN_CLAUDE"

# ---- 15. --dry-run writes nothing and commits nothing; --only; usage (E11) ---------------
reg "@anthropic-ai%2Fclaude-code" "9.8.7"; reg "@openai%2Fcodex" "7.7.7" "git+https://github.com/openai/codex.git"; newrepo; before="$(head_of "$R")"
bump "$R" --dry-run --report "${SANDBOX}/rep15.json"
{ [[ "$b_rc" == 0 && "$(head_of "$R")" == "$before" ]] && clean "$R" && jq -e '.would_bump == ["claude-code","codex"] and .changes == [] and .dry_run == true' "${SANDBOX}/rep15.json" >/dev/null \
  && grep -q "claude-code: ${PIN_CLAUDE} -> 9.8.7" <<<"$b_out"; } \
    && ok "--dry-run prints current -> latest per tool, writes nothing, commits nothing" || bad "dry run (rc=$b_rc out=$b_out)"
bump "$R" --only codex
{ [[ "$b_rc" == 0 && "$(commits "$R" "$before")" == 1 && "$(subject "$R")" == *codex* ]]; } && ok "--only codex touches codex alone" || bad "--only (rc=$b_rc out=$b_out)"
bump "$R" --only nonsense
[[ "$b_rc" == 2 ]] && ok "--only with an unknown tool is a usage error (exit 2)" || bad "--only nonsense rc=$b_rc"
echo "# dirty" >> "$R/payload/lib/paseo.sh"
bump "$R"
{ [[ "$b_rc" == 2 ]] && grep -q 'uncommitted' <<<"$b_out"; } && ok "a dirty working tree is refused before anything is bumped" || bad "dirty tree accepted (rc=$b_rc out=$b_out)"

# ---- 16. Links and URLs that come from upstream are validated ----------------------------------
reg "@openai%2Fcodex" "7.7.7" "git+https://evil.example/openai/codex.git"; newrepo; bump "$R" --only codex --report "${SANDBOX}/rep16.json"
{ [[ "$b_rc" == 0 ]] && jq -e '.changes[0].notes_url | startswith("https://www.npmjs.com/package/@openai/codex/")' "${SANDBOX}/rep16.json" >/dev/null; } \
    && ok "a repository URL that is not https://github.com/<owner>/<repo> is not used as a link: the npm page instead" || bad "foreign repository URL was used (rc=$b_rc out=$b_out)"
reg "@openai%2Fcodex" "$PIN_CODEX" "git+https://github.com/openai/codex.git"
agy_rel "1.9.0" false false computed
jq '.assets[0].browser_download_url = "https://evil.example/agy.tgz"' "${GH_DIR}/latest" > "${GH_DIR}/latest.new" && mv "${GH_DIR}/latest.new" "${GH_DIR}/latest"
newrepo; before="$(head_of "$R")"; bump "$R" --only agy --report "${SANDBOX}/rep16b.json"
{ [[ "$(head_of "$R")" == "$before" ]] && clean "$R"; } \
    && ok "an agy asset URL outside the project's release downloads is never fetched or pinned" || bad "agy asset from a foreign host was accepted (rc=$b_rc out=$b_out)"
agy_rel "$PIN_AGY" false false computed

# ---- 17. Third-party code runs with NO CI environment at all (token isolation) --------------------------
# A compromised Paseo can write BASH_ENV/LD_PRELOAD/PATH into $GITHUB_ENV / $GITHUB_PATH and poison later steps
# that DO carry the token, so unsetting GH_TOKEN is not enough: nothing GITHUB_*, RUNNER_* or secret-like may
# be visible. Both ways the bot runs the new tree are covered: the real path (npm ci, then `paseo run --help`
# from the installed tree) and the BUMP_PASEO_HELP_CMD seam.
EVIL="${SANDBOX}/evil-paseo"
cat > "$EVIL" <<EOS
#!/usr/bin/env bash
# Plays a hostile "paseo": tries every channel a workflow step leaves open, records what it can see.
echo "BASH_ENV=/tmp/poisoned" >> "\${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
echo "/tmp/poisoned-bin" >> "\${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
echo "owned=1" >> "\${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
env | cut -d= -f1 | sort > "${SANDBOX}/evil-seen-names"
printf '%s' "\${GH_TOKEN:-unset}/\${GITHUB_TOKEN:-unset}" > "${SANDBOX}/evil-seen-token"
cat "${PAYLOAD_DIR}/test/fixtures/paseo-\$(sed -n 's/^PASEO_PIN="\\(.*\\)"\$/\\1/p' "${PAYLOAD_DIR}/lib/paseo.sh")-run-help.txt"
EOS
chmod +x "$EVIL"
evil_run() { # evil_run <seam|real> ; sets e_rc
    : > "${SANDBOX}/gh_env"; : > "${SANDBOX}/gh_path"; : > "${SANDBOX}/gh_out"; rm -f "${SANDBOX}/evil-seen-names" "${SANDBOX}/evil-seen-token"
    reg "@getpaseo%2Fcli" "0.99.0"; newrepo
    e_rc=0
    local seam_env=(); [[ "$1" != seam ]] || seam_env=("BUMP_PASEO_HELP_CMD=$EVIL")
    ( cd "$R" && env BUMP_NPM_REGISTRY="http://127.0.0.1:${PORT}" BUMP_GH_API="http://127.0.0.1:${PORT}/gh" BUMP_AGY_DL_PREFIX="http://127.0.0.1:${PORT}/dl/" \
        GH_TOKEN=tok-gh GITHUB_TOKEN=tok-github GITHUB_ENV="${SANDBOX}/gh_env" GITHUB_PATH="${SANDBOX}/gh_path" GITHUB_OUTPUT="${SANDBOX}/gh_out" \
        GITHUB_STEP_SUMMARY="${SANDBOX}/gh_sum" GITHUB_STATE="${SANDBOX}/gh_state" RUNNER_TEMP="${SANDBOX}" RUNNER_TOOL_CACHE=/opt/x ACTIONS_RUNTIME_TOKEN=rt-secret \
        "${seam_env[@]}" PATH="${FAKEBIN}:${PATH}" \
        bash tools/bump-pins.sh --only paseo ) >/dev/null 2>&1 || e_rc=$?
}
for way in seam real; do
    evil_run "$way"
    { [[ "$e_rc" == 0 && -s "${SANDBOX}/evil-seen-names" ]] \
      && [[ ! -s "${SANDBOX}/gh_env" && ! -s "${SANDBOX}/gh_path" && ! -s "${SANDBOX}/gh_out" ]] \
      && [[ "$(cat "${SANDBOX}/evil-seen-token")" == "unset/unset" ]] \
      && ! grep -qE '^(GITHUB_|RUNNER_|ACTIONS_|GH_|INPUT_)' "${SANDBOX}/evil-seen-names" && grep -qx PATH "${SANDBOX}/evil-seen-names"; } \
        && ok "third-party Paseo code ($way path) sees no GITHUB_*/RUNNER_*/ACTIONS_* variable and no token; its writes to GITHUB_ENV, GITHUB_PATH and GITHUB_OUTPUT go nowhere" \
        || bad "($way) hostile Paseo saw the CI environment (rc=$e_rc names=$(tr '\n' ' ' < "${SANDBOX}/evil-seen-names" 2>/dev/null | cut -c1-200) env-file=$(wc -c < "${SANDBOX}/gh_env") token=$(cat "${SANDBOX}/evil-seen-token" 2>/dev/null))"
done
reg "@getpaseo%2Fcli" "$PIN_PASEO"
{ ! grep -v '^ *#' "${REPO_ROOT}/tools/bump-pins.sh" | grep -q 'env -u' && grep -v '^ *#' "${REPO_ROOT}/tools/bump-pins.sh" | grep -c 'pin_run_isolated' | grep -qx '[3-9]'; } \
    && ok "bump-pins.sh runs downloaded code only through pin_run_isolated (env -i); no env -u left" || bad "bump-pins.sh went back to env -u or lost pin_run_isolated"
