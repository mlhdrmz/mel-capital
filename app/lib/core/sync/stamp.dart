// Değişiklik zamanı: her kayıtta değişen ya da yeni eklenen satırlara updatedAt yazılır.
// Eşitlemede aynı kaydın iki cihazda birden değiştiği (nadir) durumda sonuncusu seçilir.

import 'merge.dart';

/// Kayıtların içerik özetleri (değişiklik zamanı hariç), listelere göre: kimlik → özet.
typedef SyncIndex = Map<String, Map<String, String>>;

String _key(Object? v) {
  if (v is num && v == v.truncate()) return v.toInt().toString();
  return '${v ?? 'null'}';
}

SyncIndex indexData(Map d) {
  final idx = <String, Map<String, String>>{};
  kSyncColls.forEach((coll, key) {
    final m = <String, String>{};
    final list = d[coll];
    if (list is List) {
      for (final r in list) {
        if (r is Map) m[_key(r[key])] = rsig(r);
      }
    }
    idx[coll] = m;
  });
  return idx;
}

/// [prev]'e göre yeni ya da değişmiş kayıtlara [now] zamanını yazar; yeni özeti döner.
/// [prev] yoksa (ilk kayıt) yalnızca özet çıkarılır.
SyncIndex stampChanges(Map d, SyncIndex? prev, String now) {
  if (prev == null) return indexData(d);
  kSyncColls.forEach((coll, key) {
    final before = prev[coll] ?? const <String, String>{};
    final list = d[coll];
    if (list is! List) return;
    for (final r in list) {
      if (r is! Map) continue;
      final s = before[_key(r[key])];
      if (s == null || s != rsig(r)) r['updatedAt'] = now;
    }
  });
  return indexData(d);
}
