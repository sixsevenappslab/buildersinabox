#!/usr/bin/env python3
"""Measure how many of the A/F-09 corpus commands a rules file stops (FEAT-043 T1).

Reads the 86-command corpus out of test-pack.sh (the `for c in '...' ...; do
guard_run` list), splits every command on `; && || |`, shlex-tokenises each
segment and asks `codex execpolicy check` for a decision per segment. That is
the optimistic case for the engine: it assumes the shell wrapper is parsed
perfectly. The strictest segment decides the command.

Usage: corpus-coverage.py RULES [--resolve-host-executables]
Env:   CODEX (binary), CODEX_HOME / HOME (scratch, never the real ones)
Prints `total=N forbidden=F prompt=P not-stopped=U` and one line per command
that is not forbidden.
"""
import json, os, re, shlex, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TESTPACK = os.path.join(HERE, "..", "test-pack.sh")
ORDER = {"none": 0, "allow": 1, "prompt": 2, "forbidden": 3}


def corpus():
    src = open(TESTPACK).read()
    start = src.index("for c in 'gh pr merge 7 --squash'")
    end = src.index("do\n    guard_run", start)
    block = src[start:end]
    cmds = []
    for line in block.split("\n"):
        line = line.strip().rstrip("\\").strip()
        line = re.sub(r"^for c in ", "", line)
        line = re.sub(r";\s*$", "", line).strip()
        if not line:
            continue
        if line.endswith(";"):
            line = line[:-1].strip()
        m = re.fullmatch(r"'(.*)'|\"(.*)\"", line)
        if not m:
            continue
        s = m.group(1) if m.group(1) is not None else m.group(2)
        # undo the bash quoting used in the list: '\"' and '\'' escapes
        s = s.replace('\\"', '"').replace("'\\''", "'")
        cmds.append(s)
    return cmds


def decision(rules, tokens, resolve):
    cmd = [os.environ.get("CODEX", "codex"), "execpolicy", "check", "--rules", rules]
    if resolve:
        cmd.append("--resolve-host-executables")
    r = subprocess.run(cmd + ["--"] + tokens, capture_output=True, text=True)
    try:
        return json.loads(r.stdout).get("decision") or "none"
    except Exception:
        return "none"


def decide(cmd, rules, resolve):
    worst = "none"
    for seg in re.split(r"\s*(?:&&|\|\||;|\|)\s*", cmd):
        seg = seg.strip()
        if not seg:
            continue
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()
        d = decision(rules, toks, resolve)
        if ORDER[d] > ORDER[worst]:
            worst = d
    return worst


def main():
    rules = sys.argv[1]
    resolve = "--resolve-host-executables" in sys.argv[2:]
    cmds = corpus()
    res = [(c, decide(c, rules, resolve)) for c in cmds]
    n = len(res)
    f = sum(1 for _, d in res if d == "forbidden")
    p = sum(1 for _, d in res if d == "prompt")
    print(f"total={n} forbidden={f} prompt={p} not-stopped={n - f - p}")
    for c, d in res:
        if d != "forbidden":
            print(f"{d}\t{c}")


if __name__ == "__main__":
    main()
