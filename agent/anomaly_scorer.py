# SPDX-License-Identifier: MIT
"""On-device adaptive anomaly scoring (Farah — ML).

Stdlib-only EWMA + rolling variance with time-of-day buckets. One
``AnomalyScorer`` per metric; the agent keeps a small dict of them in
process memory (no disk, no network — fully on-device).

Score is a sensitivity-independent 0..100 deviation magnitude; whether it
*fires* depends on the caller's sensitivity (Low/Med/High).

Canonical source: this file. The exact text between the
``BEGIN/END ANOMALY SCORER`` markers is vendored verbatim into the
``agentScript`` embedded Python in ``lib/services/agent_service.dart``
(deployed to /opt/mcp-agent/agent.py); parity is enforced by
``test/agent_embedded_parity_test.dart``. Edit here, then re-vendor.
"""

# BEGIN ANOMALY SCORER (vendored into AgentService.agentScript verbatim)
SENSITIVITIES = ("low", "medium", "high")

# Global z needed to fire per sensitivity.
_SENS_Z = {"low": 4.0, "medium": 3.0, "high": 2.0}
# Minimum 0..100 score needed to fire per sensitivity.
_SENS_FLOOR = {"low": 70.0, "medium": 50.0, "high": 30.0}
# Floor on the deviation scale (2% of the 0..1 range): exactly-flat
# baselines (e.g. a disk ratio unchanged for days) still detect jumps
# instead of dividing by a zero variance.
_MIN_STD = 0.02


def _clamp01(x):
    try:
        v = float(x)
    except (TypeError, ValueError):
        return 0.0
    if v != v:  # NaN guard
        return 0.0
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v


class AnomalyScorer(object):
    """EWMA + rolling variance with 24 hourly buckets (stdlib only)."""

    def __init__(self, alpha=0.25, warmup=15):
        self.alpha = alpha
        self.warmup = warmup
        self.n = 0
        self.ewma = 0.0
        self.var = 0.0
        self.buckets = [{"n": 0, "mean": 0.0, "m2": 0.0} for _ in range(24)]

    def _bucket_stats(self, hour):
        """(mean, var, hour_of_day) for the hourly bucket, or None when the
        hour is missing/invalid or the bucket has fewer than 2 samples."""
        if hour is None:
            return None
        try:
            h = int(hour) % 24
        except (TypeError, ValueError):
            return None
        b = self.buckets[h]
        if b["n"] < 2:
            return None
        var = b["m2"] / (b["n"] - 1)
        return (b["mean"], var if var > 0.0 else 0.0, h)

    def _observe(self, value, hour):
        self.n += 1
        if self.n == 1:
            self.ewma = value
            self.var = 0.0
        else:
            d = value - self.ewma
            self.ewma += self.alpha * d
            # Rolling variance of the residual (population form, cheap).
            self.var = (1.0 - self.alpha) * (self.var + self.alpha * d * d)
        if hour is None:
            return
        try:
            h = int(hour) % 24
        except (TypeError, ValueError):
            return
        b = self.buckets[h]
        b["n"] += 1
        d = value - b["mean"]
        b["mean"] += d / b["n"]
        b["m2"] += d * (value - b["mean"])

    def update(self, value, hour=None, sensitivity="medium"):
        value = _clamp01(value)
        if sensitivity not in _SENS_Z:
            sensitivity = "medium"
        # Score against the PRIOR baseline, then observe the sample, so a
        # spike never contaminates its own verdict. The _MIN_STD floor
        # keeps exactly-flat baselines (constant disk ratio) sensitive.
        std = max(self.var ** 0.5, _MIN_STD)

        if self.n < self.warmup:
            self._observe(value, hour)
            return {
                "score": 0.0,
                "reason": "learning baseline (%d/%d samples)" % (self.n, self.warmup),
                "firing": False,
                "z": 0.0,
                "baseline": round(self.ewma, 3),
            }

        z_global = abs(value - self.ewma) / std
        z = z_global
        basis = "usual %.2f" % self.ewma
        bucket = self._bucket_stats(hour)
        if bucket is not None:
            bmean, bvar, bhour = bucket
            bstd = max(bvar ** 0.5, _MIN_STD)
            z_bucket = abs(value - bmean) / bstd
            if z_bucket > z:
                z = z_bucket
                basis = "usual %.2f at %02d:00" % (bmean, bhour)
        self._observe(value, hour)
        # Sensitivity-independent magnitude: z=0.5 -> 0, z=5.5 -> 100.
        score = max(0.0, min(100.0, 100.0 * (z - 0.5) / 5.0))
        firing = z >= _SENS_Z[sensitivity] and score >= _SENS_FLOOR[sensitivity]
        if firing:
            reason = "%.2f vs %s (score %.0f)" % (value, basis, score)
        else:
            reason = "normal: %.2f vs %s" % (value, basis)
        return {
            "score": round(score, 1),
            "reason": reason,
            "firing": firing,
            "z": round(z, 2),
            "baseline": round(self.ewma, 3),
        }


# Module-level per-metric scorers for the agent process.
_SCORERS = {}


def score_sample(metric, value, hour=None, sensitivity="medium"):
    """Score one sample against the named metric's running baseline."""
    name = str(metric or "cpu")[:32]
    scorer = _SCORERS.get(name)
    if scorer is None:
        scorer = AnomalyScorer()
        _SCORERS[name] = scorer
    return scorer.update(value, hour=hour, sensitivity=sensitivity)


def reset_scorers():
    """Test hook: drop all running baselines."""
    _SCORERS.clear()
# END ANOMALY SCORER (vendored into AgentService.agentScript verbatim)
