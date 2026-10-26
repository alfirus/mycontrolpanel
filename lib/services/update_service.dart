import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// In-app updates from GitHub Releases (desktop: Windows / Linux / macOS).
///
/// Release asset naming convention (user uploads manually):
///   mycontrolpanel-macos-<version>.zip      (contains MyControlPanel.app)
///   mycontrolpanel-windows-<version>.zip    (portable build output)
///   mycontrolpanel-linux-<version>.tar.gz  (bundle dir, or .zip)
///   SHA256SUMS.txt  (optional `sha  filename` lines — verified when present)
class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  const ReleaseAsset({required this.name, required this.url, required this.size});
}

class ReleaseInfo {
  final String tag;
  final String name;
  final String notes;
  final List<ReleaseAsset> assets;
  const ReleaseInfo({required this.tag, required this.name, required this.notes, required this.assets});

  String get version => tag.startsWith('v') ? tag.substring(1) : tag;
}

class UpdateService {
  static const repo = 'alfirus/mycontrolpanel';
  static const _api = 'https://api.github.com/repos/$repo/releases/latest';

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<ReleaseInfo> fetchLatest() async {
    final r = await http.get(Uri.parse(_api), headers: {'Accept': 'application/vnd.github+json'});
    if (r.statusCode != 200) throw Exception('GitHub releases: HTTP ${r.statusCode}');
    final j = jsonDecode(r.body) as Map;
    final assets = ((j['assets'] as List?) ?? []).map((a) {
      final m = a as Map;
      return ReleaseAsset(
        name: ((m['name'] ?? '')).toString(),
        url: ((m['browser_download_url'] ?? '')).toString(),
        size: ((m['size'] as num?) ?? 0).toInt(),
      );
    }).where((a) => a.name.isNotEmpty && a.url.isNotEmpty).toList();
    return ReleaseInfo(
      tag: ((j['tag_name'] ?? '')).toString(),
      name: ((j['name'] ?? '')).toString(),
      notes: ((j['body'] ?? '')).toString(),
      assets: assets,
    );
  }

  /// -1 current<latest, 0 equal, 1 current>latest. Non-numeric tolerant.
  static int compareVersions(String current, String latest) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+\-]'))
        .map((p) => int.tryParse(RegExp(r'\d+').firstMatch(p)?.group(0) ?? '0') ?? 0)
        .toList();
    final a = parts(current), b = parts(latest);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  /// Pick this platform's asset from the release (null = not published).
  static ReleaseAsset? pickAsset(ReleaseInfo rel) {
    final names = rel.assets.map((a) => a.name.toLowerCase()).toList();
    bool isMac(String n) => n.contains('macos') || n.contains('osx') || n.contains('darwin');
    bool isWin(String n) => n.contains('windows') || n.contains('win64') || (n.contains('win') && !n.contains('darwin'));
    bool isLin(String n) => n.contains('linux');
    if (Platform.isMacOS) {
      for (var i = 0; i < names.length; i++) {
        if (isMac(names[i]) && (names[i].endsWith('.zip'))) return rel.assets[i];
      }
    } else if (Platform.isWindows) {
      for (var i = 0; i < names.length; i++) {
        if (isWin(names[i]) && names[i].endsWith('.zip')) return rel.assets[i];
      }
    } else if (Platform.isLinux) {
      for (var i = 0; i < names.length; i++) {
        if (isLin(names[i]) && (names[i].endsWith('.tar.gz') || names[i].endsWith('.tgz') || names[i].endsWith('.zip'))) return rel.assets[i];
      }
    }
    return null;
  }

  static ReleaseAsset? checksumFile(ReleaseInfo rel) {
    for (final a in rel.assets) {
      final n = a.name.toLowerCase();
      if (n == 'sha256sums.txt' || n == 'checksums.txt' || n == 'sha256sums' || n.endsWith('.sha256')) return a;
    }
    return null;
  }

  /// Stream-download with progress (0..1, -1 when size unknown).
  Future<File> downloadAsset(ReleaseAsset asset, Directory dir, void Function(double) onProgress) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(asset.url));
      req.headers.set('Accept', 'application/octet-stream');
      req.headers.set('User-Agent', 'MyControlPanel-Updater');
      final resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 302) {
        throw Exception('Download HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      final file = File('${dir.path}/${asset.name}');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : -1);
      }
      await sink.close();
      onProgress(1);
      return file;
    } finally {
      client.close();
    }
  }

  /// Verify SHA-256 against the release's checksum file. Returns null when
  /// no checksum file was published (caller proceeds with a warning).
  Future<bool?> verifyChecksum(ReleaseInfo rel, File file) async {
    final sum = checksumFile(rel);
    if (sum == null) return null;
    final r = await http.get(Uri.parse(sum.url));
    if (r.statusCode != 200) return null;
    final base = file.uri.pathSegments.last.toLowerCase();
    for (final line in const LineSplitter().convert(r.body)) {
      final m = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (m != null && m.group(2)!.trim().toLowerCase().endsWith(base)) {
        final digest = await sha256.bind(file.openRead()).first;
        return digest.toString().toLowerCase() == m.group(1)!.toLowerCase();
      }
    }
    return null; // asset not listed — treat as unverified, not failed
  }

  /// Extract .zip / .tar.gz into [dest]. Returns extracted top-level entries.
  Future<List<String>> extractArchive(File file, Directory dest) async {
    final bytes = await file.readAsBytes();
    final out = <String>[];
    if (file.path.endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        final path = '${dest.path}/${f.name}';
        if (f.isFile) {
          final of = File(path);
          await of.parent.create(recursive: true);
          await of.writeAsBytes(f.content as List<int>);
          out.add(f.name);
        } else {
          await Directory(path).create(recursive: true);
        }
      }
    } else if (file.path.endsWith('.tar.gz') || file.path.endsWith('.tgz')) {
      final tarBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);
      for (final f in archive) {
        final path = '${dest.path}/${f.name}';
        if (f.isFile) {
          final of = File(path);
          await of.parent.create(recursive: true);
          await of.writeAsBytes(f.content as List<int>);
          out.add(f.name);
        } else {
          await Directory(path).create(recursive: true);
        }
      }
      // restore unix exec bits for binaries
      try {
        await Process.run('chmod', ['-R', 'u+x', dest.path]);
      } catch (_) {}
    } else {
      throw Exception('Unsupported archive: ${file.path}');
    }
    return out;
  }
}
