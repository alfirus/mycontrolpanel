# Changelog

All notable changes to MyControlPanel, newest first. Versioning:
`pubspec.yaml` `version: <name>+<build>`; releases are cut as Git tags
`v<name>` via `.github/workflows/release.yml` (see
[Release checklist](docs/releases.md)).

## [Unreleased]

## [1.0.0-alpha.1+1] — 2026-10-28

### Fixed

- macOS build: `List<dynamic>` → `List<double>` type error in
  latency/CPU history (#36).
- Linux release build: add `libsecret-1-dev` for
  `flutter_secure_storage` (#11).
- Release workflow action refs (valid checkout/flutter pins, tags for
  the rest) (#10).
- README: wire real screenshots (overview + server-details) (#12);
  broken image refs removed until PNGs landed (#9).

### Added

- Real SSH log tail (journal/syslog/docker per saved server, refresh on
  poll tick; demo heartbeat only with no servers).
- Metrics history with live p95 (per-host latency/CPU ring buffer,
  cap 120) and foreground alert watcher (bell + snack on new firing
  signals / failed CI runs, diffed against last-seen set) (#13).
- Secure credentials: `flutter_secure_storage` (Keychain/Keystore) with
  one-time `SharedPreferences` migration; APM-lite agent v2 `/procstats`
  (top processes, per-port connections); GitHub Projects v2 (GraphQL)
  Tasks tab; in-app updates from GitHub Releases (Windows/Linux/macOS);
  streaming AI chat (SSE/NDJSON, Anthropic/Gemini-native, Ollama tool
  calling); AI audit trail (append-only, capped at 200) (#8).

## Template for new entries (copy, fill, move above)

```markdown
## [x.y.z+n] — YYYY-MM-DD

### Added

- …

### Changed

- …

### Fixed

- …

### Security

- …

### Docs

- …

### Removed / Deprecated

- …
```

Keep one section per heading actually used; drop the rest. Link PR/issue
numbers (`#13`) so any entry traces back to the change.
