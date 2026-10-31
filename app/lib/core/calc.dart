// Mel Capital — hesap modeli: bütün sayfalar aynı hesaptan beslenir (eski uygulamadaki app3.js).
//
// Hesap bakiyesi: hesabın kendi bakiyesidir. Hesaptan yapılan harcama, aktarma ve ödeme
// kaydedilirken bakiyeden düşülür; kayıt silinir ya da değişirse geri eklenir.
// Kart bakiyesi: debt.remaining, debt.balanceDate tarihindeki güncel borçtur. O tarihten sonra
// (aynı gün girilenlerde bakiye güncellemesinden sonra) yapılan ödemeler düşülür, harcamalar
// eklenir. balanceDate yoksa (yapılandırma, kredi) remaining, balancesAsOf ayının başındaki bakiyedir.

import 'dart:math' as math;

import 'constants.dart';
import 'model.dart';
import 'normalize.dart' show nextStatementMonthFor;
import 'util.dart';

// ---------------------------------------------------------------- Küçük hesaplar

int schedK(List<Sched> sched, String m) {
  for (final s in sched) {
    if (s.from.compareTo(m) <= 0 && (s.to == null || m.compareTo(s.to!) <= 0)) return toK(s.amount);
  }
  return 0;
}

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

int subMonthlyK(Subscription s) {
  final a = s.amount;
  if (a == null) return 0;
  final k = toK(a);
  return s.period == 'yil' ? (k / 12).round() : k;
}

/// Faturalar gibi her ay değişen tutarlar: o aya girilmiş tutar varsa o, yoksa her zamanki fiyat.
int subAmountK(Subscription s, String m) {
  final v = s.monthAmounts[m];
  return v != null ? toK(v) : subMonthlyK(s);
}

String? bankKeyOf(Debt? debt) {
  if (debt == null) return null;
  if (debt.bank.isNotEmpty && kBanks.containsKey(debt.bank)) return debt.bank;
  return detectBank(debt.creditor) ?? (debt.bank.isEmpty ? null : debt.bank);
}

// ---------------------------------------------------------------- Model

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
  final cardSubs = <String, int>{};
  for (final s in d.subscriptions) {
    final cid = srcCard(s.source);
    final k = subMonthlyK(s);
    if (cid != null && s.active && k > 0) cardSubs[cid] = (cardSubs[cid] ?? 0) + k;
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
  final liquid = sumK(d.accounts, (Account a) => toK(a.balance));
  final cash = sumK(d.accounts.where((a) => a.isCash), (Account a) => toK(a.balance));
  final subsMonthly = sumK(d.subscriptions.where((s) => s.active), subMonthlyK);
  return Model(
    cur: cur,
    base: base,
    maxM: maxM,
    payIdx: payIdx,
    insts: insts,
    byCard: byCard,
    debts: debts,
    totalRemaining: totalRemaining,
    cardDebt: cardDebt,
    cardLimit: cardLimit,
    cardAvail: cardAvail,
    cardCount: cardCount,
    loanDebt: loanDebt,
    debtFree: debtFree,
    liquid: liquid,
    cash: cash,
    goals: goals,
    projByMonth: projByMonth,
    subsMonthly: subsMonthly,
  );
}

// ---------------------------------------------------------------- Ay kalemleri

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

class IncomeItem {
  const IncomeItem({
    required this.id,
    required this.name,
    required this.k,
    this.payDay,
    this.planned = 0,
    this.actual = false,
    this.oneOff = false,
  });
  final String id;
  final String name;
  final int k;
  final int? payDay;
  final int planned;
  final bool actual;
  final bool oneOff;
}

List<IncomeItem> incomeFor(Data d, String m) {
  final list = <IncomeItem>[];
  for (final inc in d.incomes) {
    final planned = schedK(inc.schedule, m);
    final a = inc.monthAmounts[m];
    final act = a == null ? null : toK(a);
    final k = act ?? planned;
    if (k > 0 || act != null) {
      list.add(IncomeItem(id: inc.id, name: inc.name, k: k, payDay: inc.payDay, planned: planned, actual: act != null));
    }
  }
  for (final o in d.oneOffIncomes) {
    if (isDate(o.date) && monthOf(o.date) == m) {
      list.add(IncomeItem(id: o.id, name: o.name, k: toK(o.amount), payDay: dayOf(o.date), oneOff: true));
    }
  }
  return list;
}

List<Spend> spendsIn(Data d, String m) =>
    d.spends.where((s) => isDate(s.date) && monthOf(s.date) == m).toList();

const Set<String> _estExclude = {'kira', 'kart_asgari'};

int variableSpentK(Data d, String m) => sumK(
      spendsIn(d, m).where((x) => srcCard(x.source) == null && !_estExclude.contains(x.category)),
      (Spend x) => toK(x.amount),
    );

class SpendEstimate {
  const SpendEstimate(this.k, this.manual, this.auto, this.basisMonths, this.basisThisMonth);
  final int k;
  final bool manual;
  final int? auto;
  final List<String> basisMonths;
  final bool basisThisMonth;
}

/// Günlük (değişken) harcama tahmini: hesaptan ya da nakit yapılan harcamaların (kira hariç)
/// son üç ayın ortalaması; Plan'dan elle de girilebilir (meta.spendEstimate).
SpendEstimate spendEstimate(Data d, String cur) {
  final manRaw = d.meta['spendEstimate'];
  final man = manRaw is num ? toK(manRaw) : null;
  final months = <(String, int)>[];
  for (var i = 1; i <= 12 && months.length < 3; i++) {
    final m = addM(cur, -i);
    final k = variableSpentK(d, m);
    if (k > 0) months.add((m, k));
  }
  int? auto;
  var basis = <String>[];
  var thisMonth = false;
  if (months.isNotEmpty) {
    auto = (sumK(months, ((String, int) x) => x.$2) / months.length).round();
    basis = months.reversed.map((x) => x.$1).toList();
  } else {
    final day = dayOf(todayISO());
    final k = variableSpentK(d, cur);
    if (k > 0 && day >= 20) {
      auto = k;
      basis = [cur];
      thisMonth = true;
    }
  }
  return SpendEstimate(man ?? auto ?? 0, man != null, auto, basis, thisMonth);
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

class LearnedSpend {
  const LearnedSpend(this.cat, this.k, this.source, this.place, this.name, this.date);
  final String cat;
  final int k;
  final String? source;
  final String place;
  final String name;
  final String date;
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
      // Ay sonuna kadar serbest: hesaplardaki para + bu ay henüz yatmamış gelir − ödenmemiş kalemler
      final td = dayOf(todayISO());
      final rest = sumK(
        s.incomeItems.where((i) => !i.actual && !i.oneOff && i.payDay != null && i.payDay! > td),
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

// ---------------------------------------------------------------- Geçmişten öğrenme

Map<String, LearnedSpend> learnIndex(Data d) {
  final idx = <String, LearnedSpend>{};
  final sorted = d.spends.toList()
    ..sort((a, b) => ('${a.date}${a.createdAt ?? ''}').compareTo('${b.date}${b.createdAt ?? ''}'));
  for (final x in sorted) {
    final v = LearnedSpend(x.category, toK(x.amount), x.source, x.place, x.name, x.date);
    for (final t in [x.name, x.place]) {
      final n = normTxt(t);
      if (n.length >= 2) idx[n] = v;
    }
  }
  return idx;
}

/// Aynı adla (ya da yerle) en son girilen harcamanın kategorisi, tutarı, kaynağı.
LearnedSpend? learned(Data d, String? text, [Map<String, LearnedSpend>? index]) {
  final n = normTxt(text);
  if (n.isEmpty) return null;
  final idx = index ?? learnIndex(d);
  final hit = idx[n];
  if (hit != null) return hit;
  final first = n.split(' ').first;
  if (first.length >= 4) return idx[first];
  return null;
}

String smartCategory(Data d, String? text, [Map<String, LearnedSpend>? index]) =>
    learned(d, text, index)?.cat ?? guessCategory(text);

// ---------------------------------------------------------------- Kaynaklar (hesap ya da kart)

String accLabel(Account? a, String lang) {
  if (a == null) return lang == 'tr' ? 'silinmiş hesap' : 'deleted account';
  if (a.isCash) return a.name;
  if (a.bank.isNotEmpty && kBanks.containsKey(a.bank)) {
    final bn = bankName(a.bank, lang);
    return a.name.startsWith(bn) ? a.name : '$bn · ${a.name}';
  }
  return a.name;
}

String sourceName(Data d, String? src, String lang) {
  final aid = srcAcc(src);
  final cid = srcCard(src);
  if (aid != null) return accLabel(d.account(aid), lang);
  if (cid != null) {
    final x = d.debt(cid);
    return x != null ? x.creditor : (lang == 'tr' ? 'silinmiş kart' : 'deleted card');
  }
  return '';
}

class SourceBank {
  const SourceBank(this.key, this.name, {this.cash = false});
  final String? key;
  final String name;
  final bool cash;
}

SourceBank? sourceBank(Data d, String? src) {
  final aid = srcAcc(src);
  final cid = srcCard(src);
  if (aid != null) {
    final a = d.account(aid);
    return a == null ? null : SourceBank(a.bank.isEmpty ? null : a.bank, a.name, cash: a.isCash);
  }
  if (cid != null) {
    final x = d.debt(cid);
    return x == null ? null : SourceBank(bankKeyOf(x), x.creditor);
  }
  return null;
}

/// Hesap bakiyesini kuruş cinsinden değiştirir (kaynak "acc:" değilse bir şey yapmaz).
void accAdjust(Data data, String? src, int deltaK) {
  final aid = srcAcc(src);
  if (aid == null || deltaK == 0) return;
  final a = data.account(aid);
  if (a == null) return;
  a.balance = fromK(toK(a.balance) + deltaK);
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

/// En çok kullanılan harcama kaynağı (varsayılan seçim için).
String? favSource(Data data) {
  final cnt = <String, int>{};
  final spends = data.spends;
  for (final s in spends.skip(math.max(0, spends.length - 40))) {
    final src = s.source;
    if (src != null) cnt[src] = (cnt[src] ?? 0) + 1;
  }
  String? best;
  var n = 0;
  cnt.forEach((k, v) {
    if (v > n && !sourceName(data, k, 'tr').contains('silinmiş')) {
      best = k;
      n = v;
    }
  });
  if (best != null) return best;
  if (data.accounts.isEmpty) return null;
  final rich = data.accounts.toList()..sort((a, b) => b.balance.compareTo(a.balance));
  return 'acc:${rich.first.id}';
}

List<RecurringExpense> linkedExpenses(Data d, String debtId) =>
    d.recurringExpenses.where((r) => r.linkedDebtIds.contains(debtId)).toList();

BankCard? physicalCardOf(Data d, String debtId) {
  for (final c in d.cards) {
    if (c.debtId == debtId) return c;
  }
  return null;
}

List<Findeks> findeksSorted(Data d) {
  final indexed = [for (var i = 0; i < d.findeks.length; i++) (d.findeks[i], i)];
  indexed.sort((a, b) {
    final c = a.$1.date.compareTo(b.$1.date);
    return c != 0 ? c : a.$2 - b.$2;
  });
  return [for (final x in indexed) x.$1];
}

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

// ---------------------------------------------------------------- Hareketler

/// Harcamalar, aktarmalar ve ödemeler tek listede (yeniden eskiye).
class Movement {
  const Movement({
    required this.t,
    required this.id,
    required this.date,
    required this.at,
    required this.k,
    required this.name,
    this.place = '',
    this.src,
    this.from,
    this.cat,
    this.inst = 0,
    this.kind,
    this.ref,
    this.month,
  });

  final String t; // spend | transfer | pay
  final String id;
  final String date;
  final String at;
  final int k;
  final String name;
  final String place;
  final String? src;
  final String? from;
  final String? cat;
  final int inst;
  final String? kind;
  final String? ref;
  final String? month;
}

List<Movement> movements(Data d, String lang) {
  final out = <Movement>[];
  for (final s in d.spends) {
    out.add(Movement(
      t: 'spend', id: s.id, date: s.date, at: s.createdAt ?? '', k: -toK(s.amount),
      name: s.name.isEmpty ? catLabel(s.category, lang) : s.name, place: s.place, src: s.source, cat: s.category,
      inst: srcCard(s.source) != null && s.installments > 1 ? s.installments : 0,
    ));
  }
  for (final t in d.transfers) {
    out.add(Movement(
      t: 'transfer', id: t.id, date: t.date, at: t.createdAt ?? '', k: toK(t.amount),
      name: t.external ? (lang == 'tr' ? 'Para girişi' : 'Money in') : (lang == 'tr' ? 'Aktarma' : 'Transfer'),
      src: t.to, from: t.from,
    ));
  }
  for (final p in d.payments) {
    if (p.viaRefId != null || !isDate(p.paidDate)) continue;
    var name = lang == 'tr' ? 'Ödeme' : 'Payment';
    if (p.kind == 'debt') {
      name = d.debt(p.refId)?.creditor ?? (lang == 'tr' ? 'Borç' : 'Debt');
    } else if (p.kind == 'expense') {
      name = d.expense(p.refId)?.name ?? (lang == 'tr' ? 'Gider' : 'Expense');
    } else if (p.kind == 'sub') {
      name = d.subscription(p.refId)?.name ?? (lang == 'tr' ? 'Abonelik' : 'Subscription');
    }
    out.add(Movement(
      t: 'pay', id: p.id, kind: p.kind, ref: p.refId, month: p.month, date: p.paidDate!,
      at: p.createdAt ?? '', k: -toK(p.paidAmount), name: name, src: p.fromAccount,
    ));
  }
  out.sort((a, b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.at.compareTo(a.at);
  });
  return out;
}
