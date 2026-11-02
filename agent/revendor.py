# SPDX-License-Identifier: MIT
"""Re-vendor the anomaly scorer into the deployed agent script.

Canonical source: agent/anomaly_scorer.py (markers BEGIN/END ANOMALY
SCORER). Target: the agentScript embedded Python in
lib/services/agent_service.dart (deployed to /opt/mcp-agent/agent.py).

Usage: python agent/revendor.py   (run from the repo root)
Parity is enforced by test/agent_embedded_parity_test.dart.
"""
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
BEGIN = "# BEGIN ANOMALY SCORER (vendored into AgentService.agentScript verbatim)"
END = "# END ANOMALY SCORER (vendored into AgentService.agentScript verbatim)"


def _read(path):
    # Byte-level IO: never let Windows text-mode translation touch line
    # endings (repo files are LF; Dart raw-string parity depends on it).
    return path.read_bytes().decode("utf-8")


def _write(path, text):
    path.write_bytes(text.encode("utf-8"))


def main():
    scorer_src = _read(REPO / "agent" / "anomaly_scorer.py")
    si, ei = scorer_src.index(BEGIN), scorer_src.index(END) + len(END)
    block = scorer_src[si:ei]
    if "'''" in block:
        sys.exit("refusing: triple-quote would break the Dart raw string")
    if "$" in block:
        sys.exit("refusing: dollar would interpolate in the Dart string")
    dart_path = REPO / "lib" / "services" / "agent_service.dart"
    text = _read(dart_path)
    dsi, dei = text.index(BEGIN), text.index(END) + len(END)
    text = text[:dsi] + block + text[dei:]
    _write(dart_path, text)
    print("re-vendored %d lines" % (block.count("\n") + 1))


if __name__ == "__main__":
    main()
