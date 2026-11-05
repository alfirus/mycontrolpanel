// SPDX-License-Identifier: MIT
/// Series downsampling for chart rendering.
///
/// Every poll tick rebuilds the `LineChart`s in the control center, and a
/// full-series rebuild costs O(n) path work per chart per tick — on low-end
/// Android that janks once histories grow (merged multi-host latency series,
/// long-lived sessions). These helpers collapse a series to a render budget
/// _before_ `FlSpot`s are built, so chart cost stays flat no matter how long
/// the underlying history gets.
///
/// Pixel-parity contract: series at or under the budget are returned
/// **unchanged** (same values, same order), so today's small histories render
/// pixel-identically with or without this layer. Only over-budget (aged,
/// long) series are resampled.
///
/// Pure Dart on purpose — no Flutter / fl_chart import — so the math stays
/// fast under unit tests and can be reused by any future chart.
library;

/// Render budget for the per-card CPU sparklines.
///
/// In-memory per-host histories are capped at 40 points (see the poll loop),
/// so today's sparklines always pass through untouched; the cap only engages
/// if histories grow (long sessions, raised caps, merged series).
const kMaxSparklinePoints = 48;

/// Render budget for the larger metrics latency chart.
///
/// The live latency series merges every host's history, so it is the first
/// chart that can outgrow its history cap on multi-server setups.
const kMaxLatencyChartPoints = 90;

/// Downsample [values] to at most [maxPoints] points, preserving the visual
/// shape of the series (Largest-Triangle-Three-Buckets).
///
/// - `values.length <= maxPoints` → returned unchanged (pixel parity).
/// - Otherwise LTTB picks one representative per bucket, always keeping the
///   first and last points so the trend endpoints never drift.
/// - Requires `maxPoints >= 2`.
List<double> downsampleSeries(List<double> values, {int maxPoints = 90}) {
  assert(maxPoints >= 2, 'downsampleSeries needs maxPoints >= 2');
  if (values.length <= maxPoints) return List.of(values);
  if (maxPoints == 2) return [values.first, values.last];

  // LTTB with implicit x = index. Buckets cover [1, n-1); bucket 0's
  // representative anchors on values.first, the tail on values.last.
  final bucketSize = (values.length - 2) / (maxPoints - 2);
  final sampled = <double>[values.first];
  var a = 0; // index of the last selected point
  for (var i = 0; i < maxPoints - 2; i++) {
    // Average of the *next* bucket — the triangle apex reference.
    final avgStart = ((i + 1) * bucketSize).floor() + 1;
    var avgEnd = ((i + 2) * bucketSize).floor() + 1;
    if (avgEnd > values.length) avgEnd = values.length;
    var avgX = 0.0;
    var avgY = 0.0;
    for (var j = avgStart; j < avgEnd; j++) {
      avgX += j;
      avgY += values[j];
    }
    final avgLen = avgEnd - avgStart;
    avgX /= avgLen;
    avgY /= avgLen;

    // Current bucket: pick the point forming the largest triangle with
    // the last-selected point and the next-bucket average.
    final rangeStart = (i * bucketSize).floor() + 1;
    var rangeEnd = ((i + 1) * bucketSize).floor() + 1;
    if (rangeEnd > values.length - 1) rangeEnd = values.length - 1;
    final ax = a.toDouble();
    final ay = values[a];
    var maxArea = -1.0;
    var nextA = rangeStart;
    for (var j = rangeStart; j < rangeEnd; j++) {
      final area =
          ((ax - avgX) * (values[j] - ay) - (ax - j) * (avgY - ay)).abs();
      if (area > maxArea) {
        maxArea = area;
        nextA = j;
      }
    }
    sampled.add(values[nextA]);
    a = nextA;
  }
  sampled.add(values.last);
  return sampled;
}
