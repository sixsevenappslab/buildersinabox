#!/usr/bin/env python3
"""FEAT-045: the catalog parity checks of payload/test/i18n.sh, in one pass.

  i18n-parity.py parity <dump.tsv>      every en/<other> key pair; prints ok|bad lines (TAB separated)
  i18n-parity.py tok <text>             the literal-token signature of a value
  i18n-parity.py ph <text>              the printf placeholder signature of a value
  i18n-parity.py nldiff <en> <other>    why the newline shape differs, or nothing
  i18n-parity.py readme <en.md> <es.md> why two box READMEs (rendered or raw) differ in what must be literal, or nothing

<dump.tsv> is `lang TAB key TAB value`, one message per line. A value carries its newline as the
two characters backslash-n. The rules (what must survive translation) are documented in
payload/test/i18n.sh and FEAT-045 R6/R11; they used to be bash functions that forked grep per key.
"""
import re
import sys

NL_SHORT = 6  # up to this many \n in the English value, the other language has exactly as many
# Keys whose other-language value is wrapped one line longer than the English one, on purpose.
NL_EXTRA = {"wizard.paseo.not_permissioned": 1}
# Keys whose text is the same in every language on purpose (none today).
SAME_IN_BOTH = set()

PH_RE = re.compile(r"%[-+ #0]*[0-9]*(\.[0-9]+)?([sdqbxXoiuc])")
TOK_LINE = [
    (re.compile(r"`[^`]+`"), None),
    (re.compile(r"(?:^|[\s(])(--[a-z][a-z0-9-]*)"), 1),
    (re.compile(r"(?:^|[\s(])(~?/[A-Za-z0-9._/-]+)"), 1),
    (re.compile(r"biab (?:status|update|pack|paseo|auto-update|add|lang|project)\b"), None),
    (re.compile(r"https?://[A-Za-z0-9._/?=&%-]+"), None),
]
WHOLE_LINE = re.compile(r"^(?:(?:ssh|sudo) |biab$)")
UNTRANSLATED = re.compile(r"([A-Za-z]{2,}[^A-Za-z]+){3}[A-Za-z]{2,}")


def ph_sig(v):
    v = v.replace("%%", "")
    return "".join(m.group(2) + " " for m in PH_RE.finditer(v))


def tok_sig(v):
    toks = []
    for line in v.replace("\\n", "\n").split("\n"):
        for rx, grp in TOK_LINE:
            for m in rx.finditer(line):
                toks.append(m.group(grp) if grp else m.group(0))
        if WHOLE_LINE.search(line):
            toks.append(line)
    return "".join(t + " " for t in sorted(toks))


README_PATH = re.compile(r"(?:^|[\s(`])(~?/[A-Za-z0-9._{}-][A-Za-z0-9._/{}-]*[A-Za-z0-9_{}/-])")
README_CMD = re.compile(r"^ {2,}(?:sudo|ssh|curl|codex|agy|touch|t=|opencode|claude)\b")


def readme_sig(text):
    """What a translated box README must keep: markers, headings per level, backticked spans (a <placeholder>
    may be translated), flags, paths, links, variables, and the command lines of code blocks."""
    toks = []
    flat = " ".join(text.split("\n"))
    prose = " ".join(re.sub(r"```.*?```", " ", text, flags=re.S).split("\n"))
    for m in re.finditer(r"`([^`]+)`", prose):
        toks.append("`" + re.sub(r"<[^>]*>", "<>", " ".join(m.group(1).split())) + "`")
    for m in re.finditer(r"(?:^|[\s(])(--[a-z][a-z0-9-]*)", flat):
        toks.append(m.group(1))
    for m in README_PATH.finditer(flat):
        toks.append(m.group(1))
    for m in re.finditer(r"https?://[A-Za-z0-9._/?=&%-]+", flat):
        toks.append(m.group(0))
    for m in re.finditer(r"\b[A-Z][A-Z0-9]+_[A-Z0-9_]+\b|\{\{[A-Z_]+\}\}", flat):
        toks.append(m.group(0))
    for line in text.split("\n"):
        if README_CMD.search(line):
            toks.append("cmd: " + re.sub(r"<[^>]*>", "<>", line.split("  #")[0].strip()))
    marks = re.findall(r"<!-- BIB:[a-z-]+(?::start)? -->", text)
    heads = [len(m.group(1)) for m in re.finditer(r"^(#{1,6}) ", text, re.M)]
    return sorted(toks), marks, heads


def readme_diff(en, ot):
    a, b = readme_sig(en), readme_sig(ot)
    if a[1] != b[1]:
        return "marker sequence differs"
    if a[2] != b[2]:
        return "heading levels differ (en: %s, other: %s)" % (a[2], b[2])
    if a[0] != b[0]:
        only_en = [t for t in a[0] if a[0].count(t) > b[0].count(t)]
        only_ot = [t for t in b[0] if b[0].count(t) > a[0].count(t)]
        return "literals differ (only en: %s; only other: %s)" % (sorted(set(only_en))[:4], sorted(set(only_ot))[:4])
    return ""


def _lead(v):
    n = 0
    while v.startswith("\\n"):
        n += 1
        v = v[2:]
    return n


def _trail(v):
    n = 0
    while v.endswith("\\n"):
        n += 1
        v = v[:-2]
    return n


def nl_diff(en, ot, extra=0):
    if (not en and ot) or (en and not ot):
        return "empty" if not ot else "en is empty"
    if _lead(en) != _lead(ot):
        return "leading newline differs (en: %d, other: %d)" % (_lead(en), _lead(ot))
    if _trail(en) != _trail(ot):
        return "trailing newline differs (en: %d, other: %d)" % (_trail(en), _trail(ot))
    if en.count("\\n") <= NL_SHORT:
        if en.count("\\n") + extra != ot.count("\\n"):
            return "newline count differs (en: %d, other: %d)" % (en.count("\\n"), ot.count("\\n"))
    else:
        pe, po = len(en.replace("\\n\\n", "")), len(ot.replace("\\n\\n", ""))
        if (len(en) - pe) // 4 != (len(ot) - po) // 4:
            return "paragraph breaks differ (en: %d, other: %d)" % ((len(en) - pe) // 4, (len(ot) - po) // 4)
    return ""


def parity(path):
    val, keys, order = {}, {}, []
    for line in open(path, encoding="utf-8"):
        lang, key, v = line.rstrip("\n").split("\t", 2)
        val[(lang, key)] = v
        keys.setdefault(lang, []).append(key)
        if lang not in order:
            order.append(lang)
    out = []

    def ok(t):
        out.append("ok\t" + t)

    def bad(t):
        out.append("bad\t" + t)

    en_keys = sorted(keys.get("en", []))
    for lang in sorted(order):
        if lang == "en":
            continue
        missing = False
        for k in en_keys:
            if (lang, k) not in val:
                bad("parity: key '%s' is in en but not in %s" % (k, lang))
                missing = True
        for k in sorted(keys.get(lang, [])):
            if ("en", k) not in val:
                bad("parity: key '%s' is in %s but not in en" % (k, lang))
                missing = True
        if not missing:
            ok("parity: en and %s have the same %d keys" % (lang, len(en_keys)))
        flags = {"p": True, "t": True, "n": True, "u": True}
        for k in en_keys:
            if (lang, k) not in val:
                continue
            e, o = val[("en", k)], val[(lang, k)]
            why = nl_diff(e, o, NL_EXTRA.get(k, 0))
            if why:
                if why in ("empty", "en is empty"):
                    bad("parity: '%s' is empty in %s but not in en (or the reverse)" % (k, lang))
                else:
                    bad("parity: %s in '%s' (%s)" % (why, k, lang))
                flags["n"] = False
            # A value with four words or more that reads the same in both languages was copied, not translated.
            if e == o and UNTRANSLATED.search(e.replace("\\n", " ")) and k not in SAME_IN_BOTH:
                bad("untranslated: '%s' has the same text in en and %s" % (k, lang))
                flags["u"] = False
            if ph_sig(e) != ph_sig(o):
                bad("parity: placeholders differ in '%s' (en: '%s' %s: '%s')" % (k, ph_sig(e), lang, ph_sig(o)))
                flags["p"] = False
            if tok_sig(e) != tok_sig(o):
                bad("parity: literal tokens differ in '%s' (en: '%s' %s: '%s')" % (k, tok_sig(e), lang, tok_sig(o)))
                flags["t"] = False
        if flags["n"]:
            ok("parity: every %s value has the leading and trailing newline of its en value, and its line count (short values) or paragraph breaks (long ones)" % lang)
        if flags["u"]:
            ok("parity: no %s value is a copy of its en text" % lang)
        if flags["p"]:
            ok("parity: every %s value has the placeholder sequence of its en value" % lang)
        if flags["t"]:
            ok("parity: every %s value keeps the commands, flags and paths of its en value" % lang)
    print("\n".join(out))


def main(argv):
    cmd = argv[1]
    if cmd == "parity":
        parity(argv[2])
    elif cmd == "tok":
        print(tok_sig(argv[2]), end="")
    elif cmd == "ph":
        print(ph_sig(argv[2]), end="")
    elif cmd == "readme":
        print(readme_diff(open(argv[2], encoding="utf-8").read(), open(argv[3], encoding="utf-8").read()), end="")
    elif cmd == "nldiff":
        print(nl_diff(argv[2], argv[3]), end="")
    else:
        sys.exit("usage: i18n-parity.py parity|tok|ph|nldiff|readme ...")


if __name__ == "__main__":
    main(sys.argv)
