// Bellekte çalışan eşitleme sunucusu: testler ve web önizlemesi için. Gerçek sunucunun
// (mel-capital.vercel.app/api/senkron) kurallarını taklit eder: ETag ile korunan yazma (409),
// "yeni" yazmada var olan kopya (409), etiketsiz yazma (428), silinmiş kopya (404).
// Paketler şifrelenmez (yalnızca base64); gerçek şifreleme sync_io.dart'tadır.

import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;

import '../core/model.dart';
import '../core/sync/api.dart';

class MemorySyncServer {
  final Map<String, String> _body = {};
  final Map<String, String> _etag = {};
  int _n = 0;

  /// İstek sayıları (testler için).
  int gets = 0;
  int puts = 0;

  bool has(String token) => _body.containsKey(token);
  String? etagOf(String token) => _etag[token];
  String? bodyOf(String token) => _body[token];

  void store(String token, String body) {
    _body[token] = body;
    _etag[token] = '"e${++_n}"';
  }

  void remove(String token) {
    _body.remove(token);
    _etag.remove(token);
  }
}

class MemorySyncApi implements SyncApi {
  MemorySyncApi(this.server);

  final MemorySyncServer server;

  /// true: ağ yokmuş gibi davranır.
  bool offline = false;

  /// Bir sonraki PUT'un yanıtı kaybolur (sunucuya ulaşır ama cihaz yanıtı alamaz).
  bool dropNextPutResponse = false;

  /// PUT işlenmeden hemen önce çalışır (testlerde araya başka cihazın yazması için).
  Future<void> Function()? beforePut;

  static final RegExp _keyRe = RegExp(r'^[A-Za-z0-9_-]{43}$');

  @override
  Future<SyncKeys> derive(String key) async {
    if (!_keyRe.hasMatch(key)) throw SyncError('anahtar');
    final token = base64Url.encode(hash.sha256.convert(utf8.encode('kimlik:$key')).bytes).replaceAll('=', '');
    return SyncKeys(key: key, token: token, secret: utf8.encode(key));
  }

  @override
  Future<String> seal(SyncKeys keys, Json payload) async => jsonEncode({
        'mc': 'senkron',
        'v': 1,
        'z': 0,
        'iv': 'AAAAAAAAAAAAAAAA',
        'k': keys.token.substring(0, 8),
        'ct': base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', ''),
      });

  @override
  Future<Json> open(SyncKeys keys, String text) async {
    Object? o;
    try {
      o = jsonDecode(text);
    } catch (_) {
      o = null;
    }
    if (o is! Map || o['mc'] != 'senkron' || o['v'] != 1 || o['ct'] is! String) throw SyncError('bicim');
    if (o['k'] != keys.token.substring(0, 8)) throw SyncError('sifre');
    final p = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(o['ct'] as String))));
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
    // Zamanlayıcısız bekleme: widget testlerinde de takılmadan tamamlanır.
    await Future<void>.value();
    if (offline) throw SyncError('ag', 'çevrimdışı');
    final t = keys.token;
    switch (method) {
      case 'GET':
        server.gets++;
        if (!server.has(t)) return SyncResponse(404, null, '{"yok":true}', {'yok': true});
        final tag = server.etagOf(t);
        if (etag != null && etag == tag) return SyncResponse(304, tag, '', null);
        return SyncResponse(200, tag, server.bodyOf(t)!, null);
      case 'PUT':
        final hook = beforePut;
        if (hook != null) await hook();
        server.puts++;
        if (body == null || body.isEmpty) return SyncResponse(400, null, '', {'hata': 'bicim'});
        if (create) {
          if (server.has(t)) return SyncResponse(409, null, '', {'cakisma': true});
        } else {
          if (ifMatch == null) return SyncResponse(428, null, '', {'hata': 'etag-gerekli'});
          if (!server.has(t) || server.etagOf(t) != ifMatch) return SyncResponse(409, null, '', {'cakisma': true});
        }
        server.store(t, body);
        if (dropNextPutResponse) {
          dropNextPutResponse = false;
          throw SyncError('ag', 'yanıt kayboldu');
        }
        final written = server.etagOf(t)!;
        return SyncResponse(200, null, jsonEncode({'etag': written}), {'etag': written});
      case 'DELETE':
        server.remove(t);
        return SyncResponse(200, null, '', {'silindi': true});
    }
    return SyncResponse(405, null, '', null);
  }
}
