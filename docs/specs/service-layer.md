# Service-layer split — interfaces, DI, mocks

Status: **normative** for new code; migration of existing call sites is
incremental. Code: `lib/services/service_contracts.dart`,
`lib/services/service_locator.dart`, `lib/services/mock_services.dart`.

## 1. Rule

Screens and pollers depend on **abstractions**, never on concretes:

- `MetricsPoller` — one `/metrics` poll for a server (typed `AgentMetrics`,
  throws `AgentProtocolException`; never returns null).
- `ProcStatsPoller` — one `/procstats` poll (typed `AppStats`).
- `CronRepository` / `AppRepository` / `AlertRepository` — SSH discovery.
- `KeyLoader` — key resolution; error strings only, key material never
  crosses the interface.
- `SecretStore` — mirrors `SecureStore`'s static API as an injectable.

## 2. Resolution

`Services.current` is the single entry point:

- Default: `LiveServices` — thin adapters over today's `AgentService`,
  `SshKeyLoader`, `SecureStore`. Behavior unchanged.
- `--dart-define=MCP_MOCKS=true`: `MockServices` — deterministic fakes,
  no network, no secrets, no plugins. Widget tests, previews,
  screenshots.
- Tests inject any container via `Services.overrideCurrent(...)`
  (reset with `null`).

Mock secrets are deliberately strict: the default mock secret store
**throws** on read — a test that needs secrets must inject an explicit
`MockSecretStore` instance, so no test ever passes with a hidden credential.

## 3. Migration map (for squad)

| current direct call | contract method | owner |
|---|---|---|
| `AgentService().fetch` | `Services.current.metrics.pollMetrics` | Elizabeth |
| `AgentService().fetchAppStats` | `Services.current.procStats.pollProcStats` | Elizabeth |
| `AgentService().fetchCrons` | `Services.current.crons.fetchCrons` | Lisa |
| `AgentService().fetchApps` | `Services.current.apps.fetchApps` | Lisa |
| `AgentService().fetchAlerts` | `Services.current.alerts.fetchAlerts` | Alya |
| `SshKeyLoader.load` | `Services.current.keys.load` | Alya |
| `SecureStore.*` statics | `Services.current.secrets.*` | Lina (done: adapter) |

Notes:

- `GithubService` / `GitlabService` stay concrete until the GitHub API +
  Actions timeline work lands; they get `GithubRepo`-style contracts then
  (tracked in `docs/quality-gates.md`, squad split).
- Legacy `AgentService.fetch`/`fetchAppStats` keep their null-on-error
  shape; only the new `pollMetrics`/`pollProcStats` paths throw typed
  errors. Call sites migrate one screen at a time.
