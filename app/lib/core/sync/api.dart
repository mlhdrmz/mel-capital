// Eşitleme sunucusu ve şifreleme (eski Mel Capital ile aynı protokol):
//   https://mel-capital.vercel.app/api/senkron — sunucuda yalnızca şifreli bir paket durur.
//   Anahtar (32 bayt) yalnızca cihazlardadır; HKDF-SHA256 ile şifreleme anahtarı ve sunucudaki
//   alanın kimliği (token) türetilir. Paket: {mc:'senkron', v:1, z, iv, ct} (AES-GCM, gzip).
//   Erişim "Bearer <token>.<bilet>" ile; bilet, eşleştirmede verilen imzadır.
//
// Bu dosya platformdan bağımsızdır; asıl şifreleme ve ağ işleri storage/sync_io.dart'tadır.

import '../model.dart';

const String kSyncOrigin = 'https://mel-capital.vercel.app';

/// Eşitleme hatası: kodlar eski uygulamadakilerle aynı.
class SyncError implements Exception {
  SyncError(this.code, [this.info]);

  /// ag | sifre | bicim | kimlik | sunucu | eski | birlestirme | yerel | anahtar
  final String code;
  final Object? info;

  @override
  String toString() => 'SyncError($code${info == null ? '' : ': $info'})';
}

/// Anahtardan türetilenler.
class SyncKeys {
  SyncKeys({required this.key, required this.token, required this.secret});

  /// Eşleştirme anahtarı (43 karakter, base64url).
  final String key;

  /// Sunucudaki alanın kimliği (43 karakter).
  final String token;

  /// Şifreleme anahtarı (32 bayt).
  final List<int> secret;
}

class SyncResponse {
  SyncResponse(this.status, this.etag, this.text, this.json);
  final int status;
  final String? etag;
  final String text;
  final Object? json;
}

/// Sunucu ve şifreleme işleri (testlerde sahte sunucu kullanılır).
abstract class SyncApi {
  /// Anahtardan şifreleme anahtarını ve sunucudaki kimliği türetir; anahtar geçersizse
  /// SyncError('anahtar').
  Future<SyncKeys> derive(String key);

  /// Yükü şifreler; sunucuya gidecek metin.
  Future<String> seal(SyncKeys keys, Json payload);

  /// Sunucudan gelen metni açar: {v, seq, at, by, hist, data}.
  Future<Json> open(SyncKeys keys, String text);

  /// Sunucuya istek: GET (etag, fresh), PUT (create ya da ifMatch, body), DELETE.
  /// Ağ hatasında SyncError('ag').
  Future<SyncResponse> request(
    String method,
    SyncKeys keys,
    String bilet, {
    String? etag,
    bool fresh = false,
    bool create = false,
    String? ifMatch,
    String? body,
  });
}

/// Eşleştirme bağlantısı: https://mel-capital.vercel.app/#e=<anahtar>.<bilet>
String pairLink(String key, String bilet) => '$kSyncOrigin/#e=$key.$bilet';

/// Bağlantıdan (ya da yalnızca "anahtar.bilet" metninden) anahtar ve bileti çıkarır.
(String, String)? parsePairLink(String text) {
  final m = RegExp(r'(?:#e=|^)([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{86})$').firstMatch(text.trim());
  if (m == null) return null;
  return (m.group(1)!, m.group(2)!);
}

final RegExp _keyRe = RegExp(r'^[A-Za-z0-9_-]{43}$');
final RegExp _biletRe = RegExp(r'^[A-Za-z0-9_-]{86}$');

/// Eşitleme durumunun biçimi geçerli mi (eski uygulamanın senkron.json'u da aynı biçimde).
bool syncStateValid(Object? st) =>
    st is Map &&
    st['v'] == 1 &&
    st['key'] is String &&
    _keyRe.hasMatch(st['key'] as String) &&
    st['bilet'] is String &&
    _biletRe.hasMatch(st['bilet'] as String) &&
    st['dev'] is Map;
