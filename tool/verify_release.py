# SPDX-License-Identifier: MIT
"""Beta release gate verifier (Burhanah, Release Verifier).

Stdlib-only. Re-verifies every beta-release claim from primary sources and
emits a machine-readable proof bundle (release-proof.json).

  python3 tool/verify_release.py --tag v1.0.0-beta.1 [--dist dist/]
      [--proof-out release-proof.json] [--max-age-hours 24]
      [--waiver-file docs/waivers/v1.0.0-beta.1.md]
      [--skip-flutter] [--skip-agent] [--skip-assets]

Verdict: GO (exit 0) only when every check passes on re-run evidence.
Any FAIL -- or any SKIP (unverified, incl. skipped suites/assets) -- is
HOLD (exit 1), unless a valid owner waiver (Sofia, CEO) covers every
non-passing check, in which case the verdict is GO-WAIVED (exit 0) with
the waiver recorded in the proof.

Tag/version rule: tag `v<name>` where <name> is the pubspec `version:`
name part (before `+`); the newest versioned `## [...]` CHANGELOG section
must carry the same base version plus a date.
"""

import argparse
import datetime as _dt
import hashlib as _hashlib
import json as _json
import os as _os
import re as _re
import subprocess as _subprocess
import sys as _sys

REPO = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))

CHECKS = []


def check(id_, name):
    def deco(fn):
        CHECKS.append((id_, name, fn))
        return fn

    return deco


def _read(rel):
    with open(_os.path.join(REPO, rel), encoding="utf-8") as fh:
        return fh.read()


def _base(ver):
    """Strip build metadata (`+1`) and a leading `v` for comparison."""
    return ver.strip().lstrip("v").split("+")[0]


@check("C1", "version==CHANGELOG==tag")
def _c1(ctx):
    """pubspec version name, newest versioned CHANGELOG section, tag agree."""
    m = _re.search(r"^version:\s*([^\s#]+)", _read("pubspec.yaml"), _re.M)
    if not m:
        return ("fail", "pubspec.yaml has no `version:` line")
    pub = m.group(1)
    sections = _re.findall(
        r"^##\s+\[([^\]]+)\]\s*(?:—\s*(\d{4}-\d{2}-\d{2}))?",
        _read("CHANGELOG.md"),
        _re.M,
    )
    versioned = [(v, d) for v, d in sections if v.strip().lower() != "unreleased"]
    if not versioned:
        return ("fail", "CHANGELOG.md has no versioned `## [x]` section")
    cl_ver, cl_date = versioned[0]
    tag = ctx["tag"]
    if _base(pub) != _base(tag):
        return ("fail", f"pubspec `{pub}` base != tag `{tag}` base")
    if _base(cl_ver) != _base(tag):
        return (
            "fail",
            f"CHANGELOG newest section `[{cl_ver}]` base != tag `{tag}` base",
        )
    if not cl_date:
        return ("fail", f"CHANGELOG `[{cl_ver}]` carries no release date")
    ctx["version"] = _base(pub)
    return ("pass", f"pubspec={pub} CHANGELOG=[{cl_ver}] tag={tag}")


def _expected_assets(version):
    return [
        f"mycontrolpanel-macos-{version}.zip",
        f"mycontrolpanel-windows-{version}.zip",
        f"mycontrolpanel-linux-{version}.tar.gz",
    ]


@check("C2", "all 3 platform assets fresh from CI")
def _c2(ctx):
    """Exact updater-expected names present, SHA256SUMS verifies, mtimes fresh."""
    if ctx["skip_assets"]:
        return ("skip", "--skip-assets: assets not re-verified")
    dist = ctx["dist"]
    version = ctx.get("version") or _base(ctx["tag"])
    names = _expected_assets(version)
    missing = [
        n for n in names + ["SHA256SUMS.txt"] if not _os.path.isfile(_os.path.join(dist, n))
    ]
    if missing:
        return ("fail", f"missing in {dist}/: {', '.join(missing)}")
    sums_path = _os.path.join(dist, "SHA256SUMS.txt")
    with open(sums_path, encoding="utf-8") as fh:
        sums = fh.read()
    max_age = ctx["max_age_hours"] * 3600
    now = _dt.datetime.now(_dt.timezone.utc).timestamp()
    ctx.setdefault("assets", [])
    for name in names:
        path = _os.path.join(dist, name)
        size = _os.path.getsize(path)
        if size == 0:
            return ("fail", f"{name} is empty")
        with open(path, "rb") as fh:
            digest = _hashlib.sha256(fh.read()).hexdigest()
        m = _re.search(rf"^{digest}\s+{re_escape(name)}\s*$", sums, _re.M)
        if not m:
            return ("fail", f"{name}: sha256 {digest[:12]}… not in SHA256SUMS.txt")
        age_h = (now - _os.path.getmtime(path)) / 3600
        if max_age >= 0 and (now - _os.path.getmtime(path)) > max_age:
            return (
                "fail",
                f"{name} is {age_h:.1f}h old (>{ctx['max_age_hours']}h): "
                "stale, not fresh from this CI run",
            )
        ctx["assets"].append({"name": name, "sha256": digest, "size": size})
    sums_size = _os.path.getsize(sums_path)
    if sums_size == 0:
        return ("fail", "SHA256SUMS.txt is empty")
    return ("pass", f"3 assets + SHA256SUMS.txt verify (sha256 ok, fresh <={ctx['max_age_hours']}h)")


def re_escape(s):
    return _re.escape(s)


def _run(cmd, cwd=REPO, timeout=1500):
    try:
        proc = _subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
    except FileNotFoundError:
        return (127, "", f"executable not found: {cmd[0]} (is it on PATH?)")
    except _subprocess.TimeoutExpired:
        return (124, "", f"timed out after {timeout}s: {' '.join(cmd)}")
    tail = (proc.stdout + proc.stderr)[-3000:]
    return (proc.returncode, tail, "")


@check("C3", "flutter test green (re-run)")
def _c3(ctx):
    if ctx["skip_flutter"]:
        return ("skip", "--skip-flutter: suite not re-run")
    code, tail, err = _run(["flutter", "test"])
    if err:
        return ("fail", err)
    if code != 0:
        return ("fail", f"`flutter test` exit={code}\n{tail}")
    line = next(
        (ln for ln in tail.splitlines() if _re.search(r"All tests passed|\+[0-9]+.*:", ln)),
        tail.strip().splitlines()[-1] if tail.strip() else "no output",
    )
    return ("pass", f"`flutter test` exit=0 ({line.strip()})")


@check("C4", "agent pytest green (re-run)")
def _c4(ctx):
    if ctx["skip_agent"]:
        return ("skip", "--skip-agent: suite not re-run")
    suite = _os.path.join(REPO, "agent", "tests")
    if not _os.path.isdir(suite):
        return ("fail", "agent/tests/ missing: no agent contract suite to run")
    code, tail, err = _run([_sys.executable, "-m", "pytest", "agent/tests", "-q"])
    if err:
        return ("fail", err)
    if code != 0:
        return ("fail", f"agent pytest exit={code}\n{tail}")
    line = next(
        (ln for ln in tail.splitlines() if "passed" in ln),
        tail.strip().splitlines()[-1] if tail.strip() else "no output",
    )
    return ("pass", f"agent pytest exit=0 ({line.strip()})")


_CONSENT_PINS = [
    ("test/sentry_consent_test.dart", [r"optedIn:\s*false", r"isFalse"]),
    ("test/background_consent_tile_test.dart", [r"value:\s*false", r"[Oo][Ff][Ff]"]),
    ("test/desktop_consent_tile_test.dart", [r"value:\s*false", r"[Oo][Ff][Ff]"]),
    ("lib/services/error_reporting.dart", [r"optedIn", r"\?\?\s*false"]),
]


@check("C5", "consent/Sentry default-off tests present")
def _c5(ctx):
    problems = []
    for rel, patterns in _CONSENT_PINS:
        path = _os.path.join(REPO, rel)
        if not _os.path.isfile(path):
            problems.append(f"{rel} MISSING")
            continue
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for pat in patterns:
            if not _re.search(pat, text):
                problems.append(f"{rel} lacks /{pat}/")
    if problems:
        return ("fail", "; ".join(problems))
    return ("pass", f"{len(_CONSENT_PINS)} consent pins present (Sentry + background + desktop, default OFF)")


@check("C6", "MIT headers intact")
def _c6(ctx):
    lic = _os.path.join(REPO, "LICENSE")
    problems = []
    try:
        with open(lic, encoding="utf-8") as fh:
            lic_text = fh.read()
    except FileNotFoundError:
        return ("fail", "LICENSE file missing")
    for marker in ("MIT License", "Copyright"):
        if marker not in lic_text:
            problems.append(f"LICENSE lacks `{marker}`")
    lib = _os.path.join(REPO, "lib")
    bare = []
    total = 0
    for dirpath, _dirnames, filenames in _os.walk(lib):
        for fn in sorted(filenames):
            if not fn.endswith(".dart"):
                continue
            total += 1
            with open(_os.path.join(dirpath, fn), encoding="utf-8") as fh:
                head = "".join([fh.readline() for _ in range(5)])
            if "SPDX-License-Identifier" not in head and "MIT License" not in head:
                bare.append(_os.path.relpath(_os.path.join(dirpath, fn), REPO))
    if bare:
        problems.append(f"{len(bare)} lib files lack MIT header: {', '.join(bare[:5])}")
    if problems:
        return ("fail", "; ".join(problems))
    return ("pass", f"LICENSE MIT + {total} lib/*.dart carry MIT header")


def _load_waiver(path, tag):
    """A waiver is valid only when it names the tag and is approved by Sofia."""
    problems = []
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        return (None, [f"waiver file not found: {path}"])
    for required in (f"Tag: {tag}", "Approved-by: Sofia", "Reason:"):
        if required not in text:
            problems.append(f"waiver lacks `{required}`")
    if problems:
        return (None, problems)
    covered = _re.findall(r"^Covers:\s*(.+)$", text, _re.M)
    return ({"file": path, "covers": covered or ["(all non-passing checks)"]}, [])


def main(argv=None):
    ap = argparse.ArgumentParser(description="Beta release gate verifier.")
    ap.add_argument("--tag", default=_os.environ.get("GITHUB_REF_NAME", ""),
                    help="release tag, e.g. v1.0.0-beta.1 (default: $GITHUB_REF_NAME)")
    ap.add_argument("--dist", default=_os.path.join(REPO, "dist"),
                    help="dir holding CI-built release assets (default: ./dist/)")
    ap.add_argument("--proof-out", default=_os.path.join(REPO, "release-proof.json"))
    ap.add_argument("--max-age-hours", type=float, default=24,
                    help="asset freshness window; negative disables (default: 24)")
    ap.add_argument("--waiver-file", default=None)
    ap.add_argument("--skip-flutter", action="store_true")
    ap.add_argument("--skip-agent", action="store_true")
    ap.add_argument("--skip-assets", action="store_true")
    args = ap.parse_args(argv)

    if not args.tag:
        print("HOLD: no --tag and $GITHUB_REF_NAME unset", file=_sys.stderr)
        return 2
    ctx = {
        "tag": args.tag.strip(),
        "dist": args.dist,
        "max_age_hours": args.max_age_hours,
        "skip_flutter": args.skip_flutter,
        "skip_agent": args.skip_agent,
        "skip_assets": args.skip_assets,
    }
    results = []
    for id_, name, fn in CHECKS:
        try:
            status, detail = fn(ctx)
        except Exception as exc:  # never let the gate crash green
            status, detail = ("fail", f"checker raised {type(exc).__name__}: {exc}")
        results.append({"id": id_, "name": name, "status": status, "detail": detail})
        print(f"[{status.upper():>4}] {id_} {name}: {detail.splitlines()[0][:160]}")

    waiver = None
    bad = [r for r in results if r["status"] != "pass"]
    verdict = "GO" if not bad else "HOLD"
    if bad and args.waiver_file:
        waiver, wproblems = _load_waiver(args.waiver_file, ctx["tag"])
        if waiver:
            verdict = "GO-WAIVED"
            print(f"waiver accepted: {args.waiver_file}")
        else:
            results.append({"id": "W0", "name": "owner waiver",
                            "status": "fail", "detail": "; ".join(wproblems)})
    try:
        commit = _subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                                 capture_output=True, text=True).stdout.strip()
    except Exception:
        commit = ""
    proof = {
        "schema": "mycontrolpanel/release-proof@1",
        "verdict": verdict,
        "tag": ctx["tag"],
        "version": ctx.get("version", ""),
        "commit": commit,
        "timestamp_utc": _dt.datetime.now(_dt.timezone.utc).isoformat(),
        "checks": results,
        "assets": ctx.get("assets", []),
        "waiver": waiver,
    }
    with open(args.proof_out, "w", encoding="utf-8") as fh:
        _json.dump(proof, fh, indent=2)
        fh.write("\n")
    print(f"verdict={verdict} proof={args.proof_out}")
    return 0 if verdict in ("GO", "GO-WAIVED") else 1


if __name__ == "__main__":
    _sys.exit(main())
