// Mel Capital — veri değişiklikleri (eski uygulamadaki app6.js'in veri kısmı).
//
// Buradaki işlevler yalnızca veriyi değiştirir; ekran, ses ve bildirim arayüzde yapılır.
// Hepsi bir Data üzerinde çalışır ve testlerle denetlenir.

import 'calc.dart';
import 'constants.dart';
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

// ---------------------------------------------------------------- Borç, ekstre, kart bakiyesi

/// Plan satırlarını denetler ve sıralar: (satırlar, hata).
(List<Json>, String?) validateSched(List<(String?, String?, int?)> rows, {required bool openEnd, required String lang}) {
  String pick(String tr, String en) => lang == 'tr' ? tr : en;
  final sched = <Json>[];
  for (var i = 0; i < rows.length; i++) {
    final (from, to, k) = rows[i];
    final n = i + 1;
    if (!isMonth(from)) return (const [], pick('$n. satırda başlangıç ayı seçilmeli.', 'Row $n needs a start month.'));
    if (!openEnd && !isMonth(to)) return (const [], pick('$n. satırda bitiş ayı seçilmeli.', 'Row $n needs an end month.'));
    if (to != null && !isMonth(to)) return (const [], pick('$n. satırda bitiş ayı için hem ay hem yıl seç.', 'Row $n: pick both month and year for the end.'));
    if (to != null && from!.compareTo(to) > 0) return (const [], pick('$n. satırda bitiş ayı başlangıçtan önce olamaz.', 'Row $n ends before it starts.'));
    if (k == null || k <= 0) return (const [], pick('$n. satırda aylık tutar geçerli değil.', 'Row $n has no valid monthly amount.'));
    sched.add(<String, dynamic>{'from': from, 'to': to, 'amount': fromK(k)});
  }
  sched.sort((a, b) => (a['from'] as String).compareTo(b['from'] as String));
  for (var i = 1; i < sched.length; i++) {
    final prevTo = sched[i - 1]['to'] as String?;
    if (prevTo == null || (sched[i]['from'] as String).compareTo(prevTo) <= 0) {
      return (const [], pick('Plan satırlarının dönemleri çakışıyor (süresiz bir dönemden sonra yeni dönem eklenemez).', 'The plan rows overlap (no new period can follow an open-ended one).'));
    }
  }
  return (sched, null);
}

/// Borç (kredi kartı, kredi, yapılandırma...) ekler ya da günceller.
String saveDebt(Data data, Json rec, {String? id}) {
  if (id != null) {
    data.debt(id)?.j.addAll(rec);
    return id;
  }
  final nid = uniqueId(rec['creditor'] as String, data.debts.map((x) => x.id));
  data.debts.add(Debt(<String, dynamic>{'id': nid, 'statements': <dynamic>[], ...rec}));
  return nid;
}

/// Borcu ve ona ait ödeme işaretlerini siler; bu kartla yapılan harcamalar kayıtta kalır
/// ama kaynakları boşalır.
void deleteDebt(Data data, String id) {
  data.debts.removeWhere((x) => x.id == id);
  for (final p in data.spends) {
    if (srcCard(p.source) == id) p.j.addAll(<String, dynamic>{'source': null, 'installments': 1, 'firstMonth': null});
  }
  for (final s in data.subscriptions) {
    if (srcCard(s.source) == id) s.j['source'] = null;
  }
  data.payments.removeWhere((p) => p.kind == 'debt' && p.refId == id);
  for (final r in data.recurringExpenses) {
    final v = r.j['linkedDebtIds'];
    if (v is List) r.j['linkedDebtIds'] = v.where((x) => x != id).toList();
  }
  for (final c in data.cards) {
    if (c.debtId == id) c.j['debtId'] = null;
  }
}

/// Ekstre ekler ya da günceller; kesim ve son ödeme günleri, ödeme planı da yazılır.
void saveStatement(Data data, String debtId, {required String month, required int totalK, int? minK, int? cutDay, int? dueDay, required String payPlan}) {
  final x = data.debt(debtId);
  if (x == null) return;
  final list = [
    for (final s in x.statements)
      if (s.month != month) s.j,
    <String, dynamic>{'month': month, 'total': fromK(totalK), 'minimum': minK == null ? null : fromK(minK)},
  ]..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
  x.j['statements'] = list;
  x.j['statementDay'] = cutDay;
  x.j['dueDay'] = dueDay;
  x.j['payPlan'] = payPlan;
}

void deleteStatement(Data data, String debtId, String month) {
  final x = data.debt(debtId);
  if (x == null) return;
  x.j['statements'] = [for (final s in x.statements) if (s.month != month) s.j];
}

/// Kart bakiyesini bugünün tarihiyle yeniden yazar (bundan önceki ödeme ve harcamalar dahil sayılır).
void setCardBalance(Data data, String debtId, {required int debtK, int? limitK}) {
  data.debt(debtId)?.j.addAll(<String, dynamic>{
    'remaining': fromK(debtK),
    'limit': limitK == null ? null : fromK(limitK),
    'balanceDate': todayISO(),
    'balanceAt': nowISO(),
  });
}

// ---------------------------------------------------------------- Abonelik ve fatura

String saveSubscription(Data data, Json rec, {String? id}) {
  if (id != null) {
    data.subscription(id)?.j.addAll(rec);
    return id;
  }
  final nid = uniqueId(rec['name'] as String, data.subscriptions.map((x) => x.id));
  data.subscriptions.add(Subscription(<String, dynamic>{'id': nid, 'monthAmounts': <String, dynamic>{}, ...rec}));
  return nid;
}

void deleteSubscription(Data data, String id) {
  data.subscriptions.removeWhere((x) => x.id == id);
  data.payments.removeWhere((p) => p.kind == 'sub' && p.refId == id);
}

/// Faturanın o ayki tutarı (null: kaldır; o ay her zamanki tutar sayılır).
void setBillAmount(Data data, String id, String month, int? k) {
  final x = data.subscription(id);
  if (x == null) return;
  final cur = x.j['monthAmounts'];
  final map = <String, dynamic>{if (cur is Map) ...cur.cast<String, dynamic>()};
  if (k == null) {
    map.remove(month);
  } else {
    map[month] = fromK(k);
  }
  x.j['monthAmounts'] = map;
}

// ---------------------------------------------------------------- Sabit gider

String saveExpense(Data data, Json rec, {String? id}) {
  if (id != null) {
    data.expense(id)?.j.addAll(rec);
    return id;
  }
  final nid = uniqueId(rec['name'] as String, data.recurringExpenses.map((x) => x.id));
  data.recurringExpenses.add(RecurringExpense(<String, dynamic>{'id': nid, ...rec}));
  return nid;
}

void deleteExpense(Data data, String id) {
  data.recurringExpenses.removeWhere((x) => x.id == id);
  data.payments.removeWhere((p) => (p.kind == 'expense' && p.refId == id) || p.viaRefId == id);
}

// ---------------------------------------------------------------- Gelir

/// Düzenli gelir. [account]: yattığı hesap ("acc:<kimlik>"); [grossK]: brüt seçildiyse brüt tutar (bilgi;
/// plan [schedule]'daki net tutarlarla çalışır); [variable]: her ay farklı yatar.
String saveIncome(
  Data data, {
  String? id,
  required String name,
  int? payDay,
  required List<Json> schedule,
  String note = '',
  String? account,
  bool gross = false,
  int? grossK,
  bool variable = false,
}) {
  final rec = <String, dynamic>{
    'name': name,
    'payDay': payDay,
    'schedule': schedule,
    'note': note,
    'account': account,
    'basis': gross ? 'brut' : 'net',
    'grossAmount': gross && grossK != null ? fromK(grossK) : null,
    'variable': variable,
  };
  if (id != null) {
    for (final x in data.incomes) {
      if (x.id == id) x.j.addAll(rec);
    }
    return id;
  }
  final nid = uniqueId(name, [...data.incomes.map((x) => x.id), ...data.oneOffIncomes.map((x) => x.id)]);
  data.incomes.add(Income(<String, dynamic>{'id': nid, 'monthAmounts': <String, dynamic>{}, ...rec}));
  return nid;
}

void deleteIncome(Data data, String id) => data.incomes.removeWhere((x) => x.id == id);

String saveOneOffIncome(Data data, {String? id, required String name, required int k, required String date}) {
  final rec = <String, dynamic>{'name': name, 'amount': fromK(k), 'date': date};
  if (id != null) {
    for (final x in data.oneOffIncomes) {
      if (x.id == id) x.j.addAll(rec);
    }
    return id;
  }
  final nid = uniqueId(name, [...data.incomes.map((x) => x.id), ...data.oneOffIncomes.map((x) => x.id)]);
  data.oneOffIncomes.add(OneOffIncome(<String, dynamic>{'id': nid, ...rec}));
  return nid;
}

void deleteOneOffIncome(Data data, String id) => data.oneOffIncomes.removeWhere((x) => x.id == id);

/// Bir ayda gerçekte yatan gelir (null: kaldır). Hesap seçildiyse o hesaba giriş olarak eklenir.
void setIncomeActual(Data data, String id, String month, {int? k, String? date, String? to}) {
  Income? inc;
  for (final x in data.incomes) {
    if (x.id == id) inc = x;
  }
  final i = inc;
  if (i == null) return;
  final ref = '$id|$month';
  final cur = i.j['monthAmounts'];
  final map = <String, dynamic>{if (cur is Map) ...cur.cast<String, dynamic>()};
  if (k == null) {
    map.remove(month);
  } else {
    map[month] = fromK(k);
  }
  i.j['monthAmounts'] = map;
  for (final t in data.transfers.where((t) => t.incomeRef == ref).toList()) {
    accAdjust(data, t.to, -toK(t.amount));
  }
  data.transfers.removeWhere((t) => t.incomeRef == ref);
  if (k != null && k > 0 && to != null && date != null) {
    data.transfers.add(Transfer(<String, dynamic>{
      'id': rid('akt'),
      'date': date,
      'from': 'ext',
      'to': to,
      'amount': fromK(k),
      'note': '${i.name.isEmpty ? 'Gelir' : i.name} · $month',
      'createdAt': nowISO(),
      'incomeRef': ref,
    }));
    accAdjust(data, to, k);
    // Maaşın yattığı hesap hatırlanır: bundan sonraki aylarda "Yattı" demek yeter
    i.j['account'] = to;
  }
}

// ---------------------------------------------------------------- İstek listesi

String saveGoal(Data data, Json rec, {String? id}) {
  if (id != null) {
    data.goal(id)?.j.addAll(rec);
    return id;
  }
  final nid = uniqueId(rec['name'] as String, data.goals.map((x) => x.id));
  data.goals.add(Goal(<String, dynamic>{
    'id': nid,
    'status': 'active',
    'boughtAt': null,
    'boughtVia': null,
    'boughtPrice': null,
    ...rec,
  }));
  return nid;
}

void deleteGoal(Data data, String id) {
  data.goals.removeWhere((x) => x.id == id);
  data.goalContributions.removeWhere((c) => c.goalId == id);
  for (final p in data.spends) {
    if (p.goalId == id) p.j['goalId'] = null;
  }
}

/// Hedefe para ayırır (eksi tutar: geri alır).
void addContribution(Data data, String goalId, int k, String month) {
  data.goalContributions.add(GoalContribution(<String, dynamic>{
    'id': rid('ayir'),
    'goalId': goalId,
    'amount': fromK(k),
    'month': month,
    'date': todayISO(),
  }));
}

void deleteContribution(Data data, String id) => data.goalContributions.removeWhere((c) => c.id == id);

/// "Alındı" işaretini kaldırır; hedef listeye geri döner.
void reopenGoal(Data data, String id) {
  data.goal(id)?.j.addAll(<String, dynamic>{'status': 'active', 'boughtAt': null, 'boughtVia': null, 'boughtPrice': null});
}

// ---------------------------------------------------------------- Findeks ve tahmin

/// Findeks kaydı ekler ya da [index]'teki kaydı günceller. Aynı ay için ikinci kayıt eklenmez.
String? saveFindeks(Data data, {int? index, required String date, required int score, int? lateCount, String? band}) {
  final list = data.findeks;
  for (var i = 0; i < list.length; i++) {
    if (list[i].date == date && i != index) return 'dup';
  }
  final rec = <String, dynamic>{'date': date, 'score': score, 'lateCount': lateCount, 'band': band};
  if (index != null && index >= 0 && index < list.length) {
    list[index].j.addAll(rec);
  } else {
    list.add(Findeks(rec));
  }
  return null;
}

void deleteFindeks(Data data, int index) {
  final list = data.findeks;
  if (index >= 0 && index < list.length) list.removeAt(index);
}

/// Günlük harcama tahmini (null: otomatik).
void setSpendEstimate(Data data, int? k) {
  if (k == null) {
    data.meta.remove('spendEstimate');
  } else {
    data.meta['spendEstimate'] = fromK(k);
  }
}

// ---------------------------------------------------------------- Ay kapatma

/// Ayı kapatır: işaretli ödenmemiş kalemler sonraki aya taşınır; istenirse serbest kalan devreder.
void closeMonth(Data data, Model model, String month, {required List<PlanItem> carry, required bool carryCash, required bool withSnapshot}) {
  final list = [
    for (final c in data.monthCloses)
      if (c.month != month) c.j,
    <String, dynamic>{
      'month': month,
      'closedAt': nowISO(),
      'carryCash': carryCash,
      'carry': [for (final it in carry) <String, dynamic>{'kind': it.kind, 'refId': it.refId, 'from': it.fromMonth ?? month}],
      'snapshot': withSnapshot ? <String, dynamic>{'liquid': fromK(model.liquid), 'cardDebt': fromK(model.cardDebt), 'loanDebt': fromK(model.loanDebt)} : null,
    },
  ]..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
  data.j['monthCloses'] = list;
}

void reopenMonth(Data data, String month) {
  data.j['monthCloses'] = [for (final c in data.monthCloses) if (c.month != month) c.j];
}

// ---------------------------------------------------------------- Kurulum sihirbazı

/// Kurulumda eklenen kalemin bu ayki ödeme günü geçtiyse, o ayki ödemesi kurulumdan önce yapılmış
/// sayılır: ödendi işareti konur, hesap bakiyeleri değişmez (bakiyeler zaten ödemeden sonraki
/// haliyle girilir). İşaret konduysa true.
bool markPaidBeforeStart(Data data, {required String kind, required String refId, required int k, required int? day}) {
  final m = currentMonth();
  if (day == null || k <= 0 || day >= dayOf(todayISO())) return false;
  if (data.payments.any((p) => p.kind == kind && p.refId == refId && p.month == m)) return false;
  data.payments.add(Payment(<String, dynamic>{
    'id': rid('od'),
    'kind': kind,
    'refId': refId,
    'month': m,
    'paidAmount': fromK(k),
    'paidDate': '$m-${two(day)}',
    'createdAt': nowISO(),
  }));
  return true;
}

/// Kurulumda kredi kartı ekler: bugünkü güncel borç, limit, kesim ve son ödeme günü.
/// Bu ayın son ödeme günü geçtiyse bu ayki kart ödemesi yapılmış sayılır.
String addSetupCard(Data data, {required String name, required String bank, required int debtK, int? limitK, int? cutDay, int? dueDay}) {
  final id = saveDebt(data, <String, dynamic>{
    'creditor': name,
    'type': 'kredi_karti',
    'bank': bank,
    'remaining': fromK(debtK),
    'limit': limitK == null ? null : fromK(limitK),
    'schedule': <dynamic>[],
    'note': '',
    'payDay': null,
    'statementDay': cutDay,
    'dueDay': dueDay,
    'balanceDate': todayISO(),
    'balanceAt': nowISO(),
    'payPlan': 'asgari',
  });
  final estK = ((debtK * kMinPayRate) / 100).round() * 100;
  markPaidBeforeStart(data, kind: 'debt', refId: id, k: estK, day: dueDay ?? cutDay);
  return id;
}

/// Sıradaki taksit ayı: ödeme günü bu ay geçtiyse gelecek ay, geçmediyse bu ay.
String nextInstallmentMonth(int? payDay) {
  final cur = currentMonth();
  return payDay != null && payDay < dayOf(todayISO()) ? addM(cur, 1) : cur;
}

/// Kurulumda kredi ekler: aylık taksit, kalan taksit sayısı ve sıradaki taksit ayından plan kurulur.
/// Kalan borç verilmezse taksit × taksit sayısı sayılır.
String addSetupLoan(Data data,
    {required String name, required String type, required String bank, required int monthlyK, required int count, required String first, int? payDay, int? restK}) {
  return saveDebt(data, <String, dynamic>{
    'creditor': name,
    'type': type,
    'bank': bank,
    'remaining': fromK(restK ?? monthlyK * count),
    'limit': null,
    'schedule': [
      <String, dynamic>{'from': first, 'to': addM(first, count - 1), 'amount': fromK(monthlyK)},
    ],
    'note': '',
    'payDay': payDay,
    'statementDay': null,
    'dueDay': null,
    'balanceDate': null,
    'payPlan': 'asgari',
  });
}

/// Kurulumda düzenli gelir ekler (bu aydan itibaren, süresiz). [k] hesaba yatan net tutardır.
String addSetupIncome(Data data, {required String name, required int k, int? payDay, String? account, bool gross = false, int? grossK}) {
  final b = data.balancesAsOf;
  final start = maxMonth(currentMonth(), isMonth(b) ? b : currentMonth());
  return saveIncome(data, name: name, payDay: payDay, account: account, gross: gross, grossK: grossK, schedule: [
    <String, dynamic>{'from': start, 'to': null, 'amount': fromK(k)},
  ]);
}

/// Kurulumda düzenli ödeme ekler: kira gibi sabit gider ya da abonelik/fatura.
/// Ödeme günü bu ay geçtiyse bu ayki ödemesi yapılmış sayılır.
String addSetupCost(Data data, {required String name, required bool expense, required String group, required int k, int? day, String? source}) {
  if (expense) {
    final b = data.balancesAsOf;
    final id = saveExpense(data, <String, dynamic>{
      'name': name,
      'category': group,
      'amount': fromK(k),
      'startMonth': maxMonth(currentMonth(), isMonth(b) ? b : currentMonth()),
      'endMonth': null,
      'day': day,
      'linkedDebtIds': <String>[],
      'note': '',
    });
    markPaidBeforeStart(data, kind: 'expense', refId: id, k: k, day: day);
    return id;
  }
  final id = saveSubscription(data, <String, dynamic>{
    'name': name,
    'group': group,
    'amount': fromK(k),
    'period': 'ay',
    'day': day,
    'source': source,
    'active': true,
    'note': '',
  });
  markPaidBeforeStart(data, kind: 'sub', refId: id, k: k, day: day);
  return id;
}
