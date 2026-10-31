// Mel Capital — kayıt yeri: profiller, veri dosyaları, ayarlar ve yedekler.
//
// Windows'ta ve telefonda dosyalara yazar (store_io.dart); web önizlemesinde ve testlerde
// bellekte tutar (store_memory.dart).

import '../core/model.dart';
import '../core/util.dart';
import 'store_factory_stub.dart' if (dart.library.io) 'store_factory_io.dart' as platform;

/// Bir profil: kendi verisi, ayarları ve yedekleri olan ayrı bir kişi/hesap.
class ProfileInfo {
  ProfileInfo({required this.id, required this.name, required this.createdAt, this.lastOpenedAt, this.color});

  factory ProfileInfo.fromJson(Json j) => ProfileInfo(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
        lastOpenedAt: j['lastOpenedAt'] as String?,
        color: j['color'] as String?,
      );

  final String id;
  String name;
  final String createdAt;
  String? lastOpenedAt;
  String? color;

  Json toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'lastOpenedAt': lastOpenedAt,
        'color': color,
      };
}

class ProfileIndex {
  ProfileIndex({this.last, this.lang, List<ProfileInfo>? profiles}) : profiles = profiles ?? [];

  factory ProfileIndex.fromJson(Json j) => ProfileIndex(
        last: j['last'] as String?,
        lang: j['lang'] == 'tr' || j['lang'] == 'en' ? j['lang'] as String : null,
        profiles: [
          for (final p in (j['profiles'] is List ? j['profiles'] as List : const []))
            if (p is Map) ProfileInfo.fromJson(p.cast<String, dynamic>()),
        ],
      );

  String? last;

  /// Arayüz dili (bütün profiller için).
  String? lang;
  final List<ProfileInfo> profiles;

  ProfileInfo? byId(String? id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Json toJson() => {'v': 1, 'last': last, 'lang': lang, 'profiles': [for (final p in profiles) p.toJson()]};
}

class BackupInfo {
  const BackupInfo(this.name, this.size, this.time, this.auto);
  final String name;
  final int size;
  final DateTime time;
  final bool auto;
}

final RegExp backupNameRe = RegExp(r'^[A-Za-z0-9_.-]{1,80}\.json$');

abstract class Store {
  /// Dosya ve yedeklerin bulunduğu klasör (yoksa null: web).
  Future<String?> folder();

  Future<ProfileIndex> loadIndex();
  Future<void> saveIndex(ProfileIndex index);

  /// Profilin ham verisi (JSON). Dosya yoksa null; okunamazsa hata fırlatır.
  Future<Object?> loadData(String profileId);

  /// Veriyi güvenle yazar; günün ilk kaydında otomatik yedek alır.
  Future<void> saveData(String profileId, Json data);

  Future<Json> loadSettings(String profileId);
  Future<void> saveSettings(String profileId, Json settings);

  Future<List<BackupInfo>> listBackups(String profileId);
  Future<String> backupNow(String profileId, {String prefix = 'yedek'});
  Future<Object?> readBackup(String profileId, String name);

  Future<void> deleteProfile(String profileId);

  /// Eski Mel Capital'in veri dosyası (yalnızca okunur, hiç değiştirilmez).
  Future<Object?> readLegacyData();

  /// Profilin klasörünü dosya gezgininde açar (web'de açılamaz: false).
  Future<bool> openFolder(String? profileId, {bool backups = false});
}

Store createStore() => platform.createPlatformStore();

/// Yeni profil kimliği.
String newProfileId(String name, Iterable<String> existing) {
  final base = slugify(name).isEmpty ? 'profil' : slugify(name);
  return uniqueId(base, existing);
}
