// Mel Capital — veri değişiklikleri (eski uygulamadaki app6.js'in veri kısmı).
//
// Buradaki işlevler yalnızca veriyi değiştirir; ekran, ses ve bildirim arayüzde yapılır.
// Hepsi bir Data üzerinde çalışır ve testlerle denetlenir.

import 'calc.dart';
import 'model.dart';
import 'util.dart';

// ---------------------------------------------------------------- Ödeme işaretleme

/// Bir kalemin o ayki ödemesini (bağlı borçlara dağılımı dahil) siler; hesaptan düşülen
/// tutar hesaba geri eklenir.
void removePaymentFor(Data data, String kind, String refId, String m) {
  data.payments.removeWhere((p) {
    final hit = (p.viaRefId == null && p.kind == kind && p.refId == refId && p.month == m) ||
        (kind == 'expense' && p.viaRefId == refId && p.month == m);
    if (hit && p.viaRefId == null && p.fromAccount != null) accAdjust(data, p.fromAccount, toK(p.paidAmount));
    return hit;
  });
}

/// Birden çok karta bağlı ödemeyi kartların güncel borcuna göre orantılı böler.
List<(String, int)> proportionalSplit(Model model, int totalK, List<String> ids) {
  final bal = [for (final id in ids) (id, model.debts[id]?.current ?? 0)];
  final sumB = bal.fold<int>(0, (a, x) => a + x.$2);
  if (sumB <= 0) return const [];
  final pay = totalK < sumB ? totalK : sumB;
  final out = [for (final x in bal) (x.$1, (pay * x.$2) ~/ sumB)];
  var rest = pay - out.fold<int>(0, (a, x) => a + x.$2);
  out.sort((a, b) => b.$2 - a.$2);
  for (var i = 0; rest > 0 && i < out.length; i++, rest--) {
    out[i] = (out[i].$1, out[i].$2 + 1);
  }
  return out.where((x) => x.$2 > 0).toList();
}

/// Ödemenin varsayılan hesabı: aboneliğin kendi hesabı ya da bu kalem için son kullanılan hesap.
String? defaultPayFrom(Data data, PlanItem it) {
  if (it.kind == 'sub') {
    final s = data.subscription(it.refId);
    final acc = srcAcc(s?.source);
    if (s != null && acc != null && data.account(acc) != null) return s.source;
    if (s != null && srcCard(s.source) != null) return null;
  }
  return lastFromFor(data, it.kind, it.refId);
}

/// Kalemi planlanan tutarla bugün ödendi olarak işaretler. Kullanılan hesabı döndürür.
String? markPaid(Data data, Model model, PlanItem it, String m) {
  final paidDate = todayISO();
  final from = defaultPayFrom(data, it);
  final createdAt = nowISO();
  final p = <String, dynamic>{
    'id': rid('od'),
    'kind': it.kind,
    'refId': it.refId,
    'month': m,
    'paidAmount': fromK(it.planned),
    'paidDate': paidDate,
    'createdAt': createdAt,
  };
  if (from != null) p['fromAccount'] = from;
  final linked = it.linked.where((id) => data.debt(id) != null).toList();
  var split = const <(String, int)>[];
  if (it.kind == 'expense' && linked.length == 1) {
    split = [(linked.first, it.planned)];
  } else if (it.kind == 'expense' && linked.length > 1) {
    split = proportionalSplit(model, it.planned, linked);
  }
  data.payments.add(Payment(p));
  if (from != null) accAdjust(data, from, -it.planned);
  for (final x in split) {
    data.payments.add(Payment(<String, dynamic>{
      'id': rid('od'),
      'kind': 'debt',
      'refId': x.$1,
      'month': m,
      'paidAmount': fromK(x.$2),
      'paidDate': paidDate,
      'viaRefId': it.refId,
      'createdAt': createdAt,
    }));
  }
  return from;
}

/// Kapanan (borcu sıfırlanan) krediler: değişiklikten önceki ve sonraki hesaba göre.
List<Debt> closedDebts(Data data, Model before, Model after) => data.debts.where((x) {
      final b = before.debts[x.id], a = after.debts[x.id];
      return b != null && a != null && b.current > 0 && a.current == 0 && !x.isCard;
    }).toList();

// ---------------------------------------------------------------- Abonelik

/// Aboneliği dondurur ya da devam ettirir; yeni durumu döndürür.
bool toggleSubscription(Data data, String id) {
  final s = data.subscription(id);
  if (s == null) return false;
  final next = !s.active;
  s.j['active'] = next;
  return next;
}
