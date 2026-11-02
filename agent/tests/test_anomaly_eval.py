# SPDX-License-Identifier: MIT
"""Offline eval harness for adaptive anomaly scoring (Farah — ML).

Synthetic traces, deterministic (modular pseudo-noise — no RNG, no I/O
except stdout). Acceptance gates for the tray-mode alert-quality work:

* precision > 0.85 at Medium sensitivity on the ops-day trace,
* < 1 false alert per idle device-day at Medium,
* scoring cost far below 1% CPU at a 60 s poll cadence.

Run: python -m pytest agent/tests/test_anomaly_eval.py -q
"""
import sys
import time
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from anomaly_scorer import AnomalyScorer


def noise(i, amp=1.0):
    """Deterministic pseudo-noise in [-amp, +amp]."""
    return amp * (((i * 37) % 11) / 11 - 0.5) * 2.0


def idle_day():
    """An idle device-day: flat 0.08 base, tiny jitter, zero incidents."""
    return [max(0.0, 0.08 + noise(i, 0.01) * 0.5) for i in range(1440)]


def ops_day():
    """A busy day: diurnal curve + 10 spikes + 1 sustained shift.

    Returns (samples, events) where events are (start_idx, end_idx)
    half-open windows counted as true-anomaly minutes.
    """
    samples = []
    for i in range(1440):
        hour = (i // 60) % 24
        # Day curve: 0.15 overnight, ramps to ~0.45 midday.
        if 9 <= hour < 17:
            base = 0.40 + 0.05 * ((hour - 9) / 8)
        elif 7 <= hour < 9 or 17 <= hour < 20:
            base = 0.25
        else:
            base = 0.15
        samples.append(max(0.0, base + noise(i, 0.02)))
    events = []
    # 10 short spikes (0.9 for 3 min) spread across the day.
    for k in range(10):
        at = 60 + k * 120
        for j in range(3):
            samples[at + j] = 0.90 + noise(at + j, 0.02)
        events.append((at, at + 3))
    # One sustained shift: 0.35 -> 0.75 for 2 h. An adaptive detector
    # should fire on the onset, then accept the new normal — so only the
    # first 15 min count as true-anomaly minutes.
    shift_at = 1080
    for j in range(120):
        samples[shift_at + j] = 0.75 + noise(shift_at + j, 0.02)
    events.append((shift_at, shift_at + 15))
    return samples, events


def run_trace(samples, hours=None, sensitivity="medium"):
    scorer = AnomalyScorer()
    firings = []
    for i, v in enumerate(samples):
        h = hours[i] if hours is not None else (i // 60) % 24
        r = scorer.update(v, hour=h, sensitivity=sensitivity)
        if r["firing"]:
            firings.append(i)
    return firings


def score_events(firings, events, grace=2):
    """Event-level + sample-level stats. A firing within [s, e+grace)
    marks the event detected; firings outside every window are false."""
    fired = set(firings)
    detected = 0
    covered = set()
    for (s, e) in events:
        window = set(range(s, e + grace))
        covered |= window
        if fired & window:
            detected += 1
    tp = len(fired & covered)
    fp = len(fired - covered)
    precision = tp / (tp + fp) if (tp + fp) else 1.0
    recall_events = detected / len(events) if events else 1.0
    return {
        "events": len(events),
        "detected": detected,
        "recall_events": recall_events,
        "tp_samples": tp,
        "fp_samples": fp,
        "precision": precision,
    }


def test_idle_day_zero_false_alerts_medium():
    firings = run_trace(idle_day(), sensitivity="medium")
    assert len(firings) < 1, "idle day fired %d times: %s" % (len(firings), firings[:10])


def test_ops_day_precision_above_gate_medium():
    samples, events = ops_day()
    firings = run_trace(samples, sensitivity="medium")
    stats = score_events(firings, events)
    print("\nops-day@medium: %s" % stats)
    assert stats["precision"] > 0.85, stats
    assert stats["recall_events"] >= 0.8, stats


def test_sensitivity_monotonic_firings():
    samples, events = ops_day()
    counts = {}
    for sens in ("low", "medium", "high"):
        counts[sens] = len(run_trace(samples, sensitivity=sens))
    print("\nfirings low/med/high: %s" % counts)
    assert counts["high"] >= counts["medium"] >= counts["low"]
    assert counts["low"] <= counts["medium"]


def test_scoring_cost_well_below_one_percent_cpu():
    scorer = AnomalyScorer()
    for i in range(2000):  # warm the baseline past warmup
        scorer.update(0.30 + noise(i, 0.02), hour=(i // 60) % 24)
    n = 20000
    t0 = time.perf_counter()
    for i in range(n):
        scorer.update(0.30 + noise(i + 99999, 0.02), hour=(i // 60) % 24)
    dt = time.perf_counter() - t0
    mean_ms = dt / n * 1000.0
    print("\nscoring cost: %.4f ms/sample over %d samples" % (mean_ms, n))
    # 1% of a 60 s poll cadence = 600 ms. Per-sample cost must be
    # orders of magnitude below that; 5 ms is a very generous bound.
    assert mean_ms < 5.0, "too slow: %.4f ms/sample" % mean_ms
    # A full idle device-day (1440 samples) must score in well under 5 s.
    day = idle_day()
    t0 = time.perf_counter()
    run_trace(day)
    assert time.perf_counter() - t0 < 5.0
