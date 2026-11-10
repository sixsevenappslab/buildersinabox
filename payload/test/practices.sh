#!/usr/bin/env bash
# Test suite for FEAT-037 (Practices Pack: verdicts, personal-refs guard,
# 3-column skill manifest + groups, add-only core skill sync on update).
#
# Locates the repo from BASH_SOURCE (or PAYLOAD_DIR override) so mutation runs
# on a /tmp copy test the copy, never the shared tree (§4.5).
# Skips verdict-file assertions cleanly when specs/ is absent (a public clone
# or extracted git archive, E-26).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="${PAYLOAD_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPO_ROOT="$(cd "${PAYLOAD_DIR}/.." && pwd)"

pass=0
fail=0
ok()  { echo "practices: ok: $*"; pass=$((pass + 1)); }
bad() { echo "practices: FAIL: $*" >&2; fail=$((fail + 1)); }

echo "== PK-01..PK-06: Verdict table & manifest consistency (F-01, F-40, E-25..E-27) =="

VERDICT_FILE="${REPO_ROOT}/specs/verdicts/practices-pack.tsv"
MANIFEST_FILE="${PAYLOAD_DIR}/skills/manifest.tsv"

# E-14: manifest has no CRLF line endings
if [[ "$(grep -c $'\r' "$MANIFEST_FILE" || true)" -eq 0 ]]; then
    ok "PK-01a: manifest.tsv has no CRLF line endings (E-14)"
else
    bad "PK-01a: manifest.tsv contains CRLF line endings"
fi

# Every directory under payload/skills/<dir>/SKILL.md has a manifest row, and vice versa
missing_in_manifest=0
for sdir in "${PAYLOAD_DIR}/skills"/*/; do
    [[ -d "$sdir" ]] || continue
    sname="$(basename "$sdir")"
    if ! awk -F'\t' -v s="$sname" '{sub(/\r$/,"")} !/^#/ && NF && $1==s {found=1} END{exit !found}' "$MANIFEST_FILE"; then
        bad "PK-01b: skill dir '$sname' has no row in manifest.tsv"
        missing_in_manifest=1
    fi
done
[[ "$missing_in_manifest" -eq 0 ]] && ok "PK-01b: every dir under payload/skills/ has a row in manifest.tsv"

missing_dir=0
while IFS=$'\t' read -r sname stier sgroup || [[ -n "${sname:-}" ]]; do
    sname="${sname%$'\r'}"; stier="${stier%$'\r'}"; sgroup="${sgroup%$'\r'}"
    [[ -z "$sname" || "$sname" == \#* ]] && continue
    if [[ ! -d "${PAYLOAD_DIR}/skills/${sname}" || ! -f "${PAYLOAD_DIR}/skills/${sname}/SKILL.md" ]]; then
        bad "PK-01c: manifest row '$sname' has no payload/skills/${sname}/SKILL.md"
        missing_dir=1
    fi
    if [[ "$stier" != "core" && "$stier" != "optional" ]]; then
        bad "PK-01c: manifest row '$sname' has invalid tier '$stier'"
        missing_dir=1
    fi
done < "$MANIFEST_FILE"
[[ "$missing_dir" -eq 0 ]] && ok "PK-01c: every manifest.tsv row points to an existing skill dir with valid tier"

validate_verdict_file() {
    local vf="$1"
    awk -F'\t' '
        { sub(/\r$/, "") }
        /^[[:space:]]*$/ || /^#/ { next }
        {
            rows++
            if (NF != 5) {
                printf "line %d: expected 5 tab-separated columns, got %d\n", NR, NF
                errs++
                next
            }
            kind = $1; canon = $2; verdict = $3; box = $4; reason = $5
            if (kind !~ /^(skill|hook|plugin|policy)$/) {
                printf "line %d: invalid kind \"%s\"\n", NR, kind
                errs++
            }
            if (verdict !~ /^(core|optional|shipped|deferred|personal)$/) {
                printf "line %d: invalid verdict \"%s\"\n", NR, verdict
                errs++
            }
            if (canon == "" || reason == "" || reason ~ /^[[:space:]]*$/) {
                printf "line %d: empty canon_name or reason\n", NR
                errs++
            }
            if ((verdict == "personal" || verdict == "deferred") && length(reason) < 15) {
                printf "line %d: personal/deferred reason too short to name private dependency: \"%s\"\n", NR, reason
                errs++
            }
            if ((verdict == "core" || verdict == "optional" || verdict == "shipped") && (box == "" || box == "-")) {
                printf "line %d: %s item \"%s\" must name its box_name\n", NR, verdict, canon
                errs++
            }
            key = kind SUBSEP canon
            if (seen[key]++) {
                printf "line %d: duplicate (kind, canon_name) pair (%s, %s)\n", NR, kind, canon
                errs++
            }
        }
        END {
            if (rows == 0) { print "no verdict rows found"; errs++ }
            if (errs == 0) printf "ROWS=%d\n", rows
            exit (errs > 0 ? 1 : 0)
        }
    ' "$vf"
}

if [[ ! -d "${REPO_ROOT}/specs" || ! -f "$VERDICT_FILE" ]]; then
    echo "practices: SKIP: specs/verdicts/practices-pack.tsv absent (public clone / git archive, E-26)"
    ok "PK-02: verdict checks skipped cleanly when specs/ is absent"
else
    vout="$(validate_verdict_file "$VERDICT_FILE" 2>&1)"
    if [[ $? -eq 0 ]]; then
        ok "PK-02: verdict file structure valid (${vout})"
    else
        bad "PK-02: verdict file invalid: ${vout}"
    fi

    # Every shipped skill dir has a non-personal/deferred verdict row matching box_name
    unverdicted_skill=0
    for sdir in "${PAYLOAD_DIR}/skills"/*/; do
        [[ -d "$sdir" ]] || continue
        sname="$(basename "$sdir")"
        if ! awk -F'\t' -v s="$sname" '
            {sub(/\r$/,"")}
            !/^#/ && NF==5 && $1=="skill" && $4==s && ($3=="core" || $3=="optional" || $3=="shipped") {found=1}
            END {exit !found}
        ' "$VERDICT_FILE"; then
            bad "PK-03a: shipped skill '$sname' has no core/optional/shipped row in practices-pack.tsv"
            unverdicted_skill=1
        fi
    done
    [[ "$unverdicted_skill" -eq 0 ]] && ok "PK-03a: every payload/skills/<dir> has a core/optional/shipped verdict row"

    # Every payload/hooks/biab-*.sh has a core/optional/shipped verdict row
    unverdicted_hook=0
    for hfile in "${PAYLOAD_DIR}/hooks"/biab-*.sh; do
        [[ -f "$hfile" ]] || continue
        hname="$(basename "$hfile")"
        if ! awk -F'\t' -v h="$hname" '
            {sub(/\r$/,"")}
            !/^#/ && NF==5 && $1=="hook" && $4==h && ($3=="core" || $3=="optional" || $3=="shipped") {found=1}
            END {exit !found}
        ' "$VERDICT_FILE"; then
            bad "PK-03b: hook '$hname' has no core/optional/shipped row in practices-pack.tsv"
            unverdicted_hook=1
        fi
    done
    [[ "$unverdicted_hook" -eq 0 ]] && ok "PK-03b: every payload/hooks/biab-*.sh has a core/optional/shipped verdict row"

    # F-40 / E-25: no personal or deferred skill or hook exists under payload/skills or payload/hooks
    leaked_item=0
    while IFS=$'\t' read -r kind canon verdict box _reason || [[ -n "${kind:-}" ]]; do
        kind="${kind%$'\r'}"
        [[ -z "$kind" || "$kind" == \#* ]] && continue
        if [[ "$verdict" == "personal" || "$verdict" == "deferred" ]]; then
            if [[ "$kind" == "skill" && ( -e "${PAYLOAD_DIR}/skills/${canon}" || ( "$box" != "-" && -e "${PAYLOAD_DIR}/skills/${box}" ) ) ]]; then
                bad "PK-04: ${verdict} skill '${canon}' exists under payload/skills/"
                leaked_item=1
            fi
            if [[ "$kind" == "hook" && ( -e "${PAYLOAD_DIR}/hooks/${canon}" || ( "$box" != "-" && -e "${PAYLOAD_DIR}/hooks/${box}" ) ) ]]; then
                bad "PK-04: ${verdict} hook '${canon}' exists under payload/hooks/"
                leaked_item=1
            fi
        fi
    done < "$VERDICT_FILE"
    [[ "$leaked_item" -eq 0 ]] && ok "PK-04: no personal or deferred skill/hook exists in payload/ (AC-1, AC-10)"

    # E-27: malformed verdict file rows turn validate_verdict_file red
    bad_vf="$(mktemp)"
    printf 'skill\tonly-four-cols\tcore\tbox\n' > "$bad_vf"
    if ! validate_verdict_file "$bad_vf" >/dev/null 2>&1; then
        ok "PK-05a: 4-column row rejected (E-27)"
    else
        bad "PK-05a: 4-column row was accepted"
    fi
    printf 'skill\tfoo\tshiped\tfoo\ttypo in verdict\n' > "$bad_vf"
    if ! validate_verdict_file "$bad_vf" >/dev/null 2>&1; then
        ok "PK-05b: misspelled verdict 'shiped' rejected (E-27)"
    else
        bad "PK-05b: misspelled verdict 'shiped' was accepted"
    fi
    printf 'skill\tfoo\tpersonal\t-\t\n' > "$bad_vf"
    if ! validate_verdict_file "$bad_vf" >/dev/null 2>&1; then
        ok "PK-05c: empty reason rejected (E-27)"
    else
        bad "PK-05c: empty reason was accepted"
    fi
    printf 'skill\tdup\tcore\tdup\treason one\nskill\tdup\toptional\tdup\treason two\n' > "$bad_vf"
    if ! validate_verdict_file "$bad_vf" >/dev/null 2>&1; then
        ok "PK-05d: duplicate (kind, canon_name) rejected (E-27)"
    else
        bad "PK-05d: duplicate (kind, canon_name) was accepted"
    fi
    rm -f "$bad_vf"
fi

# E-26: running practices.sh in a copy without specs/ skips verdict checks and exits 0
if [[ "${PK_SUBTEST_NO_SPECS:-0}" != "1" ]]; then
    no_specs_tmp="$(mktemp -d)"
    mkdir -p "$no_specs_tmp/payload" "$no_specs_tmp/tools"
    cp -r "${PAYLOAD_DIR}/skills" "${PAYLOAD_DIR}/hooks" "${PAYLOAD_DIR}/lib" "${PAYLOAD_DIR}/install" "${PAYLOAD_DIR}/test" "${PAYLOAD_DIR}/statusline" "${PAYLOAD_DIR}/docs" "${PAYLOAD_DIR}/skeleton" "${PAYLOAD_DIR}/templates" "${PAYLOAD_DIR}/install.sh" "$no_specs_tmp/payload/"
    cp "${REPO_ROOT}/tools/check-no-personal-refs.sh" "$no_specs_tmp/tools/"
    if PK_SUBTEST_NO_SPECS=1 PAYLOAD_DIR="$no_specs_tmp/payload" bash "$no_specs_tmp/payload/test/practices.sh" >/dev/null 2>&1; then
        ok "PK-06: practices.sh exits 0 when specs/ is absent (E-26)"
    else
        bad "PK-06: practices.sh failed when specs/ is absent"
    fi
    rm -rf "$no_specs_tmp"
fi

echo "== PK-07..PK-09: Personal-refs guard fixtures (F-02, F-03, E-28, E-29) =="

if [[ -x "${REPO_ROOT}/tools/check-no-personal-refs.sh" || -f "${REPO_ROOT}/tools/check-no-personal-refs.sh" ]]; then
    G="$(mktemp -d)"
    mkdir -p "$G/tools" "$G/payload/skills/x"
    cp "${REPO_ROOT}/tools/check-no-personal-refs.sh" "$G/tools/"

    # F-02 & E-28: forbidden maintainer/project/infra strings across file types and locales
    # (split in source so check-no-personal-refs.sh does not flag this test file, same pattern as starter-kit.sh:252)
    guard_caught_all=1
    fix_lower="Jes""ús ""ganga""24 ""MH ""Server"
    fix_upper="JES""ÚS ""GANGA""24 ""mh ""server ""MAC ""MINI"
    for fext in "SKILL.md" "helper.py" "config.json" ".hidden"; do
        rm -f "$G/payload/skills/x"/* "$G/payload/skills/x"/.* 2>/dev/null || true
        printf '%s\n' "$fix_lower" > "$G/payload/skills/x/$fext"
        for loc in C C.UTF-8; do
            out="$(LC_ALL="$loc" bash "$G/tools/check-no-personal-refs.sh" 2>&1)" && {
                bad "PK-07a: guard passed on fixture ($fext, LC_ALL=$loc)"
                guard_caught_all=0
            }
            for pat in "Jes" "ganga""24" "MH ""Server"; do
                if ! grep -Eqi "Found references to /[^/]*${pat}" <<<"$out"; then
                    bad "PK-07a: guard output missed pattern '$pat' ($fext, LC_ALL=$loc)"
                    guard_caught_all=0
                fi
            done
        done
    done
    # Uppercase variants (E-28)
    rm -f "$G/payload/skills/x"/* "$G/payload/skills/x"/.* 2>/dev/null || true
    printf '%s\n' "$fix_upper" > "$G/payload/skills/x/SKILL.md"
    if LC_ALL=C.UTF-8 bash "$G/tools/check-no-personal-refs.sh" >/dev/null 2>&1; then
        bad "PK-07b: guard passed on uppercase/mixed-case fixture (E-28)"
        guard_caught_all=0
    fi
    [[ "$guard_caught_all" -eq 1 ]] && ok "PK-07: guard exits 1 on forbidden maintainer/project/server strings across files & locales (F-02, E-28)"

    # E-29: false positives (ai-platform, stratops, sixseven, Sofia) must exit 0
    rm -f "$G/payload/skills/x"/* "$G/payload/skills/x"/.* 2>/dev/null || true
    printf 'Workspace ~/ai-platform/stratops built by SixSeven Apps for Sofia.\n' > "$G/payload/skills/x/SKILL.md"
    if bash "$G/tools/check-no-personal-refs.sh" >/dev/null 2>&1; then
        ok "PK-08: guard exits 0 on ai-platform, stratops, sixseven and Sofia (E-29)"
    else
        bad "PK-08: guard false-positived on clean text (E-29)"
    fi
    rm -rf "$G"
fi

echo "== PK-10..PK-15: 3-column manifest, skill groups, add-only sync & symlinks (F-04..F-12, E-09..E-22) =="

# Source libs in a subshell-friendly way
# shellcheck source=../lib/common.sh
source "${PAYLOAD_DIR}/lib/common.sh"
# shellcheck source=../lib/ai-cli.sh
source "${PAYLOAD_DIR}/lib/ai-cli.sh"
# shellcheck source=../lib/paseo.sh
source "${PAYLOAD_DIR}/lib/paseo.sh"
# shellcheck source=../lib/guard.sh
source "${PAYLOAD_DIR}/lib/guard.sh"
# shellcheck source=../lib/user-content.sh
source "${PAYLOAD_DIR}/lib/user-content.sh"
set +e

# F-04 & E-13: 3-column manifest with mixed groups and empty 3rd column installs core rows
T4="$(mktemp -d)"
export BIB_LOG_DIR="$T4/log" BIB_LOG_FILE="$T4/log/bootstrap.log"
mkdir -p "$BIB_LOG_DIR" "$T4/skills/alpha" "$T4/skills/beta" "$T4/skills/gamma" "$T4/home"
printf '# name: alpha\n' > "$T4/skills/alpha/SKILL.md"
printf '# name: beta\n'  > "$T4/skills/beta/SKILL.md"
printf '# name: gamma\n' > "$T4/skills/gamma/SKILL.md"
cat > "$T4/skills/manifest.tsv" <<'EOF'
# 3-col test manifest
alpha	core	g1
beta	core	
gamma	optional	g1
EOF
uc_sync_core_skills "$T4/home" "claude" "$T4/skills" >/dev/null 2>&1
if [[ -f "$T4/home/.agents/skills/alpha/SKILL.md" && -f "$T4/home/.agents/skills/beta/SKILL.md" && ! -e "$T4/home/.agents/skills/gamma" && -L "$T4/home/.claude/skills/alpha" && -L "$T4/home/.claude/skills/beta" ]]; then
    ok "PK-10: 3-column manifest installs core rows and skips optional rows (F-04, E-13)"
else
    bad "PK-10: 3-column manifest failed: $(ls -la "$T4/home/.agents/skills" 2>&1)"
fi
rm -rf "$T4"

# Antigravity skills dirs parity (D11): links into .claude/skills, .gemini/skills, .gemini/antigravity-cli/skills, .gemini/config/skills
Tagy="$(mktemp -d)"
export BIB_LOG_DIR="$Tagy/log" BIB_LOG_FILE="$Tagy/log/bootstrap.log"
mkdir -p "$BIB_LOG_DIR" "$Tagy/skills/alpha" "$Tagy/home"
printf '# name: alpha\n' > "$Tagy/skills/alpha/SKILL.md"
printf 'alpha\tcore\n' > "$Tagy/skills/manifest.tsv"
uc_sync_core_skills "$Tagy/home" "antigravity" "$Tagy/skills" >/dev/null 2>&1
if [[ -L "$Tagy/home/.claude/skills/alpha" \
   && -L "$Tagy/home/.gemini/skills/alpha" \
   && -L "$Tagy/home/.gemini/antigravity-cli/skills/alpha" \
   && -L "$Tagy/home/.gemini/config/skills/alpha" ]]; then
    ok "PK-10b: antigravity box symlinks skills into all 4 discovery directories (D11)"
else
    bad "PK-10b: antigravity skill symlinks missing"
fi
rm -rf "$Tagy"

# F-05, F-08, E-15..E-19: `biab add` skill and group resolution, comma-separated usage
Tadd="$(mktemp -d)"
mkdir -p "$Tadd/home" "$Tadd/opt/payload/skills/s-core" "$Tadd/opt/payload/skills/s-opt1" "$Tadd/opt/payload/skills/s-opt2" "$Tadd/opt/payload/skills/grp-clash"
cp -r "${PAYLOAD_DIR}/lib" "$Tadd/opt/payload/"
for d in s-core s-opt1 s-opt2 grp-clash; do
    printf '# %s\n' "$d" > "$Tadd/opt/payload/skills/$d/SKILL.md"
done
cat > "$Tadd/opt/payload/skills/manifest.tsv" <<'EOF'
s-core	core
s-opt1	optional	mygroup
s-opt2	optional	mygroup
grp-clash	optional	othergrp
s-other	optional	grp-clash
EOF
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh" \
    | sed "s#/opt/buildersinabox#$Tadd/opt#g" > "$Tadd/biab"

# F-08 (1) & E-18: no arg / empty arg -> rc 1, comma-separated usage listing group + optional skills
u_out="$(HOME="$Tadd/home" bash "$Tadd/biab" add "" 2>&1)"
u_rc=$?
if [[ "$u_rc" -eq 1 ]] && grep -q "mygroup, s-opt1, s-opt2" <<<"$u_out"; then
    ok "PK-11a: 'biab add' with empty arg exits 1 with comma-separated usage (F-08, Q-3, E-18)"
else
    bad "PK-11a: 'biab add' empty arg failed (rc=$u_rc, out=$u_out)"
fi

# F-08 (2) & E-15: unknown group -> rc 1
if ! HOME="$Tadd/home" bash "$Tadd/biab" add nonexistent >/dev/null 2>&1; then
    ok "PK-11b: 'biab add nonexistent' exits 1 (E-15)"
else
    bad "PK-11b: 'biab add nonexistent' succeeded unexpectedly"
fi

# F-08 (3): core skill -> already installed, rc 0
c_out="$(HOME="$Tadd/home" bash "$Tadd/biab" add s-core 2>&1)"
if [[ $? -eq 0 ]] && grep -q "core skill" <<<"$c_out"; then
    ok "PK-11c: 'biab add <core>' reports already installed and exits 0 (F-08)"
else
    bad "PK-11c: 'biab add <core>' failed ($c_out)"
fi

# Group install: installs all skills in group, second run reports already installed and preserves edits (E-19, MU-22, MU-23)
HOME="$Tadd/home" bash "$Tadd/biab" add mygroup >/dev/null 2>&1
if [[ -f "$Tadd/home/.agents/skills/s-opt1/SKILL.md" && -f "$Tadd/home/.agents/skills/s-opt2/SKILL.md" ]]; then
    ok "PK-11d: 'biab add <group>' installs every skill in the group (MU-21, MU-22)"
else
    bad "PK-11d: 'biab add mygroup' did not install both skills"
fi
printf 'user edit\n' >> "$Tadd/home/.agents/skills/s-opt1/SKILL.md"
sha_before="$(sha256sum "$Tadd/home/.agents/skills/s-opt1/SKILL.md" | awk '{print $1}')"
HOME="$Tadd/home" bash "$Tadd/biab" add mygroup >/dev/null 2>&1
second_out="$(HOME="$Tadd/home" bash "$Tadd/biab" add s-opt1 2>&1)"
sha_after="$(sha256sum "$Tadd/home/.agents/skills/s-opt1/SKILL.md" | awk '{print $1}')"
if [[ "$sha_before" == "$sha_after" && ! -e "$Tadd/home/.agents/skills/s-opt1/s-opt1" ]] \
   && grep -q "'s-opt1' is already installed" <<<"$second_out"; then
    ok "PK-11e: 'biab add' reports already installed and never overwrites an edited skill (F-05, E-19, MU-23)"
else
    bad "PK-11e: 'biab add' overwrote or re-copied an existing skill (out=$second_out)"
fi

# E-17: skill name wins over group name when they share a name (`grp-clash` is both a skill and a group for `s-other`)
HOME="$Tadd/home" bash "$Tadd/biab" add grp-clash >/dev/null 2>&1
if [[ -d "$Tadd/home/.agents/skills/grp-clash" && ! -e "$Tadd/home/.agents/skills/s-other" ]]; then
    ok "PK-11f: skill name wins over group name on collision (E-17)"
else
    bad "PK-11f: group name overrode skill name on collision"
fi
rm -rf "$Tadd"

# F-09, F-10, E-09: add-only sync on a temp HOME with a space in the path, an edited core skill, and a missing core skill
Tsync="$(mktemp -d)"
SPACE_HOME="$Tsync/my home"
mkdir -p "$SPACE_HOME/.agents/skills/code-review" "$Tsync/skills/code-review" "$Tsync/skills/spec-implementer"
printf 'upstream code-review\n' > "$Tsync/skills/code-review/SKILL.md"
printf 'upstream spec-implementer\n' > "$Tsync/skills/spec-implementer/SKILL.md"
printf 'user customised code-review\n' > "$SPACE_HOME/.agents/skills/code-review/SKILL.md"
cat > "$Tsync/skills/manifest.tsv" <<'EOF'
code-review	core
spec-implementer	core
EOF
edit_sha_before="$(sha256sum "$SPACE_HOME/.agents/skills/code-review/SKILL.md" | awk '{print $1}')"
uc_sync_core_skills "$SPACE_HOME" "claude" "$Tsync/skills" >/dev/null 2>&1
edit_sha_after="$(sha256sum "$SPACE_HOME/.agents/skills/code-review/SKILL.md" | awk '{print $1}')"
if [[ -f "$SPACE_HOME/.agents/skills/spec-implementer/SKILL.md" \
   && -L "$SPACE_HOME/.claude/skills/spec-implementer" \
   && ! -e "$SPACE_HOME/.agents/skills/code-review/code-review" \
   && "$edit_sha_before" == "$edit_sha_after" ]]; then
    ok "PK-12a: uc_sync_core_skills adds missing core skill and leaves edited skill byte-identical, including HOME with space (F-09, E-09, MU-14)"
else
    bad "PK-12a: uc_sync_core_skills failed (edit_sha_before=$edit_sha_before, after=$edit_sha_after)"
fi

# F-10: second run is a complete no-op
snap1="$(find "$SPACE_HOME" -printf '%P %y %s\n' | sort)"
uc_sync_core_skills "$SPACE_HOME" "claude" "$Tsync/skills" >/dev/null 2>&1
snap2="$(find "$SPACE_HOME" -printf '%P %y %s\n' | sort)"
if [[ "$snap1" == "$snap2" ]]; then
    ok "PK-12b: second uc_sync_core_skills run changes nothing (F-10)"
else
    bad "PK-12b: second uc_sync_core_skills run modified the tree"
fi
rm -rf "$Tsync"

# E-10, E-11, MU-15: symlinked ~/.agents or ~/.claude is refused without writing through the link
Tlink="$(mktemp -d)"
mkdir -p "$Tlink/elsewhere" "$Tlink/home" "$Tlink/skills/alpha"
printf 'untouched\n' > "$Tlink/elsewhere/sentinel"
printf '# alpha\n' > "$Tlink/skills/alpha/SKILL.md"
printf 'alpha\tcore\n' > "$Tlink/skills/manifest.tsv"
ln -s "$Tlink/elsewhere" "$Tlink/home/.agents"
ln -s "$Tlink/elsewhere" "$Tlink/home/.claude"
uc_sync_core_skills "$Tlink/home" "claude" "$Tlink/skills" >/dev/null 2>&1 || true
uc_seed_hooks "$Tlink/home" "claude" >/dev/null 2>&1 || true
if [[ ! -e "$Tlink/elsewhere/skills" && ! -e "$Tlink/elsewhere/settings.json" && "$(cat "$Tlink/elsewhere/sentinel")" == "untouched" ]]; then
    ok "PK-13: symlinked ~/.agents and ~/.claude are refused and target is untouched (E-10, E-11, MU-15)"
else
    bad "PK-13: wrote through symlinked ~/.agents or ~/.claude into target"
fi
rm -rf "$Tlink"

# F-11, E-21, E-22, E-34, MU-16: 48-user-content.sh executable bit, install.sh registration, scaffold_done gate, user home isolation
if [[ -x "${PAYLOAD_DIR}/install/48-user-content.sh" ]] && grep -q 'run_install "install/48-user-content.sh"' "${PAYLOAD_DIR}/install.sh"; then
    ok "PK-14a: 48-user-content.sh is executable and registered in install.sh (F-11, E-34)"
else
    bad "PK-14a: 48-user-content.sh missing +x or not in payload/install.sh"
fi

T48="$(mktemp -d)"
mkdir -p "$T48/state" "$T48/log" "$T48/root-home" "$T48/user-home"
export BIB_STATE_DIR="$T48/state" BIB_STATE_FILE="$T48/state/state.json"
export BIB_LOG_DIR="$T48/log" BIB_LOG_FILE="$T48/log/bootstrap.log"
printf '{"version":2,"bib_user":"%s","ai_cli":"claude","phases":{}}\n' "$(id -un)" > "$BIB_STATE_FILE"
BIB_PASEO_TEST=1 BIB_USER_HOME="$T48/user-home" HOME="$T48/root-home" bash "${PAYLOAD_DIR}/install/48-user-content.sh" >/dev/null 2>&1
if [[ -z "$(ls -A "$T48/user-home")" && -z "$(ls -A "$T48/root-home")" ]]; then
    ok "PK-14b: 48-user-content.sh is a no-op when scaffold_done is unset (F-11, E-22, MU-16)"
else
    bad "PK-14b: 48-user-content.sh wrote files when scaffold_done was unset"
fi

printf '{"version":2,"bib_user":"%s","ai_cli":"claude","phases":{"scaffold_done":true}}\n' "$(id -un)" > "$BIB_STATE_FILE"
BIB_PASEO_TEST=1 BIB_USER_HOME="$T48/user-home" HOME="$T48/root-home" bash "${PAYLOAD_DIR}/install/48-user-content.sh" >/dev/null 2>&1
if [[ -d "$T48/user-home/.agents/skills/code-review" && -f "$T48/user-home/.claude/settings.json" && -z "$(ls -A "$T48/root-home")" ]]; then
    ok "PK-14c: 48-user-content.sh syncs core skills & hooks into box user home and leaves root HOME empty (F-11, E-21)"
else
    bad "PK-14c: 48-user-content.sh failed to populate user-home or polluted root-home"
fi
rm -rf "$T48"

echo "== PK-16..PK-20: Wave 2 — spec-implementer & pr-review (F-15..F-19, RG-12, MU-30, MU-31) =="

SI_FILE="${PAYLOAD_DIR}/skills/spec-implementer/SKILL.md"
PR_FILE="${PAYLOAD_DIR}/skills/pr-review/SKILL.md"

# F-15 & MU-31: existence, byte size caps (<= 7000 B and <= 4500 B), frontmatter name/description, core tier
if [[ -f "$SI_FILE" && -f "$PR_FILE" ]]; then
    si_bytes="$(wc -c < "$SI_FILE")"
    pr_bytes="$(wc -c < "$PR_FILE")"
    if [[ "$si_bytes" -le 7000 && "$pr_bytes" -le 4500 ]]; then
        ok "PK-16a: spec-implementer (${si_bytes}B <= 7000B) and pr-review (${pr_bytes}B <= 4500B) within size budget (F-15)"
    else
        bad "PK-16a: size budget exceeded (spec-implementer=${si_bytes}B, pr-review=${pr_bytes}B)"
    fi
else
    bad "PK-16a: spec-implementer/SKILL.md or pr-review/SKILL.md missing"
fi

si_name="$(awk '/^name:/{sub(/^name: */, ""); print; exit}' "$SI_FILE" 2>/dev/null)"
pr_name="$(awk '/^name:/{sub(/^name: */, ""); print; exit}' "$PR_FILE" 2>/dev/null)"
si_desc_len="$(LC_ALL=C.UTF-8 awk '/^description:/{sub(/^description: */, ""); print length($0); exit}' "$SI_FILE" 2>/dev/null)"
pr_desc_len="$(LC_ALL=C.UTF-8 awk '/^description:/{sub(/^description: */, ""); print length($0); exit}' "$PR_FILE" 2>/dev/null)"
if [[ "$si_name" == "spec-implementer" && "$pr_name" == "pr-review" \
   && "${si_desc_len:-999}" -gt 20 && "${si_desc_len:-999}" -lt 300 \
   && "${pr_desc_len:-999}" -gt 20 && "${pr_desc_len:-999}" -lt 300 ]] \
   && ! grep -q '^model:' "$SI_FILE" "$PR_FILE"; then
    ok "PK-16b: frontmatter name matches dir, description < 300 chars (${si_desc_len}, ${pr_desc_len}), no hardcoded model (F-15)"
else
    bad "PK-16b: frontmatter invalid (si_name=$si_name, pr_name=$pr_name, si_desc_len=$si_desc_len, pr_desc_len=$pr_desc_len)"
fi

core_count="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $2=="core"{c++} END{print c+0}' "$MANIFEST_FILE")"
si_tier="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $1=="spec-implementer"{print $2; exit}' "$MANIFEST_FILE")"
pr_tier="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $1=="pr-review"{print $2; exit}' "$MANIFEST_FILE")"
if [[ "$core_count" -eq 27 && "$si_tier" == "core" && "$pr_tier" == "core" ]]; then
    ok "PK-16c: manifest has 27 core skills including spec-implementer and pr-review as core (F-15, MU-31)"
else
    bad "PK-16c: manifest core count ($core_count != 27) or tiers ($si_tier, $pr_tier) wrong"
fi

# F-16 & MU-30: no forbidden maintainer/v2/self-merge strings in spec-implementer or pr-review
# (split in source so check-no-personal-refs.sh does not flag this test file)
forb_re="closure""-loop|tracking\\.json|READY-TO-CLOSE|Mac ""mini|bypassPermissions|dangerously|gh pr merge|Jes""(u|ú|Ú)s|wt""-new|pre branch|code-reviewer|security-auditor|/home/"
if ! grep -rEq "$forb_re" "${PAYLOAD_DIR}/skills/spec-implementer" "${PAYLOAD_DIR}/skills/pr-review"; then
    ok "PK-17: spec-implementer and pr-review contain no forbidden v2/maintainer/merge strings (F-16, AC-3, MU-30)"
else
    bad "PK-17: forbidden string found in spec-implementer or pr-review: $(grep -rnE "$forb_re" "${PAYLOAD_DIR}/skills/spec-implementer" "${PAYLOAD_DIR}/skills/pr-review")"
fi

# F-17, F-18 & D1: required v1 workflow clauses and read-only sdd.json switch
# shellcheck disable=SC2088
if grep -q 'validated_by' "$SI_FILE" \
   && grep -q 'git worktree' "$SI_FILE" \
   && grep -q 'origin/main' "$SI_FILE" \
   && grep -q '## Tasks' "$SI_FILE" \
   && grep -q 'PR body' "$SI_FILE" \
   && grep -q 'gh pr create' "$SI_FILE" \
   && grep -q '~/.config/buildersinabox/sdd.json' "$SI_FILE" \
   && grep -q 'stop-at-pr' "$SI_FILE" \
   && ! grep -Eq '(>|tee|mv|cp).*sdd\.json' "$SI_FILE" "$PR_FILE"; then
    ok "PK-18a: spec-implementer covers v1 layout, git worktree from origin/main, PR body progress, and read-only stop-at-pr switch (F-17, D1)"
else
    bad "PK-18a: spec-implementer missing required v1 or D1 clauses"
fi

if grep -q 'Review depth' "$PR_FILE" \
   && grep -qi 'verification, not opinion' "$PR_FILE" \
   && grep -q -- '--repo' "$PR_FILE" \
   && grep -q 'Verdict:' "$PR_FILE" \
   && grep -qi 'the owner merges' "$PR_FILE" \
   && grep -q 'disable-model-invocation' "$PR_FILE"; then
    ok "PK-18b: pr-review has size table, verification-not-opinion, gh --repo caveat, Verdict block, and owner-merges rule (F-18)"
else
    bad "PK-18b: pr-review missing required clauses"
fi

# F-19 & AC-13: core description total <= 7794 chars
desc_total=0
for s in $(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $2=="core"{print $1}' "$MANIFEST_FILE"); do
    len="$(LC_ALL=C.UTF-8 awk '/^description:/{sub(/^description: */, ""); print length($0); exit}' "${PAYLOAD_DIR}/skills/${s}/SKILL.md" 2>/dev/null)"
    desc_total=$((desc_total + ${len:-0}))
done
if [[ "$desc_total" -le 7794 ]]; then
    ok "PK-19: core description character total is ${desc_total} <= 7794 (F-19, AC-13)"
else
    bad "PK-19: core description character total ${desc_total} exceeds 7794 limit (AC-13)"
fi

# RG-12 & Q-7: README and SDD docs consistency
if [[ -f "${PAYLOAD_DIR}/skills/README.md" && -f "${PAYLOAD_DIR}/docs/sdd-workflow.md" && -f "${PAYLOAD_DIR}/docs/adopting-sdd.md" ]]; then
    if ! grep -q 'Coming in a later update' "${PAYLOAD_DIR}/skills/README.md" \
       && grep -q '`spec-implementer`' "${PAYLOAD_DIR}/skills/README.md" \
       && grep -q '`pr-review`' "${PAYLOAD_DIR}/skills/README.md" \
       && ! grep -q 'optionally deploys' "${PAYLOAD_DIR}/docs/sdd-workflow.md" \
       && ! grep -q 'spec-triage' "${PAYLOAD_DIR}/docs/sdd-workflow.md" \
       && ! grep -q 'spec-implementer matrix' "${PAYLOAD_DIR}/docs/adopting-sdd.md"; then
        ok "PK-20: skills/README.md, sdd-workflow.md and adopting-sdd.md updated consistently (RG-12, Q-7)"
    else
        bad "PK-20: stale spec-implementer/pr-review wording in README or docs"
    fi
fi

# ── PK-21..PK-25: Wave 3 — 6 optional own skills (F-06, F-20..F-23) ─────────
echo "== PK-21..PK-25: Wave 3 — agent-handover, wrapup, unwrap, hotfix, fact-checker, verify-frontend-change =="

# F-20: run the 3 agent-handover test suites with isolated HOME/state
ho_tmp="$(mktemp -d)"
mkdir -p "$ho_tmp/home" "$ho_tmp/state"
ho_ok=1
for t in "${PAYLOAD_DIR}/skills/agent-handover/tests"/test-*.sh; do
    if [[ ! -f "$t" ]] || ! PYTHONDONTWRITEBYTECODE=1 HOME="$ho_tmp/home" AGENT_HANDOVER_STATE_DIR="$ho_tmp/state" bash "$t" >/dev/null 2>&1; then
        ho_ok=0
        bad "PK-21: handover test failed: $t"
    fi
done
rm -rf "$ho_tmp"
if [[ "$ho_ok" -eq 1 ]]; then
    ok "PK-21: all 3 agent-handover test suites pass in isolated temp state (F-20)"
fi

# F-21: handover.py AST parse, no Spanish accents / FEAT-0 / personal / bypassPermissions / /home/, no openai.yaml or __pycache__
w3_dirs=(
    "${PAYLOAD_DIR}/skills/agent-handover"
    "${PAYLOAD_DIR}/skills/wrapup"
    "${PAYLOAD_DIR}/skills/unwrap"
    "${PAYLOAD_DIR}/skills/hotfix"
    "${PAYLOAD_DIR}/skills/fact-checker"
    "${PAYLOAD_DIR}/skills/verify-frontend-change"
)
w3_forb="[áéíóúñ¿¡]|FEAT-0[0-9]+|Jes""(u|ú|Ú)s|bypassPermissions|/home/"
if python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "${PAYLOAD_DIR}/skills/agent-handover/scripts/handover.py" 2>/dev/null \
   && ! LC_ALL=C.UTF-8 grep -rEIq "$w3_forb" "${w3_dirs[@]}" \
   && [[ -z "$(find "${w3_dirs[@]}" -name 'openai.yaml' -o -name '__pycache__')" ]]; then
    ok "PK-22: handover.py parses under python3 -I, no Spanish/FEAT/personal/bypass strings, no openai.yaml or __pycache__ (F-21)"
else
    bad "PK-22: F-21 check failed on Wave 3 skill directories"
fi

# F-22: content checks on hotfix, fact-checker, verify-frontend-change
hf_file="${PAYLOAD_DIR}/skills/hotfix/SKILL.md"
fc_file="${PAYLOAD_DIR}/skills/fact-checker/SKILL.md"
vf_file="${PAYLOAD_DIR}/skills/verify-frontend-change/SKILL.md"
w3_priv="ganga""24|\\bso""fi\\b|he""zu|chord""na|jun""tale|\\bdy""a\\b|stratops|euros?\\b|4b48""5174|f927""746e"
if grep -q 'gh pr create' "$hf_file" \
   && grep -q 'git revert' "$hf_file" \
   && grep -qi 'the owner merges' "$hf_file" \
   && grep -q 'Primary source\|primary source' "$fc_file" \
   && grep -q 'Confirmed' "$fc_file" \
   && grep -q 'biab-browse' "$vf_file" \
   && grep -q 'visual verification pending' "$vf_file" \
   && ! grep -Eiq "$w3_priv" "$hf_file" "$fc_file" "$vf_file"; then
    ok "PK-23: hotfix, fact-checker and verify-frontend-change meet BIAB rewrite rules (F-22)"
else
    bad "PK-23: hotfix, fact-checker or verify-frontend-change failed F-22 content checks"
fi

# F-23: manifest has 27 core, >=13 optional, handover group has 3 members, 3 single skills
opt_count="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $2=="optional"{c++} END{print c+0}' "$MANIFEST_FILE")"
ho_group="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $2=="optional" && $3=="handover"{print $1}' "$MANIFEST_FILE" | sort | paste -sd, -)"
singles_ok=1
for s in hotfix fact-checker verify-frontend-change; do
    row_tier="$(awk -F'\t' -v s="$s" '{sub(/\r$/,"")} !/^#/ && NF && $1==s{print $2 ":" $3}' "$MANIFEST_FILE")"
    [[ "$row_tier" == "optional:" ]] || singles_ok=0
done
if [[ "$core_count" -eq 27 && "$opt_count" -ge 13 && "$ho_group" == "agent-handover,unwrap,wrapup" && "$singles_ok" -eq 1 ]]; then
    ok "PK-24: manifest has 27 core, ${opt_count} optional, group handover=(agent-handover,unwrap,wrapup), and 3 single optionals (F-23)"
else
    bad "PK-24: manifest check failed (core=$core_count, opt=$opt_count, ho_group=$ho_group, singles_ok=$singles_ok)"
fi

# F-06 & F-08 step 4: real biab add handover and biab add hotfix on a temp HOME
w3_add="$(mktemp -d)"
mkdir -p "$w3_add/home" "$w3_add/opt/payload" "$w3_add/etc/buildersinabox"
cp -r "${PAYLOAD_DIR}/skills" "${PAYLOAD_DIR}/lib" "$w3_add/opt/payload/"
printf 'BIB_AI_CLI=claude\n' > "$w3_add/etc/buildersinabox/biab.env"
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh" \
    | sed "s#/opt/buildersinabox#$w3_add/opt#g; s#/etc/buildersinabox#$w3_add/etc/buildersinabox#g" > "$w3_add/biab"
out_ho1="$(HOME="$w3_add/home" bash "$w3_add/biab" add handover 2>&1)"
rc_ho1=$?
hash_before="$(find "$w3_add/home/.agents/skills" -type f -exec sha256sum {} + | sort | sha256sum)"
out_ho2="$(HOME="$w3_add/home" bash "$w3_add/biab" add handover 2>&1)"
rc_ho2=$?
hash_after="$(find "$w3_add/home/.agents/skills" -type f -exec sha256sum {} + | sort | sha256sum)"
out_hf="$(HOME="$w3_add/home" bash "$w3_add/biab" add hotfix 2>&1)"
rc_hf=$?
if [[ "$rc_ho1" -eq 0 && "$rc_ho2" -eq 0 && "$rc_hf" -eq 0 \
   && -d "$w3_add/home/.agents/skills/agent-handover" \
   && -d "$w3_add/home/.agents/skills/wrapup" \
   && -d "$w3_add/home/.agents/skills/unwrap" \
   && -L "$w3_add/home/.claude/skills/agent-handover" \
   && -L "$w3_add/home/.claude/skills/wrapup" \
   && -L "$w3_add/home/.claude/skills/unwrap" \
   && "$hash_before" == "$hash_after" \
   && "$(grep -c 'already installed' <<<"$out_ho2")" -eq 3 \
   && -d "$w3_add/home/.agents/skills/hotfix" \
   && -L "$w3_add/home/.claude/skills/hotfix" ]]; then
    ok "PK-25: 'biab add handover' installs 3 skills with symlinks (idempotent on rerun) and 'biab add hotfix' installs 1 (F-06, F-08)"
else
    bad "PK-25: biab add handover/hotfix failed (rc_ho1=$rc_ho1, rc_ho2=$rc_ho2, rc_hf=$rc_hf, out_ho1=$out_ho1, out_ho2=$out_ho2, out_hf=$out_hf)"
fi
rm -rf "$w3_add"

# ── PK-26..PK-30: Wave 4 — core hooks & quota_watchdog.py (F-29, F-30, E-34, MU-13, D11) ──
echo "== PK-26..PK-30: Wave 4 — biab-secret-guard.sh, biab-quota-window.sh, quota_watchdog.py & agy wrappers =="

SG_HOOK="${PAYLOAD_DIR}/hooks/biab-secret-guard.sh"
QW_HOOK="${PAYLOAD_DIR}/hooks/biab-quota-window.sh"
SG_AGY_HOOK="${PAYLOAD_DIR}/hooks/biab-secret-guard-agy.sh"
FMT_AGY_HOOK="${PAYLOAD_DIR}/hooks/biab-format-agy.sh"
SPC_AGY_HOOK="${PAYLOAD_DIR}/hooks/biab-specs-agy.sh"
QW_PY="${PAYLOAD_DIR}/skills/quota/scripts/quota_watchdog.py"
QR_PY="${PAYLOAD_DIR}/skills/quota/scripts/quota_report.py"
QUOTA_SKILL="${PAYLOAD_DIR}/skills/quota/SKILL.md"

# E-34: executable bit on all new hooks and quota_watchdog.py
if [[ -x "$SG_HOOK" && -x "$QW_HOOK" && -x "$SG_AGY_HOOK" && -x "$FMT_AGY_HOOK" && -x "$SPC_AGY_HOOK" && -x "$QW_PY" ]]; then
    ok "PK-26: biab-secret-guard.sh, biab-quota-window.sh, agy wrappers and quota_watchdog.py are executable (E-34)"
else
    bad "PK-26: missing +x on one or more Wave 4 hooks or quota_watchdog.py"
fi

# F-29 & MU-13: no network / sudo / maintainer strings in hooks; source lib.sh and call biab_hooks_disabled
w4_forb="curl|wget|/dev/tcp|\\bnc\\b|sudo|Jes""(u|ú|Ú)s"
if ! grep -nE "$w4_forb" "$SG_HOOK" "$QW_HOOK" "$SG_AGY_HOOK" "$FMT_AGY_HOOK" "$SPC_AGY_HOOK" >/dev/null 2>&1 \
   && grep -q 'source "${HOOK_DIR}/lib.sh"' "$SG_HOOK" \
   && grep -q 'source "${HOOK_DIR}/lib.sh"' "$QW_HOOK" \
   && grep -q 'biab_hooks_disabled && exit 0' "$SG_HOOK" \
   && grep -q 'biab_hooks_disabled && exit 0' "$QW_HOOK"; then
    ok "PK-27: Wave 4 hooks contain no network/sudo/personal strings and source lib.sh + biab_hooks_disabled (F-29, MU-13)"
else
    bad "PK-27: Wave 4 hook static check failed (F-29, MU-13)"
fi

# F-30: quota_watchdog.py parses under python3 -I, stdlib imports only, no private project paths or requests, named in quota/SKILL.md
w4_py_forb="projects/so""fi|SOFI_CRON|send_telegram|requests|[áéíóúñ¿¡]"
if python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read()); ast.parse(open(sys.argv[2]).read())" "$QW_PY" "$QR_PY" 2>/dev/null \
   && ! LC_ALL=C.UTF-8 grep -Eiq "$w4_py_forb" "$QW_PY" "$QR_PY" \
   && grep -q 'quota_watchdog.py' "$QUOTA_SKILL"; then
    ok "PK-28: quota_watchdog.py and quota_report.py parse under python3 -I, stdlib-only, no private refs, named in quota/SKILL.md (F-30)"
else
    bad "PK-28: quota_watchdog.py / quota/SKILL.md check failed (F-30)"
fi

# Functional smoke of quota_watchdog.py --check in an isolated temp HOME
qw_tmp="$(mktemp -d)"
qw_json="$(PYTHONDONTWRITEBYTECODE=1 HOME="$qw_tmp" python3 -B "$QW_PY" --check 2>/dev/null)"
qw_status="$(printf '%s' "$qw_json" | jq -r '.status // empty' 2>/dev/null)"
rm -rf "$qw_tmp"
if [[ "$qw_status" == "ok" ]]; then
    ok "PK-29: quota_watchdog.py --check runs cleanly on an empty HOME and outputs status=ok"
else
    bad "PK-29: quota_watchdog.py --check failed on empty HOME (json=$qw_json)"
fi

# Functional smoke of Antigravity wrappers (biab-secret-guard-agy.sh, biab-format-agy.sh, biab-specs-agy.sh)
agy_sg_ask="$(printf '{"toolCall":{"name":"read_file","args":{"Path":".env"}}}' | "$SG_AGY_HOOK" | jq -r '.decision // empty')"
agy_sg_pass="$(printf '{"toolCall":{"name":"read_file","args":{"Path":".env.example"}}}' | "$SG_AGY_HOOK")"
agy_fmt_out="$(printf '{"toolCall":{"name":"write_file","args":{"Path":"README.md"}}}' | "$FMT_AGY_HOOK")"
agy_sp_dir="$(mktemp -d)"; mkdir -p "$agy_sp_dir/specs/draft"; : > "$agy_sp_dir/specs/draft/FEAT-001.md"
agy_sp_out="$(jq -cn --arg w "$agy_sp_dir" '{workspacePaths:[$w]}' | "$SPC_AGY_HOOK" | jq -r '.injectSteps[0].systemMessage.systemMessage // empty')"
rm -rf "$agy_sp_dir"
if [[ "$agy_sg_ask" == "ask" && -z "$agy_sg_pass" && "$agy_fmt_out" == "{}" && "$agy_sp_out" == *"1 draft, 0 active"* ]]; then
    ok "PK-30: Antigravity hook wrappers (biab-secret-guard-agy, biab-format-agy, biab-specs-agy) pass functional contract (D11)"
else
    bad "PK-30: Antigravity hook wrappers failed (ask=$agy_sg_ask pass=[$agy_sg_pass] fmt=[$agy_fmt_out] sp=[$agy_sp_out])"
fi

# ── PK-31..PK-35: Wave 5 — 19 MIT marketing skills (F-07, F-32..F-35, F-41, E-23, E-24) ──
echo "== PK-31..PK-35: Wave 5 — 19 MIT marketing skills (group 'marketing') =="

MKT_LOCK="${PAYLOAD_DIR}/skills/marketingskills.lock.json"
MKT_LIC="${PAYLOAD_DIR}/skills/LICENSE.marketingskills"
EXPECTED_LIC_SHA="b70d71e24e40fce5da8f4b6f9cd862096a048e433db7f3c8cac5e348e6d34591"

# F-32 & E-23 (MU-28): LICENSE.marketingskills + 19 per-skill LICENSE copies match exact sha256
mkt_manifest_skills="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $2=="optional" && $3=="marketing"{print $1}' "$MANIFEST_FILE" | sort)"
mkt_manifest_count="$(printf '%s\n' "$mkt_manifest_skills" | sed '/^$/d' | wc -l | tr -d ' ')"
lic_ok=1
if [[ ! -f "$MKT_LIC" ]] || [[ "$(sha256sum "$MKT_LIC" | awk '{print $1}')" != "$EXPECTED_LIC_SHA" ]]; then
    lic_ok=0
fi
while IFS= read -r mskill; do
    [[ -z "$mskill" ]] && continue
    slic="${PAYLOAD_DIR}/skills/${mskill}/LICENSE"
    if [[ ! -f "$slic" ]] || [[ "$(sha256sum "$slic" | awk '{print $1}')" != "$EXPECTED_LIC_SHA" ]]; then
        lic_ok=0
        break
    fi
done <<<"$mkt_manifest_skills"
if [[ "$mkt_manifest_count" -eq 19 && "$lic_ok" -eq 1 ]]; then
    ok "PK-31: LICENSE.marketingskills and all 19 per-skill LICENSE files match pinned sha256 (F-32, E-23, AC-6)"
else
    bad "PK-31: marketing LICENSE sha256 mismatch or missing file (count=$mkt_manifest_count, lic_ok=$lic_ok)"
fi

# F-33 & MU-32: marketingskills.lock.json matches 19 skills, commit, license, omitted, renamed, adapted_files
lock_skills="$(jq -r '.skills[]? // empty' "$MKT_LOCK" 2>/dev/null | sort)"
lock_commit="$(jq -r '.commit // empty' "$MKT_LOCK" 2>/dev/null)"
lock_license="$(jq -r '.license // empty' "$MKT_LOCK" 2>/dev/null)"
lock_omitted="$(jq -r '.omitted[]? // empty' "$MKT_LOCK" 2>/dev/null)"
lock_renamed="$(jq -r '.renamed["product-marketing"] // empty' "$MKT_LOCK" 2>/dev/null)"
lock_adapted_ok=1
for af in "ads/SKILL.md" "ai-seo/SKILL.md" "analytics/SKILL.md" "attribution/SKILL.md" "revops/SKILL.md" "marketing-context/SKILL.md" "marketing-loops/references/loop-catalog.md"; do
    if ! jq -e --arg af "$af" '.adapted_files | index($af) != null' "$MKT_LOCK" >/dev/null 2>&1; then
        lock_adapted_ok=0
    fi
done
if [[ "$lock_skills" == "$mkt_manifest_skills" \
   && "$lock_commit" == "5b2c0007766c6a1cf1d53fd8fc73e979e0821022" \
   && "$lock_license" == "MIT" \
   && "$lock_omitted" == "evals/" \
   && "$lock_renamed" == "marketing-context" \
   && "$lock_adapted_ok" -eq 1 ]]; then
    ok "PK-32: marketingskills.lock.json matches the 19 marketing dirs, upstream commit, omitted evals/, rename and adapted_files (F-33, AC-6, AC-11)"
else
    bad "PK-32: marketingskills.lock.json check failed (commit=$lock_commit, license=$lock_license, omitted=$lock_omitted, renamed=$lock_renamed, adapted_ok=$lock_adapted_ok)"
fi

# F-34 & E-24 (MU-29): no maintainer server string, no evals/ dir, marketing-context renamed cleanly, BIAB's product-marketing intact
mh_srv="MH ""Server"
evals_found="$(find "${PAYLOAD_DIR}/skills" -type d -name evals)"
mc_name="$(awk '/^name:/{print $2; exit}' "${PAYLOAD_DIR}/skills/marketing-context/SKILL.md")"
pm_name="$(awk '/^name:/{print $2; exit}' "${PAYLOAD_DIR}/skills/product-marketing/SKILL.md")"
if ! grep -rIqi "$mh_srv" "${PAYLOAD_DIR}/skills" \
   && [[ -z "$evals_found" ]] \
   && [[ "$mc_name" == "marketing-context" ]] \
   && [[ "$pm_name" == "product-marketing" ]] \
   && grep -q '`competitor-profiling`, `competitors`, `marketing-context`' "${PAYLOAD_DIR}/skills/marketing-loops/references/loop-catalog.md"; then
    ok "PK-33: no maintainer server string, no evals/ directories, marketing-context renamed cleanly, and BIAB product-marketing intact (F-34, E-24)"
else
    bad "PK-33: marketing content hygiene check failed (evals=[$evals_found], mc_name=$mc_name, pm_name=$pm_name)"
fi

# F-35 & AC-3: manifest has 27 core and 32 optional; default core sync does not install any marketing skill
opt_count_w5="$(awk -F'\t' '{sub(/\r$/,"")} !/^#/ && NF && $2=="optional"{c++} END{print c+0}' "$MANIFEST_FILE")"
w5_def="$(mktemp -d)"
(
    export BIB_AI_CLI="claude"
    # shellcheck source=/dev/null
    source "${PAYLOAD_DIR}/lib/ai-cli.sh"
    # shellcheck source=/dev/null
    source "${PAYLOAD_DIR}/lib/user-content.sh"
    uc_sync_core_skills "$w5_def" "claude" "${PAYLOAD_DIR}/skills" >/dev/null
)
mkt_in_default=0
while IFS= read -r mskill; do
    [[ -z "$mskill" ]] && continue
    [[ -e "$w5_def/.agents/skills/$mskill" ]] && mkt_in_default=1
done <<<"$mkt_manifest_skills"
rm -rf "$w5_def"
if [[ "$core_count" -eq 27 && "$opt_count_w5" -eq 32 && "$mkt_in_default" -eq 0 ]]; then
    ok "PK-34: manifest has 27 core and 32 optional skills, and default install includes 0 marketing skills (F-35, AC-3)"
else
    bad "PK-34: manifest/default install check failed (core=$core_count, opt=$opt_count_w5, mkt_in_default=$mkt_in_default)"
fi

# F-07, F-08 & AC-5: 'biab add marketing' installs 19 dirs each with LICENSE, idempotent on second run, usage lists handover, marketing
w5_add="$(mktemp -d)"
mkdir -p "$w5_add/home" "$w5_add/opt/payload" "$w5_add/etc/buildersinabox"
cp -r "${PAYLOAD_DIR}/skills" "${PAYLOAD_DIR}/lib" "$w5_add/opt/payload/"
printf 'BIB_AI_CLI=claude\n' > "$w5_add/etc/buildersinabox/biab.env"
awk "/<<'WRAPPER'/{f=1;next} /^WRAPPER\$/{f=0} f" "${PAYLOAD_DIR}/install/05-biab-command.sh" \
    | sed "s#/opt/buildersinabox#$w5_add/opt#g; s#/etc/buildersinabox#$w5_add/etc/buildersinabox#g" > "$w5_add/biab"
out_mk1="$(HOME="$w5_add/home" bash "$w5_add/biab" add marketing 2>&1)"
rc_mk1=$?
mkt_hash1="$(find "$w5_add/home/.agents/skills" -type f -exec sha256sum {} + | sort | sha256sum)"
out_mk2="$(HOME="$w5_add/home" bash "$w5_add/biab" add marketing 2>&1)"
rc_mk2=$?
mkt_hash2="$(find "$w5_add/home/.agents/skills" -type f -exec sha256sum {} + | sort | sha256sum)"
mkt_installed_lics="$(find "$w5_add/home/.agents/skills" -mindepth 2 -maxdepth 2 -name LICENSE | wc -l | tr -d ' ')"
out_usage="$(HOME="$w5_add/home" bash "$w5_add/biab" add 2>&1 || true)"
rm -rf "$w5_add"
if [[ "$rc_mk1" -eq 0 && "$rc_mk2" -eq 0 \
   && "$mkt_installed_lics" -eq 19 \
   && "$mkt_hash1" == "$mkt_hash2" \
   && "$(grep -c 'Installed skill' <<<"$out_mk1")" -eq 19 \
   && "$(grep -c 'already installed' <<<"$out_mk2")" -eq 19 \
   && "$out_usage" == *", handover,"* \
   && "$out_usage" == *", marketing,"* ]]; then
    ok "PK-35: 'biab add marketing' installs 19 skills with LICENSE (idempotent on rerun) and usage lists 'handover' and 'marketing' (F-07, F-08, AC-5)"
else
    bad "PK-35: 'biab add marketing' failed (rc1=$rc_mk1, rc2=$rc_mk2, lics=$mkt_installed_lics, usage=$out_usage)"
fi

# ── PK-36..PK-40: Wave 6 — operating-rules.md, skeleton CLAUDE.md & PROJECT-CLAUDE.md (F-36..F-42, AC-12, AC-14, MU-33) ──
echo "== PK-36..PK-40: Wave 6 — operating-rules.md & context pointers =="

OP_DOC="${PAYLOAD_DIR}/docs/operating-rules.md"
SKEL_CLAUDE="${PAYLOAD_DIR}/skeleton/ai-platform/CLAUDE.md"
TPL_CLAUDE="${PAYLOAD_DIR}/templates/PROJECT-CLAUDE.md"

# F-36, AC-12, MU-33: operating-rules.md exists, <= 6000 B, names the 6 hard stops, brakes vs branch protection lock, no personal/maintainer terms
op_size=999999
[[ -f "$OP_DOC" ]] && op_size="$(wc -c < "$OP_DOC" | tr -d ' ')"
op_stops_ok=1
for w in money credentials external irreversible production sudo; do
    grep -qi "$w" "$OP_DOC" 2>/dev/null || op_stops_ok=0
done
op_forb="Jes""(u|ú|Ú)s|wt-""new|closure"
if [[ -f "$OP_DOC" && "$op_size" -le 6000 && "$op_stops_ok" -eq 1 ]] \
   && grep -qi 'brake' "$OP_DOC" \
   && grep -qi 'branch protection' "$OP_DOC" \
   && grep -q 'git worktree' "$OP_DOC" \
   && ! grep -Eqi "$op_forb" "$OP_DOC"; then
    ok "PK-36: operating-rules.md (${op_size}B <= 6000B) covers the 6 hard stops, git worktree, brakes vs branch protection lock, and has no forbidden terms (F-36, AC-12, MU-33)"
else
    bad "PK-36: operating-rules.md check failed (size=$op_size, stops_ok=$op_stops_ok)"
fi

# F-37, AC-14, MU-33: skeleton/ai-platform/CLAUDE.md <= 2000 B, <= 42 lines (grew by <= 12 lines from 30), points to operating-rules.md
skel_size="$(wc -c < "$SKEL_CLAUDE" | tr -d ' ')"
skel_lines="$(wc -l < "$SKEL_CLAUDE" | tr -d ' ')"
if [[ "$skel_size" -le 2000 && "$skel_lines" -le 42 ]] && grep -q 'operating-rules.md' "$SKEL_CLAUDE"; then
    ok "PK-37: skeleton/ai-platform/CLAUDE.md (${skel_size}B <= 2000B, ${skel_lines} lines <= 42) points to operating-rules.md (F-37, AC-14, MU-33)"
else
    bad "PK-37: skeleton/ai-platform/CLAUDE.md check failed (size=$skel_size, lines=$skel_lines)"
fi

# F-38: every hook script, skill or script named in operating-rules.md exists in payload/
doc_refs_ok=1
for href in $(grep -oE 'biab-[a-z0-9-]+(\.sh)?|opencode-guard\.sh' "$OP_DOC" | sort -u); do
    if [[ "$href" == *.sh ]]; then
        [[ -f "${PAYLOAD_DIR}/hooks/${href}" ]] || { doc_refs_ok=0; bad "PK-38: missing hook ${href}"; }
    fi
done
for sref in spec-implementer pr-review hotfix agent-handover wrapup unwrap; do
    grep -q "$sref" "$OP_DOC" && [[ ! -d "${PAYLOAD_DIR}/skills/${sref}" ]] && { doc_refs_ok=0; bad "PK-38: missing skill ${sref}"; }
done
for pyref in quota_report.py quota_watchdog.py; do
    grep -q "$pyref" "$OP_DOC" && [[ ! -f "${PAYLOAD_DIR}/skills/quota/scripts/${pyref}" ]] && { doc_refs_ok=0; bad "PK-38: missing script ${pyref}"; }
done
if [[ "$doc_refs_ok" -eq 1 ]]; then
    ok "PK-38: every hook, skill and script named in operating-rules.md exists in payload/ (F-38)"
fi

# F-39 & Q-6: PROJECT-CLAUDE.md points to operating-rules.md so AGENTS.md rendered for Codex/Antigravity includes the pointer
if grep -q 'operating-rules.md' "$TPL_CLAUDE"; then
    ok "PK-39: templates/PROJECT-CLAUDE.md points to operating-rules.md for AGENTS.md rendering on Codex/Antigravity (F-39, Q-6)"
else
    bad "PK-39: templates/PROJECT-CLAUDE.md missing pointer to operating-rules.md (F-39, Q-6)"
fi

# F-41, F-42, AC-11: skills/README.md covers all 27 core skills and optional groups
readme_missing=0
while IFS=$'\t' read -r sname _tier _grp || [[ -n "${sname:-}" ]]; do
    sname="${sname%$'\r'}"
    [[ -z "$sname" || "$sname" == \#* ]] && continue
    grep -q "\`${sname}\`" "${PAYLOAD_DIR}/skills/README.md" || { readme_missing=1; bad "PK-40: skills/README.md missing ${sname}"; }
done < "$MANIFEST_FILE"
if [[ "$readme_missing" -eq 0 ]]; then
    ok "PK-40: payload/skills/README.md documents every skill in manifest.tsv (T6)"
fi

echo ""
echo "RESULT: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
