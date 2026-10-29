# Agent v3 — sysstats for APM-lite capacity planning

## Why

The v2 agent answers "is this host healthy right now" (`/metrics`,
`/procstats`). Sizing on-host model serving (LM Studio / Ollama) needs
one more level: load pressure over time, real memory headroom, GPU
presence, and agent self-uptime (to tell a fresh reboot from a stuck
reporter). That is `/sysstats`.

## Endpoints (TCP 9108, unchanged port/auth)

- `GET /metrics` — v2 schema unchanged + additive `load1` (1-min load
  average). Existing validators ignore unknown keys, so v2 app releases
  keep parsing v3 agents.
- `GET /procstats` — unchanged.
- `GET /sysstats` (v3+) — `version`, `load1/5/15`, `mem` (`total_mb`,
  `avail_mb`, `swap_total_mb`, `swap_free_mb`), `gpu` (`present`,
  `count` from `/dev/nvidia[0-9]*`), `agent_uptime_s`.

## Non-goals (deliberate)

- **No GPU utilization %**: stdlib-only agent, no NVML. Presence +
  count is enough to decide "route GPU work here or not".
- **No inference counters in the agent**: per-model latency / token /
  error stats live app-side in `LlmReliability` (SharedPreferences) and
  are correlated by host. The agent never fabricates inference numbers
  it cannot observe.
- **No new dependencies**: still stdlib-only Python, same systemd unit,
  same install path. Upgrade = reinstall (version floor logic in
  `agent_protocol.dart` already accepts v3: `version >= kMinAgentVersion`).

## Verification

- `test/agent_sysstats_test.dart` — contract test on the embedded
  script (v3 markers present, v2 endpoints intact).
- Live-booted the extracted script on Windows: `/metrics`,
  `/procstats`, `/sysstats` return 200 with the documented shapes,
  unknown paths still 404 (zeros expected — no `/proc` on Windows; on
  Linux the same code paths read real values like the v2 readers do).
