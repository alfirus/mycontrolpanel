# SPDX-License-Identifier: MIT
"""Dependency SBOM generator (Aisyah, DevOps).

Stdlib-only. Converts the resolved ``pubspec.lock`` into a CycloneDX 1.5
JSON bill of materials so every tagged release ships a machine-readable
dependency manifest alongside the platform artifacts.

  python3 tool/sbom.py --lockfile pubspec.lock --app-version 1.0.0-alpha.1
      --out sbom.cyclonedx.json
  python3 tool/sbom.py --lockfile pubspec.lock --check   # parse only, no file

Scope mapping: ``direct main`` -> required; ``direct dev`` + transitive ->
optional (transitive deps of shipped code are still listed, just marked
optional so auditors can tell direct attack surface from indirect).

Exit 0 on success; exit 1 with a stderr message on any parse/IO failure.
"""

import argparse as _argparse
import datetime as _dt
import json as _json
import re as _re
import sys as _sys

_SCOPE = {"direct main": "required"}


def _parse_lockfile(text):
    """Minimal indentation-aware parser for pub's generated lockfile.

    Returns a list of dicts: name, version, source, dependency, sha256|None.
    Raises ValueError on structural problems.
    """
    packages = []
    current = None
    in_packages = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.strip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()
        if indent == 0:
            in_packages = stripped == "packages:"
            continue
        if not in_packages:
            continue
        if indent == 2 and stripped.endswith(":"):
            name = stripped[:-1].strip().strip("'\"")
            if not name:
                raise ValueError(f"line {lineno}: empty package name")
            current = {"name": name, "version": None, "source": None,
                       "dependency": None, "sha256": None}
            packages.append(current)
            continue
        if current is None:
            continue
        if indent == 4 and ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip().strip("'\"")
            if key in ("version", "source", "dependency"):
                current[key] = value or None
        elif indent == 6 and stripped.startswith("sha256:"):
            _, _, value = stripped.partition(":")
            current["sha256"] = value.strip().strip("'\"") or None
    if not packages:
        raise ValueError("no `packages:` entries found — not a pubspec.lock?")
    bad = [p["name"] for p in packages if not p["version"]]
    if bad:
        raise ValueError(f"packages without a version: {', '.join(bad[:5])}")
    return packages


def _component(pkg):
    ref = f"pkg:pub/{pkg['name']}@{pkg['version']}"
    comp = {
        "type": "library",
        "bom-ref": ref,
        "name": pkg["name"],
        "version": pkg["version"],
        "scope": _SCOPE.get((pkg["dependency"] or "").strip(), "optional"),
        "purl": ref,
    }
    if pkg["sha256"]:
        comp["hashes"] = [{"alg": "SHA-256", "content": pkg["sha256"]}]
    if pkg["source"] == "hosted":
        comp["externalReferences"] = [{
            "type": "website",
            "url": f"https://pub.dev/packages/{pkg['name']}",
        }]
    props = []
    if pkg["source"]:
        props.append({"name": "pub:source", "value": pkg["source"]})
    if pkg["dependency"]:
        props.append({"name": "pub:dependency", "value": pkg["dependency"]})
    if props:
        comp["properties"] = props
    return comp


def build_bom(packages, app_name, app_version):
    stamp = _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0)
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "timestamp": stamp.isoformat().replace("+00:00", "Z"),
            "tools": [{"vendor": "MyControlPanel",
                       "name": "tool/sbom.py", "version": "1"}],
            "component": {"type": "application", "name": app_name,
                          "version": app_version},
        },
        "components": [_component(p) for p in packages],
    }


def main(argv=None):
    ap = _argparse.ArgumentParser(description=("sbom: pubspec.lock -> CycloneDX"))
    ap.add_argument("--lockfile", default="pubspec.lock")
    ap.add_argument("--out", default="sbom.cyclonedx.json")
    ap.add_argument("--app-name", default="my-control-panel")
    ap.add_argument("--app-version", default="0.0.0")
    ap.add_argument("--check", action="store_true",
                    help="parse + report counts, write nothing")
    args = ap.parse_args(argv)
    try:
        with open(args.lockfile, encoding="utf-8") as fh:
            packages = _parse_lockfile(fh.read())
    except FileNotFoundError:
        print(f"sbom: lockfile not found: {args.lockfile}", file=_sys.stderr)
        return 1
    except ValueError as exc:
        print(f"sbom: {exc}", file=_sys.stderr)
        return 1
    hashed = sum(1 for p in packages if p["sha256"])
    direct = sum(1 for p in packages if (p["dependency"] or "") == "direct main")
    print(f"sbom: {len(packages)} packages ({direct} direct, "
          f"{hashed} with sha256) from {args.lockfile}")
    if args.check:
        return 0
    bom = build_bom(packages, args.app_name, args.app_version)
    try:
        with open(args.out, "w", encoding="utf-8") as fh:
            _json.dump(bom, fh, indent=2)
            fh.write("\n")
    except OSError as exc:
        print(f"sbom: cannot write {args.out}: {exc}", file=_sys.stderr)
        return 1
    print(f"sbom: wrote {args.out} "
          f"({len(bom['components'])} components, CycloneDX 1.5)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
