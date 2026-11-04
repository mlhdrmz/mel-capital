// Eşitlemenin şifreleme ve ağ işleri (Windows ve telefon). Eski Mel Capital tarayıcıda Web Crypto
// ile aynı işi yapıyordu; burada aynı algoritmalar kullanılır, böylece iki uygulama aynı paketi
// okuyup yazabilir:
//   HKDF-SHA256 (tuz 'mel-capital/senkron/v1'): 'sifreleme' → AES-GCM-256 anahtarı, 'kimlik' → token
//   AES-GCM: 12 baytlık rastgele iv, ek veri 'mc-senkron-1', çıktı = şifreli metin + 16 baytlık etiket
//   Sıkıştırma: gzip (z = 1)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart' as pc;

import '../core/model.dart';
import '../core/sync/api.dart';

SyncApi? createPlatformSyncApi() => IoSyncApi();

final Uint8List _salt = Uint8List.fromList(utf8.encode('mel-capital/senkron/v1'));
final Uint8List _aad = Uint8List.fromList(utf8.encode('mc-senkron-1'));
final Random _random = Random.secure();

/// Baytlar → base64url (dolgusuz).
String b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// base64url (dolgulu ya da dolgusuz) → baytlar; geçersizse FormatException.
Uint8List unb64u(String s) => base64Url.decode(base64Url.normalize(s));

Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

/// RFC 5869 HKDF (HMAC-SHA256).
Uint8List hkdfSha256(List<int> ikm, List<int> salt, List<int> info, int length) {
  final prk = hash.Hmac(hash.sha256, salt).convert(ikm).bytes;
  final out = BytesBuilder(copy: false);
  var t = <int>[];
  for (var i = 1; out.length < length; i++) {
    t = hash.Hmac(hash.sha256, prk).convert([...t, ...info, i]).bytes;
    out.add(t);
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

/// AES-GCM (128 bit etiket, ek veri 'mc-senkron-1'). Etiket tutmazsa hata fırlatır.
Uint8List aesGcm(bool encrypt, List<int> key, List<int> iv, List<int> input) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine())
    ..init(encrypt, pc.AEADParameters(pc.KeyParameter(Uint8List.fromList(key)), 128, Uint8List.fromList(iv), _aad));
  return cipher.process(Uint8List.fromList(input));
}

class IoSyncApi implements SyncApi {
  IoSyncApi({this.origin = kSyncOrigin, this.timeout = const Duration(seconds: 25)});

  final String origin;
  final Duration timeout;

  @override
  Future<SyncKeys> derive(String key) async {
    Uint8List raw;
    try {
      raw = unb64u(key);
    } catch (_) {
      throw SyncError('anahtar');
    }
    if (raw.length != 32) throw SyncError('anahtar');
    final enc = hkdfSha256(raw, _salt, utf8.encode('sifreleme'), 32);
    final id = hkdfSha256(raw, _salt, utf8.encode('kimlik'), 32);
    return SyncKeys(key: key, token: b64u(id), secret: enc);
  }

  @override
  Future<String> seal(SyncKeys keys, Json payload) async {
    final iv = randomBytes(12);
    final plain = gzip.encode(utf8.encode(jsonEncode(payload)));
    final ct = aesGcm(true, keys.secret, iv, plain);
    return jsonEncode({'mc': 'senkron', 'v': 1, 'z': 1, 'iv': b64u(iv), 'ct': b64u(ct)});
  }

  @override
  Future<Json> open(SyncKeys keys, String text) async {
    Object? o;
    try {
      o = jsonDecode(text);
    } catch (_) {
      o = null;
    }
    if (o is! Map || o['mc'] != 'senkron' || o['v'] != 1 || o['iv'] is! String || o['ct'] is! String) {
      throw SyncError('bicim');
    }
    List<int> plain;
    try {
      plain = aesGcm(false, keys.secret, unb64u(o['iv'] as String), unb64u(o['ct'] as String));
    } catch (_) {
      throw SyncError('sifre');
    }
    Object? p;
    try {
      if (o['z'] == 1) plain = gzip.decode(plain);
      p = jsonDecode(utf8.decode(plain));
    } catch (e) {
      throw SyncError('bicim', '$e');
    }
    if (p is! Map || p['seq'] is! int || (p['seq'] as int) < 1 || p['data'] is! Map) throw SyncError('bicim');
    return p.cast<String, dynamic>();
  }

  @override
  Future<SyncResponse> request(
    String method,
    SyncKeys keys,
    String bilet, {
    String? etag,
    bool fresh = false,
    bool create = false,
    String? ifMatch,
    String? body,
  }) async {
    var uri = Uri.parse('$origin/api/senkron');
    if (method == 'GET') {
      final q = <String, String>{
        if (etag != null) 'etag': etag,
        if (fresh) 'taze': '1',
      };
      if (q.isNotEmpty) uri = uri.replace(queryParameters: q);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'MelCapital';
    try {
      final req = await client.openUrl(method, uri).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${keys.token}.$bilet');
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (method == 'PUT') {
        req.headers.contentType = ContentType.json;
        if (create) {
          req.headers.set('X-MC-Yeni', '1');
        } else if (ifMatch != null) {
          req.headers.set('X-MC-Eslesme', ifMatch);
        }
        final bytes = utf8.encode(body ?? '');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final text = res.statusCode == 304 ? '' : await res.transform(utf8.decoder).join().timeout(timeout);
      Object? json;
      if (method != 'GET' || res.statusCode != 200) {
        try {
          json = text.isEmpty ? null : jsonDecode(text);
        } catch (_) {
          json = null;
        }
      }
      final raw = res.headers.value('x-mc-etag') ?? res.headers.value(HttpHeaders.etagHeader) ?? '';
      final tag = raw.replaceFirst(RegExp(r'^W/'), '');
      return SyncResponse(res.statusCode, tag.isEmpty ? null : tag, text, json);
    } on SyncError {
      rethrow;
    } on SocketException catch (e) {
      throw SyncError('ag', e.message);
    } on TimeoutException {
      throw SyncError('ag', 'zaman aşımı');
    } on HandshakeException catch (e) {
      throw SyncError('ag', e.message);
    } on HttpException catch (e) {
      throw SyncError('ag', e.message);
    } on IOException catch (e) {
      throw SyncError('ag', '$e');
    } finally {
      client.close(force: true);
    }
  }
}
