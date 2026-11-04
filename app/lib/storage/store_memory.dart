import 'dart:convert';

import '../core/model.dart';
import '../core/util.dart';
import 'store.dart';

/// Bellekte çalışan kayıt yeri (web önizlemesi ve testler).
class MemoryStore implements Store {
  MemoryStore({ProfileIndex? index, Map<String, Json>? data})
      : _index = index ?? ProfileIndex(),
        _data = {for (final e in (data ?? const <String, Json>{}).entries) e.key: jsonEncode(e.value)};

  ProfileIndex _index;
  final Map<String, String> _data;
  final Map<String, Json> _settings = {};
  final Map<String, Map<String, String>> _backups = {};
  final Map<String, String> _sync = {};
  Object? legacy;
  Object? legacySync;

  @override
  Future<String?> folder() async => null;

  @override
  Future<ProfileIndex> loadIndex() async => ProfileIndex.fromJson(jsonDecode(jsonEncode(_index.toJson())) as Json);

  @override
  Future<void> saveIndex(ProfileIndex index) async => _index = ProfileIndex.fromJson(index.toJson());

  @override
  Future<Object?> loadData(String profileId) async {
    final s = _data[profileId];
    return s == null ? null : jsonDecode(s);
  }

  @override
  Future<void> saveData(String profileId, Json data) async {
    final day = todayISO();
    final backups = _backups.putIfAbsent(profileId, () => {});
    final old = _data[profileId];
    if (old != null && !backups.containsKey('otomatik_$day.json')) backups['otomatik_$day.json'] = old;
    _data[profileId] = jsonEncode(data);
  }

  @override
  Future<Json> loadSettings(String profileId) async =>
      Map<String, dynamic>.from(_settings[profileId] ?? const <String, dynamic>{});

  @override
  Future<void> saveSettings(String profileId, Json settings) async =>
      _settings[profileId] = Map<String, dynamic>.from(settings);

  @override
  Future<List<BackupInfo>> listBackups(String profileId) async => [
        for (final e in (_backups[profileId] ?? const <String, String>{}).entries)
          BackupInfo(e.key, e.value.length, clock(), e.key.startsWith('otomatik_')),
      ];

  @override
  Future<String> backupNow(String profileId, {String prefix = 'yedek'}) async {
    final name = '${prefix}_${stamp()}.json';
    _backups.putIfAbsent(profileId, () => {})[name] = _data[profileId] ?? '{}';
    return name;
  }

  @override
  Future<Object?> readBackup(String profileId, String name) async {
    final s = _backups[profileId]?[name];
    return s == null ? null : jsonDecode(s);
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    _data.remove(profileId);
    _settings.remove(profileId);
    _backups.remove(profileId);
    _sync.remove(profileId);
  }

  @override
  Future<Object?> readLegacyData() async => legacy;

  @override
  Future<Object?> loadSyncState(String profileId) async {
    final s = _sync[profileId];
    return s == null ? null : jsonDecode(s);
  }

  @override
  Future<void> saveSyncState(String profileId, Json? state) async {
    if (state == null) {
      _sync.remove(profileId);
    } else {
      _sync[profileId] = jsonEncode(state);
    }
  }

  @override
  Future<Object?> readLegacySync() async => legacySync;

  @override
  Future<bool> openFolder(String? profileId, {bool backups = false}) async => false;
}
