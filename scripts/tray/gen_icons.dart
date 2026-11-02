// SPDX-License-Identifier: MIT
// Tray icon generator (Elizabeth, TM-4). Run once with:
//   dart scripts/tray/gen_icons.dart
// Emits 4 deterministic 32x32 RGBA PNGs into assets/tray/ (ok / firing /
// stale / quiet). Kira `docs/design/06-alert-tray-ux.md` §7.1: every state
// pairs its dot color with a distinct white glyph (check / bang / clock /
// crescent) + tooltip + semantic label — never color-only, so Linux
// monochrome trays stay readable. stdlib only (`dart:io`, `dart:convert`,
// `dart:typed_data`) — no image package needed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const size = 32;
const radius = 14;
const cx = 16;
const cy = 16;

int argb(int r, int g, int b, [int a = 255]) =>
    (a << 24) | (r << 16) | (g << 8) | b;

const white = 0xFFFFFFFF;

final Map<String, int> dotColors = {
  'ok': argb(0x22, 0xC5, 0x5E),
  'firing': argb(0xEF, 0x44, 0x44),
  'stale': argb(0xEA, 0xB3, 0x08),
  'quiet': argb(0x9C, 0xA3, 0xAF),
};

void main() {
  final out =
      Directory('assets/tray');
  out.createSync(recursive: true);
  for (final entry in dotColors.entries) {
    final px = Uint32List(size * size);
    final dot = entry.value;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = x - cx + 0.5;
        final dy = y - cy + 0.5;
        final d = dx * dx + dy * dy;
        var color = 0x00000000;
        if (d <= radius * radius) color = dot;
        // Quiet crescent: carve an offset disk out of the dot.
        if (entry.key == 'quiet') {
          final qx = x - (cx + 6);
          final qy = y - (cy - 4);
          if (qx * qx + qy * qy <= 11 * 11) color = 0x00000000;
        }
        px[y * size + x] = color;
      }
    }
    switch (entry.key) {
      case 'ok':
        // Check: two thick white strokes.
        line(px, 9, 17, 14, 22, 3);
        line(px, 14, 22, 23, 11, 3);
      case 'firing':
        // Bang: vertical bar + dot.
        line(px, 16, 9, 16, 19, 4);
        disk(px, 16, 23, 2);
      case 'stale':
        // Clock: white ring + two hands.
        ring(px, 16, 16, 8, 2);
        line(px, 16, 16, 16, 10, 2);
        line(px, 16, 16, 21, 18, 2);
      case 'quiet':
        break; // crescent is carved above; no glyph overlay.
    }
    final png = encodePng(px);
    File('assets/tray/tray-${entry.key}.png')
        .writeAsBytesSync(png);
    print('wrote assets/tray/tray-${entry.key}.png (${png.length} bytes)');
  }
}

void setPx(Uint32List px, int x, int y, int color) {
  if (x < 0 || y < 0 || x >= size || y >= size) return;
  px[y * size + x] = color;
}

void disk(Uint32List px, int x0, int y0, int r) {
  for (var y = y0 - r; y <= y0 + r; y++) {
    for (var x = x0 - r; x <= x0 + r; x++) {
      final dx = x - x0;
      final dy = y - y0;
      if (dx * dx + dy * dy <= r * r) setPx(px, x, y, white);
    }
  }
}

void ring(Uint32List px, int x0, int y0, int r, int w) {
  for (var y = y0 - r - w; y <= y0 + r + w; y++) {
    for (var x = x0 - r - w; x <= x0 + r + w; x++) {
      final d2 = (x - x0) * (x - x0) + (y - y0) * (y - y0);
      final inner = (r - w) * (r - w);
      final outer = (r + w) * (r + w);
      if (d2 >= inner && d2 <= outer) setPx(px, x, y, white);
    }
  }
}

void line(Uint32List px, int x0, int y0, int x1, int y1, int w) {
  final steps = ((x1 - x0).abs() > (y1 - y0).abs()
          ? (x1 - x0).abs()
          : (y1 - y0).abs()) *
      2;
  for (var i = 0; i <= steps; i++) {
    final x = (x0 + (x1 - x0) * i / steps).round();
    final y = (y0 + (y1 - y0) * i / steps).round();
    disk(px, x, y, (w / 2).round());
  }
}

// --- Minimal PNG encoder (RGBA8, filter 0) ---

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final t = type.codeUnits;
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  out.add(t);
  out.add(data);
  final crc = ByteData(4)..setUint32(0, _crc([...t, ...data]));
  out.add(crc.buffer.asUint8List());
}

Uint8List encodePng(Uint32List px) {
  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0);
    for (var x = 0; x < size; x++) {
      final p = px[y * size + x];
      raw.add([(p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF, (p >> 24) & 0xFF]);
    }
  }
  final compressed = ZLibEncoder().convert(raw.toBytes());
  _chunk(out, 'IDAT', compressed);
  _chunk(out, 'IEND', []);
  return out.toBytes();
}
