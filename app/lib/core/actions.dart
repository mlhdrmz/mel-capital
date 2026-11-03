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

// ---------------------------------------------------------------- Harcama

/// Harcamayı ekler (id yoksa) ya da günceller; kaynak hesapsa tutar bakiyeden düşülür.
/// [goalId] verilirse o istek "alındı" olarak işaretlenir ve ayrılan birikim bütçeye döner.
String saveSpend(Data data, Json rec, {String? id, String? goalId}) {
  final k = toK(rec['amount']);
  final source = rec['source'] as String?;
  if (id != null) {
    for (final x in data.spends) {
      if (x.id != id) continue;
      accAdjust(data, x.source, toK(x.amount));
      x.j.addAll(rec);
      x.j['updatedAt'] = nowISO();
      accAdjust(data, source, -k);
      return id;
    }
  }
  final nid = rid('h');
  data.spends.add(Spend(<String, dynamic>{'id': nid, 'goalId': goalId, 'createdAt': nowISO(), 'batch': null, ...rec}));
  accAdjust(data, source, -k);
  if (goalId != null) {
    final date = rec['date'] as String;
    final saved = sumK(data.goalContributions.where((c) => c.goalId == goalId), (GoalContribution c) => toK(c.amount));
    if (saved > 0) {
      data.goalContributions.add(GoalContribution(<String, dynamic>{
        'id': rid('ayir'),
        'goalId': goalId,
        'amount': fromK(-saved),
        'month': date.substring(0, 7),
        'date': date,
      }));
    }
    data.goal(goalId)?.j.addAll(<String, dynamic>{
      'status': 'bought',
      'boughtAt': date,
      'boughtVia': srcCard(source) != null ? 'kart' : 'nakit',
      'boughtPrice': fromK(k),
    });
  }
  return nid;
}

/// Harcamayı siler; hesaptan düşülen tutar geri eklenir.
Spend? deleteSpend(Data data, String id) {
  Spend? found;
  for (final x in data.spends) {
    if (x.id == id) found = x;
  }
  final f = found;
  if (f == null) return null;
  data.spends.removeWhere((x) => x.id == id);
  accAdjust(data, f.source, toK(f.amount));
  return f;
}

class QuickLine {
  const QuickLine(this.raw, this.name, this.k, this.cat);
  final String raw;
  final String name;
  final int k;
  final String cat;
  bool get ok => k > 0;
}

/// Hızlı giriş satırları: "kahve 85", "market 340,50", "simit 15, otobüs 27", "85 kahve".
List<QuickLine> parseQuickLines(Data d, String text) {
  final idx = learnIndex(d);
  final parts = text.split(RegExp(r'\r?\n|;|,(?=\s*[^\d\s])')).map((s) => s.trim()).where((s) => s.isNotEmpty);
  final out = <QuickLine>[];
  for (final raw in parts) {
    var name = '';
    int? amt;
    final m1 = RegExp(r'^(.*?)[\s:=-]*(\d[\d.,]*)\s*(?:tl|₺)?$', caseSensitive: false).firstMatch(raw);
    if (m1 != null) {
      name = m1.group(1)!.trim();
      amt = parseAmount(m1.group(2));
    } else {
      final m2 = RegExp(r'^(\d[\d.,]*)\s*(?:tl|₺)?\s+(.+)$', caseSensitive: false).firstMatch(raw);
      if (m2 != null) {
        amt = parseAmount(m2.group(1));
        name = m2.group(2)!.trim();
      }
    }
    out.add(QuickLine(raw, name.isEmpty ? 'Harcama' : name, amt != null && amt > 0 ? amt : 0, smartCategory(d, name, idx)));
  }
  return out;
}

/// Hızlı girişteki satırları tek seferde ekler.
void saveQuickSpends(Data data, List<(String, int, String)> rows, {required String date, String? source, String? firstMonth}) {
  final batch = rows.length > 1 ? rid('toplu') : null;
  final at = nowISO();
  var total = 0;
  for (var i = 0; i < rows.length; i++) {
    final (name, k, cat) = rows[i];
    total += k;
    data.spends.add(Spend(<String, dynamic>{
      'id': rid('h'),
      'date': date,
      'name': name,
      'place': '',
      'category': cat,
      'amount': fromK(k),
      'source': source,
      'installments': 1,
      'firstMonth': firstMonth,
      'note': '',
      'url': '',
      'goalId': null,
      'createdAt': at.replaceFirst(RegExp(r'\.\d+Z$'), '.${i.toString().padLeft(3, '0')}Z'),
      'batch': batch,
    }));
  }
  accAdjust(data, source, -total);
}

// ---------------------------------------------------------------- Aktarma ve kart ödemesi

/// Kart ödemesinin yazılacağı ay: bu ay ya da gelecek ayın ekstresi girildiyse o ay.
String cardPayMonth(Ctx ctx, Debt debt) {
  final sts = debt.statements.where((s) => s.month.compareTo(addM(ctx.cur, 1)) <= 0).toList()..sort((a, b) => a.month.compareTo(b.month));
  if (sts.isNotEmpty && sts.last.month.compareTo(ctx.cur) >= 0) return sts.last.month;
  return ctx.cur;
}

/// Kart borcuna ödeme (ödeme kaydı; hesap seçildiyse bakiyeden düşülür).
void payCard(Data data, String cardId, String month, int k, String date, String? from) {
  final p = <String, dynamic>{
    'id': rid('od'),
    'kind': 'debt',
    'refId': cardId,
    'month': month,
    'paidAmount': fromK(k),
    'paidDate': date,
    'createdAt': nowISO(),
  };
  if (srcAcc(from) != null) {
    p['fromAccount'] = from;
    accAdjust(data, from, -k);
  }
  data.payments.add(Payment(p));
}

/// Aktarma ekler ya da günceller (hesaplar arası ya da dışarıdan giriş).
void saveTransfer(Data data, {String? id, required String from, required String to, required int k, required String date, String note = ''}) {
  if (id != null) {
    for (final x in data.transfers) {
      if (x.id != id) continue;
      if (x.from != 'ext') accAdjust(data, x.from, toK(x.amount));
      accAdjust(data, x.to, -toK(x.amount));
      x.j.addAll(<String, dynamic>{'from': from, 'to': to, 'amount': fromK(k), 'date': date, 'note': note, 'updatedAt': nowISO()});
    }
  } else {
    data.transfers.add(Transfer(<String, dynamic>{
      'id': rid('akt'),
      'date': date,
      'from': from,
      'to': to,
      'amount': fromK(k),
      'note': note,
      'createdAt': nowISO(),
    }));
  }
  if (from != 'ext') accAdjust(data, from, -k);
  accAdjust(data, to, k);
}

void deleteTransfer(Data data, String id) {
  for (final x in data.transfers) {
    if (x.id != id) continue;
    if (x.from != 'ext') accAdjust(data, x.from, toK(x.amount));
    accAdjust(data, x.to, -toK(x.amount));
  }
  data.transfers.removeWhere((x) => x.id == id);
}

// ---------------------------------------------------------------- Ödeme düzenleme

/// Bir kalemin o ayki ödemesini yeniden yazar (tutar, tarih, hesap, bağlı borçlara dağılım).
void savePayment(Data data, {required String kind, required String refId, required String month, required int k, required String date, String? from, List<(String, int)> allocs = const []}) {
  removePaymentFor(data, kind, refId, month);
  final createdAt = nowISO();
  final p = <String, dynamic>{
    'id': rid('od'),
    'kind': kind,
    'refId': refId,
    'month': month,
    'paidAmount': fromK(k),
    'paidDate': date,
    'createdAt': createdAt,
  };
  if (from != null) {
    p['fromAccount'] = from;
    accAdjust(data, from, -k);
  }
  data.payments.add(Payment(p));
  for (final (id, v) in allocs) {
    data.payments.add(Payment(<String, dynamic>{
      'id': rid('od'),
      'kind': 'debt',
      'refId': id,
      'month': month,
      'paidAmount': fromK(v),
      'paidDate': date,
      'viaRefId': refId,
      'createdAt': createdAt,
    }));
  }
}

// ---------------------------------------------------------------- Hesap ve kart

/// Hesap ekler ya da günceller.
void saveAccount(Data data, {String? id, required String bank, required String name, required String type, required int balanceK, String note = ''}) {
  final rec = <String, dynamic>{'bank': bank, 'name': name, 'type': type, 'balance': fromK(balanceK), 'asOf': todayISO(), 'note': note};
  if (id != null) {
    final a = data.account(id);
    if (a == null) return;
    final changed = toK(a.balance) != balanceK;
    a.j.addAll(rec);
    if (changed) a.j['setAt'] = nowISO();
    return;
  }
  data.accounts.add(Account(<String, dynamic>{
    'id': uniqueId(slugify('${bank.isEmpty ? 'nakit' : bank}-$name'), data.accounts.map((x) => x.id)),
    ...rec,
    'setAt': nowISO(),
  }));
}

/// Hesabı siler; bu hesaba bağlı kartların bağlantısı kaldırılır (geçmiş kayıtlar kalır).
void deleteAccount(Data data, String id) {
  data.accounts.removeWhere((x) => x.id == id);
  for (final c in data.cards) {
    if (c.accountId == id) c.j['accountId'] = null;
  }
}

/// Fiziksel kartı ekler ya da günceller (görünüm ve bağlantılar).
void saveCard(Data data, Json rec, {String? id}) {
  if (id != null) {
    for (final c in data.cards) {
      if (c.id == id) c.j.addAll(rec);
    }
    return;
  }
  data.cards.add(BankCard(<String, dynamic>{
    'id': uniqueId(slugify('${rec['bank']}-${rec['name']}'), data.cards.map((x) => x.id)),
    'note': '',
    ...rec,
  }));
}

void deleteCard(Data data, String id) => data.cards.removeWhere((x) => x.id == id);
