// Mel Capital — PLAN MOTORU
//
// Bütün motorların sonuçlarını bir araya getirir: [buildModel] (borçlar, hedefler, hesaplar),
// [Ctx] (ay kalemleri, aylık özet, harcanabilir para, devir, yaklaşan ödemeler). Hesaplar Ctx
// içinde bir kez kurulur; bütün sayfalar aynı Ctx'i okur.
// Yazar: ödeme işaretleri (kalem ödendi; hesaptan ödendiyse Çekirdek'teki [accAdjust] ile
// bakiyeden düşer), ay kapatma ve devir, istek listesi ve birikim ayırmaları.

import 'dart:math' as math;

import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'borc.dart';
import 'cekirdek.dart';
import 'gelir.dart';
import 'gider.dart';

// ---------------------------------------------------------------- Ödeme dizini ve model

/// Bir kalemin o ayki doğrudan ödemeleri (toplam).
class PayEntry {
  PayEntry(this.kind, this.refId, this.month, this.k, this.paidDate, this.list);
  final String kind;
  final String refId;
  final String month;
  int k;
  String? paidDate;
  final List<Payment> list;
  double get paidAmount => fromK(k);
}

class GoalInfo {
  GoalInfo(this.saved, this.target, this.lastCon);
  final int saved;
  final int target;
  final String? lastCon;
  int get remaining => math.max(0, target - saved);
  double get pct => target > 0 ? math.min(1.0, saved / target) : (saved > 0 ? 1.0 : 0.0);
  String? completion;
  final Map<String, int> projected = {};
}

class Model {
  Model({
    required this.cur,
    required this.base,
    required this.maxM,
    required this.payIdx,
    required this.insts,
    required this.byCard,
    required this.debts,
    required this.totalRemaining,
    required this.cardDebt,
    required this.cardLimit,
    required this.cardAvail,
    required this.cardCount,
    required this.loanDebt,
    required this.debtFree,
    required this.liquid,
    required this.cash,
    required this.goals,
    required this.projByMonth,
    required this.subsMonthly,
  });

  final String cur;
  final String base;
  final String maxM;
  final Map<String, PayEntry> payIdx;
  final Map<String, List<Installment>> insts;
  final Map<String, List<Spend>> byCard;
  final Map<String, DebtInfo> debts;
  final int totalRemaining;
  final int cardDebt;
  final int cardLimit;
  final int cardAvail;
  final int cardCount;
  final int loanDebt;
  final String? debtFree;
  final int liquid;
  final int cash;
  final Map<String, GoalInfo> goals;
  final Map<String, int> projByMonth;
  final int subsMonthly;

  /// Net değer: hesaplardaki para − tüm borçlar.
  int get netWorth => liquid - totalRemaining;

  PayEntry? pay(String kind, String refId, String month) => payIdx['$kind|$refId|$month'];
}

Model buildModel(Data d, String cur) {
  final base = isMonth(d.balancesAsOf) ? d.balancesAsOf : cur;
  final payIdx = <String, PayEntry>{};
  final viaIdx = <String, List<Payment>>{};
  var maxM = maxMonth(cur, base);
  for (final x in d.debts) {
    for (final s in x.schedule) {
      final to = s.to;
      if (to != null && to.compareTo(maxM) > 0) maxM = to;
    }
    for (final s in x.statements) {
      if (s.month.compareTo(maxM) > 0) maxM = s.month;
    }
  }
  final insts = <String, List<Installment>>{};
  final byCard = <String, List<Spend>>{};
  for (final p in d.spends) {
    final cid = srcCard(p.source);
    if (cid == null || !isMonth(p.firstMonth)) continue;
    final l = installmentsOf(p);
    if (l.isEmpty) continue;
    insts[p.id] = l;
    byCard.putIfAbsent(cid, () => []).add(p);
    if (l.last.month.compareTo(maxM) > 0) maxM = l.last.month;
  }
  for (final p in d.payments) {
    if (p.month.compareTo(maxM) > 0) maxM = p.month;
    if (p.viaRefId != null) {
      if (p.kind == 'debt') viaIdx.putIfAbsent('${p.refId}|${p.month}', () => []).add(p);
      continue;
    }
    final key = '${p.kind}|${p.refId}|${p.month}';
    final e = payIdx[key];
    if (e == null) {
      payIdx[key] = PayEntry(p.kind, p.refId, p.month, toK(p.paidAmount), p.paidDate, [p]);
    } else {
      e.k += toK(p.paidAmount);
      e.list.add(p);
      final pd = p.paidDate;
      if (isDate(pd) && (e.paidDate == null || pd!.compareTo(e.paidDate!) > 0)) e.paidDate = pd;
    }
  }
  final b = borclariHesapla(d, cur: cur, base: base, maxM: maxM, payIdx: payIdx, viaIdx: viaIdx, insts: insts, byCard: byCard);

  // Hedefler: biriken tutar ve aylık plana göre tahmini ayırmalar
  final goals = <String, GoalInfo>{};
  final projByMonth = <String, int>{};
  for (final g in d.goals) {
    final cons = d.goalContributions.where((c) => c.goalId == g.id).toList();
    final saved = math.max(0, sumK(cons, (GoalContribution c) => toK(c.amount)));
    String? lastCon;
    for (final c in cons) {
      if (lastCon == null || c.month.compareTo(lastCon) > 0) lastCon = c.month;
    }
    final target = toK(g.target);
    final info = GoalInfo(saved, target, lastCon);
    if (g.isActive) {
      final plan = g.monthlyPlan == null ? 0 : toK(g.monthlyPlan);
      if (saved >= target && target > 0) {
        info.completion = lastCon ?? cur;
      } else if (plan > 0) {
        var acc = saved;
        var m = addM(maxMonth(cur, lastCon ?? cur), 1);
        var n = 0;
        while (acc < target && n < 240) {
          final k = math.min(plan, target - acc);
          info.projected[m] = k;
          projByMonth[m] = (projByMonth[m] ?? 0) + k;
          acc += k;
          info.completion = m;
          m = addM(m, 1);
          n++;
        }
      }
    }
    goals[g.id] = info;
  }
  final liquid = liquidK(d);
  final cash = cashK(d);
  final subsMonthly = subsMonthlyK(d);
  return Model(
    cur: cur,
    base: base,
    maxM: maxM,
    payIdx: payIdx,
    insts: insts,
    byCard: byCard,
    debts: b.debts,
    totalRemaining: b.totalRemaining,
    cardDebt: b.cardDebt,
    cardLimit: b.cardLimit,
    cardAvail: b.cardAvail,
    cardCount: b.cardCount,
    loanDebt: b.loanDebt,
    debtFree: b.debtFree,
    liquid: liquid,
    cash: cash,
    goals: goals,
    projByMonth: projByMonth,
    subsMonthly: subsMonthly,
  );
}

// ---------------------------------------------------------------- Ay kalemleri ve özet

/// Plandaki bir ödeme kalemi.
class PlanItem {
  PlanItem({
    required this.kind,
    required this.refId,
    required this.name,
    required this.group,
    required this.category,
    required this.planned,
    this.pay,
    this.linked = const [],
    this.bank,
    this.day,
    this.card = false,
    this.instK = 0,
    this.st,
    this.estK = 0,
    this.pending = false,
    this.est = false,
    this.rec = false,
    this.sub = false,
    this.viaCard = false,
    this.bill = false,
    this.monthSet = false,
    this.carry = false,
    this.fromMonth,
  });

  final String kind; // debt | expense | sub
  final String refId;
  final String name;
  final String group; // taksit | sabit | abonelik | kart
  final String category;
  final int planned;
  final PayEntry? pay;
  final List<String> linked;
  final String? bank;
  final int? day;
  final bool card;
  final int instK;
  final Statement? st;
  final int estK;
  final bool pending;
  final bool est;
  final bool rec;
  final bool sub;
  final bool viaCard;
  final bool bill;
  final bool monthSet;
  final bool carry;
  final String? fromMonth;
  bool carriedOut = false;

  String key(String m) => '$kind|$refId|${fromMonth ?? m}';

  PlanItem carried(String from) => PlanItem(
        kind: kind,
        refId: refId,
        name: name,
        group: group,
        category: category,
        planned: planned,
        pay: pay,
        linked: linked,
        bank: bank,
        day: day,
        card: card,
        instK: instK,
        st: st,
        estK: estK,
        pending: pending,
        est: est,
        rec: rec,
        sub: sub,
        viaCard: viaCard,
        bill: bill,
        monthSet: monthSet,
        carry: true,
        fromMonth: from,
      );
}

class MonthSummary {
  MonthSummary(this.month, this.items);
  final String month;
  final List<PlanItem> items;
  int total = 0, taksit = 0, sabit = 0, abonelik = 0, kart = 0;
  int paid = 0, unpaid = 0, pendingCards = 0, estK = 0, carriedK = 0;
  bool allPaid = false;
  MonthClose? close;
  int carryIn = 0;
  List<IncomeItem> incomeItems = const [];
  int income = 0;
  int savingsActual = 0, savingsPlanned = 0;
  int get savings => savingsActual + savingsPlanned;
  List<Spend> spendList = const [];
  int spent = 0, spentCard = 0, estSpend = 0;
  int free = 0;
  int? incomeRest;
  int? safe;
  int get debtPay => taksit + kart;
  double? get load => income > 0 ? debtPay / income : null;

  int groupTotal(String g) => switch (g) {
        'taksit' => taksit,
        'sabit' => sabit,
        'abonelik' => abonelik,
        'kart' => kart,
        _ => 0,
      };

  void _add(String g, int k) {
    switch (g) {
      case 'taksit':
        taksit += k;
      case 'sabit':
        sabit += k;
      case 'abonelik':
        abonelik += k;
      case 'kart':
        kart += k;
    }
  }
}

class Upcoming {
  const Upcoming(this.item, this.month, this.date, this.late);
  final PlanItem item;
  final String month;
  final String date;
  final bool late;
}

class NextPayment {
  const NextPayment(this.month, this.amount, this.items);
  final String month;
  final int amount;
  final List<PlanItem> items;
}

class PurchaseState {
  const PurchaseState(this.list, this.billedN, this.remainK);
  final List<Installment> list;
  final int billedN;
  final int remainK;
  int get monthly => list.isEmpty ? 0 : list.first.k;
  String? get end => list.isEmpty ? null : list.last.month;
  bool get done => remainK == 0;
}

/// Bir veri kopyası için bütün hesaplar (ay kalemleri ve özetleri hafızada tutulur).
class Ctx {
  Ctx(this.data, {String? month})
      : cur = month ?? currentMonth() {
    model = buildModel(data, cur);
    est = spendEstimate(data, cur);
  }

  final Data data;
  final String cur;
  late final Model model;
  late final SpendEstimate est;
  final Map<String, List<PlanItem>> _items = {};
  final Map<String, MonthSummary> _sums = {};

  List<PlanItem> items(String m) => _items[m] ??= _monthItems(m);
  MonthSummary sum(String m) => _sums[m] ??= _monthSummary(m);

  bool _carriedFrom(MonthClose? cl, String kind, String id, String m) {
    if (cl == null) return false;
    return cl.carry.any((c) => c.kind == kind && c.refId == id && c.from == m);
  }

  /// Bir ayın planlı çıkış kalemleri. Bağlı gider (linkedDebtIds) aktifse o borçların ödemesi
  /// ayrıca eklenmez. Kredi kartı: o ayın ekstresi girildiyse ekstre kalemi; girilmediyse
  /// "ekstre bekleniyor" kalemi (bilinen taksitler en az tutar olarak). Abonelik: bu aydan
  /// itibaren, aylık payıyla; karttan ödenen abonelik, kartın o ay ekstresi girilmişse ekstrenin
  /// içinde sayılır.
  List<PlanItem> _monthItems(String m) {
    final d = data;
    final mm = model;
    final items = <PlanItem>[];
    final activeRec = d.recurringExpenses.where((r) => isMonth(r.startMonth) && r.activeIn(m)).toList();
    final covered = <String>{for (final r in activeRec) ...r.linkedDebtIds};
    final cl = d.closeOf(m);
    for (final debt in d.debts) {
      if (covered.contains(debt.id)) continue;
      final dInfo = mm.debts[debt.id];
      final pm = dInfo?.months[m];
      final pay = mm.pay('debt', debt.id, m);
      final bank = bankKeyOf(debt);
      if (debt.isCard) {
        final st = pm?.st;
        var instK = 0;
        for (final p in mm.byCard[debt.id] ?? const <Spend>[]) {
          for (final it in mm.insts[p.id] ?? const <Installment>[]) {
            if (it.month == m) instK += it.k;
          }
        }
        final name = debt.creditor.isEmpty ? 'Kredi kartı' : debt.creditor;
        if (st != null) {
          items.add(PlanItem(
            kind: 'debt', refId: debt.id, name: name, group: 'kart', category: '__kart__',
            planned: pm!.planned, pay: pay, bank: bank, card: true, instK: instK, st: st, day: debt.dueDay,
          ));
        } else if (pay != null ||
            ((m.compareTo(cur) >= 0 || _carriedFrom(cl, 'debt', debt.id, m)) &&
                dInfo != null &&
                (dInfo.current > 0 || instK > 0))) {
          // Ekstre girilmedi: asgari ödeme tahmini (borcun %20'si; bilinen taksitler fazlaysa onlar)
          final estK = dInfo != null ? math.max(instK, ((dInfo.current * kMinPayRate) / 100).round() * 100) : instK;
          items.add(PlanItem(
            kind: 'debt', refId: debt.id, name: name, group: 'kart', category: '__kart__',
            planned: pay != null ? pay.k : estK, pay: pay, bank: bank, card: true, instK: instK, estK: estK,
            pending: pay == null, est: pay == null, day: debt.dueDay ?? debt.statementDay,
          ));
        }
        continue;
      }
      final planned = pm?.planned ?? 0;
      if (planned > 0 || pay != null) {
        items.add(PlanItem(
          kind: 'debt', refId: debt.id, name: debt.creditor.isEmpty ? 'belirtilmemiş' : debt.creditor,
          group: 'taksit', category: '__borc__', planned: planned, pay: pay, bank: bank, day: debt.payDay,
        ));
      }
    }
    for (final r in activeRec) {
      final linked = r.linkedDebtIds;
      final linkedBank = linked.length == 1 ? bankKeyOf(d.debt(linked.first)) : null;
      items.add(PlanItem(
        kind: 'expense', refId: r.id, name: r.name.isEmpty ? 'belirtilmemiş' : r.name,
        group: r.category == 'kart_asgari' ? 'kart' : 'sabit', category: r.category, planned: toK(r.amount),
        pay: mm.pay('expense', r.id, m), linked: linked, bank: linkedBank, day: r.day, rec: true,
      ));
    }
    for (final s in d.subscriptions) {
      final pay = mm.pay('sub', s.id, m);
      final k = subAmountK(s, m);
      if (pay == null && (!s.active || k <= 0 || (m.compareTo(cur) < 0 && !_carriedFrom(cl, 'sub', s.id, m)))) continue;
      final cid = srcCard(s.source);
      final aid = srcAcc(s.source);
      if (pay == null && cid != null) {
        final pm = mm.debts[cid]?.months[m];
        if (pm?.st != null) continue;
      }
      final String? bank;
      if (cid != null) {
        bank = bankKeyOf(d.debt(cid));
      } else if (aid != null) {
        final a = d.account(aid);
        bank = a == null || a.bank.isEmpty ? null : a.bank;
      } else {
        bank = null;
      }
      items.add(PlanItem(
        kind: 'sub', refId: s.id, name: s.name.isEmpty ? 'Abonelik' : s.name, group: 'abonelik',
        category: s.isBill ? 'fatura' : 'abonelik', planned: k, pay: pay, bank: bank, day: s.day, sub: true,
        viaCard: cid != null, bill: s.isBill, monthSet: s.monthAmounts.containsKey(m),
      ));
    }
    // Önceki ay kapatılırken bu aya taşınan ödenmemiş kalemler (ödeme yine kalemin asıl ayına yazılır)
    final pmonth = addM(m, -1);
    final pc = d.closeOf(pmonth);
    if (pc != null && pc.carry.isNotEmpty) {
      final prev = this.items(pmonth);
      for (final c in pc.carry) {
        for (final orig in prev) {
          if (orig.kind == c.kind && orig.refId == c.refId && (orig.fromMonth ?? pmonth) == c.from) {
            items.add(orig.carried(c.from));
            break;
          }
        }
      }
    }
    return items;
  }

  MonthSummary _monthSummary(String m) {
    final list = items(m);
    final s = MonthSummary(m, list);
    final close = data.closeOf(m);
    s.close = close;
    final out = close == null ? null : {for (final c in close.carry) '${c.kind}|${c.refId}|${c.from}'};
    for (final it in list) {
      if (out != null && out.contains(it.key(m))) {
        it.carriedOut = true;
        s.carriedK += it.planned;
        continue;
      }
      if (it.est) s.estK += it.planned;
      final k = it.pay?.k ?? it.planned; // ödendiyse gerçekte ödenen tutar
      s.total += k;
      s._add(it.group, k);
      final p = it.pay;
      if (p != null) {
        s.paid += p.k;
      } else {
        s.unpaid += it.planned;
      }
      if (it.pending) s.pendingCards++;
    }
    final due = list.where((it) => it.planned > 0 && !it.carriedOut).toList();
    s.allPaid = due.isNotEmpty && due.every((it) => it.pay != null);
    final prevClose = data.closeOf(addM(m, -1));
    s.carryIn = prevClose != null && prevClose.carryCash ? sum(addM(m, -1)).free : 0;
    s.incomeItems = incomeFor(data, m);
    s.income = sumK(s.incomeItems, (IncomeItem x) => x.k);
    s.savingsActual = sumK(data.goalContributions.where((c) => c.month == m), (GoalContribution c) => toK(c.amount));
    s.savingsPlanned = m.compareTo(cur) > 0 ? (model.projByMonth[m] ?? 0) : 0;
    final sp = spendsIn(data, m);
    s.spendList = sp;
    s.spent = sumK(sp.where((x) => srcCard(x.source) == null), (Spend x) => toK(x.amount));
    s.spentCard = sumK(sp.where((x) => srcCard(x.source) != null), (Spend x) => toK(x.amount));
    s.estSpend = m.compareTo(cur) > 0 ? est.k : 0;
    s.free = s.income + s.carryIn - s.total - s.savings - s.spent - s.estSpend;
    if (m == cur) {
      // Ay sonuna kadar serbest: hesaplardaki para + bu ay henüz yatmamış gelir − ödenmemiş kalemler.
      // Günü geçse de "yattı" denmemiş gelir beklenen sayılır (eski uygulamada günü geçince düşüyordu);
      // yattığı onaylanınca hesaba eklenir, buradan çıkar. Zilde "Maaşın yattı mı?" diye sorulur.
      final rest = sumK(
        s.incomeItems.where((i) => !i.actual && !i.oneOff),
        (IncomeItem i) => i.k,
      );
      s.incomeRest = rest;
      s.safe = model.liquid + rest - s.unpaid;
    }
    return s;
  }

  /// Önümüzdeki günlerin ödemeleri: ödenmemiş, günü belli kalemler; bu ayın gecikenleri de.
  List<Upcoming> upcoming(int days) {
    final today = todayISO();
    final end = addDays(today, days);
    final out = <Upcoming>[];
    for (final m in [cur, addM(cur, 1)]) {
      if (data.closeOf(m) != null) continue;
      final nD = daysInMonth(m);
      for (final it in sum(m).items) {
        final day = it.day;
        if (it.pay != null || it.carriedOut || it.planned <= 0 || day == null) continue;
        final date = '$m-${two(math.min(day, nD))}';
        if (date.compareTo(end) > 0 || (date.compareTo(today) < 0 && m != cur)) continue;
        out.add(Upcoming(it, m, date, date.compareTo(today) < 0));
      }
    }
    out.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : b.item.planned - a.item.planned;
    });
    return out;
  }

  NextPayment? nextPayment() {
    final start = maxMonth(cur, model.base);
    for (var i = 0; i < 48; i++) {
      final m = addM(start, i);
      if (data.closeOf(m) != null) continue;
      final open = items(m).where((it) => it.pay == null && it.planned > 0).toList();
      if (open.isNotEmpty) return NextPayment(m, sumK(open, (PlanItem it) => it.planned), open);
    }
    return null;
  }

  List<(String, int)> overdueMonths() {
    final out = <(String, int)>[];
    for (var i = mIdx(model.base); i < mIdx(cur); i++) {
      final m = mFromIdx(i);
      if (data.closeOf(m) != null) continue;
      final c = items(m).where((it) => it.pay == null && it.planned > 0).length;
      if (c > 0) out.add((m, c));
    }
    return out;
  }

  String defaultPlanMonth() {
    var m = maxMonth(cur, model.base);
    for (var i = 0; i < 24 && data.closeOf(m) != null; i++) {
      m = addM(m, 1);
    }
    return m;
  }
}

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

/// Son kullanılan ödeme hesabı (aynı kalem için).
String? lastFromFor(Data data, String kind, String refId) {
  final list = data.payments
      .where((p) =>
          p.kind == kind &&
          p.refId == refId &&
          p.fromAccount != null &&
          p.viaRefId == null &&
          data.account(srcAcc(p.fromAccount)) != null)
      .toList();
  if (list.isEmpty) return null;
  list.sort((a, b) => (a.paidDate ?? '').compareTo(b.paidDate ?? ''));
  return list.last.fromAccount;
}

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

/// Kurulumda "bu ayki ödemesi yapılmış" işareti konmuş mu (hesaptan düşülmeyen ödeme)?
bool paidBeforeStart(Data d, String kind, String id) {
  final m = currentMonth();
  return d.payments.any((p) => p.kind == kind && p.refId == id && p.month == m && p.fromAccount == null && p.viaRefId == null);
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

// ---------------------------------------------------------------- İstek listesi ve birikim

List<Goal> activeGoalsSorted(Data d) {
  final indexed = [
    for (var i = 0; i < d.goals.length; i++)
      if (d.goals[i].isActive) (d.goals[i], i),
  ];
  indexed.sort((a, b) {
    final c = (kPriorityOrder[a.$1.priority] ?? 1) - (kPriorityOrder[b.$1.priority] ?? 1);
    return c != 0 ? c : a.$2 - b.$2;
  });
  return [for (final x in indexed) x.$1];
}

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
