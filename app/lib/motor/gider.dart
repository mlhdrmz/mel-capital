// Mel Capital — GİDER MOTORU
//
// Harcamalar (tek tek, hızlı giriş, taksitli kart harcaması), abonelikler ve faturalar, sabit
// giderler (kira gibi), günlük harcama tahmini, geçmişten kategori öğrenme.
// Yazar: harcamalar, abonelikler, sabit giderler. Hesaptan yapılan harcama Çekirdek'teki
// [accAdjust] ile bakiyeden düşer; karttan yapılan harcamayı Borç Motoru kart borcuna ekler
// (ayrıca bir kayıt yazılmaz, aynı harcama kaydını okur).
// Kullananlar: Plan Motoru (ayın harcamaları ve tahmin), Borç Motoru (kart harcamaları).

import 'dart:math' as math;

import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'cekirdek.dart';
import 'plan.dart';

// ---------------------------------------------------------------- Abonelik ve fatura tutarları

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

/// Aktif aboneliklerin aylık toplamı (kuruş).
int subsMonthlyK(Data d) => sumK(d.subscriptions.where((s) => s.active), subMonthlyK);

// ---------------------------------------------------------------- Ayın harcamaları ve tahmin

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

// ---------------------------------------------------------------- Harcama listesi

/// Harcama listesindeki bir satır: harcama ya da o ayki abonelik/fatura.
class SpendLine {
  const SpendLine({
    required this.id,
    required this.name,
    required this.date,
    required this.k,
    required this.category,
    this.source,
    this.place = '',
    this.createdAt = '',
    this.installments = 1,
    this.note = '',
    this.isSub = false,
  });

  factory SpendLine.of(Spend x) => SpendLine(
        id: x.id,
        name: x.name,
        date: x.date,
        k: toK(x.amount),
        category: x.category,
        source: x.source,
        place: x.place,
        createdAt: x.createdAt ?? '',
        installments: x.installments,
        note: x.note,
      );

  final String id;
  final String name;
  final String date;
  final int k;
  final String category;
  final String? source;
  final String place;
  final String createdAt;
  final int installments;
  final String note;
  final bool isSub;
}

/// Yeniden eskiye (aynı gün: sonra girilen önce).
int spendLinesNewestFirst(SpendLine a, SpendLine b) {
  final c = b.date.compareTo(a.date);
  return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
}

/// Ödenen abonelik ve faturalar ödendikleri gün gider olarak görünür (ödenen tutarla). Ödendiği
/// onaylanmamış olanlar günü geçse de harcamaya sayılmaz: zilde ve Plan'da "Ödedin mi?" diye sorulur.
List<SpendLine> subSpendsIn(Ctx ctx, String m) {
  final d = ctx.data;
  final out = <SpendLine>[];
  if (m.compareTo(ctx.cur) > 0) return out;
  final nD = daysInMonth(m);
  for (final s in d.subscriptions) {
    final pay = ctx.model.pay('sub', s.id, m);
    if (pay == null) continue;
    final dayISO = '$m-${two(math.min(s.day ?? 1, nD))}';
    final pd = pay.paidDate;
    final date = pd != null && isDate(pd) && monthOf(pd) == m ? pd : dayISO;
    var src = s.source;
    for (final p in pay.list) {
      if (p.fromAccount != null) {
        src = p.fromAccount;
        break;
      }
    }
    out.add(SpendLine(id: s.id, name: s.name, date: date, k: pay.k, source: src, category: s.isBill ? 'fatura' : 'abonelik', isSub: true));
  }
  return out;
}

/// Arama: ad, yer, not, kategori, kaynak; tutar yazılırsa o tutardaki harcamalar. Tüm aylarda.
List<SpendLine> spendSearch(Data d, String q, String lang) {
  final nq = normTxt(q);
  if (nq.isEmpty) return const [];
  final k = RegExp(r'^[\d.,\s]+(tl)?$', caseSensitive: false).hasMatch(q.trim()) ? parseAmount(q) : null;
  final words = nq.split(' ');
  final out = <SpendLine>[];
  for (final x in d.spends) {
    if (k != null && toK(x.amount) == k) {
      out.add(SpendLine.of(x));
      continue;
    }
    final hay = normTxt([x.name, x.place, x.note, catLabel(x.category, lang), sourceName(d, x.source, lang)].join(' '));
    if (words.every(hay.contains)) out.add(SpendLine.of(x));
  }
  out.sort(spendLinesNewestFirst);
  return out.take(300).toList();
}

// ---------------------------------------------------------------- Geçmişten öğrenme

class LearnedSpend {
  const LearnedSpend(this.cat, this.k, this.source, this.place, this.name, this.date);
  final String cat;
  final int k;
  final String? source;
  final String place;
  final String name;
  final String date;
}

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

// ---------------------------------------------------------------- Harcama kayıtları

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

/// Günlük harcama tahmini (null: otomatik).
void setSpendEstimate(Data data, int? k) {
  if (k == null) {
    data.meta.remove('spendEstimate');
  } else {
    data.meta['spendEstimate'] = fromK(k);
  }
}

// ---------------------------------------------------------------- Abonelik ve fatura kayıtları

/// Aboneliği dondurur ya da devam ettirir; yeni durumu döndürür.
bool toggleSubscription(Data data, String id) {
  final s = data.subscription(id);
  if (s == null) return false;
  final next = !s.active;
  s.j['active'] = next;
  return next;
}

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

// ---------------------------------------------------------------- Sabit giderler

List<RecurringExpense> linkedExpenses(Data d, String debtId) =>
    d.recurringExpenses.where((r) => r.linkedDebtIds.contains(debtId)).toList();

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
