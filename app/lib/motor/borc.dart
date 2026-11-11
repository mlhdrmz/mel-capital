// Mel Capital — BORÇ MOTORU
//
// Kredi kartları (güncel borç, boş limit, ekstre, asgari ödeme, taksitli harcamalar), krediler ve
// yapılandırmalar (taksit planı), fiziksel kartlar, Findeks.
// Yazar: borçlar, ekstreler, kart bakiyesi, kart ödemesi (ödeme kaydı; hesaptan ödendiyse
// Çekirdek'teki [accAdjust] ile bakiyeden düşer), fiziksel kartlar, Findeks kayıtları.
// Okur: Gider Motoru'nun kart harcamaları ve kart abonelikleri, Plan Motoru'nun ödeme dizinleri.
// Kullananlar: Plan Motoru (kart ve taksit kalemleri), Bankalar (boş limit), Alışveriş.
//
// Kart borcu: debt.remaining, debt.balanceDate tarihindeki güncel borçtur. O tarihten sonra (aynı
// gün girilenlerde bakiye güncellemesinden sonra) yapılan ödemeler düşülür, harcamalar eklenir.
// balanceDate yoksa (yapılandırma, kredi) remaining, balancesAsOf ayının başındaki bakiyedir.
// (Eski uygulamada app3.js; veri değişiklikleri app6.js.)

import 'dart:math' as math;

import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import '../core/normalize.dart' show nextStatementMonthFor;
import 'cekirdek.dart';
import 'gider.dart';
import 'plan.dart';

// ---------------------------------------------------------------- Taksit ve ekstre takvimi

class Installment {
  const Installment(this.i, this.n, this.month, this.k);
  final int i;
  final int n;
  final String month;
  final int k;
}

List<Installment> installmentsOf(Spend p) {
  final first = p.firstMonth;
  if (first == null || !isMonth(first)) return const [];
  final n = math.max(1, p.installments);
  final total = toK(p.amount);
  final base = total ~/ n;
  final rem = total - base * n;
  return [
    for (var i = 0; i < n; i++) Installment(i, n, addM(first, i), base + (i == n - 1 ? rem : 0)),
  ];
}

/// Ekstrede ödenmesi planlanan tutar: plan "tamamı" ise ekstre borcu, değilse asgari (yoksa ekstre).
int statementPlanK(Debt debt, Statement? st) {
  if (st == null) return 0;
  if (debt.payPlan == 'tamami' || st.minimum == null) return toK(st.total);
  return toK(st.minimum);
}

/// Bir tarihte yapılan kart harcamasının ilk taksitinin düşeceği ekstre (son ödeme) ayı.
String nextStatementMonth(Debt? debt, String? date) => nextStatementMonthFor(debt?.j, date);

class Cycle {
  const Cycle(this.cutDay, this.cutM, this.dueDay, this.dueM);
  final int cutDay;
  final String cutM;
  final int? dueDay;
  final String? dueM;
}

/// Bugünden sonraki ilk hesap kesimi ve son ödeme.
Cycle? nextCycle(Debt? debt) {
  final stDay = debt?.statementDay;
  if (debt == null || stDay == null) return null;
  final t = todayISO();
  final day = dayOf(t);
  final cm = monthOf(t);
  final cutM = day <= stDay ? cm : addM(cm, 1);
  final due = debt.dueDay;
  final dueM = due != null ? (due > stDay ? cutM : addM(cutM, 1)) : null;
  return Cycle(stDay, cutM, due, dueM);
}

/// Bir ekstre (son ödeme) ayına ait hesap kesim ayı.
String cutMonthOf(Debt debt, String m) {
  final due = debt.dueDay;
  final st = debt.statementDay;
  return due != null && st != null && due < st ? addM(m, -1) : m;
}

/// Kart bakiyesi girildikten sonra mı? (Aynı gün: bakiye güncellemesinden sonra girilenler.)
bool afterSnap(Debt debt, String? date, String? createdAt) {
  final snap = isDate(debt.balanceDate) ? debt.balanceDate! : null;
  if (snap == null) return true;
  if (!isDate(date)) return false;
  if (date != snap) return date!.compareTo(snap) > 0;
  final at = debt.balanceAt;
  return at != null && createdAt != null && createdAt.compareTo(at) > 0;
}

String? bankKeyOf(Debt? debt) {
  if (debt == null) return null;
  if (debt.bank.isNotEmpty && kBanks.containsKey(debt.bank)) return debt.bank;
  return detectBank(debt.creditor) ?? (debt.bank.isEmpty ? null : debt.bank);
}

// ---------------------------------------------------------------- Borç durumu

class DebtMonth {
  const DebtMonth(this.planned, this.direct, this.via, this.st);
  final int planned;
  final PayEntry? direct;
  final int via;
  final Statement? st;
}

class DebtInfo {
  DebtInfo({
    required this.initial,
    required this.purchAdd,
    required this.current,
    required this.unbilled,
    required this.limit,
    required this.outstanding,
    required this.unplanned,
    required this.lastPlanned,
    required this.nextPlanned,
    required this.months,
    required this.purchases,
    required this.snap,
    required this.card,
    required this.subsK,
  });

  final int initial;
  final int purchAdd;
  int get gross => initial + purchAdd;
  final int current;
  final int unbilled;
  final int? limit;
  int? get available => limit == null ? null : limit! - current;
  final int outstanding;
  final int unplanned;
  final String? lastPlanned;
  final String? nextPlanned;
  final Map<String, DebtMonth> months;
  final List<Spend> purchases;
  final String? snap;
  final bool card;
  final int subsK;

  /// m ayından itibaren ödenmemiş plan taksiti sayısı.
  int installmentsLeft(String m) {
    var n = 0;
    months.forEach((k, v) {
      if (k.compareTo(m) >= 0 && v.planned > 0 && v.direct == null && v.st == null) n++;
    });
    return n;
  }
}

/// Bütün borçların güncel durumu ve toplamları (kartlar ve krediler).
class BorcDurumu {
  const BorcDurumu({
    required this.debts,
    required this.totalRemaining,
    required this.cardDebt,
    required this.cardLimit,
    required this.cardAvail,
    required this.cardCount,
    required this.loanDebt,
    required this.debtFree,
  });
  final Map<String, DebtInfo> debts;
  final int totalRemaining;
  final int cardDebt;
  final int cardLimit;
  final int cardAvail;
  final int cardCount;
  final int loanDebt;
  final String? debtFree;
}

/// Borç Motoru'nun ana hesabı. Kart borcu: kart bakiyesinin girildiği günden sonraki harcamalar
/// eklenir, ödemeler düşülür. Kredi: plan taksitleri ve ödemeler. [payIdx] ve [viaIdx] Plan
/// Motoru'nun ödeme dizinleridir; [insts] ve [byCard] karttan yapılan taksitli harcamalar.
BorcDurumu borclariHesapla(
  Data d, {
  required String cur,
  required String base,
  required String maxM,
  required Map<String, PayEntry> payIdx,
  required Map<String, List<Payment>> viaIdx,
  required Map<String, List<Installment>> insts,
  required Map<String, List<Spend>> byCard,
}) {
  final cardSubs = <String, int>{};
  for (final s in d.subscriptions) {
    final cid = srcCard(s.source);
    final k = subMonthlyK(s);
    if (cid != null && s.active && k > 0) cardSubs[cid] = (cardSubs[cid] ?? 0) + k;
  }
  // Karttan ödenen aboneliklerin "ödendi" işaretleri kart harcaması gibi sayılır (Melih'in kararı):
  // kartın son kesiminden (bakiye tarihinden) sonraysa borca eklenir, boş limitten düşer. Ekstre
  // girilince kesimden önceki ödemeler ekstrenin içinde sayılır, iki kez sayılmaz.
  final cardSubPays = <String, List<Payment>>{};
  for (final p in d.payments) {
    if (p.kind != 'sub' || p.viaRefId != null || p.fromAccount != null) continue;
    final cid = srcCard(d.subscription(p.refId)?.source);
    if (cid != null) cardSubPays.putIfAbsent(cid, () => []).add(p);
  }

  final debts = <String, DebtInfo>{};
  var totalRemaining = 0, cardDebt = 0, cardLimit = 0, cardAvail = 0, cardCount = 0, loanDebt = 0;
  String? debtFree;
  for (final debt in d.debts) {
    final snap = isDate(debt.balanceDate) ? debt.balanceDate : null;
    bool counts(Payment p) {
      if (snap == null) return true;
      final pd = p.paidDate;
      return isDate(pd) ? afterSnap(debt, pd, p.createdAt) : p.month.compareTo(snap.substring(0, 7)) > 0;
    }

    final card = debt.isCard;
    final stMap = {for (final s in debt.statements) s.month: s};
    final initial = toK(debt.remaining);
    var proj = initial, paidSum = 0, outstanding = 0;
    String? lastPlanned, nextPlanned;
    final months = <String, DebtMonth>{};
    for (var i = mIdx(base); i <= mIdx(maxM); i++) {
      final m = mFromIdx(i);
      final st = card ? stMap[m] : null;
      final planned = st != null ? statementPlanK(debt, st) : math.min(schedK(debt.schedule, m), proj);
      final direct = payIdx['debt|${debt.id}|$m'];
      final directK = direct == null ? 0 : sumK(direct.list.where(counts), (Payment p) => toK(p.paidAmount));
      final viaK = sumK((viaIdx['${debt.id}|$m'] ?? const <Payment>[]).where(counts), (Payment p) => toK(p.paidAmount));
      paidSum += directK + viaK;
      if (st != null || card) {
        proj = math.max(0, proj - directK - viaK);
      } else {
        proj = math.max(0, proj - (direct != null ? directK : planned) - viaK);
      }
      if (planned > 0 && st == null) {
        lastPlanned = m;
        if (direct == null) outstanding += planned;
        if (nextPlanned == null && m.compareTo(cur) >= 0) nextPlanned = m;
      }
      months[m] = DebtMonth(planned, direct, viaK, st);
    }
    var purchAdd = 0, unbilled = 0;
    if (card) {
      for (final p in cardSubPays[debt.id] ?? const <Payment>[]) {
        if (afterSnap(debt, p.paidDate, p.createdAt)) purchAdd += toK(p.paidAmount);
      }
    }
    final purchases = byCard[debt.id] ?? const <Spend>[];
    for (final p in purchases) {
      if (afterSnap(debt, p.date, p.createdAt)) purchAdd += toK(p.amount);
      for (final it in insts[p.id] ?? const <Installment>[]) {
        if (it.month.compareTo(cur) > 0) unbilled += it.k;
        if (lastPlanned == null || it.month.compareTo(lastPlanned) > 0) lastPlanned = it.month;
      }
    }
    final current = math.max(0, initial + purchAdd - paidSum);
    final lim = debt.limit;
    final limit = lim != null ? toK(lim) : null;
    final unplanned = debt.schedule.isNotEmpty ? math.max(0, initial - paidSum - outstanding) : 0;
    debts[debt.id] = DebtInfo(
      initial: initial,
      purchAdd: purchAdd,
      current: current,
      unbilled: unbilled,
      limit: limit,
      outstanding: outstanding,
      unplanned: unplanned,
      lastPlanned: lastPlanned,
      nextPlanned: nextPlanned,
      months: months,
      purchases: purchases,
      snap: snap,
      card: card,
      subsK: cardSubs[debt.id] ?? 0,
    );
    totalRemaining += current;
    if (card) {
      cardDebt += current;
      cardCount++;
      if (limit != null) {
        cardLimit += limit;
        cardAvail += math.max(0, limit - current);
      }
    } else {
      loanDebt += current;
      if (lastPlanned != null && current > 0 && (debtFree == null || lastPlanned.compareTo(debtFree) > 0)) {
        debtFree = lastPlanned;
      }
    }
  }
  return BorcDurumu(
    debts: debts,
    totalRemaining: totalRemaining,
    cardDebt: cardDebt,
    cardLimit: cardLimit,
    cardAvail: cardAvail,
    cardCount: cardCount,
    loanDebt: loanDebt,
    debtFree: debtFree,
  );
}

// ---------------------------------------------------------------- Kart soruları

/// Borç Motoru'nun hesaplara sorduğu sorular.
extension BorcSorulari on Ctx {
  /// Kart harcamasının taksit durumu: bu aya kadarki taksitler ekstreye yansımış sayılır.
  PurchaseState purchaseState(Spend p) {
    final list = model.insts[p.id] ?? const <Installment>[];
    var billed = 0, remain = 0;
    for (final it in list) {
      if (it.month.compareTo(cur) <= 0) {
        billed++;
      } else {
        remain += it.k;
      }
    }
    return PurchaseState(list, billed, remain);
  }
}

/// Taksit için en çok boş limiti olan kart.
String? bestCardFor(Ctx ctx, int k) {
  String? best;
  var bestAvail = -1;
  for (final c in ctx.data.debts) {
    final info = ctx.model.debts[c.id];
    if (!c.isCard || info?.limit == null) continue;
    final a = info!.available ?? 0;
    if (a >= k && a > bestAvail) {
      best = c.id;
      bestAvail = a;
    }
  }
  return best;
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

/// Kapanan (borcu sıfırlanan) krediler: değişiklikten önceki ve sonraki hesaba göre.
List<Debt> closedDebts(Data data, Model before, Model after) => data.debts.where((x) {
      final b = before.debts[x.id], a = after.debts[x.id];
      return b != null && a != null && b.current > 0 && a.current == 0 && !x.isCard;
    }).toList();

/// Kart ödemesinin yazılacağı ay: bu ay ya da gelecek ayın ekstresi girildiyse o ay.
String cardPayMonth(Ctx ctx, Debt debt) {
  final sts = debt.statements.where((s) => s.month.compareTo(addM(ctx.cur, 1)) <= 0).toList()..sort((a, b) => a.month.compareTo(b.month));
  if (sts.isNotEmpty && sts.last.month.compareTo(ctx.cur) >= 0) return sts.last.month;
  return ctx.cur;
}

// ---------------------------------------------------------------- Borç, ekstre ve kart bakiyesi kayıtları

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

// ---------------------------------------------------------------- Kurulumda kart ve kredi

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

// ---------------------------------------------------------------- Fiziksel kartlar

BankCard? physicalCardOf(Data d, String debtId) {
  for (final c in d.cards) {
    if (c.debtId == debtId) return c;
  }
  return null;
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

// ---------------------------------------------------------------- Findeks

List<Findeks> findeksSorted(Data d) {
  final indexed = [for (var i = 0; i < d.findeks.length; i++) (d.findeks[i], i)];
  indexed.sort((a, b) {
    final c = a.$1.date.compareTo(b.$1.date);
    return c != 0 ? c : a.$2 - b.$2;
  });
  return [for (final x in indexed) x.$1];
}

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

// ---------------------------------------------------------------- Borç kapatma hesabı
//
// "Ne kadar ödersem ne zaman biter?" Yalnızca hesaplar; veriye hiçbir şey yazmaz. Bütün açık
// borçlar (krediler, yapılandırmalar, kredi kartları) birlikte, ay ay yürütülür:
//   - Kredi: planındaki taksit her ay ödenir. Uygulamadaki "kalan borç" kalan taksitlerin toplamıdır
//     (faiz taksitin içinde). Aylık faiz oranı girildiyse anapara, kalan taksitlerin bugünkü
//     değeridir; fazladan ödeme anaparadan düşer ve kalan ayların faizi ödenmez. Oran yoksa borç
//     faizsiz sayılır: fazladan ödeme son taksitlerden düşer.
//   - Kart: her ay en az asgari ([kMinPayRate], en az [kKapatmaAsgariTabanK]) ödenir; oran
//     girildiyse kalan borca faiz işler. Yeni kart harcaması eklenmediği varsayılır.
//   - Zorunlu ödemelerden (taksitler, asgariler) artan para sıradaki borca gider ([KapatmaSirasi]);
//     bir borç kapanınca ona giden para sıradakine geçer.
// Hesap ondalıklı yürür; sonuçlar kuruşa yuvarlanır.

/// Kart asgarisinin alt sınırı (100 TL): küçük borç sonsuza kadar %20'şer azalmasın.
const int kKapatmaAsgariTabanK = 10000;

/// Kapatma hesabına giren bir borç, bugünkü durumuyla.
class KapatmaBorcu {
  const KapatmaBorcu({required this.id, required this.ad, required this.kart, required this.kalanK, this.taksitler = const <int>[], this.oran = 0});

  final String id;
  final String ad;
  final bool kart;

  /// Uygulamadaki güncel borç (kredide kalan taksitlerin toplamı; faiz içinde).
  final int kalanK;

  /// Kredi: bu aydan başlayarak ay ay ödenmemiş plan taksiti (taksit olmayan ay 0). Kartta boş.
  final List<int> taksitler;

  /// Aylık faiz oranı, yüzde (0: girilmemiş; faizsiz sayılır).
  final double oran;
}

/// Zorunlu ödemelerden artan paranın önce hangi borca gideceği.
enum KapatmaSirasi {
  /// Faizi en yüksek olana (eşitse küçük borca): en az faiz ödenir.
  faiz,

  /// En küçük borca: borçlar tek tek en hızlı kapanır.
  kucuk,
}

/// Kapatma hesabının bir ayı.
class KapatmaAyi {
  const KapatmaAyi({required this.ay, required this.odemeK, required this.faizK, required this.kapananlar});

  /// Bu aydan kaç ay sonra (0: bu ay).
  final int ay;

  /// O ay bütün borçlara ödenen.
  final int odemeK;

  /// O ay kalan borca işleyen faiz.
  final int faizK;

  /// O ay kapanan borçların kimlikleri.
  final List<String> kapananlar;
}

class KapatmaSonucu {
  const KapatmaSonucu({
    required this.aylar,
    required this.bitti,
    required this.toplamK,
    required this.faizK,
    required this.kapanis,
    required this.ilkZorunluK,
  });

  /// Ödeme yapılan aylar, sırayla.
  final List<KapatmaAyi> aylar;

  /// Bütün borçlar kapandı mı (kapanmadıysa: planı olmayan borç var ya da süre yetmedi).
  final bool bitti;

  /// Toplam ödenen.
  final int toplamK;

  /// Hesap süresince işleyen faiz.
  final int faizK;

  /// Borç kimliği → kapandığı ay (bu aydan kaç ay sonra).
  final Map<String, int> kapanis;

  /// İlk ayın zorunlu ödemeleri (taksitler + kart asgarileri).
  final int ilkZorunluK;

  /// Son ödemenin ayı (bu aydan kaç ay sonra); bitmediyse null.
  int? get bitisAy => !bitti ? null : (aylar.isEmpty ? 0 : aylar.last.ay);
}

/// Açık borçları kapatma hesabına hazırlar (bugünkü kalan borç, kalan taksitler, faiz oranı).
List<KapatmaBorcu> kapatmaBorclari(Ctx ctx) {
  final out = <KapatmaBorcu>[];
  final c0 = mIdx(ctx.cur);
  for (final d in ctx.data.debts) {
    final info = ctx.model.debts[d.id];
    if (info == null || info.current <= 0) continue;
    var taksitler = const <int>[];
    if (!d.isCard) {
      final aylik = <int, int>{};
      var son = -1;
      info.months.forEach((m, v) {
        final t = mIdx(m) - c0;
        if (t >= 0 && v.planned > 0 && v.direct == null && v.st == null) {
          aylik[t] = v.planned;
          if (t > son) son = t;
        }
      });
      // Taksitlerin toplamı kalan borcu geçmez (fazlası son taksitlerden düşer)
      var kalan = info.current;
      final liste = List<int>.filled(son + 1, 0);
      for (var t = 0; t <= son && kalan > 0; t++) {
        final a = math.min(aylik[t] ?? 0, kalan);
        liste[t] = a;
        kalan -= a;
      }
      taksitler = liste;
    }
    out.add(KapatmaBorcu(id: d.id, ad: d.creditor, kart: d.isCard, kalanK: info.current, taksitler: taksitler, oran: d.rate ?? 0));
  }
  return out;
}

/// Borçları ay ay yürütür. [aylikK]: borçlara ayda ayrılan toplam tutar (zorunlu ödemelerin
/// altındaysa zorunlu ödemeler yine de ödenir); 0 ise yalnızca zorunlu ödemeler. [topluK]: bu ay
/// bir kerelik fazladan ödeme. En çok [enCokAy] ay yürütülür.
KapatmaSonucu kapatmaHesapla(List<KapatmaBorcu> borclar, {int aylikK = 0, int topluK = 0, KapatmaSirasi sira = KapatmaSirasi.faiz, int enCokAy = 600}) {
  const esik = 0.5; // yarım kuruşun altı kapanmış sayılır
  final n = borclar.length;
  final r = [for (final b in borclar) b.oran > 0 ? b.oran / 100 : 0.0];
  // Anapara: kredide kalan taksitlerin bugünkü değeri (+ planı olmayan kısım), kartta güncel borç
  final p = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final b = borclar[i];
    if (b.kart || b.taksitler.isEmpty) {
      p[i] = b.kalanK.toDouble();
      continue;
    }
    var deger = 0.0, carpan = 1.0;
    var toplam = 0;
    for (final a in b.taksitler) {
      deger += a / carpan;
      toplam += a;
      carpan *= 1 + r[i];
    }
    p[i] = deger + math.max(0, b.kalanK - toplam);
  }
  final sirali = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      if (sira == KapatmaSirasi.faiz) {
        final c = r[b].compareTo(r[a]);
        if (c != 0) return c;
      }
      final c = p[a].compareTo(p[b]);
      return c != 0 ? c : a.compareTo(b);
    });

  final aylar = <KapatmaAyi>[];
  final kapanis = <String, int>{};
  var toplamOdeme = 0, toplamFaiz = 0.0, ilkZorunlu = 0;
  for (var t = 0; t < enCokAy; t++) {
    if (p.every((x) => x <= esik)) break;
    // Zorunlu ödemeler
    final ode = List<double>.filled(n, 0);
    var zorunlu = 0.0;
    for (var i = 0; i < n; i++) {
      if (p[i] <= esik) continue;
      final b = borclar[i];
      double z;
      if (b.kart) {
        final asgari = math.max((p[i] * kMinPayRate / 100).roundToDouble() * 100, kKapatmaAsgariTabanK.toDouble());
        z = math.min(p[i], asgari);
      } else {
        z = t < b.taksitler.length ? math.min(p[i], b.taksitler[t].toDouble()) : 0.0;
      }
      ode[i] = z;
      zorunlu += z;
    }
    if (t == 0) ilkZorunlu = zorunlu.round();
    // Artan para sıradaki borca
    var ek = math.max(0.0, aylikK - zorunlu) + (t == 0 ? topluK : 0);
    for (final i in sirali) {
      if (ek <= 0) break;
      final acik = p[i] - ode[i];
      if (acik <= esik) continue;
      final x = math.min(ek, acik);
      ode[i] += x;
      ek -= x;
    }
    // Ödemeler düşülür, kalan borca faiz işler
    var ayOdeme = 0.0, ayFaiz = 0.0;
    final kapananlar = <String>[];
    for (var i = 0; i < n; i++) {
      if (p[i] <= esik) continue;
      p[i] -= ode[i];
      ayOdeme += ode[i];
      if (p[i] <= esik) {
        p[i] = 0;
        kapanis[borclar[i].id] = t;
        kapananlar.add(borclar[i].id);
      } else if (r[i] > 0) {
        final f = p[i] * r[i];
        p[i] += f;
        ayFaiz += f;
      }
    }
    toplamFaiz += ayFaiz;
    if (ayOdeme <= 0) {
      // Bu ay ödeme yok. İleride taksit de yoksa (planı olmayan borç, ayrılan para yok) hesap bitmez.
      var ileride = false;
      for (var i = 0; i < n && !ileride; i++) {
        if (p[i] <= esik) continue;
        final liste = borclar[i].taksitler;
        for (var k = t + 1; k < liste.length; k++) {
          if (liste[k] > 0) {
            ileride = true;
            break;
          }
        }
      }
      if (!ileride) break;
      continue;
    }
    final odemeK = ayOdeme.round();
    toplamOdeme += odemeK;
    aylar.add(KapatmaAyi(ay: t, odemeK: odemeK, faizK: ayFaiz.round(), kapananlar: kapananlar));
  }
  return KapatmaSonucu(
    aylar: aylar,
    bitti: p.every((x) => x <= esik),
    toplamK: toplamOdeme,
    faizK: toplamFaiz.round(),
    kapanis: kapanis,
    ilkZorunluK: ilkZorunlu,
  );
}

/// Bütün borçları [ay] ay içinde (bu ay dahil) bitirmek için ayda ayrılması gereken en küçük tutar
/// (TL'ye yuvarlı). 0: zorunlu ödemeler zaten yetiyor. Hesaplanamıyorsa null.
int? kapatmaIcinAylik(List<KapatmaBorcu> borclar, int ay, {KapatmaSirasi sira = KapatmaSirasi.faiz}) {
  if (ay < 1 || borclar.isEmpty) return null;
  bool yeter(int k) => kapatmaHesapla(borclar, aylikK: k, sira: sira, enCokAy: ay).bitti;
  if (yeter(0)) return 0;
  var alt = 0; // yetmeyen (TL)
  var ust = (sumK(borclar, (KapatmaBorcu b) => b.kalanK) / 100).ceil() + 1; // yeten (TL): hepsi bu ay ödenir
  if (!yeter(ust * 100)) return null;
  while (ust - alt > 1) {
    final orta = (alt + ust) ~/ 2;
    if (yeter(orta * 100)) {
      ust = orta;
    } else {
      alt = orta;
    }
  }
  return ust * 100;
}
