# SPDX-License-Identifier: MIT
"""Rollback planner for bad releases (Aisyah, DevOps).

Stdlib-only. Given a bad tag, prints (or with --execute, runs) the
rollback: mark the GitHub Release appropriately, point the updater at the
last-good release, and draft the incident note. Never deletes anything
without --execute, never force-pushes, never retags.

  python3 tool/rollback_release.py --bad-tag v1.0.0-beta.2 --last-good v1.0.0-beta.1
  python3 tool/rollback_release.py --bad-tag v1.0.0 --last-good v1.0.0-beta.3 --execute

Rollback policy (see docs/runbooks/rollout.md): the updater follows
`/releases/latest` (stable) or the newest non-draft (beta), so rolling
back means making the bad release invisible to those endpoints (mark as
draft, or delete the release and keep the tag as a record) — never
moving tags.
"""

import argparse as _argparse
import subprocess as _subprocess
import sys as _sys


def _base(tag):
    return tag.strip().lstrip("v").split("+")[0]


def plan(bad_tag, last_good, stable):
    """Ordered rollback steps as (title, command-or-None) pairs."""
    track = "stable" if stable else "beta"
    return [
        ("Mark the bad release so updaters skip it",
         f"gh release edit {bad_tag} --draft "
         f"# alt: `gh release delete {bad_tag} -y` (keeps the tag as a record)"),
        ("Confirm the track endpoint now resolves to last-good",
         f"gh release view {last_good} --json tagName,isDraft,isPrerelease "
         f"# {track} track: /releases/latest must be {last_good}"
         + ("" if stable else " (or newest non-draft for beta)")),
        ("Verify the asset set the updater expects is intact",
         f"gh release view {last_good} --json assets "
         f"# expect mycontrolpanel-{{macos,windows}}-*, mycontrolpanel-linux-*.tar.gz, SHA256SUMS.txt"),
        ("Post the incident note (docs/runbooks/incident.md)",
         None),
    ]


def _run(cmd):
    proc = _subprocess.run(cmd, shell=True)
    return proc.returncode


def main(argv=None):
    ap = _argparse.ArgumentParser(description="Plan (or execute) a release rollback.")
    ap.add_argument("--bad-tag", required=True, help="e.g. v1.0.0-beta.2")
    ap.add_argument("--last-good", required=True, help="e.g. v1.0.0-beta.1")
    ap.add_argument("--stable", action="store_true",
                    help="bad release was on the stable track (default: beta)")
    ap.add_argument("--execute", action="store_true",
                    help="run the gh commands instead of only printing them")
    args = ap.parse_args(argv)

    if _base(args.bad_tag) == _base(args.last_good):
        print("rollback: --bad-tag and --last-good resolve to the same "
              "version; refusing.", file=_sys.stderr)
        return 1

    steps = plan(args.bad_tag, args.last_good, args.stable)
    print(f"rollback {args.bad_tag} -> {args.last_good} "
          f"({'stable' if args.stable else 'beta'} track, "
          f"{'EXECUTE' if args.execute else 'dry-run'})")
    rc = 0
    for i, (title, cmd) in enumerate(steps, 1):
        print(f"\n{i}. {title}")
        if cmd is None:
            print("   (manual: open docs/runbooks/incident.md and file it)")
            continue
        print(f"   $ {cmd}")
        if args.execute and not cmd.startswith("#"):
            rc = _run(cmd.split(" # ")[0]) or rc
    if not args.execute:
        print("\ndry-run: nothing executed. Re-run with --execute to run the gh commands.")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
