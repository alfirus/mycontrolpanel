# Regression Checklist — Alerts + Cronjobs + Apps

Owner: Balqis (QA Engineer) · Cadence: run on every PR touching
`lib/services/agent_service.dart`, `lib/models/cron_entry.dart`,
`lib/services/alert_watch.dart`, or the Alerts/Cronjobs/Apps segments.
Code under test: `fetchAlerts` (disk warn ≥80% / critical ≥90%, failed units,
brute-force 5/20, load vs nproc, kernel errors, reboot <1h), `fetchCrons`
(crontab + `/etc/crontab` + `/etc/cron.d/*`), `fetchApps` (systemd + docker +
listening ports), `AlertWatch` (bell badge + snack diff).

Executable coverage lives in `test/qa_regression_test.dart` (pure-logic:
cron parse edges, alert badge/fresh-title diff). SSH-live rows below need a
lab host (Ubuntu 24.04 + Debian 12) and are manual until a lab harness exists.

## A. Alerts regression

| ID | Case | Steps / oracle | Expected |
|----|------|----------------|----------|
| AL-01 | Disk warn threshold 80% | Fixture `df` line: `/ 82%` | 1 warning alert, `disk • <host>` |
| AL-02 | Disk critical threshold 90% | Fixture `df` line: `/ 93%` | 1 critical alert |
| AL-03 | Disk boundary 79% | Fixture `df` line: `/ 79%` | No alert |
| AL-04 | Boundary 80/90 exact | `80%` → warning; `90%` → critical | Exact-boundary mapping |
| AL-05 | Failed units | 2 failed `.service` units | 2 critical `Service failed: <name>` alerts |
| AL-06 | Failed units empty | No failed units | No systemd alerts, no crash |
| AL-07 | Brute-force warn (5–19) | 7 `Failed password` in 24h | 1 warning `7 failed SSH logins in 24h` |
| AL-08 | Brute-force critical (≥20) | 25 failures | 1 critical `(possible brute force)` |
| AL-09 | Brute-force quiet (0–4) | 3 failures | No auth alert |
| AL-10 | Load warn vs critical | load 6 on 4 CPUs → warning; load 9 on 4 CPUs → critical; load 2 → none | `load > cpus` warn, `> 2x` critical |
| AL-11 | Kernel OOM | dmesg contains OOM | Critical `Out-of-memory killer fired` |
| AL-12 | Kernel non-OOM warnings | 3 generic warn lines | 1 warning `3 kernel warnings in last 24h` |
| AL-13 | Recent reboot | uptime 1800s | Warning `rebooted 30m ago` |
| AL-14 | No reboot | uptime 90000s | No uptime alert |
| AL-15 | Watcher badge diff | 1 new firing alert since last seen | Bell +1, snack shows title (max 3) |
| AL-16 | Resolved alerts excluded | Alert status `resolved` | Not in badge set (`AlertWatch.currentKeys`) |
| AL-17 | Failed CI runs badge | 1 failed deploy run | Badged + `CI failed: <app> <ver>` snack |
| AL-18 | Empty lab (no signals) | Clean host | Zero alerts, segments render empty-state, no exception |

## B. Cronjobs regression (crontab discovery edges)

| ID | Case | Expected |
|----|------|----------|
| CR-01 | User crontab 5-field line | Parsed, source `crontab`, no user field |
| CR-02 | `/etc/crontab` user field | User skipped via offset, command correct |
| CR-03 | `/etc/cron.d/*` multi-file | `###FILE:` split attributes each entry to its file |
| CR-04 | `@reboot` / `@daily` | Schedule `@reboot`, command parsed |
| CR-05 | `@daily` with user field | User stripped, command kept |
| CR-06 | Comments + blank lines | Skipped |
| CR-07 | Env assignments (`PATH=`, `MAILTO=`) | Skipped, not parsed as jobs |
| CR-08 | Malformed line (too few fields) | Skipped, no throw |
| CR-09 | No crontab on host (`NO_CRONTAB`) | Empty list, no error |
| CR-10 | `rawLine` preserved | In-place edit has exact original line |
| CR-11 | Step values (`*/5 * * * *`) | Accepted by field regex |
| CR-12 | Cron log viewer per job | `fetchCronLogs` returns output, empty renders empty-state |

## C. Apps regression

| ID | Case | Expected |
|----|------|----------|
| AP-01 | Running systemd service listed | `source: systemd`, `detail: systemd • running` |
| AP-02 | Infra noise filtered | dbus/systemd/sshd/cron/rsyslog units hidden |
| AP-03 | Template units (`foo@bar`) | Deduped by base name, shown once |
| AP-04 | Docker containers | `source: docker`, `detail: <image> • <status>` |
| AP-05 | No docker (`NO_DOCKER`) | Skipped silently, systemd + ports still shown |
| AP-06 | Listening ports | `source: port`, `listening :<port>`, proc name when visible |
| AP-07 | Ports 22 + 9108 excluded | SSH and own agent never listed as apps |
| AP-08 | `/procstats` top processes | pid/name/cpu/mem_mb shown in Apps + Server Details |
| AP-09 | Empty host (nothing running) | Empty-state, no crash |

## D. Foreground-watcher notes (known limits, by design)

Background polling while the app is closed is out of scope (needs
workmanager + local notifications). The checklist above covers the
foreground watcher only: badge + snack on new firing alerts / failed CI
runs diffed against the last-seen set in `SharedPreferences`.
