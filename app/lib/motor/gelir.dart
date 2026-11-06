// Mel Capital — GELİR MOTORU
//
// Düzenli gelirler (maaş), tek seferlik gelirler, "Maaşın yattı mı?" onayı.
// Yazar: gelirler; maaş yattığında Çekirdek'e para girişi (aktarma, incomeRef = "<gelir>|<ay>").
// Okur: hesaplar (gelirin yattığı hesap).
// Kullananlar: Plan Motoru (ayın geliri, harcanabilir para), zil (bekleyen maaşlar).

import 'dart:math' as math;

import '../core/model.dart';
import '../core/util.dart';
import 'cekirdek.dart';
import 'plan.dart';

// ---------------------------------------------------------------- Ay gelirleri

class IncomeItem {
  const IncomeItem({
    required this.id,
    required this.name,
    required this.k,
    this.payDay,
    this.planned = 0,
    this.actual = false,
    this.oneOff = false,
    this.est = false,
    this.account,
  });
  final String id;
  final String name;
  final int k;
  final int? payDay;
  final int planned;
  final bool actual;
  final bool oneOff;

  /// Değişken gelir, henüz yatmadı: tutar son yatan tutardan tahmin.
  final bool est;

  /// Yattığı hesap ("acc:<kimlik>").
  final String? account;
}

/// Gelirin [m] ayından önce en son yatan tutarı (hiç girilmediyse null).
int? lastIncomeK(Income inc, String m) {
  String? best;
  for (final e in inc.monthAmounts.entries) {
    if (isMonth(e.key) && e.key.compareTo(m) < 0 && (best == null || e.key.compareTo(best) > 0)) best = e.key;
  }
  return best == null ? null : toK(inc.monthAmounts[best]!);
}

List<IncomeItem> incomeFor(Data d, String m) {
  final list = <IncomeItem>[];
  for (final inc in d.incomes) {
    final planned = schedK(inc.schedule, m);
    final a = inc.monthAmounts[m];
    final act = a == null ? null : toK(a);
    var k = act ?? planned;
    var est = false;
    if (act == null && planned > 0 && inc.variable) {
      // Değişken gelir henüz yatmadı: son yatan tutar (yoksa plandaki) tahmini olarak kullanılır
      k = lastIncomeK(inc, m) ?? planned;
      est = true;
    }
    if (k > 0 || act != null) {
      list.add(IncomeItem(id: inc.id, name: inc.name, k: k, payDay: inc.payDay, planned: planned, actual: act != null, est: est, account: inc.account));
    }
  }
  for (final o in d.oneOffIncomes) {
    if (isDate(o.date) && monthOf(o.date) == m) {
      list.add(IncomeItem(id: o.id, name: o.name, k: toK(o.amount), payDay: dayOf(o.date), oneOff: true));
    }
  }
  return list;
}

/// Kimliğiyle düzenli gelir.
Income? incomeById(Data d, String id) {
  for (final x in d.incomes) {
    if (x.id == id) return x;
  }
  return null;
}

// ---------------------------------------------------------------- Zil: bekleyen gelirler

/// Gelir Motoru'nun hesaplara sorduğu sorular.
extension GelirSorulari on Ctx {
  /// "Maaşın yattı mı?": bu ay günü gelmiş, yattığı henüz onaylanmamış düzenli gelirler.
  List<IncomeItem> pendingIncomes() {
    if (data.closeOf(cur) != null) return const [];
    final td = dayOf(todayISO());
    return [
      for (final i in sum(cur).incomeItems)
        if (!i.actual && !i.oneOff && i.k > 0 && i.payDay != null && math.min(i.payDay!, daysInMonth(cur)) <= td) i,
    ];
  }
}

// ---------------------------------------------------------------- Gelir kayıtları

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

/// Kurulumda düzenli gelir ekler (bu aydan itibaren, süresiz). [k] hesaba yatan net tutardır.
String addSetupIncome(Data data, {required String name, required int k, int? payDay, String? account, bool gross = false, int? grossK}) {
  final b = data.balancesAsOf;
  final start = maxMonth(currentMonth(), isMonth(b) ? b : currentMonth());
  return saveIncome(data, name: name, payDay: payDay, account: account, gross: gross, grossK: grossK, schedule: [
    <String, dynamic>{'from': start, 'to': null, 'amount': fromK(k)},
  ]);
}
