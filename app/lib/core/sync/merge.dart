// Telefon ile bilgisayar arasındaki eşitlemenin birleştirme kuralları (eski Mel Capital'deki
// app6b_sync.js ile birebir aynı). Her eşitlemede üç hâl birleştirilir: son ortak hâl (base, B),
// bu cihazdaki hâl (L) ve sunucudaki hâl (R).
//
// - Yalnız bir tarafta değişen kayıt o taraftan alınır; iki tarafta değişen kayıtta alan alan
//   birleştirilir, ikisinde de değişen alanda son değiştirilen (updatedAt) kazanır.
// - Hesap bakiyeleri toplanarak birleşir: iki cihazdaki harcamaların ikisi de düşülür. Bakiye bir
//   tarafta elle girildiyse (setAt) o değer geçerli olur.
// - Silme, değiştirmeye üstün gelir. İki cihazda aynı ay için aynı ödeme işaretlenmişse biri sayılır.

import '../../motor/cekirdek.dart' show accAdjust;
import '../model.dart';
import '../normalize.dart';
import '../util.dart';

/// Anahtar türü belirsiz JSON nesnesi.
typedef AnyMap = Map<dynamic, dynamic>;

/// Eşitlenen listeler ve kayıtlarının anahtarı.
const Map<String, String> kSyncColls = {
  'debts': 'id',
  'recurringExpenses': 'id',
  'incomes': 'id',
  'oneOffIncomes': 'id',
  'accounts': 'id',
  'spends': 'id',
  'transfers': 'id',
  'subscriptions': 'id',
  'goals': 'id',
  'goalContributions': 'id',
  'payments': 'id',
  'findeks': 'date',
  'cards': 'id',
  'monthCloses': 'month',
};

/// "Yok" değeri (JavaScript'teki undefined): anahtarı hiç olmayan alan.
class _Absent {
  const _Absent();
}

const Object absent = _Absent();

class MergeError implements Exception {
  MergeError(this.errors);
  final List<String> errors;
  @override
  String toString() => 'Birleştirme hatası: ${errors.take(5).join(' · ')}';
}

bool _plain(Object? v) => v is Map;

Object? _get(Object? m, String k) {
  if (m is! Map) return absent;
  return m.containsKey(k) ? m[k] : absent;
}

String _num(num v) {
  if (v is int) return v.toString();
  if (v.isFinite && v == v.truncateToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

String _str(String s) {
  final b = StringBuffer('"');
  for (final c in s.runes) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        if (c < 0x20) {
          b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
  return b.toString();
}

/// Anahtar sırasından bağımsız metin (karşılaştırma için).
String canon(Object? v) {
  if (identical(v, absent)) return '~';
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return _num(v);
  if (v is String) return _str(v);
  if (v is List) return '[${v.map((x) => identical(x, absent) ? 'null' : canon(x)).join(',')}]';
  if (v is Map) {
    final ks = [
      for (final k in v.keys)
        if (!identical(v[k], absent)) '$k',
    ]..sort();
    return '{${ks.map((k) => '${_str(k)}:${canon(v[k])}').join(',')}}';
  }
  return _str('$v');
}

/// Kaydın içeriği (değişiklik zamanı hariç).
String rsig(Object? r) {
  if (r is! Map) return canon(r);
  final c = Map<String, dynamic>.from(r)..remove('updatedAt');
  return canon(c);
}

/// Nesnelerin anahtarları, görünme sırasıyla (tekrarsız).
List<String> _keysOf(List<Object?> objs) {
  final out = <String>[];
  final seen = <String>{};
  for (final o in objs) {
    if (o is Map) {
      for (final k in o.keys) {
        if (seen.add('$k')) out.add('$k');
      }
    }
  }
  return out;
}

Object? _pick3(Object? b, Object? l, Object? r, String prefer) {
  final cl = canon(l), cr = canon(r);
  if (cl == cr) return l;
  final cb = canon(b);
  if (cl == cb) return r;
  if (cr == cb) return l;
  return prefer == 'r' ? r : l;
}

Object? _mergeVal(Object? b, Object? l, Object? r, String prefer) {
  if (_plain(l) && _plain(r) && (identical(b, absent) || b == null || _plain(b)) && canon(l) != canon(r)) {
    return _mergeObj(b, l, r, prefer);
  }
  return _pick3(b, l, r, prefer);
}

Object? _mergeObj(Object? b, Object? l, Object? r, String prefer) {
  if (!_plain(l) || !_plain(r)) return _pick3(b, l, r, prefer);
  final bb = _plain(b) ? b as Map : const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final k in _keysOf([r, l])) {
    final v = _mergeVal(_get(bb, k), _get(l, k), _get(r, k), prefer);
    if (!identical(v, absent)) out[k] = v;
  }
  return out;
}

Map<String, AnyMap> _keyedMap(Object? a, String key) {
  final m = <String, AnyMap>{};
  if (a is List) {
    for (final x in a) {
      if (x is Map) m[_keyStr(x[key])] = x;
    }
  }
  return m;
}

/// JavaScript'teki String(x): sayılar tam sayıysa noktasız.
String _keyStr(Object? v) {
  if (v == null) return 'null';
  if (v is num) return _num(v);
  return '$v';
}

List<String> _keysOfMaps(List<Map<String, AnyMap>> maps) {
  final out = <String>[];
  final seen = <String>{};
  for (final m in maps) {
    for (final k in m.keys) {
      if (seen.add(k)) out.add(k);
    }
  }
  return out;
}

/// Anahtarlı liste (ör. kartın ekstreleri, aya göre).
List<Object?> _mergeKeyed(Object? b, Object? l, Object? r, String key, String prefer) {
  final bm = _keyedMap(b, key), lm = _keyedMap(l, key), rm = _keyedMap(r, key);
  final out = <Object?>[];
  for (final k in _keysOfMaps([rm, lm])) {
    final bv = bm[k], lv = lm[k], rv = rm[k];
    Object? v;
    if (bv == null) {
      v = lv != null && rv != null ? _mergeVal(absent, lv, rv, prefer) : (lv ?? rv);
    } else if (lv == null || rv == null) {
      v = null; // bir tarafta silinmiş
    } else {
      v = _mergeVal(bv, lv, rv, prefer);
    }
    if (v != null && !identical(v, absent)) out.add(v);
  }
  out.sort((x, y) => _keyStr((x as Map)[key]).compareTo(_keyStr((y as Map)[key])));
  return out;
}

String _s(Object? v) => v is String ? v : '';

/// Hesap bakiyesi: iki taraftaki değişim toplanır; bir tarafta elle girildiyse (setAt) o geçerli.
Object? _mergeBalance(AnyMap? b, AnyMap l, AnyMap r, String prefer) {
  if (b == null) return prefer == 'r' ? r['balance'] : l['balance'];
  final sb = _s(b['setAt']), sl = _s(l['setAt']), sr = _s(r['setAt']);
  final lSet = sl != sb, rSet = sr != sb;
  if (lSet && rSet) return sl.compareTo(sr) >= 0 ? l['balance'] : r['balance'];
  if (lSet) return l['balance'];
  if (rSet) return r['balance'];
  return fromK(toK(l['balance']) + toK(r['balance']) - toK(b['balance']));
}

AnyMap _mergeRec(String coll, AnyMap? b, AnyMap l, AnyMap r) {
  final sl = rsig(l), sr = rsig(r);
  // Hesaplarda bakiye her zaman toplanarak birleşir: iki cihazda aynı tutarda iki ayrı harcama, iki
  // kayıt aynı görünse de iki kez düşülmelidir.
  final additive = coll == 'accounts' && b != null;
  final ul = _s(l['updatedAt']), ur = _s(r['updatedAt']);
  if (sl == sr && !additive) return ul.compareTo(ur) >= 0 ? l : r;
  if (b != null) {
    final sb = rsig(b);
    if (sl == sb) return r;
    if (sr == sb) return l;
  }
  final prefer = ul.compareTo(ur) >= 0 ? 'l' : 'r';
  final bb = b ?? const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final k in _keysOf([r, l])) {
    if (k == 'updatedAt') continue;
    Object? v;
    if (coll == 'accounts' && k == 'balance') {
      v = _mergeBalance(b, l, r, prefer);
    } else if (coll == 'debts' && k == 'statements') {
      v = _mergeKeyed(_get(bb, 'statements'), _get(l, 'statements'), _get(r, 'statements'), 'month', prefer);
    } else {
      v = _mergeVal(_get(bb, k), _get(l, k), _get(r, k), prefer);
    }
    if (!identical(v, absent)) out[k] = v;
  }
  if (ul.isNotEmpty || ur.isNotEmpty) out['updatedAt'] = ul.compareTo(ur) > 0 ? ul : ur;
  return out;
}

List<Object?> _mergeColl(String coll, Object? ba, Object? la, Object? ra) {
  final key = kSyncColls[coll]!;
  final bm = _keyedMap(ba, key), lm = _keyedMap(la, key), rm = _keyedMap(ra, key);
  final out = <Object?>[];
  for (final k in _keysOfMaps([rm, lm])) {
    final b = bm[k], l = lm[k], r = rm[k];
    AnyMap? v;
    if (b == null) {
      v = l != null && r != null ? _mergeRec(coll, null, l, r) : (l ?? r); // yeni kayıt
    } else if (l == null || r == null) {
      v = null; // bir tarafta silinmiş: silme kazanır
    } else {
      v = _mergeRec(coll, b, l, r);
    }
    if (v != null) out.add(v);
  }
  return out;
}

/// Üç yönlü birleştirme (doğrulama yapılmaz; bkz. [syncMerge]).
Map<String, dynamic> merge3(Object? base, AnyMap l, AnyMap r) {
  final b = base is Map ? base : const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final k in _keysOf([r, l])) {
    Object? v;
    if (kSyncColls.containsKey(k)) {
      v = _mergeColl(k, _get(b, k), _get(l, k), _get(r, k));
    } else if (k == 'meta') {
      v = _mergeObj(_get(b, 'meta'), l['meta'] is Map ? l['meta'] : const <String, dynamic>{}, r['meta'] is Map ? r['meta'] : const <String, dynamic>{}, 'l');
    } else {
      v = _pick3(_get(b, k), _get(l, k), _get(r, k), 'l');
    }
    if (!identical(v, absent)) out[k] = v;
  }
  return out;
}

Set<String> _ids(Object? d, String coll) {
  final a = _get(d, coll);
  return {
    if (a is List)
      for (final x in a)
        if (x is Map) _keyStr(x['id']),
  };
}

/// İki cihazda birbirinden habersiz girilmiş aynı işlem (aynı ay için aynı ödeme, aynı maaş girişi)
/// bir kez sayılır: karşı taraftaki kopya çıkarılır ve hesap bakiyesine etkisi geri alınır.
Map<String, dynamic> dedupeConcurrent(Object? b, AnyMap l, AnyMap r, Map<String, dynamic> m) {
  bool Function(AnyMap) isNew(String coll, {required bool local}) {
    final bi = _ids(b, coll), li = _ids(l, coll), ri = _ids(r, coll);
    return (x) {
      final id = _keyStr(x['id']);
      return !bi.contains(id) && (local ? li.contains(id) && !ri.contains(id) : ri.contains(id) && !li.contains(id));
    };
  }

  final data = Data(m);
  if (m['payments'] is List) {
    final lNew = isNew('payments', local: true), rNew = isNew('payments', local: false);
    String sig(AnyMap p) => [p['kind'], p['refId'], p['month'], _truthy(p['viaRefId']) ? p['viaRefId'] : ''].map((x) => '${x ?? ''}').join('|');
    // JavaScript'teki gibi: listede nesne olmayan öğeler de olduğu gibi kalır.
    final list = m['payments'] as List;
    final mine = {
      for (final p in list)
        if (p is Map && lNew(p)) sig(p),
    };
    final keep = <Object?>[];
    for (final p in list) {
      if (p is! Map || !rNew(p) || !mine.contains(sig(p))) {
        keep.add(p);
        continue;
      }
      if (!_truthy(p['viaRefId']) && _truthy(p['fromAccount'])) accAdjust(data, '${p['fromAccount']}', toK(p['paidAmount']));
    }
    m['payments'] = keep;
  }
  if (m['transfers'] is List) {
    final lNew = isNew('transfers', local: true), rNew = isNew('transfers', local: false);
    final list = m['transfers'] as List;
    final mine = {
      for (final t in list)
        if (t is Map && _truthy(t['incomeRef']) && lNew(t)) '${t['incomeRef']}',
    };
    final keep = <Object?>[];
    for (final t in list) {
      if (t is! Map || !_truthy(t['incomeRef']) || !rNew(t) || !mine.contains('${t['incomeRef']}')) {
        keep.add(t);
        continue;
      }
      accAdjust(data, t['to'] == null ? null : '${t['to']}', -toK(t['amount']));
      if (t['from'] != 'ext') accAdjust(data, t['from'] == null ? null : '${t['from']}', toK(t['amount']));
    }
    m['transfers'] = keep;
  }
  return m;
}

/// JavaScript'teki doğruluk değeri (boş metin, 0, null ve false "yanlış").
bool _truthy(Object? v) => !(v == null || v == false || v == '' || (v is num && (v == 0 || v.isNaN)));

/// Birleştirmeden sonra kopuk bağlar: silinmiş hedefe ait birikimler.
Map<String, dynamic> repairRefs(Map<String, dynamic> d) {
  if (d['goals'] is List && d['goalContributions'] is List) {
    final g = {
      for (final x in d['goals'] as List)
        if (x is Map) _keyStr(x['id']),
    };
    d['goalContributions'] = [
      for (final c in d['goalContributions'] as List)
        if (c is Map && g.contains(_keyStr(c['goalId']))) c,
    ];
  }
  return d;
}

/// Tam birleştirme: sonuç doğrulanmış veri; birleştirilemezse [MergeError].
Data syncMerge(Object? base, AnyMap l, AnyMap r) {
  final m = repairRefs(dedupeConcurrent(base, l, r, merge3(base, deepCopy(l) as AnyMap, deepCopy(r) as AnyMap)));
  final n = normalizeData(m);
  if (!n.ok) throw MergeError(n.errors);
  return n.data!;
}
