// Telefon ile bilgisayar arasındaki eşitleme (eski Mel Capital'deki runSync'in birebir karşılığı).
//
// Sunucuda yalnızca şifreli bir paket durur; anahtar yalnızca cihazlardadır. Her eşitlemede üç
// yönlü birleştirme yapılır: son ortak hâl (base), bu cihazdaki hâl ve sunucudaki hâl (bkz.
// merge.dart). Sunucudaki paket ETag ile korunur: arada başka cihaz yazdıysa yazma reddedilir (409);
// son hâl alınıp yeniden birleştirilir.
//
// Eşitleme durumu (st) eski uygulamanın senkron.json'u ile aynı biçimdedir:
//   {v:1, key, bilet, dev:{id, ad}, etag, seq, base, hist, pending:{seq, base}, at, peer:{ad, at},
//    paired, lost, budget:{m, r, w}}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../model.dart';
import '../util.dart';
import 'api.dart';
import 'merge.dart';

enum SyncStatus { off, ok, busy, offline, err, lost, wait }

/// Eşitlemenin kullanıcıya bildirdikleri.
enum SyncNotice { synced, peerChanges, offline, failed, lost, paused }

/// Eşitlemenin uygulamadan istedikleri.
abstract class SyncHost {
  /// Uygulamadaki güncel veri (yoksa null: eşitleme yapılmaz). Değiştirilmez.
  Json? get syncData;

  /// Açık bir düzenleme paneli ya da "Geri al" süresi var mı: varsa gelen değişiklikler bekletilir.
  bool get syncUiBusy;

  /// "Geri al" süresinin bittiği an (yoksa null).
  DateTime? get syncUndoUntil;

  /// Birleşmiş veriyi uygulamaya koyar; önce veri, sonra eşitleme durumu kaydedilir.
  Future<void> syncAdopt(Json merged, Json state);

  /// Eşitleme durumunu kaydeder (null: eşleştirme kaldırıldı).
  Future<void> syncPersist(Json? state);

  /// Durum değişti (ekranı yenile).
  void syncChanged();

  /// Kullanıcıya haber.
  void syncNotify(SyncNotice notice, {String? detail});
}

/// Bekleme süreleri: telefonda daha sık eşitlenir.
class SyncTiming {
  const SyncTiming({
    required this.debounce,
    required this.maxWait,
    required this.poll,
    required this.readLimit,
    required this.writeLimit,
  });

  /// Masaüstü (eski uygulamadaki değerler).
  static const SyncTiming desktop = SyncTiming(
    debounce: Duration(seconds: 4),
    maxWait: Duration(seconds: 20),
    poll: Duration(minutes: 4),
    readLimit: 5000,
    writeLimit: 1000,
  );

  /// Telefon.
  static const SyncTiming phone = SyncTiming(
    debounce: Duration(milliseconds: 1200),
    maxWait: Duration(seconds: 6),
    poll: Duration(seconds: 90),
    readLimit: 2500,
    writeLimit: 600,
  );

  /// Kayıttan sonra gönderme beklemesi.
  final Duration debounce;

  /// Art arda kayıtlarda en uzun bekleme.
  final Duration maxWait;

  /// Ekran açıkken ve kullanıcı etkinken yoklama aralığı.
  final Duration poll;

  /// Aylık güvenlik sınırı (bu cihaz): okuma ve yazma sayısı.
  final int readLimit;
  final int writeLimit;
}

/// Yeni cihaz kimliği: 'pc-…' ya da 'tel-…' (eski uygulamadaki gibi 6 rastgele bayt).
Json newSyncDevice({required bool phone}) {
  final r = math.Random.secure();
  final id = base64Url.encode(List<int>.generate(6, (_) => r.nextInt(256))).replaceAll('=', '');
  return {'id': '${phone ? 'tel' : 'pc'}-$id', 'ad': phone ? 'Telefon' : 'Bilgisayar'};
}

/// Eski eşleştirmenin son ortak hâli ile bu profilin verisi aynı kaynaktan mı geliyor: ortak
/// hâldeki kayıtların en az %80'i bu profilde de varsa evet. Değilse eşleştirme sürdürülürken
/// son ortak hâl kullanılmaz (yoksa profilde olmayan kayıtlar "silinmiş" sayılırdı).
bool syncSameOrigin(Object? base, AnyMap local) {
  if (base is! Map) return false;
  var total = 0;
  var found = 0;
  kSyncColls.forEach((coll, key) {
    final b = base[coll];
    final l = local[coll];
    if (b is! List) return;
    final ids = <String>{
      if (l is List)
        for (final x in l)
          if (x is Map) '${x[key]}',
    };
    for (final x in b) {
      if (x is! Map) continue;
      total++;
      if (ids.contains('${x[key]}')) found++;
    }
  });
  return total > 0 && found / total >= 0.8;
}

Json _json(Object? v) => v is Json ? v : Map<String, dynamic>.from(v as Map);

class SyncEngine {
  SyncEngine({
    required this.api,
    required this.host,
    required this.phone,
    SyncTiming? timing,
  }) : timing = timing ?? (phone ? SyncTiming.phone : SyncTiming.desktop);

  final SyncApi api;
  final SyncHost host;

  /// Bu cihaz telefon mu (eski uygulamada PLATFORM === 'web').
  final bool phone;
  final SyncTiming timing;

  /// Eşitleme durumu (eşleştirme yoksa null).
  Json? st;
  SyncKeys? keys;

  SyncStatus status = SyncStatus.off;

  /// Son hatanın kısa açıklaması (kod).
  String? errorCode;

  bool _busy = false;
  Future<void>? _running;
  bool _again = false;
  bool _waitUI = false;
  bool _started = false;
  Timer? _timer;
  int _dirtyAt = 0;
  int lastRun = 0;
  int lastOk = 0;
  int _lastToast = 0;
  int _fails = 0;
  int _pausedUntil = 0;
  final List<int> _pushes = [];

  /// Son kullanıcı etkinliği (yoklama sıklığı için).
  int lastActive = 0;

  /// Uygulama ekranda mı (arka plandayken yoklama yapılmaz).
  bool visible = true;

  bool get busy => _busy;
  bool get paired => st != null;
  bool get lost => st?['lost'] == true;
  bool get dirty => _dirtyAt != 0;

  /// Eşleştirme bağlantısı (QR kodu): yalnızca eşleştirme varsa.
  String? get link {
    final s = st;
    if (s == null) return null;
    return pairLink(s['key'] as String, s['bilet'] as String);
  }

  /// Karşı cihazdaki son değişiklik zamanı.
  String? get peerAt {
    final p = st?['peer'];
    if (p is Map && p['at'] is String && (p['at'] as String).isNotEmpty) return p['at'] as String;
    return null;
  }

  /// Son başarılı eşitleme zamanı.
  String? get syncedAt => st?['at'] is String ? st!['at'] as String : null;

  int get _now => clock().millisecondsSinceEpoch;

  String get _devId {
    final d = st?['dev'];
    return d is Map ? '${d['id'] ?? ''}' : '';
  }

  void _setStatus(SyncStatus s, [String? code]) {
    status = s;
    errorCode = code;
    host.syncChanged();
  }

  // ---------------------------------------------------------------- Açılış ve kapanış

  /// Kayıtlı eşitleme durumunu yükler (geçersizse eşleştirme yok sayılır).
  Future<bool> load(Object? state) async {
    stop();
    st = null;
    keys = null;
    status = SyncStatus.off;
    if (!syncStateValid(state)) return false;
    try {
      keys = await api.derive((state as Map)['key'] as String);
    } catch (_) {
      return false;
    }
    st = deepCopy(state) as Json;
    status = lost ? SyncStatus.lost : SyncStatus.ok;
    return true;
  }

  /// Zamanlayıcıları başlatır ve ilk eşitlemeyi planlar.
  void start() {
    if (st == null || _started) return;
    _started = true;
    lastActive = _now;
    if (!lost) schedule(Duration(milliseconds: phone ? 200 : 1500), 'acilis');
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => tick());
  }

  Timer? _tick;

  /// Zamanlayıcıları durdurur (profil değişince, uygulama kapanınca, testlerin sonunda).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _tick?.cancel();
    _tick = null;
    _started = false;
  }

  /// Zamanlayıcıları durdurur ve süren eşitlemenin bitmesini bekler.
  Future<void> close() async {
    stop();
    final r = _running;
    if (r != null) {
      try {
        await r;
      } catch (_) {
        // yok say
      }
    }
  }

  // ---------------------------------------------------------------- Zamanlama

  void schedule(Duration wait, String reason) {
    if (st == null || lost || !_started) return;
    _timer?.cancel();
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _timer = null;
      unawaited(run(reason));
    });
  }

  bool get _slow {
    final b = st?['budget'];
    return b is Map &&
        b['m'] == currentMonth() &&
        ((b['r'] is int && (b['r'] as int) > timing.readLimit) || (b['w'] is int && (b['w'] as int) > timing.writeLimit));
  }

  void _count(String kind) {
    final s = st;
    if (s == null) return;
    final m = currentMonth();
    var b = s['budget'];
    if (b is! Map || b['m'] != m) {
      b = <String, dynamic>{'m': m, 'r': 0, 'w': 0};
      s['budget'] = b;
    }
    b[kind] = (b[kind] is int ? b[kind] as int : 0) + 1;
  }

  /// Uygulamada kayıt yapıldı: kısa bir beklemeden sonra gönder.
  void onSave() {
    if (st == null || lost) return;
    final now = _now;
    if (_dirtyAt == 0) _dirtyAt = now;
    final slow = _slow;
    var wait = slow ? 60000 : timing.debounce.inMilliseconds;
    // Art arda çok gönderim: biriktir.
    if (_pushes.where((t) => now - t < 120000).length >= 6) wait = math.max(wait, 20000);
    wait = math.min(wait, math.max(0, _dirtyAt + timing.maxWait.inMilliseconds * (slow ? 6 : 1) - now));
    schedule(Duration(milliseconds: wait), 'kayit');
  }

  /// Kapanan panel ya da biten "Geri al" süresi: bekleyen eşitleme varsa şimdi.
  void uiFree() {
    if (!_waitUI || host.syncUiBusy) return;
    _waitUI = false;
    schedule(const Duration(milliseconds: 250), 'pencere');
  }

  /// 30 saniyede bir: uzun süredir eşitlenmediyse yokla.
  void tick() {
    if (st == null || _busy || _timer != null || !visible || lost || _slow) return;
    final idle = _now - lastActive > 10 * 60000;
    final every = idle ? 30 * 60000 : timing.poll.inMilliseconds;
    if (_now - lastRun >= every) unawaited(run('yoklama'));
  }

  /// Uygulama arka plana geçti: bekleyen değişiklik varsa hemen gönder.
  void onHidden() {
    if (st != null && _dirtyAt != 0) unawaited(run('gizlendi'));
  }

  /// Uygulama yeniden öne geldi.
  void onVisible() {
    if (st != null && _now - lastRun > 15000) unawaited(run('odak'));
  }

  // ---------------------------------------------------------------- Sunucu

  Future<SyncResponse> _req(SyncKeys k, String bilet, String method,
      {String? etag, bool fresh = false, bool create = false, String? ifMatch, String? body}) {
    if (method == 'GET') _count('r');
    if (method == 'PUT') _count('w');
    return api.request(method, k, bilet, etag: etag, fresh: fresh, create: create, ifMatch: ifMatch, body: body);
  }

  // ---------------------------------------------------------------- Eşitleme

  /// Bir eşitleme turu. [reason]: 'elle' (kullanıcı istedi), 'kayit', 'yoklama', 'acilis'…
  Future<void> run(String reason) {
    if (st == null || keys == null || lost) return Future<void>.value();
    if (_busy) {
      _again = true;
      return _running ?? Future<void>.value();
    }
    if (_now < _pausedUntil && reason != 'elle') return Future<void>.value();
    if (host.syncData == null) return Future<void>.value();
    final f = _run(reason);
    _running = f;
    return f;
  }

  Future<void> _run(String reason) async {
    final k = keys!;
    final bilet = st!['bilet'] as String;
    _busy = true;
    lastRun = _now;
    _timer?.cancel();
    _timer = null;
    final manual = reason == 'elle';
    _setStatus(SyncStatus.busy);
    var fresh = reason == 'baglan';
    var result = 'retry';
    var adopted = false;
    var peerChange = false;
    var notFound = 0;
    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        final s = st;
        if (s == null) return; // bu arada eşleştirme kaldırıldı
        final local = host.syncData;
        if (local == null) {
          result = 'later';
          break;
        }
        final l = deepCopy(local) as Json;
        final lstr = canon(l);
        final res = await _req(k, bilet, 'GET', etag: s['etag'] as String?, fresh: fresh);
        if (res.status == 401) throw SyncError('kimlik');
        if (res.status == 404) {
          if (++notFound < 2) {
            fresh = true;
            continue;
          }
          result = 'lost';
          break;
        }
        if (res.status != 200 && res.status != 304) throw SyncError('sunucu', res.status);
        Json? remote;
        Json? payload;
        if (res.status == 304 && s['pending'] != null) s.remove('pending'); // önceki gönderim sunucuya ulaşmamış
        if (res.status == 200) {
          payload = await api.open(k, res.text);
          final pseq = payload['seq'] as int;
          // Yanıtı gelmeyen bir gönderim vardıysa: sunucuya ulaşmış mı? Ulaştıysa ortak hâl
          // gönderdiğimiz hâldir (yoksa bakiyedeki değişiklik iki kez sayılırdı).
          final pending = s['pending'];
          if (pending is Map) {
            final hist = payload['hist'];
            final landed = hist is List && hist.any((x) => x is Map && x['s'] == pending['seq'] && x['d'] == _devId);
            if (landed) {
              s['base'] = pending['base'];
              s['seq'] = math.max(_int(s['seq']), _int(pending['seq']));
            }
            if (landed || pseq >= _int(pending['seq']) || fresh) {
              s.remove('pending');
            } else if (!fresh) {
              fresh = true;
              continue;
            }
          }
          final hist = payload['hist'];
          s['hist'] = hist is List ? _last20(hist) : <Object?>[];
          if (pseq < _int(s['seq'])) {
            // önbellekten gelen eski kopya
            if (!fresh) {
              fresh = true;
              continue;
            }
            throw SyncError('eski');
          }
          if (res.etag != s['etag']) {
            if (pseq == _int(s['seq']) && canon(payload['data']) == canon(s['base'])) {
              s['etag'] = res.etag; // aynı hâl, yeni etiket
            } else {
              remote = _json(payload['data']);
            }
          }
        }
        var merged = l;
        var mstr = lstr;
        if (remote != null) {
          try {
            merged = syncMerge(s['base'], l, remote).j;
          } on MergeError catch (e) {
            throw SyncError('birlestirme', e.errors.take(5).toList());
          }
          mstr = canon(merged);
          if (mstr != lstr) {
            if (canon(host.syncData) != lstr) {
              // bu arada kullanıcı değiştirdi
              _again = true;
              result = 'later';
              break;
            }
            if (host.syncUiBusy) {
              // açık panel ya da "Geri al" süresi
              _waitUI = true;
              result = 'wait';
              break;
            }
          }
          // Sunucudaki hâl artık bu cihazda: ortak hâl odur.
          final changed = mstr != lstr;
          s['base'] = remote;
          s['etag'] = res.etag;
          s['seq'] = payload!['seq'];
          final by = payload['by'];
          if (by is Map && by['id'] != _devId) {
            s['peer'] = {'ad': '${by['ad'] ?? ''}', 'at': '${payload['at'] ?? ''}'};
            peerChange = changed;
          }
          if (changed) {
            try {
              await host.syncAdopt(deepCopy(merged) as Json, s);
            } catch (e) {
              throw SyncError('yerel', '$e');
            }
            adopted = true;
          }
        }
        if (canon(s['base']) == mstr) {
          // gönderilecek değişiklik yok
          s['at'] = nowISO();
          result = 'ok';
          break;
        }
        // Bu cihazdaki değişiklikleri gönder. Yanıt gelmezse (bağlantı koparsa) gönderilen hâl
        // "bekleyen" olarak saklanır; sonraki okumada sunucuya ulaşıp ulaşmadığı geçmiş listesinden
        // (hist) anlaşılır.
        final seq = _int(s['seq']) + 1;
        final prevHist = s['hist'];
        final hist = _last20([...(prevHist is List ? prevHist : const <Object?>[]), {'s': seq, 'd': _devId}]);
        final env = await api.seal(k, {'v': 1, 'seq': seq, 'at': nowISO(), 'by': s['dev'], 'hist': hist, 'data': merged});
        s['pending'] = {'seq': seq, 'base': merged};
        try {
          await host.syncPersist(s);
        } catch (e) {
          s.remove('pending');
          throw SyncError('yerel', '$e');
        }
        final put = await _req(k, bilet, 'PUT', ifMatch: s['etag'] as String?, body: env);
        // 409: başka cihaz araya yazmış olabilir. "Bekleyen" kayıt silinmez; sonraki okuma
        // gönderimin sunucuya ulaşıp ulaşmadığını gösterir.
        if (put.status == 409 || put.status == 412 || put.status == 404 || put.status == 428) {
          fresh = true;
          continue;
        }
        if (put.status == 401) {
          s.remove('pending');
          throw SyncError('kimlik');
        }
        final j = put.json;
        final etag = j is Map ? j['etag'] : null;
        if (put.status != 200 || etag is! String) throw SyncError('sunucu', put.status);
        s.remove('pending');
        s['base'] = merged;
        s['etag'] = etag;
        s['seq'] = seq;
        s['hist'] = hist;
        s['at'] = nowISO();
        final now = _now;
        _pushes
          ..add(now)
          ..removeWhere((t) => now - t >= 600000);
        if (_pushes.length > 40) _pausedUntil = now + 15 * 60000; // beklenmedik döngüye karşı fren
        result = 'ok';
        break;
      }
      if (st == null) return; // bu arada eşleştirme kaldırıldı
      if (result == 'lost') {
        await _markLost();
        return;
      }
      if (result == 'ok') {
        _dirtyAt = 0;
        _fails = 0;
        lastOk = _now;
        try {
          await host.syncPersist(st);
        } catch (_) {
          // durum bir sonraki seferde yazılır
        }
        final paused = _now < _pausedUntil;
        _setStatus(paused ? SyncStatus.err : SyncStatus.ok, paused ? 'sik' : null);
        if (paused) {
          host.syncNotify(SyncNotice.paused);
        } else if (manual) {
          host.syncNotify(SyncNotice.synced);
        }
      } else if (result == 'wait') {
        _setStatus(SyncStatus.wait);
        final until = host.syncUndoUntil;
        if (until != null && until.isAfter(clock())) {
          schedule(until.difference(clock()) + const Duration(milliseconds: 300), 'pencere');
        }
      } else if (result == 'retry') {
        // art arda çakışma: biraz sonra yeniden
        _setStatus(SyncStatus.ok);
        schedule(const Duration(seconds: 5), 'tekrar');
      } else {
        _setStatus(SyncStatus.ok);
      }
    } catch (e) {
      if (st == null) return; // bu arada eşleştirme kaldırıldı
      _fails++;
      final code = e is SyncError ? e.code : 'beklenmeyen';
      final offline = code == 'ag';
      _setStatus(offline ? SyncStatus.offline : SyncStatus.err, offline ? null : code);
      if (manual) host.syncNotify(offline ? SyncNotice.offline : SyncNotice.failed, detail: offline ? null : code);
      const fatal = {'sifre', 'kimlik', 'birlestirme', 'eski'};
      if (!fatal.contains(code)) {
        final ms = math.min(5 * 60000, 5000 * math.pow(2, math.min(6, _fails - 1)).toInt());
        schedule(Duration(milliseconds: ms), 'tekrar');
      }
    } finally {
      _busy = false;
      _running = null;
      if (adopted && peerChange && _now - _lastToast > 20000) {
        _lastToast = _now;
        host.syncNotify(SyncNotice.peerChanges);
      }
      if (_again) {
        _again = false;
        schedule(const Duration(milliseconds: 800), 'tekrar');
      }
    }
  }

  /// Sunucudaki kopya silinmiş: eşleştirme kaldırılmış.
  Future<void> _markLost() async {
    final s = st;
    if (s == null) return;
    s['lost'] = true;
    stop();
    try {
      await host.syncPersist(s);
    } catch (_) {
      // yok say
    }
    _setStatus(SyncStatus.lost);
    host.syncNotify(SyncNotice.lost);
  }

  // ---------------------------------------------------------------- Eşleştirme

  /// Yeni eşleştirme durumu: bağlantıdaki anahtar ve bilet, yeni cihaz kimliği.
  static Json newState(String key, String bilet, Json dev) => {
        'v': 1,
        'key': key,
        'bilet': bilet,
        'dev': dev,
        'etag': null,
        'seq': 0,
        'base': null,
        'hist': <Object?>[],
        'paired': nowISO(),
        'at': null,
        'peer': null,
      };

  /// Telefon: bağlantıdaki anahtarla sunucudaki veriyi indirir. Başarılıysa eşleştirme durumu
  /// kurulur ve indirilen veri döner (uygulama bu veriyle açılmalı); başarısızsa SyncError.
  Future<Json> pair(String key, String bilet, Json dev) async {
    stop();
    final k = await api.derive(key);
    final s = newState(key, bilet, dev);
    final res = await api.request('GET', k, bilet, fresh: true);
    if (res.status == 404) throw SyncError('yok');
    if (res.status == 401) throw SyncError('kimlik');
    if (res.status != 200) throw SyncError('sunucu', res.status);
    final payload = await api.open(k, res.text);
    final data = _json(payload['data']);
    s['base'] = deepCopy(data);
    s['etag'] = res.etag;
    s['seq'] = payload['seq'];
    final hist = payload['hist'];
    s['hist'] = hist is List ? _last20(hist) : <Object?>[];
    s['at'] = nowISO();
    final by = payload['by'];
    if (by is Map && by['id'] != dev['id']) s['peer'] = {'ad': '${by['ad'] ?? ''}', 'at': '${payload['at'] ?? ''}'};
    st = s;
    keys = k;
    _fails = 0;
    status = SyncStatus.ok;
    return data;
  }

  /// Bilgisayar: eski Mel Capital'in eşleştirmesini bu profille sürdürür. [union] ise son ortak hâl
  /// kullanılmaz: iki taraftaki kayıtlar birleşir, hiçbir kayıt silinmez (veri eski dosyadan
  /// gelmediyse).
  Future<void> adopt(Json legacy, {required bool union}) async {
    if (!syncStateValid(legacy)) throw SyncError('bicim');
    stop();
    final k = await api.derive(legacy['key'] as String);
    final s = deepCopy(legacy) as Json;
    s.remove('lost');
    s.remove('budget');
    if (union) {
      s['base'] = null;
      s['etag'] = null;
      s.remove('pending');
    }
    s['adopted'] = nowISO();
    st = s;
    keys = k;
    _fails = 0;
    status = SyncStatus.ok;
    await host.syncPersist(s);
  }

  /// Eşleştirmeyi kaldırır: sunucudaki şifreli kopya silinir (yalnızca [deleteRemote] ise) ve bu
  /// cihaz eşitlemeyi bırakır.
  Future<void> unpair({bool deleteRemote = true}) async {
    final s = st;
    final k = keys;
    if (s == null || k == null) return;
    final wasStarted = _started;
    await close();
    if (deleteRemote && !lost) {
      try {
        final r = await _req(k, s['bilet'] as String, 'DELETE');
        if (r.status != 200 && r.status != 404) throw SyncError('sunucu', r.status);
      } catch (_) {
        if (wasStarted) start();
        rethrow;
      }
    }
    st = null;
    keys = null;
    _dirtyAt = 0;
    _waitUI = false;
    status = SyncStatus.off;
    await host.syncPersist(null);
    host.syncChanged();
  }
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

List<Object?> _last20(List<Object?> list) => list.length <= 20 ? [...list] : list.sublist(list.length - 20);
