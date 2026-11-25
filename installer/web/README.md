# installer/web

The one-line installer bootstrap served at **`https://buildersinabox.com/install.sh`**.

```bash
curl -fsSL https://buildersinabox.com/install.sh | sudo bash
```

`install.sh` here is a thin shim: it validates the host, fetches the
installer repo into `/opt/buildersinabox`, and hands off to the real
installer (`payload/install.sh`). It's intentionally small (<120 lines)
so anyone can read it before piping to bash.

## Contract with the landing (FEAT-010)

This file is published **byte-for-byte** to `buildersinabox.com/install.sh`.
The landing's `site/build.sh` copies it into the Pages output and fails the
build if the two ever drift. Don't edit the served copy directly — edit
this one.

## Overrides (for testing / advanced use)

| Env | Effect |
|---|---|
| `BIB_OS_OVERRIDE=1` | skip the Ubuntu 24.04 check |
| `BIB_REF=<tag\|branch>` | clone a specific ref (default `main`) — pin a release for reproducibility |
| `BIB_REPO_URL=<url>` | clone from a fork/mirror (default: the public repo) |
| `BIB_DEST=<path>` | install location (default `/opt/buildersinabox`) |
| `BIB_BOOTSTRAP_DRYRUN=1` | fetch only, don't exec the installer |

Any extra arguments pass through to `payload/install.sh` (e.g. `--flavor=gift`).

## Test

`./test-bootstrap.sh` builds a throwaway bare repo from the current tree
and runs the bootstrap against it in dry-run mode — no root, no network.
