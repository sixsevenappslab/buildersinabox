# Flags user-facing English left in a migrated shell file (FEAT-045 ratchet).
# usage: awk -v funcs=a,b -f i18n-scan.awk file   (funcs empty = the whole file)
# Run by payload/test/i18n.sh; plain POSIX awk (CI's default is mawk).
#
# A statement continued with a trailing backslash is read as one line. A line is flagged when it is not a comment, carries no "i18n-ok" marker, and is
#   - a bare `cat <<EOF` heredoc (message text; `cat > file <<EOF` writes a file and is fine), or
#   - a read -p prompt or a printf/echo (also printf -- and printf -v var) whose quoted text, once $(...), ${...} and $var are taken out, holds
#     two words in a row (letters only, two or more each), or
#   - a warn/die/prompt_*/wizard_step_header/oauth label call, same test (also the names in -v extra=say|err, for a file whose own
#     output helpers have other names: the night-shift pack's say and err).
# Text that comes from the catalog is `$(msg ...)` or `msg ...` and has no literal words.
function strip(t) {
    gsub(/\$\([^()]*\)/, "", t)
    gsub(/\$\([^()]*\)/, "", t)
    gsub(/\$\{[^}]*\}/, "", t)
    gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, "", t)
    gsub(/%[-+ #0]*[0-9]*[sdq]/, "", t)
    return t
}
function has_words(t) { return (t ~ /[A-Za-z][A-Za-z]+[ ]+[A-Za-z][A-Za-z]+/) }
BEGIN {
    n = split(funcs, F, ",")
    for (i = 1; i <= n; i++) if (F[i] != "") want[F[i]] = 1
    whole = (funcs == "")
    infunc = ""
    tag = ""
    xcalls = (extra == "") ? "" : "|" extra
}
{
    line = $0
    if (tag == "" && line !~ /^[ \t]*#/ && line ~ /\\$/) {   # a statement continued on the next line: read it as one
        if (buf == "") bufno = FNR
        sub(/\\$/, " ", line); buf = buf line
        next
    }
    if (buf != "") { line = buf line; buf = ""; lineno = bufno } else lineno = FNR
    if (tag != "") {            # inside a heredoc body: skip it
        t = line
        if (dash) sub(/^\t+/, "", t)
        if (t == tag) tag = ""
        next
    }
    if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/)) {
        infunc = substr(line, 1, RLENGTH); sub(/\(\).*/, "", infunc)
    }
    inscope = whole || (infunc in want)
    heredoc = 0
    if (match(line, /(^|[^<])<<-?[ ]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
        h = substr(line, RSTART, RLENGTH); sub(/^[^<]*<</, "", h)
        dash = (h ~ /^-/); sub(/^-/, "", h); gsub(/[ '"]/, "", h)
        tag = h; heredoc = 1
    }
    if (line ~ /^}/) infunc = ""
    if (!inscope) next
    if (line ~ /^[ \t]*#/ || line ~ /i18n-ok/) next
    if (heredoc) {
        if (line ~ /^[ \t]*cat[ \t]+(>&[0-9]+[ \t]+)?<</) print FILENAME ":" lineno ": heredoc text: " line
        next
    }
    if (match(line, /(^|[ \t;&|({])(printf|echo)[ \t]+((-[A-Za-z]+|--|-v[ \t]+[A-Za-z_][A-Za-z0-9_]*)[ \t]+)*['"]/)) {
        rest = substr(line, RSTART + RLENGTH - 1)
        if (has_words(strip(rest))) print FILENAME ":" lineno ": " line
        next
    }
    if (match(line, /(^|[ \t;&|({])read[ \t]+(-[A-Za-z]+[ \t]+)*-[A-Za-z]*p[ \t]*['"]/)) {
        rest = substr(line, RSTART + RLENGTH - 1)
        if (has_words(strip(rest))) print FILENAME ":" lineno ": " line
        next
    }
    if (match(line, "(^|[ \t;&|({])(warn|die" xcalls "|prompt_confirm|prompt_header|prompt_text|prompt_choice|prompt_password|prompt_url)[ \t]+([0-9]+[ \t]+)?['\"]") \
        || match(line, /(^|[ \t;&|({])wizard_step_header[ \t]+[0-9"$]+[ \t]+[0-9]+[ \t]+['"]/)) {
        rest = substr(line, RSTART + RLENGTH - 1)
        if (has_words(strip(rest))) print FILENAME ":" lineno ": " line
    }
}
