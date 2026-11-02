# SPDX-License-Identifier: MIT
"""Unit tests for the on-device adaptive anomaly scorer (Farah — ML).

Deterministic, stdlib-only, no I/O. Run: python -m pytest agent/tests -q
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from anomaly_scorer import AnomalyScorer, reset_scorers, score_sample


def steady(n=30, base=0.30, amp=0.02):
    return [base + amp * ((i * 37 % 11) / 11 - 0.5) for i in range(n)]


def test_warmup_returns_zero_score_not_firing():
    reset_scorers()
    s = AnomalyScorer(warmup=10)
    r = None
    for v in steady(n=10):
        r = s.update(v, hour=14)
    assert r is not None
    assert r["score"] == 0.0
    assert r["firing"] is False
    assert "learning baseline" in r["reason"]


def test_spike_fires_at_medium_with_reason():
    s = AnomalyScorer()
    for v in steady(n=40):
        s.update(v, hour=14)
    r = s.update(0.95, hour=14)
    assert r["firing"] is True
    assert r["score"] >= 50.0
    assert "0.95" in r["reason"]
    assert "score" in r["reason"]


def test_steady_sample_does_not_fire():
    s = AnomalyScorer()
    for v in steady(n=40):
        s.update(v, hour=14)
    r = s.update(0.31, hour=14)
    assert r["firing"] is False
    assert r["score"] < 50.0
    assert r["reason"].startswith("normal:")


def _scorer_at(ewma=0.30, std=0.05):
    """A scorer already past warmup with a known baseline (hour=None
    isolates the global EWMA path from the time-of-day buckets)."""
    s = AnomalyScorer()
    s.n = 99
    s.ewma = ewma
    s.var = std * std
    return s


def test_sensitivity_ordering_low_medium_high():
    # z = (probe - ewma) / std with ewma=0.30, std=0.05.
    # Probe 0.41 -> z=2.2, score=34: high only.
    assert _scorer_at().update(0.41, sensitivity="high")["firing"] is True
    assert _scorer_at().update(0.41, sensitivity="medium")["firing"] is False
    assert _scorer_at().update(0.41, sensitivity="low")["firing"] is False
    # Probe 0.52 -> z=4.4, score=78: all fire (nesting: low => med => high).
    assert _scorer_at().update(0.52, sensitivity="low")["firing"] is True
    assert _scorer_at().update(0.52, sensitivity="medium")["firing"] is True
    assert _scorer_at().update(0.52, sensitivity="high")["firing"] is True


def test_invalid_sensitivity_falls_back_to_medium():
    s = AnomalyScorer()
    for v in steady(n=40):
        s.update(v, hour=3)
    r = s.update(0.95, hour=3, sensitivity="ultra")
    assert r["firing"] is True


def test_score_bounds_and_nan_safety():
    s = AnomalyScorer()
    for v in steady(n=40):
        s.update(v, hour=3)
    for bad in (float("nan"), -5.0, 99.0, None):
        r = s.update(bad, hour=3)
        assert 0.0 <= r["score"] <= 100.0
        assert isinstance(r["firing"], bool)


def test_score_sample_registry_per_metric():
    reset_scorers()
    for v in steady(n=40):
        score_sample("cpu", v, hour=10)
        score_sample("ram", v, hour=10)
    r = score_sample("cpu", 0.95, hour=10)
    assert r["firing"] is True
    # ram baseline untouched by the cpu spike
    r2 = score_sample("ram", 0.30, hour=10)
    assert r2["firing"] is False


def test_flat_baseline_jump_fires():
    # A disk ratio constant for days has zero variance; the _MIN_STD
    # floor must keep it sensitive to jumps (not divide by zero).
    s = AnomalyScorer()
    for _ in range(100):
        r = s.update(0.41, hour=6)
    assert r["firing"] is False
    r = s.update(0.90, hour=6)
    assert r["firing"] is True
    assert r["score"] >= 50.0


def test_time_of_day_bucket_in_reason():
    s = AnomalyScorer()
    for v in steady(n=40, base=0.20):
        s.update(v, hour=9)
    r = s.update(0.90, hour=9)
    assert r["firing"] is True
    assert "09:00" in r["reason"] or "usual" in r["reason"]
