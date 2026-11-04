// Arka plan fotoğrafları dosyalarda (bilgisayar ve telefon): eski Mel Capital'deki gibi internet varken bir
// kez ekranın çözünürlüğünde indirilir, saklanır ve sonra internetsiz kullanılır. Her fotoğrafın ortalama
// parlaklığı da hesaplanır (akşam teması için).
//
// Windows'ta eski uygulamanın indirdiği fotoğraflar (%LOCALAPPDATA%\Mel Capital\Fotograflar) yalnızca
// okunur: aynı fotoğraflar yeniden indirilmez, o klasöre hiçbir şey yazılmaz.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../core/model.dart';
import '../core/photos.dart';
import 'photos.dart';

class IoPhotoStore implements PhotoStore {
  IoPhotoStore({this.dirOverride, this.legacyDirOverride, this.base = 'https://images.unsplash.com', this.lumOf = jpegLuminance});

  /// Testlerde: fotoğraf klasörü, eski uygulamanın durum klasörü, sunucu adresi ve parlaklık ölçümü.
  final String? dirOverride;
  final String? legacyDirOverride;
  final String base;
  final Future<double> Function(Uint8List bytes) lumOf;

  String? _dir;
  String? _legacyDir;
  Json _meta = {};
  Json _legacyMeta = {};
  final Map<String, PhotoSrc> _avail = {};
  PhotoSize? _size;
  bool _busy = false;
  bool _again = false;
  bool _closed = false;
  int _missing = 0;

  @override
  void Function()? onChange;

  @override
  Map<String, PhotoSrc> get available => Map.unmodifiable(_avail);

  @override
  int get missing => _missing;

  @override
  bool get busy => _busy;

  String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  Future<String> _ownDir() async {
    if (_dir != null) return _dir!;
    if (dirOverride != null) return _dir = dirOverride!;
    // Telefonda kalıcı uygulama klasörü (önbellek temizlenince silinmesin); bilgisayarda yerel önbellek.
    final root = Platform.isAndroid || Platform.isIOS ? await getApplicationSupportDirectory() : await getApplicationCacheDirectory();
    return _dir = _join(root.path, 'Fotograflar');
  }

  /// Eski uygulamanın durum klasörü (yalnızca Windows).
  String? _legacyRoot() {
    if (legacyDirOverride != null) return legacyDirOverride;
    if (!Platform.isWindows) return null;
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    return _join(local, 'Mel Capital');
  }

  Future<Json> _readMeta(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString());
      return j is Map ? j.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }

  static int _w(Object? m) => m is Map && m['w'] is num ? (m['w'] as num).toInt() : 0;
  static int _h(Object? m) => m is Map && m['h'] is num ? (m['h'] as num).toInt() : 0;
  static double _lum(Object? m) => m is Map && m['lum'] is num ? (m['lum'] as num).toDouble() : -1;

  Future<bool> _usable(String path) async {
    try {
      final f = File(path);
      return await f.exists() && await f.length() > 20000;
    } catch (_) {
      return false;
    }
  }

  /// Bu boyutta yeniden indirilmesi gerekmiyor mu?
  bool _fits(Object? m, PhotoSize size) => size.phone ? _w(m) == size.width && _h(m) == size.height : _w(m) >= size.width;

  @override
  Future<void> start(PhotoSize size) async {
    _size = size;
    final dir = await _ownDir();
    _meta = await _readMeta(_join(dir, 'fotolar.json'));
    final legacy = _legacyRoot();
    if (legacy != null) {
      _legacyDir = _join(legacy, 'Fotograflar');
      _legacyMeta = await _readMeta(_join(_legacyDir!, 'fotolar.json'));
    }
    await _scan();
    onChange?.call();
    unawaited(_download());
  }

  /// Var olan fotoğrafları bulur: önce bu uygulamanınkiler, yoksa eski uygulamanınkiler.
  Future<void> _scan() async {
    final size = _size!;
    final dir = await _ownDir();
    _avail.clear();
    var missing = 0;
    for (final p in kPhotos) {
      final own = _join(dir, '${p.id}.jpg');
      final ownOk = await _usable(own);
      String? legacyPath;
      if (!ownOk && _legacyDir != null && !size.phone) {
        final lp = _join(_legacyDir!, '${p.id}.jpg');
        if (await _usable(lp)) legacyPath = lp;
      }
      if (ownOk) {
        _avail[p.id] = PhotoSrc(path: own, lum: _lum(_meta[p.id]));
      } else if (legacyPath != null) {
        _avail[p.id] = PhotoSrc(path: legacyPath, lum: _lum(_legacyMeta[p.id]));
      }
      final fits = ownOk ? _fits(_meta[p.id], size) : (legacyPath != null && _fits(_legacyMeta[p.id], size));
      if (!fits) missing++;
    }
    _missing = missing;
  }

  /// Eksik ya da istenenden küçük fotoğrafları sırayla indirir. Aynı anda tek indirme çalışır; internet
  /// yoksa (üç deneme başarısız) bırakır, bir sonraki açılışta yeniden dener.
  Future<void> _download() async {
    if (_busy) {
      _again = true;
      return;
    }
    final size = _size;
    if (size == null || _closed) return;
    _busy = true;
    final dir = await _ownDir();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'MelCapital';
    try {
      // Önce hiç olmayanlar, sonra düşük çözünürlüklüler
      final none = <String>[];
      final small = <String>[];
      for (final p in kPhotos) {
        final have = _avail[p.id];
        if (have == null) {
          none.add(p.id);
        } else {
          final ownMeta = _meta[p.id];
          final legacyMeta = _legacyMeta[p.id];
          final fits = have.path != null && have.path!.startsWith(dir) ? _fits(ownMeta, size) : _fits(legacyMeta, size);
          if (!fits) small.add(p.id);
        }
      }
      var fails = 0;
      for (final id in [...none, ...small]) {
        if (_closed) return;
        final bytes = await _fetch(client, size, id);
        if (bytes == null) {
          if (++fails >= 3) return;
          continue;
        }
        final path = _join(dir, '$id.jpg');
        try {
          final tmp = File('$path.iniyor');
          await tmp.parent.create(recursive: true);
          await tmp.writeAsBytes(bytes, flush: true);
          final f = File(path);
          if (await f.exists()) await f.delete();
          await tmp.rename(path);
        } catch (_) {
          continue;
        }
        final lum = await lumOf(bytes);
        _meta[id] = size.phone ? {'w': size.width, 'h': size.height, 'lum': lum} : {'w': size.width, 'lum': lum};
        await _saveMeta(dir);
        _avail[id] = PhotoSrc(path: path, lum: lum);
        if (_missing > 0) _missing--;
        onChange?.call();
      }
    } finally {
      client.close(force: true);
      _busy = false;
      if (_again && !_closed) {
        _again = false;
        unawaited(_download());
      }
    }
  }

  Future<Uint8List?> _fetch(HttpClient client, PhotoSize size, String id) async {
    try {
      final url = size.url(id).replaceFirst('https://images.unsplash.com', base);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final b = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 90))) {
        b.add(chunk);
        if (b.length > 24 << 20) return null;
      }
      final bytes = b.takeBytes();
      if (bytes.length < 20000 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMeta(String dir) async {
    try {
      final path = _join(dir, 'fotolar.json');
      final tmp = File('$path.yaziliyor');
      await tmp.writeAsString(jsonEncode(_meta), flush: true);
      final f = File(path);
      if (await f.exists()) await f.delete();
      await tmp.rename(path);
    } catch (_) {}
  }

  @override
  Future<Json?> readLegacyPrefs() async {
    final root = _legacyRoot();
    if (root == null) return null;
    try {
      final f = File(_join(root, 'ayarlar.json'));
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _closed = true;
    onChange = null;
  }
}

/// Fotoğrafın ortalama parlaklığı (0–1, üç basamak); çözülemezse -1. Küçük bir kopyası üzerinden ölçülür.
Future<double> jpegLuminance(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null || data.lengthInBytes < 4) return -1;
    var sum = 0.0;
    final n = data.lengthInBytes ~/ 4;
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      sum += 0.2126 * data.getUint8(o) + 0.7152 * data.getUint8(o + 1) + 0.0722 * data.getUint8(o + 2);
    }
    return (sum / n / 255 * 1000).floor() / 1000;
  } catch (_) {
    return -1;
  }
}

PhotoStore? createPlatformPhotoStore({bool network = false}) => IoPhotoStore();
