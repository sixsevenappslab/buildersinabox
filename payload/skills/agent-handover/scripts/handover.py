#!/usr/bin/env python3
"""Persist compact, agent-neutral task handovers outside agent runtimes."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


REQUIRED_HEADINGS = (
    "Objective",
    "Completed",
    "Decisions",
    "Files changed",
    "Validation",
    "Blockers",
    "Pending",
    "Next step",
)
SECRET_PATTERNS = (
    re.compile(r"\b(?:sk|gh[opusr]|AIza)[-_A-Za-z0-9]{16,}\b"),
    re.compile(r"\b(?:xox[baprs]-|glpat-)[-_A-Za-z0-9]{16,}\b"),
    re.compile(r"\bgithub_pat_[-_A-Za-z0-9]{20,}\b"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"https://hooks\.slack\.com/services/[A-Za-z0-9/_-]{20,}"),
    re.compile(
        r"\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://"
        r"[^\s:/@]+:[^\s/@]+@"
    ),
    re.compile(
        r"(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)"
        r"\s*[:=]\s*['\"]?[^\s'\"<>]{8,}"
    ),
)
MAX_PAYLOAD_BYTES = 64 * 1024


def run_git(cwd: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(cwd), *args],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def repository_context(cwd: Path) -> dict[str, str]:
    repo_root = run_git(cwd, "rev-parse", "--show-toplevel")
    identity = Path(repo_root).resolve() if repo_root else cwd.resolve()
    branch = run_git(identity, "branch", "--show-current") if repo_root else None
    commit = run_git(identity, "rev-parse", "HEAD") if repo_root else None
    porcelain = run_git(identity, "status", "--short") if repo_root else None
    return {
        "identity": str(identity),
        "repo_root": repo_root or "none",
        "branch": branch or "detached-or-none",
        "commit": commit or "none",
        "dirty": "yes" if porcelain else "no",
    }


def state_root() -> Path:
    override = os.environ.get("AGENT_HANDOVER_STATE_DIR")
    if override:
        return Path(override).expanduser().resolve()
    xdg_state = os.environ.get("XDG_STATE_HOME")
    base = (
        Path(xdg_state).expanduser() if xdg_state else Path.home() / ".local" / "state"
    )
    return base / "agent-handover"


def project_directory(context: dict[str, str]) -> Path:
    identity = context["identity"]
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]
    slug = (
        re.sub(r"[^a-zA-Z0-9._-]+", "-", Path(identity).name).strip("-") or "workspace"
    )
    return state_root() / f"{slug}-{digest}"


def unique_archive_path(archive_dir: Path, stamp: str, label: str) -> Path:
    archive = archive_dir / f"{stamp}-{label}.md"
    suffix = 1
    while archive.exists():
        archive = archive_dir / f"{stamp}-{label}-{suffix}.md"
        suffix += 1
    return archive


def validate_payload(payload: str) -> None:
    if not payload.strip():
        raise ValueError("handover payload is empty")
    if len(payload.encode("utf-8")) > MAX_PAYLOAD_BYTES:
        raise ValueError(f"handover payload exceeds {MAX_PAYLOAD_BYTES} bytes")
    missing = [
        heading for heading in REQUIRED_HEADINGS if f"## {heading}" not in payload
    ]
    if missing:
        raise ValueError("missing required headings: " + ", ".join(missing))
    for pattern in SECRET_PATTERNS:
        if pattern.search(payload):
            raise ValueError(
                "payload looks like it contains a credential or secret value"
            )


def render_handover(
    payload: str, agent: str, cwd: Path, context: dict[str, str]
) -> str:
    created_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    metadata = (
        "---\n"
        "schema_version: 1\n"
        f"created_at: {created_at}\n"
        f"source_agent: {agent}\n"
        f"cwd: {cwd.resolve()}\n"
        f"repo_root: {context['repo_root']}\n"
        f"branch: {context['branch']}\n"
        f"commit: {context['commit']}\n"
        f"dirty: {context['dirty']}\n"
        "---\n\n"
    )
    return metadata + payload.strip() + "\n"


def _normalize_item(item: str) -> str:
    """Comparable form of a bullet, insensitive to the ways agents restyle one.

    Markdown emphasis and trailing punctuation are dropped because they are not
    the item: without this, "- rotate token", "- rotate token." and
    "- **rotate token**" would be treated as three separate items across saves.
    """
    stripped = re.sub(r"^(?:[-*]|\d+\.)\s+", "", item.strip())
    stripped = re.sub(r"[*_`]+", "", stripped)
    stripped = re.sub(r"\s+", " ", stripped).strip()
    return stripped.rstrip(".,;:!\u2014- ").casefold()


# Placeholder bullets ("None.", "N/A") appear when agents fill an empty section
# rather than leave it blank; carrying those forward as inherited blockers would
# be noise. Kept as a closed list rather than a broad prefix pattern so real
# terse items are never dropped.
_PLACEHOLDER_ITEM = re.compile(
    r"^(?:none|nothing|n/?a|empty|no (?:blockers|pending(?: items?)?)"
    r"|ninguno|ninguna|nada|vacio|vac\u00edo"
    r"|sin (?:bloqueos|pendientes|blockers))\b[.\s]*$"
)


def _section_bullets(text: str, heading: str) -> list[str]:
    """Items under `## <heading>`, each keeping its indented continuation lines.

    Handovers often wrap an item's reason onto the next indented line; reading
    only the marker line would carry the title forward and drop the context.
    """
    items: list[str] = []
    for line in extract_section(text, heading).splitlines():
        stripped = line.strip()
        if re.match(r"^(?:[-*]|\d+\.)\s+\S", stripped):
            items.append(line.rstrip())
        elif (
            items
            and stripped
            and line[:1].isspace()  # indented: a wrapped line, not a new block
            and not stripped.startswith("#")  # never the `### Inherited` marker
        ):
            items[-1] += "\n" + line.rstrip()
    return [i for i in items if not _PLACEHOLDER_ITEM.match(_normalize_item(i))]


def _append_to_section(text: str, heading: str, addition: str) -> str:
    """Insert `addition` at the end of `## <heading>`'s body, later sections intact."""
    pattern = re.compile(
        rf"^(## {re.escape(heading)}\s*$)(.*?)(?=^## |\Z)",
        re.MULTILINE | re.DOTALL,
    )

    def repl(match: "re.Match[str]") -> str:
        body = match.group(2).strip()
        parts = [match.group(1)]
        if body:
            parts.append(body)
        parts.append(addition)
        return "\n".join(parts) + "\n\n"

    return pattern.sub(repl, text, count=1)


def carry_forward(
    payload: str, previous: str, overhead: int = 0
) -> tuple[str, list[str], list[str]]:
    """Re-attach unresolved Blockers/Pending items the new payload left out.

    `save` archives instead of merging and only `current.md` is ever read back,
    so an item the new payload omits would otherwise be lost. An item is left
    behind only when the new payload accounts for it somewhere: still open in
    Blockers/Pending, closed in Completed, or dropped on purpose in Decisions.

    Matching is deliberately literal: a reworded item is carried twice rather
    than assumed handled. A visible duplicate is the safe failure mode; a
    silently dropped blocker is not.
    """
    created = parse_metadata(previous).get("created_at", "unknown")
    carried: list[str] = []
    skipped: list[str] = []
    # Still-open items, compared for equality and pooled across both sections:
    # an item promoted from Blockers to Pending (or back) is the same item.
    # Equality rather than substring containment prevents a negated sentence
    # ("do not deploy gateway yet") from silently swallowing "deploy gateway".
    still_open = {
        _normalize_item(b)
        for h in ("Blockers", "Pending")
        for b in _section_bullets(payload, h)
    }
    # Retired items: closing an item means restating it at the start of a
    # Completed/Decisions bullet followed by the evidence.
    retired = [
        _normalize_item(b)
        for h in ("Completed", "Decisions")
        for b in _section_bullets(payload, h)
    ]

    def _closes(done: str, norm: str) -> bool:
        """Does this Completed/Decisions bullet close exactly `norm`?

        Anchored at the start AND required to end at a separator or end-of-line
        so "- rotate Slack token: done" never retires the separate item
        "- rotate token".
        """
        if not done.startswith(norm):
            return False
        rest = done[len(norm) :].lstrip()
        return rest == "" or rest[0] in ":\u2014-.,;()"

    def accounted_for(item: str) -> bool:
        norm = _normalize_item(item)
        return norm in still_open or any(_closes(done, norm) for done in retired)

    for heading in ("Blockers", "Pending"):
        old_items = _section_bullets(previous, heading)
        if not old_items:
            continue
        missing = [i for i in old_items if not accounted_for(i)]
        if not missing:
            continue
        header = f"### Inherited from handover {created} \u2014 unresolved"
        accepted: list[str] = []
        for item in missing:
            block = "\n".join([header, *accepted, item])
            candidate = _append_to_section(payload, heading, block)
            if len(candidate.encode("utf-8")) + overhead > MAX_PAYLOAD_BYTES:
                skipped.append(item)
                continue
            accepted.append(item)
        if accepted:
            payload = _append_to_section(
                payload, heading, "\n".join([header, *accepted])
            )
            carried.extend(accepted)
    return payload, carried, skipped


def save(args: argparse.Namespace) -> int:
    cwd = Path(args.cwd).expanduser().resolve()
    input_path = Path(args.input).expanduser().resolve()
    payload = input_path.read_text(encoding="utf-8")
    validate_payload(payload)
    context = repository_context(cwd)
    target_dir = project_directory(context)
    archive_dir = target_dir / "archive"
    target_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    archive_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    current = target_dir / "current.md"
    lock_path = target_dir / ".lock"

    archived_from = None
    carried: list[str] = []
    skipped: list[str] = []
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if current.exists():
            stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            archive = unique_archive_path(archive_dir, stamp, args.agent)
            shutil.copy2(current, archive)
            archived_from = (archive, current.read_text(encoding="utf-8"))
            overhead = len(
                render_handover("", args.agent, cwd, context).encode("utf-8")
            )
            payload, carried, skipped = carry_forward(
                payload, archived_from[1], overhead=overhead
            )

        rendered = render_handover(payload, args.agent, cwd, context)
        fd, temp_name = tempfile.mkstemp(prefix=".current-", dir=target_dir, text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(rendered)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temp_name, 0o600)
            os.replace(temp_name, current)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)

    if carried:
        print(
            f"NOTE: {len(carried)} unresolved item(s) from the previous handover "
            "were automatically carried forward to Blockers/Pending under "
            "'Inherited'. Review them: if any are already resolved, close them "
            "with evidence in the next save.",
            file=sys.stderr,
        )
    if skipped:
        print(
            f"WARNING: {len(skipped)} item(s) from the previous handover exceed "
            f"the {MAX_PAYLOAD_BYTES}-byte limit and were left out.\n"
            "         Recover them manually from the archive before continuing:",
            file=sys.stderr,
        )
        for item in skipped:
            print(f"         {item}", file=sys.stderr)

    # Backstop for items reworded past literal recognition when Blockers/Pending
    # shrink significantly compared to the archived handover.
    if archived_from is not None:
        archive_path, previous = archived_from
        old_items = [
            b for h in ("Blockers", "Pending") for b in _section_bullets(previous, h)
        ]
        if old_items:
            new_body = "\n".join(
                extract_section(payload, h) for h in ("Blockers", "Pending")
            )
            if len(new_body.split()) < len(" ".join(old_items).split()) // 3:
                print(
                    f"WARNING: the archived handover had {len(old_items)} "
                    "items in Blockers/Pending and the new one has much less "
                    "text in those sections.\n"
                    f"         Check that nothing was dropped: {archive_path}\n"
                    "         (automatic carry-forward only matches literal items: "
                    "if you reworded one, copy it manually)",
                    file=sys.stderr,
                )

    print(current)
    return 0


def parse_metadata(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}
    metadata: dict[str, str] = {}
    for line in text[4:end].splitlines():
        key, separator, value = line.partition(":")
        if separator:
            metadata[key.strip()] = value.strip()
    return metadata


def load_current(target_dir: Path, keep: bool):
    current = target_dir / "current.md"
    if not current.exists():
        return None
    archive_dir = target_dir / "archive"
    target_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    archive_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = target_dir / ".lock"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if not current.exists():
            return None
        text = current.read_text(encoding="utf-8")
        # Reserve rather than consume on read so a session that exits early
        # does not lose the handover before completing the work (`commit`).
        if not keep:
            if claim_is_contended(target_dir):
                raise ClaimContention(
                    "another session claimed this handover seconds ago; "
                    "not handing it to two sessions at once"
                )
            write_claim(target_dir)
    return text, None


# Two thresholds govern claims:
# - CONTENTION: rejects a second reader within 60 seconds so two sessions do not
#   grab the same handover simultaneously, while allowing retries after a crash.
# - GRACE: sweeps stale claims older than 4 hours automatically.
CLAIM_CONTENTION_SECONDS = 60
CLAIM_GRACE_SECONDS = 4 * 60 * 60


class ClaimContention(RuntimeError):
    """Raised when another session holds a fresh claim on the handover."""


def claim_path(target_dir: Path) -> Path:
    return target_dir / "current.claim"


def write_claim(target_dir: Path) -> None:
    """Mark the handover as taken without moving it."""
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    payload = f"claimed_at: {stamp}\npid: {os.getpid()}\n"
    path = claim_path(target_dir)
    path.write_text(payload, encoding="utf-8")
    os.chmod(path, 0o600)


def claim_age_seconds(target_dir: Path) -> float | None:
    """Age of the current claim, or None when absent or expired past grace."""
    path = claim_path(target_dir)
    if not path.exists():
        return None
    try:
        age = dt.datetime.now().timestamp() - path.stat().st_mtime
    except OSError:
        return None
    if age > CLAIM_GRACE_SECONDS:
        path.unlink(missing_ok=True)
        return None
    return age


def claim_is_contended(target_dir: Path) -> bool:
    """True only while another session's claim is seconds old."""
    age = claim_age_seconds(target_dir)
    return age is not None and age < CLAIM_CONTENTION_SECONDS


def commit(args) -> int:
    """Consume the handover: the session says the work is done."""
    cwd = Path(args.cwd).expanduser().resolve()
    context = repository_context(cwd)
    target_dir = project_directory(context)
    current = target_dir / "current.md"
    archive_dir = target_dir / "archive"
    archive_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not current.exists():
        print("no handover to commit", file=sys.stderr)
        return 3
    lock_path = target_dir / ".lock"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if not current.exists():
            print("no handover to commit", file=sys.stderr)
            return 3
        text = current.read_text(encoding="utf-8")
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        label = parse_metadata(text).get("source_agent", "unknown") + "-consumed"
        archive = unique_archive_path(archive_dir, stamp, label)
        os.replace(current, archive)
        claim_path(target_dir).unlink(missing_ok=True)
    print(archive)
    return 0


def resume(args: argparse.Namespace) -> int:
    cwd = Path(args.cwd).expanduser().resolve()
    context = repository_context(cwd)
    target_dir = project_directory(context)
    loaded = load_current(target_dir, args.keep)
    if loaded is None:
        print(f"No handover found for {context['identity']}")
        return 3
    text, consumed_archive = loaded
    metadata = parse_metadata(text)

    warnings: list[str] = []
    source_agent = metadata.get("source_agent", "unknown")
    if source_agent == "unknown":
        transfer_kind = "unknown"
    elif source_agent == args.agent:
        transfer_kind = "same-harness"
    else:
        transfer_kind = "cross-harness"
    created_at = metadata.get("created_at")
    if created_at:
        try:
            created = dt.datetime.fromisoformat(created_at)
            age = dt.datetime.now(dt.timezone.utc) - created
            if age > dt.timedelta(hours=24):
                warnings.append(
                    f"handover is {age.days * 24 + age.seconds // 3600}h old"
                )
        except ValueError:
            warnings.append("handover has an invalid creation timestamp")

    for key in ("repo_root", "branch", "commit", "dirty"):
        previous = metadata.get(key)
        current_value = context[key]
        if previous and previous != current_value:
            warnings.append(f"{key} changed: {previous} -> {current_value}")

    print(f"# Handover for {args.agent}\n")
    print("## Transfer context")
    print(f"- source harness: {source_agent}")
    print(f"- target harness: {args.agent}")
    print(f"- transfer kind: {transfer_kind}")
    if consumed_archive is not None:
        print(f"- consumed archive: {consumed_archive}")
    if transfer_kind == "same-harness" and not warnings:
        print("- continuation mode: use Next step directly")
    elif transfer_kind == "same-harness":
        print("- continuation mode: verify drift before using Next step")
    else:
        print("- continuation mode: reconcile project before using Next step")
    print()
    if warnings:
        print("## Verification warnings")
        for warning in warnings:
            print(f"- {warning}")
        print()
    print(text, end="")
    return 0


def show_path(args: argparse.Namespace) -> int:
    context = repository_context(Path(args.cwd).expanduser().resolve())
    print(project_directory(context) / "current.md")
    return 0


def extract_section(text: str, heading: str) -> str:
    """Body of `## <heading>` up to the next `## ` heading, or "" if absent."""
    match = re.search(
        rf"^## {re.escape(heading)}\s*$(.*?)(?=^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    return match.group(1).strip() if match else ""


def pending(args: argparse.Namespace) -> int:
    """Print the live handover's Blockers/Pending so a new save can carry them.

    `save` re-attaches unresolved items automatically, but it matches
    literally: a reworded item is carried twice, and an item you finished is
    only retired if you account for it in Completed or Decisions. Run this
    BEFORE writing a new handover and resolve each item explicitly.

    Read-only: never claims, consumes or writes anything, so it is safe to
    run at any point and does not interfere with a resume/commit cycle.
    """
    context = repository_context(Path(args.cwd).expanduser().resolve())
    current = project_directory(context) / "current.md"
    if not current.exists():
        print("no current handover: nothing to carry forward", file=sys.stderr)
        return 3

    text = current.read_text(encoding="utf-8")
    created = parse_metadata(text).get("created_at", "unknown")
    print(f"# active handover \u2014 created_at: {created}")
    print(f"# {current}")
    for heading in ("Blockers", "Pending"):
        body = extract_section(text, heading)
        print(f"\n## {heading}\n")
        print(body if body else "(empty)")
    print(
        "\nDecide item by item: still live (repeat it) / resolved (move to "
        "Completed, with evidence) / superseded (move to Decisions).\nAnything "
        "not repeated or accounted for is re-attached automatically under '### Inherited'.",
        file=sys.stderr,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("save", "resume", "commit", "path", "pending"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--cwd", default=os.getcwd())
        if command in ("save", "resume"):
            subparser.add_argument(
                "--agent", required=True, choices=("claude", "codex", "other")
            )
        if command == "resume":
            subparser.add_argument("--keep", action="store_true")
        if command == "save":
            subparser.add_argument("--input", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "save":
            return save(args)
        if args.command == "resume":
            return resume(args)
        if args.command == "commit":
            return commit(args)
        if args.command == "pending":
            return pending(args)
        return show_path(args)
    except ClaimContention as exc:
        # Distinct exit code: the caller can tell "someone else is on it" from
        # "there is nothing here" (3) and from a real error (2).
        print(f"handover busy: {exc}", file=sys.stderr)
        return 4
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"handover error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
