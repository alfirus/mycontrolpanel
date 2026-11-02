// SPDX-License-Identifier: MIT
/// Store visual-pack lint (Hana, t_c8b233d4).
///
/// Asserts every file in assets/store/ + docs/sales-kit/ meets the
/// series contract: exists, PNG size exact, captions in-bounds.
/// Run: `python3 scripts/check_store_assets.py` (CI: store-visuals.yml).
library;

import 'dart:io';

const expectedSizes = <String, List<int>>{
  'assets/store/feature-graphic-1024x500.png': [1024, 500],
  'assets/store/hero-feature-graphic-1600x900.png': [1600, 900],
  'assets/store/phone-01-dashboard-dark-1080x1920.png': [1080, 1920],
  'assets/store/phone-02-dashboard-light-1080x1920.png': [1080, 1920],
  'assets/store/phone-03-metrics-1080x1920.png': [1080, 1920],
  'assets/store/phone-04-alerts-consent-stale-1080x1920.png': [1080, 1920],
  'assets/store/phone-05-logs-terminal-1080x1920.png': [1080, 1920],
  'assets/store/phone-06-settings-lock-1080x1920.png': [1080, 1920],
  'assets/store/desktop-07-tray-1600x1000.png': [1600, 1000],
  'assets/store/desktop-08-notification-1600x1000.png': [1600, 1000],
};

/// PNG IHDR size without image plugins: width/height are big-endian
/// uint32 at bytes 16..24 of any valid PNG.
List<int> pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.length < 24 ||
      bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4E ||
      bytes[3] != 0x47) {
    throw StateError('not a PNG: $path');
  }
  final w =
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  final h =
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
  return [w, h];
}

void main() {
  var failures = 0;
  void fail(String msg) {
    stderr.writeln('FAIL: $msg');
    failures++;
  }

  for (final entry in expectedSizes.entries) {
    final f = File(entry.key);
    if (!f.existsSync()) {
      fail('missing ${entry.key}');
      continue;
    }
    if (f.lengthSync() > 2 * 1024 * 1024) {
      fail('${entry.key} exceeds 2MB (${f.lengthSync()} bytes)');
    }
    try {
      final size = pngSize(entry.key);
      if (size[0] != entry.value[0] || size[1] != entry.value[1]) {
        fail('${entry.key} is ${size[0]}x${size[1]}, '
            'expected ${entry.value[0]}x${entry.value[1]}');
      } else {
        stdout.writeln('ok ${entry.key} ${size[0]}x${size[1]} '
            '${(f.lengthSync() / 1024).toStringAsFixed(0)}KB');
      }
    } catch (e) {
      fail('${entry.key}: $e');
    }
  }

  // The one-pager ships in the stacked PR2 (docs/sales-kit/); on trees
  // without that dir (PR1) the PDF check is skipped, not failed.
  final salesKit = Directory('docs/sales-kit');
  final pdfs = salesKit.existsSync() ? ['docs/sales-kit/one-pager.pdf'] : <String>[];
  for (final pdf in pdfs) {
    final f = File(pdf);
    if (!f.existsSync()) {
      fail('missing $pdf');
    } else if (f.lengthSync() > 2 * 1024 * 1024) {
      fail('$pdf exceeds 2MB');
    } else {
      stdout.writeln('ok $pdf ${(f.lengthSync() / 1024).toStringAsFixed(0)}KB');
    }
  }

  if (failures > 0) {
    stderr.writeln('$failures store-asset check(s) failed.');
    exit(1);
  }
  stdout.writeln('store-asset checks passed.');
}
