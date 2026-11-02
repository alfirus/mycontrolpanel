# SPDX-License-Identifier: MIT
"""Agent install-contract tests (Burhanah release gate C4 / R8).

Pins the deploy contract the app, installer, and systemd unit must agree on:
port :9108, unit markers, installer defaults, embedded payload endpoints.
Pure stdlib + pytest — no network, no root, no SSH.
"""

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
AGENT_DIR = REPO / "agent"
SERVICE = AGENT_DIR / "mcp-agent.service"
INSTALLER = REPO / "scripts" / "install-agent.sh"
APP_SERVICE = REPO / "lib" / "services" / "agent_service.dart"
LIFECYCLE = REPO / "docs" / "runbooks" / "agent-lifecycle.md"

PORT = "9108"


def _text(path):
    return path.read_text(encoding="utf-8")


def test_unit_file_present_and_targets_9108():
    assert SERVICE.is_file(), "agent/mcp-agent.service missing"
    text = _text(SERVICE)
    assert PORT in text, "unit file does not reference :9108"
    assert "agent.py" in text, "unit ExecStart does not run agent.py"


def test_unit_file_hardening_markers():
    text = _text(SERVICE)
    for marker in ("NoNewPrivileges=true", "WantedBy=", "[Service]", "[Install]"):
        assert marker in text, f"unit file lacks hardening marker `{marker}`"


def test_installer_defaults_agree_with_unit():
    assert INSTALLER.is_file(), "scripts/install-agent.sh missing"
    text = _text(INSTALLER)
    assert 'AGENT_PORT="9108"' in text or "AGENT_PORT='9108'" in text or "9108" in text, (
        "installer does not default to port 9108"
    )
    assert "agent/mcp-agent.service" in text, (
        "installer default UNIT_FILE is not agent/mcp-agent.service"
    )
    assert "/opt/mcp-agent" in text, "installer does not target /opt/mcp-agent"


def test_app_service_agrees_on_port_and_endpoints():
    assert APP_SERVICE.is_file(), "lib/services/agent_service.dart missing"
    text = _text(APP_SERVICE)
    assert "agentPort = 9108" in text, "app agentPort drifted from 9108"
    for endpoint in ("/metrics", "/procstats"):
        assert endpoint in text, f"app/payload lost endpoint {endpoint}"


def test_lifecycle_runbook_exists():
    assert LIFECYCLE.is_file(), "docs/runbooks/agent-lifecycle.md missing"
    text = _text(LIFECYCLE)
    assert PORT in text, "lifecycle runbook does not mention :9108"


def test_no_hardcoded_secrets_in_contract_files():
    secret_pat = re.compile(r"(?i)(BEGIN [A-Z ]*PRIVATE KEY|sk-(live|test)-[A-Za-z0-9]{8})")
    for path in (SERVICE, INSTALLER):
        assert not secret_pat.search(_text(path)), f"{path.name} looks leaked"
