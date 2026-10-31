import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/model.dart';
import '../core/util.dart';
import 'store.dart';

/// Dosyalarla çalışan kayıt yeri.
///
/// Windows: Belgeler\Mel Capital\Profiller\<profil>\veri.json (+ ayarlar.json, Yedekler\).
/// Eski Mel Capital'in Belgeler\Mel Capital\mel-capital-veri.json dosyasına yalnızca okumak için
/// bakılır; o dosya hiçbir zaman değiştirilmez.
class FileStore implements Store {
  FileStore({this.rootOverride});

  /// Testlerde kök klasör.
  final String? rootOverride;
  static const int keepAuto = 30;
  String? _root;

  Future<String> _rootDir() async {
    if (_root != null) return _root!;
    if (rootOverride != null) return _root = rootOverride!;
    final docs = await getApplicationDocumentsDirectory();
    return _root = '${docs.path}${Platform.pathSeparator}Mel Capital';
  }

  String _join(List<String> parts) => parts.join(Platform.pathSeparator);

  Future<String> _profilesDir() async => _join([await _rootDir(), 'Profiller']);
  Future<String> _profileDir(String id) async => _join([await _profilesDir(), id]);
  Future<String> _backupDir(String id) async => _join([await _profileDir(id), 'Yedekler']);

  Future<Object?> _readJson(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString());
  }

  /// Önce geçici dosyaya yazar, sonra yerine koyar; yarım kalan yazım veriyi bozamaz.
  Future<void> _writeAtomic(String path, String content) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.yaziliyor');
    await tmp.writeAsString(content, flush: true);
    if (await f.exists()) {
      final old = File('$path.eski');
      if (await old.exists()) await old.delete();
      await f.rename(old.path);
      await tmp.rename(path);
      await old.delete();
    } else {
      await tmp.rename(path);
    }
  }

  @override
  Future<String?> folder() async => _profilesDir();

  @override
  Future<ProfileIndex> loadIndex() async {
    final raw = await _readJson(_join([await _profilesDir(), 'profiller.json']));
    return raw is Map ? ProfileIndex.fromJson(raw.cast<String, dynamic>()) : ProfileIndex();
  }

  @override
  Future<void> saveIndex(ProfileIndex index) async =>
      _writeAtomic(_join([await _profilesDir(), 'profiller.json']), const JsonEncoder.withIndent(' ').convert(index.toJson()));

  @override
  Future<Object?> loadData(String profileId) async => _readJson(_join([await _profileDir(profileId), 'veri.json']));

  @override
  Future<void> saveData(String profileId, Json data) async {
    final path = _join([await _profileDir(profileId), 'veri.json']);
    final current = File(path);
    if (await current.exists()) {
      final dir = Directory(await _backupDir(profileId));
      await dir.create(recursive: true);
      final auto = File(_join([dir.path, 'otomatik_${todayISO()}.json']));
      if (!await auto.exists()) {
        await current.copy(auto.path);
        await _pruneAuto(dir);
      }
    }
    await _writeAtomic(path, const JsonEncoder.withIndent(' ').convert(data));
  }

  Future<void> _pruneAuto(Directory dir) async {
    final autos = <File>[];
    await for (final e in dir.list()) {
      final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
      if (e is File && name.startsWith('otomatik_') && name.endsWith('.json')) autos.add(e);
    }
    autos.sort((a, b) => a.path.compareTo(b.path));
    while (autos.length > keepAuto) {
      await autos.removeAt(0).delete();
    }
  }

  @override
  Future<Json> loadSettings(String profileId) async {
    final raw = await _readJson(_join([await _profileDir(profileId), 'ayarlar.json']));
    return raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  }

  @override
  Future<void> saveSettings(String profileId, Json settings) async =>
      _writeAtomic(_join([await _profileDir(profileId), 'ayarlar.json']), jsonEncode(settings));

  @override
  Future<List<BackupInfo>> listBackups(String profileId) async {
    final dir = Directory(await _backupDir(profileId));
    if (!await dir.exists()) return [];
    final out = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (!backupNameRe.hasMatch(name)) continue;
      final stat = await e.stat();
      out.add(BackupInfo(name, stat.size, stat.modified, name.startsWith('otomatik_')));
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  @override
  Future<String> backupNow(String profileId, {String prefix = 'yedek'}) async {
    final src = File(_join([await _profileDir(profileId), 'veri.json']));
    if (!await src.exists()) throw StateError('Yedeklenecek veri yok');
    final dir = Directory(await _backupDir(profileId));
    await dir.create(recursive: true);
    var name = '${prefix}_${stamp()}.json';
    var i = 2;
    while (await File(_join([dir.path, name])).exists()) {
      name = '${prefix}_${stamp()}_$i.json';
      i++;
    }
    await src.copy(_join([dir.path, name]));
    return name;
  }

  @override
  Future<Object?> readBackup(String profileId, String name) async {
    if (!backupNameRe.hasMatch(name)) return null;
    return _readJson(_join([await _backupDir(profileId), name]));
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    final dir = Directory(await _profileDir(profileId));
    if (!await dir.exists()) return;
    // Silmeden önce verinin bir kopyası "Silinen profiller" klasörüne taşınır.
    final trash = Directory(_join([await _profilesDir(), 'Silinen profiller']));
    await trash.create(recursive: true);
    await dir.rename(_join([trash.path, '${profileId}_${stamp()}']));
  }

  @override
  Future<bool> openFolder(String? profileId, {bool backups = false}) async {
    final path = profileId == null
        ? await _profilesDir()
        : backups
            ? await _backupDir(profileId)
            : await _profileDir(profileId);
    await Directory(path).create(recursive: true);
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path]);
    } else {
      return false;
    }
    return true;
  }

  @override
  Future<Object?> readLegacyData() async {
    try {
      return await _readJson(_join([await _rootDir(), 'mel-capital-veri.json']));
    } catch (_) {
      return null;
    }
  }
}
