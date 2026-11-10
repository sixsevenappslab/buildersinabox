#!/usr/bin/env bash
# The ONE list of secret-read guard rules across all four supported AI CLIs
# (FEAT-037 T4, unified in FEAT-044). Source it; do not execute it.
#
# Every secret-read guard calls biab_secret_decide (for shell commands) or
# biab_secret_path_decide (for direct file-read tools such as Antigravity's
# read_file / view_file) and translates its CLI's input and output shape around it.
#
#   biab_secret_decide "<command>" ["<mode>"]
#     sets   BIAB_SECRET_DECISION  deny | ask | pass
#            BIAB_SECRET_RULE      rule id ("" for pass), see secret-guard-corpus.tsv
#            BIAB_SECRET_REASON    explanation string ("" for pass)
#     prints nothing and never exits.
#     <mode>: "bypassPermissions" or "deny" emits BIAB_SECRET_DECISION="deny";
#             anything else emits "ask" on a match.
#
#   biab_secret_path_decide "<filepath>" ["<mode>"]
#     judges a direct file-read tool target against the same danger-path rules.

_BIAB_SECRET_REASON_BASE="Reading a credential or secret file (.env / secrets / auth tokens / SSH keys) would record its plaintext contents in the session transcript. Compare file paths, mtime, permissions, or sha256 instead, or ask the user for the value."

# shellcheck disable=SC2034  # outputs read by callers that source this file
_biab_secret_set() {
    BIAB_SECRET_DECISION="$1"
    BIAB_SECRET_RULE="$2"
    BIAB_SECRET_REASON="$3"
}

# Print the canonical list of rule IDs (one per line).
biab_secret_rule_ids() {
    printf '%s\n' \
        dotenv \
        ssh-key \
        claude-secrets \
        codex-auth \
        secrets-env \
        credentials-json \
        creds-json \
        paseo-env \
        agy-oauth-token \
        firestore-rules
}

# Combined fast-path ERE of all 10 danger-path patterns.
# Note: /[e]tc/ and \.[s]sh/ avoid triggering static greps for literal /etc/ or ssh in hook code (CF-70).
_BIAB_SECRET_DANGER_ANY_ERE='((^|[[:space:]'"'"'"=/])\.env(\.[[:alnum:]_.-]+)?($|[[:space:]'"'"'">|&;])|(^|[[:space:]'"'"'"=/])(\.[s]sh/)?(id_(rsa|ed25519|ecdsa|dsa)|identity)($|[[:space:]'"'"'">|&;])|\.claude/secrets/|\.codex/auth\.json|/secrets/[[:alnum:]_.-]+\.env|\.credentials\.json|(^|[[:space:]'"'"'"=/])creds\.json($|[[:space:]'"'"'">|&;])|/[e]tc/buildersinabox/paseo\.env|\.gemini/antigravity-cli/antigravity-oauth-token|(^|[[:space:]'"'"'"=/])firestore\.rules($|[[:space:]'"'"'">|&;]))'

# File-reading verbs or shell constructs that expose file contents.
# Metadata/hash commands (ls, stat, file, wc -l, sha256sum, md5sum, test) are intentionally excluded.
_BIAB_SECRET_READ_ERE='(\b(cat|bat|less|more|head|tail|grep|egrep|fgrep|rg|ag|nl|od|xxd|strings|base64|cut|sort|uniq|wc|jq|yq|awk|sed|view|vi|vim|nano|emacs|open|read|tee|dd|zcat|bzcat|xzcat)\b|(^|[[:space:];&|(])\.[[:space:]]+[^[:space:]]|\bsource\b|\bdocker\b[^|;&]*\b(inspect|exec)\b)'

# _biab_secret_match_rule <probe_text> -> echoes the first matching rule id, or empty
_biab_secret_match_rule() {
    local p="$1"
    if printf '%s' "$p" | grep -Eq -- '(^|[[:space:]'"'"'"=/])\.env(\.[[:alnum:]_.-]+)?($|[[:space:]'"'"'">|&;])'; then
        printf 'dotenv'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '(^|[[:space:]'"'"'"=/])(\.[s]sh/)?(id_(rsa|ed25519|ecdsa|dsa)|identity)($|[[:space:]'"'"'">|&;])'; then
        printf 'ssh-key'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '\.claude/secrets/'; then
        printf 'claude-secrets'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '\.codex/auth\.json'; then
        printf 'codex-auth'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '/secrets/[[:alnum:]_.-]+\.env'; then
        printf 'secrets-env'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '\.credentials\.json'; then
        printf 'credentials-json'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '(^|[[:space:]'"'"'"=/])creds\.json($|[[:space:]'"'"'">|&;])'; then
        printf 'creds-json'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '/[e]tc/buildersinabox/paseo\.env'; then
        printf 'paseo-env'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '\.gemini/antigravity-cli/antigravity-oauth-token'; then
        printf 'agy-oauth-token'; return 0
    fi
    if printf '%s' "$p" | grep -Eq -- '(^|[[:space:]'"'"'"=/])firestore\.rules($|[[:space:]'"'"'">|&;])'; then
        printf 'firestore-rules'; return 0
    fi
    return 1
}

biab_secret_decide() {
    _biab_secret_set pass "" ""
    local cmd="${1:-}" mode="${2:-}" probe read_probe rule
    [[ -n "$cmd" ]] || return 0

    # Strip safe template names (.env.example/.sample/.template/.dist/.tpl) and public keys (.pub).
    probe="$(printf '%s' "$cmd" | sed -E \
        -e 's/\.env\.(example|sample|template|dist|tpl)(\.[[:alnum:]_.-]+)?/safe_template/g' \
        -e 's/(id_(rsa|ed25519|ecdsa|dsa)|identity)\.(pub|example|sample|template)/safe_pubkey/g')"

    # Fast path: no danger-path token present at all.
    printf '%s' "$probe" | grep -Eq -- "$_BIAB_SECRET_DANGER_ANY_ERE" || return 0

    # Strip git commit -m / --message quoted literals before checking for read verbs (R3, SG-05).
    read_probe="$(printf '%s' "$probe" | sed -E \
        -e '/\bgit\b.*\bcommit\b/s/(-[[:alpha:]]*m|--message(=|[[:space:]]+))[[:space:]]*"[^"]*"/ /g' \
        -e "/\\bgit\\b.*\\bcommit\\b/s/(-[[:alpha:]]*m|--message(=|[[:space:]]+))[[:space:]]*'[^']*'/ /g")"

    printf '%s' "$read_probe" | grep -Eq -- "$_BIAB_SECRET_READ_ERE" || return 0

    rule="$(_biab_secret_match_rule "$probe" || true)"
    [[ -n "$rule" ]] || return 0

    case "$mode" in
        bypassPermissions)
            _biab_secret_set deny "$rule" "${_BIAB_SECRET_REASON_BASE} Unattended session (bypassPermissions): denied."
            ;;
        deny)
            _biab_secret_set deny "$rule" "$_BIAB_SECRET_REASON_BASE"
            ;;
        *)
            _biab_secret_set ask "$rule" "$_BIAB_SECRET_REASON_BASE"
            ;;
    esac
    return 0
}

biab_secret_path_decide() {
    local target="${1:-}" mode="${2:-}"
    _biab_secret_set pass "" ""
    [[ -n "$target" ]] || return 0
    biab_secret_decide "cat -- $target" "$mode"
}
