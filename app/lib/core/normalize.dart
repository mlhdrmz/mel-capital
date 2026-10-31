// Mel Capital — veri denetimi ve düzenleme (eski uygulamadaki normalizeData'nın karşılığı).
//
// Dosyadan, yedekten ya da eşitlemeden gelen veriyi denetler; eksik alanları tamamlar,
// geçersiz bağlantıları temizler. Bilinmeyen alanlar korunur. Sürüm 4 biçimini okur.

import 'model.dart';
import 'util.dart';

const int kDataVersion = 4;

class NormalizeResult {
  NormalizeResult(this.data, this.errors);
  final Data? data;
  final List<String> errors;
  bool get ok => data != null && errors.isEmpty;
}

const Set<String> _accountTypes = {'vadesiz', 'nakit', 'on_odemeli', 'cuzdan', 'birikim', 'diger'};
const Set<String> _subGroups = {
  'fatura', 'video', 'muzik', 'yz', 'guvenlik', 'is', 'yemek', 'yayin', 'iletisim', 'oyun', 'bulut', 'spor', 'diger',
};
const Set<String> _cardKinds = {'banka', 'kredi', 'on_odemeli'};
const Set<String> _patterns = {'none', 'lines', 'waves', 'dots', 'rings', 'geo', 'glow', 'confetti'};
const Set<String> _inks = {'light', 'dark', 'gold'};
final RegExp _color = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Boş bir veri (yeni profil).
Data emptyData() => Data({
      'version': kDataVersion,
      'balancesAsOf': currentMonth(),
      'debts': <Json>[],
      'recurringExpenses': <Json>[],
      'incomes': <Json>[],
      'oneOffIncomes': <Json>[],
      'spends': <Json>[],
      'transfers': <Json>[],
      'subscriptions': <Json>[],
      'goals': <Json>[],
      'goalContributions': <Json>[],
      'payments': <Json>[],
      'findeks': <Json>[],
      'accounts': <Json>[
        {'id': 'elde-nakit', 'bank': '', 'name': 'Elde nakit', 'type': 'nakit', 'balance': 0, 'asOf': null, 'note': ''},
      ],
      'cards': <Json>[],
      'monthCloses': <Json>[],
      'findeksReport': null,
      'meta': <String, dynamic>{'lastBackupAt': null, 'billsSplit': true},
    });

bool _isAmt(Object? v) => v is num && v.isFinite && v >= 0;
bool _isNum(Object? v) => v is num && v.isFinite;
String _str(Object? v) => v == null ? '' : v.toString();
Object? _optNull(Object? v) => (v == null || v == '') ? null : v;
String? _optISO(Object? v) => v is String && DateTime.tryParse(v) != null ? v : null;

Map<String, dynamic> _amtMap(Object? v) {
  if (v is! Map) return {};
  return {
    for (final e in v.entries)
      if (isMonth(e.key) && _isAmt(e.value)) e.key.toString(): e.value,
  };
}

Json _copy(Object? x) => {for (final e in (x as Map).entries) e.key.toString(): deepCopy(e.value)};

/// Kart harcamasının ilk taksitinin düşeceği ekstre (son ödeme) ayı.
String nextStatementMonthFor(Json? debt, String? date) {
  final d = isDate(date) ? date! : todayISO();
  final dm = d.substring(0, 7);
  final day = int.parse(d.substring(8, 10));
  final stDay = debt == null ? null : (debt['statementDay'] is num ? (debt['statementDay'] as num).toInt() : null);
  if (stDay == null) return addM(dm, 1);
  final cutM = day <= stDay ? dm : addM(dm, 1);
  final dueDay = debt!['dueDay'] is num ? (debt['dueDay'] as num).toInt() : null;
  return dueDay != null && dueDay < stDay ? addM(cutM, 1) : cutM;
}

NormalizeResult normalizeData(Object? raw) {
  final errors = <String>[];
  if (raw is! Map) return NormalizeResult(null, ['Veri bir JSON nesnesi değil.']);
  final src = raw.cast<String, dynamic>();

  List<dynamic> list(String key) {
    final v = src[key];
    if (v == null) return const [];
    if (v is! List) {
      errors.add('"$key" bir dizi olmalı.');
      return const [];
    }
    return v;
  }

  int? optDay(Object? v, String where, String field) {
    final x = _optNull(v);
    if (x == null) return null;
    if (x is num && x == x.roundToDouble() && x >= 1 && x <= 31) return x.toInt();
    errors.add('$where: "$field" 1–31 arası bir gün olmalı.');
    return null;
  }

  final ver = src['version'] ?? 1;
  if (ver != 4) {
    errors.add(ver is num && ver < 4
        ? 'Bu veri eski bir sürümden (sürüm $ver). Önce eski Mel Capital\'de açıp kaydedin.'
        : 'Desteklenmeyen sürüm: $ver');
  }
  if (!isMonth(src['balancesAsOf'])) errors.add('"balancesAsOf" YYYY-AA biçiminde olmalı (ör. 2026-10).');

  final out = <String, dynamic>{'version': kDataVersion, 'balancesAsOf': src['balancesAsOf']};

  void Function(String id, String where) idSet() {
    final seen = <String>{};
    return (id, where) {
      if (id.isEmpty) {
        errors.add('$where: "id" boş.');
      } else if (seen.contains(id)) {
        errors.add('$where: "$id" kimliği tekrar ediyor.');
      }
      seen.add(id);
    };
  }

  List<Json> checkSchedule(Object? sch, String where, bool allowOpen) {
    if (sch == null) return [];
    if (sch is! List) {
      errors.add('$where: "schedule" bir dizi olmalı.');
      return [];
    }
    final result = <Json>[];
    for (var j = 0; j < sch.length; j++) {
      final s = sch[j];
      final m = s is Map ? s : const {};
      final from = m['from'];
      final to = allowOpen ? _optNull(m['to']) : m['to'];
      final bad = s is! Map ||
          !isMonth(from) ||
          (to != null && (!isMonth(to) || (from as String).compareTo(to as String) > 0)) ||
          (!allowOpen && to == null) ||
          !_isAmt(m['amount']);
      if (bad) errors.add('$where.schedule[$j] geçersiz.');
      result.add({'from': from, 'to': to, 'amount': m['amount']});
    }
    return result;
  }

  // ---- Borçlar
  final debtCheck = idSet();
  final debts = <Json>[];
  final rawDebts = list('debts');
  for (var i = 0; i < rawDebts.length; i++) {
    final x = rawDebts[i];
    final w = 'debts[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    debtCheck(id, w);
    if (!_isAmt(x['remaining'])) errors.add('$w: "remaining" geçerli bir tutar değil.');
    final limit = _optNull(x['limit']);
    if (limit != null && !_isAmt(limit)) errors.add('$w: "limit" geçerli bir tutar değil.');
    final sch = checkSchedule(x['schedule'], w, false);
    var sts = x['statements'] ?? const [];
    if (sts is! List) {
      errors.add('$w: "statements" bir dizi olmalı.');
      sts = const [];
    }
    final seen = <String>{};
    final statements = <Json>[];
    for (var j = 0; j < (sts as List).length; j++) {
      final s = sts[j];
      if (s is! Map || !isMonth(s['month']) || !_isAmt(s['total'])) {
        errors.add('$w.statements[$j] geçersiz.');
        continue;
      }
      if (seen.contains(s['month'])) {
        errors.add('$w.statements[$j]: ${s['month']} ayı tekrar ediyor.');
        continue;
      }
      seen.add(s['month'] as String);
      final min = _optNull(s['minimum']);
      if (min != null && !_isAmt(min)) errors.add('$w.statements[$j]: "minimum" geçersiz.');
      statements.add({'month': s['month'], 'total': s['total'], 'minimum': min != null && _isAmt(min) ? min : null});
    }
    statements.sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
    final bd = _optNull(x['balanceDate']);
    if (bd != null && !isDate(bd)) errors.add('$w: "balanceDate" YYYY-AA-GG biçiminde olmalı.');
    debts.add(_copy(x)
      ..addAll({
        'id': id,
        'creditor': _str(x['creditor']),
        'bank': _str(x['bank']),
        'type': _str(x['type']),
        'remaining': x['remaining'],
        'limit': limit,
        'schedule': sch,
        'note': _str(x['note']),
        'payDay': optDay(x['payDay'], w, 'payDay'),
        'statementDay': optDay(x['statementDay'], w, 'statementDay'),
        'dueDay': optDay(x['dueDay'], w, 'dueDay'),
        'balanceDate': bd != null && isDate(bd) ? bd : null,
        'balanceAt': _optISO(x['balanceAt']),
        'payPlan': x['payPlan'] == 'tamami' ? 'tamami' : 'asgari',
        'statements': statements,
      }));
  }
  out['debts'] = debts;
  final debtIds = {for (final d in debts) d['id'] as String};
  final cardIds = {for (final d in debts) if (d['type'] == 'kredi_karti') d['id'] as String};
  Json? debtById(String id) {
    for (final d in debts) {
      if (d['id'] == id) return d;
    }
    return null;
  }

  // ---- Sabit giderler
  final expCheck = idSet();
  final expenses = <Json>[];
  final rawExp = list('recurringExpenses');
  for (var i = 0; i < rawExp.length; i++) {
    final x = rawExp[i];
    final w = 'recurringExpenses[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    expCheck(id, w);
    if (!_isAmt(x['amount'])) errors.add('$w: "amount" geçerli bir tutar değil.');
    if (!isMonth(x['startMonth'])) errors.add('$w: "startMonth" geçersiz.');
    final end = _optNull(x['endMonth']);
    if (end != null &&
        (!isMonth(end) || (isMonth(x['startMonth']) && (end as String).compareTo(x['startMonth'] as String) < 0))) {
      errors.add('$w: "endMonth" geçersiz.');
    }
    var linked = x['linkedDebtIds'] ?? const [];
    if (linked is! List) {
      errors.add('$w: "linkedDebtIds" bir dizi olmalı.');
      linked = const [];
    }
    expenses.add(_copy(x)
      ..addAll({
        'id': id,
        'name': _str(x['name']),
        'category': _str(x['category']),
        'amount': x['amount'],
        'startMonth': x['startMonth'],
        'endMonth': end,
        'day': optDay(x['day'], w, 'day'),
        'linkedDebtIds': [for (final v in linked as List) if (debtIds.contains(v.toString())) v.toString()],
        'note': _str(x['note']),
      }));
  }
  out['recurringExpenses'] = expenses;

  // ---- Gelirler
  final incCheck = idSet();
  final incomes = <Json>[];
  final rawInc = list('incomes');
  for (var i = 0; i < rawInc.length; i++) {
    final x = rawInc[i];
    final w = 'incomes[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    incCheck(id, w);
    incomes.add(_copy(x)
      ..addAll({
        'id': id,
        'name': _str(x['name']),
        'schedule': checkSchedule(x['schedule'], w, true),
        'payDay': optDay(x['payDay'], w, 'payDay'),
        'note': _str(x['note']),
        'monthAmounts': _amtMap(x['monthAmounts']),
      }));
  }
  out['incomes'] = incomes;
  final oneOff = <Json>[];
  final rawOne = list('oneOffIncomes');
  for (var i = 0; i < rawOne.length; i++) {
    final x = rawOne[i];
    final w = 'oneOffIncomes[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    incCheck(id, w);
    if (!_isAmt(x['amount'])) errors.add('$w: "amount" geçerli bir tutar değil.');
    if (!isDate(x['date'])) errors.add('$w: "date" geçersiz.');
    oneOff.add(_copy(x)..addAll({'id': id, 'name': _str(x['name']), 'amount': x['amount'], 'date': x['date']}));
  }
  out['oneOffIncomes'] = oneOff;

  // ---- Hesaplar
  final accCheck = idSet();
  final accounts = <Json>[];
  final rawAcc = list('accounts');
  for (var i = 0; i < rawAcc.length; i++) {
    final x = rawAcc[i];
    final w = 'accounts[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    accCheck(id, w);
    if (!_isNum(x['balance'])) errors.add('$w: "balance" geçerli bir tutar değil.');
    final asOf = _optNull(x['asOf']);
    if (asOf != null && !isDate(asOf)) errors.add('$w: "asOf" geçersiz.');
    accounts.add(_copy(x)
      ..addAll({
        'id': id,
        'bank': _str(x['bank']),
        'name': _str(x['name']),
        'type': _accountTypes.contains(x['type']) ? x['type'] : 'diger',
        'balance': x['balance'],
        'asOf': asOf,
        'note': _str(x['note']),
      }));
  }
  out['accounts'] = accounts;
  final accIds = {for (final a in accounts) a['id'] as String};

  String? cleanSrc(Object? v) {
    final s = _optNull(v);
    if (s is! String) return null;
    if (srcAcc(s) != null) return s;
    final c = srcCard(s);
    if (c != null) return cardIds.contains(c) ? s : null;
    return null;
  }

  // ---- Harcamalar
  final spendCheck = idSet();
  final spends = <Json>[];
  final rawSp = list('spends');
  for (var i = 0; i < rawSp.length; i++) {
    final x = rawSp[i];
    final w = 'spends[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    var id = _str(x['id']).trim();
    if (x['legacy'] == true && id.isEmpty) id = rid('h');
    spendCheck(id, w);
    if (!_isAmt(x['amount'])) errors.add('$w: "amount" geçerli bir tutar değil.');
    if (!isDate(x['date'])) errors.add('$w: "date" YYYY-AA-GG biçiminde olmalı.');
    final source = cleanSrc(x['source']);
    final instRaw = x['installments'];
    final n = instRaw is num && instRaw == instRaw.roundToDouble() && instRaw >= 1 && instRaw <= 60 ? instRaw.toInt() : 1;
    Object? first = _optNull(x['firstMonth']);
    if (first != null && !isMonth(first)) {
      errors.add('$w: "firstMonth" geçersiz.');
      first = null;
    }
    final cid = srcCard(source);
    if (cid != null && first == null && isDate(x['date'])) {
      first = nextStatementMonthFor(debtById(cid), x['date'] as String);
    }
    spends.add({
      'id': id,
      'date': x['date'],
      'name': _str(x['name']),
      'place': _str(x['place']),
      'category': _str(x['category']).isEmpty ? 'diger' : _str(x['category']),
      'amount': x['amount'],
      'source': source,
      'installments': cid != null ? n : 1,
      'firstMonth': cid != null ? first : null,
      'note': _str(x['note']),
      'url': _str(x['url']),
      'goalId': _optNull(x['goalId']),
      'createdAt': _optISO(x['createdAt']),
      'batch': _optNull(x['batch']),
      'updatedAt': _optISO(x['updatedAt']),
    });
  }
  out['spends'] = spends;

  // ---- Aktarmalar
  final trCheck = idSet();
  final transfers = <Json>[];
  final rawTr = list('transfers');
  for (var i = 0; i < rawTr.length; i++) {
    final x = rawTr[i];
    final w = 'transfers[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    trCheck(id, w);
    if (!_isAmt(x['amount'])) errors.add('$w: "amount" geçerli bir tutar değil.');
    if (!isDate(x['date'])) errors.add('$w: "date" geçersiz.');
    final from = x['from'] == 'ext' ? 'ext' : _str(x['from']);
    final to = _str(x['to']);
    if (from != 'ext' && srcAcc(from) == null) errors.add('$w: "from" geçersiz.');
    if (srcAcc(to) == null) errors.add('$w: "to" geçersiz.');
    final tr = <String, dynamic>{
      'id': id,
      'date': x['date'],
      'from': from,
      'to': to,
      'amount': x['amount'],
      'note': _str(x['note']),
      'createdAt': _optISO(x['createdAt']),
      'updatedAt': _optISO(x['updatedAt']),
    };
    if (x['incomeRef'] is String && (x['incomeRef'] as String).isNotEmpty) tr['incomeRef'] = x['incomeRef'];
    transfers.add(tr);
  }
  out['transfers'] = transfers;

  // ---- Abonelikler ve faturalar
  final subCheck = idSet();
  final subs = <Json>[];
  final rawSub = list('subscriptions');
  for (var i = 0; i < rawSub.length; i++) {
    final x = rawSub[i];
    final w = 'subscriptions[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    subCheck(id, w);
    final amount = _optNull(x['amount']);
    if (amount != null && !_isAmt(amount)) errors.add('$w: "amount" geçerli bir tutar değil.');
    subs.add({
      'id': id,
      'name': _str(x['name']),
      'group': _subGroups.contains(x['group']) ? x['group'] : 'diger',
      'amount': amount != null && _isAmt(amount) ? amount : null,
      'period': x['period'] == 'yil' ? 'yil' : 'ay',
      'day': optDay(x['day'], w, 'day'),
      'source': cleanSrc(x['source']),
      'active': x['active'] != false,
      'note': _str(x['note']),
      'monthAmounts': _amtMap(x['monthAmounts']),
      'updatedAt': _optISO(x['updatedAt']),
    });
  }
  out['subscriptions'] = subs;

  // ---- Hedefler (istek listesi)
  final goalCheck = idSet();
  final goals = <Json>[];
  final rawGoal = list('goals');
  for (var i = 0; i < rawGoal.length; i++) {
    final x = rawGoal[i];
    final w = 'goals[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    goalCheck(id, w);
    if (!_isAmt(x['target'])) errors.add('$w: "target" geçerli bir tutar değil.');
    final mp = _optNull(x['monthlyPlan']);
    if (mp != null && !_isAmt(mp)) errors.add('$w: "monthlyPlan" geçersiz.');
    final bp = _optNull(x['boughtPrice']);
    if (bp != null && !_isAmt(bp)) errors.add('$w: "boughtPrice" geçersiz.');
    goals.add(_copy(x)
      ..addAll({
        'id': id,
        'name': _str(x['name']),
        'target': x['target'],
        'emoji': _str(x['emoji']).isEmpty ? '🎯' : _str(x['emoji']),
        'priority': const {'yuksek', 'orta', 'dusuk'}.contains(x['priority']) ? x['priority'] : 'orta',
        'monthlyPlan': mp,
        'status': x['status'] == 'bought' ? 'bought' : 'active',
        'boughtAt': _optNull(x['boughtAt']),
        'boughtVia': _optNull(x['boughtVia']),
        'boughtPrice': bp,
        'url': _str(x['url']),
        'note': _str(x['note']),
      }));
  }
  out['goals'] = goals;
  final goalIds = {for (final g in goals) g['id'] as String};
  final conCheck = idSet();
  final contributions = <Json>[];
  final rawCon = list('goalContributions');
  for (var i = 0; i < rawCon.length; i++) {
    final x = rawCon[i];
    final w = 'goalContributions[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    conCheck(id, w);
    if (!goalIds.contains(_str(x['goalId']))) errors.add('$w: "goalId" kayıtlı bir hedefe ait değil.');
    if (!_isNum(x['amount'])) errors.add('$w: "amount" geçersiz.');
    if (!isMonth(x['month'])) errors.add('$w: "month" geçersiz.');
    final date = _optNull(x['date']);
    if (date != null && !isDate(date)) errors.add('$w: "date" geçersiz.');
    contributions.add(_copy(x)..addAll({'id': id, 'goalId': _str(x['goalId']), 'amount': x['amount'], 'month': x['month'], 'date': date}));
  }
  out['goalContributions'] = contributions;

  // ---- Ödemeler
  final payments = <Json>[];
  final rawPay = list('payments');
  for (var i = 0; i < rawPay.length; i++) {
    final x = rawPay[i];
    final w = 'payments[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    if (!const ['debt', 'expense', 'sub'].contains(x['kind'])) errors.add('$w: "kind" geçersiz.');
    if (_str(x['refId']).isEmpty) errors.add('$w: "refId" boş.');
    if (!isMonth(x['month'])) errors.add('$w: "month" geçersiz.');
    if (!_isAmt(x['paidAmount'])) errors.add('$w: "paidAmount" geçerli bir tutar değil.');
    final pd = _optNull(x['paidDate']);
    if (pd != null && !isDate(pd)) errors.add('$w: "paidDate" geçersiz.');
    final p = <String, dynamic>{
      'id': _str(x['id']).isEmpty ? rid('od') : _str(x['id']),
      'kind': x['kind'],
      'refId': _str(x['refId']),
      'month': x['month'],
      'paidAmount': x['paidAmount'],
      'paidDate': pd,
    };
    if (x['viaRefId'] != null) p['viaRefId'] = _str(x['viaRefId']);
    if (srcAcc(x['fromAccount']) != null) p['fromAccount'] = x['fromAccount'];
    final ca = _optISO(x['createdAt']);
    if (ca != null) p['createdAt'] = ca;
    final ua = _optISO(x['updatedAt']);
    if (ua != null) p['updatedAt'] = ua;
    if (x['fromPurchase'] != null) p['fromPurchase'] = _str(x['fromPurchase']);
    payments.add(p);
  }
  out['payments'] = payments;

  // ---- Findeks notları
  final findeks = <Json>[];
  final rawF = list('findeks');
  for (var i = 0; i < rawF.length; i++) {
    final x = rawF[i];
    final w = 'findeks[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    if (!isMonth(x['date'])) errors.add('$w: "date" geçersiz.');
    if (!_isNum(x['score'])) errors.add('$w: "score" geçersiz.');
    final lateCount = x['lateCount'];
    if (lateCount != null && !(lateCount is num && lateCount == lateCount.roundToDouble() && lateCount >= 0)) {
      errors.add('$w: "lateCount" geçersiz.');
    }
    findeks.add({
      'date': x['date'],
      'score': x['score'],
      'lateCount': lateCount,
      'band': _optNull(x['band']) == null ? null : _str(x['band']),
      'updatedAt': _optISO(x['updatedAt']),
    });
  }
  out['findeks'] = findeks;

  // ---- Fiziksel kartlar
  final cardCheck = idSet();
  final cards = <Json>[];
  final rawCards = list('cards');
  for (var i = 0; i < rawCards.length; i++) {
    final x = rawCards[i];
    final w = 'cards[$i]';
    if (x is! Map) {
      errors.add('$w geçersiz.');
      continue;
    }
    final id = _str(x['id']).trim();
    cardCheck(id, w);
    final st = x['style'] is Map ? x['style'] as Map : const {};
    final accountId = _optNull(x['accountId']);
    final debtId = _optNull(x['debtId']);
    cards.add(_copy(x)
      ..addAll({
        'id': id,
        'bank': _str(x['bank']),
        'name': _str(x['name']),
        'kind': _cardKinds.contains(x['kind']) ? x['kind'] : 'banka',
        'accountId': accountId != null && accIds.contains(accountId.toString()) ? accountId.toString() : null,
        'debtId': debtId != null && debtIds.contains(debtId.toString()) ? debtId.toString() : null,
        'status': x['status'] == 'kapali' ? 'kapali' : 'aktif',
        'network': _optNull(x['network']) == null ? null : _str(x['network']),
        'style': {
          'c1': st['c1'] is String && _color.hasMatch(st['c1'] as String) ? st['c1'] : null,
          'c2': st['c2'] is String && _color.hasMatch(st['c2'] as String) ? st['c2'] : null,
          'ink': _inks.contains(st['ink']) ? st['ink'] : 'light',
          'pattern': _patterns.contains(st['pattern']) ? st['pattern'] : 'none',
          'accent': st['accent'] is String && _color.hasMatch(st['accent'] as String) ? st['accent'] : null,
        },
        'note': _str(x['note']),
      }));
  }
  out['cards'] = cards;

  // ---- Ay kapatma kayıtları
  final closeSeen = <String>{};
  final closes = <Json>[];
  final rawCl = list('monthCloses');
  for (var i = 0; i < rawCl.length; i++) {
    final x = rawCl[i];
    if (x is! Map || !isMonth(x['month'])) {
      errors.add('monthCloses[$i]: "month" geçersiz.');
      continue;
    }
    final month = x['month'] as String;
    if (closeSeen.contains(month)) continue;
    closeSeen.add(month);
    final carry = <Json>[
      for (final c in (x['carry'] is List ? x['carry'] as List : const []))
        if (c is Map && const ['debt', 'expense', 'sub'].contains(c['kind']) && _str(c['refId']).isNotEmpty)
          {
            'kind': c['kind'],
            'refId': _str(c['refId']),
            'from': isMonth(c['from']) && (c['from'] as String).compareTo(month) <= 0 ? c['from'] : month,
          },
    ];
    final sn = x['snapshot'];
    final snapshot = sn is Map && ['liquid', 'cardDebt', 'loanDebt'].every((k) => _isNum(sn[k]))
        ? {'liquid': sn['liquid'], 'cardDebt': sn['cardDebt'], 'loanDebt': sn['loanDebt']}
        : null;
    closes.add({
      'month': month,
      'closedAt': _optISO(x['closedAt']),
      'carryCash': x['carryCash'] != false,
      'carry': carry,
      'snapshot': snapshot,
      'updatedAt': _optISO(x['updatedAt']),
    });
  }
  closes.sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
  out['monthCloses'] = closes;
  out['findeksReport'] = src['findeksReport'] is Map ? _copy(src['findeksReport']) : null;

  final meta = src['meta'] is Map ? _copy(src['meta']) : <String, dynamic>{};
  meta.putIfAbsent('lastBackupAt', () => null);
  if (meta['lastBackupAt'] != null && meta['lastBackupAt'] is! String) errors.add('"meta.lastBackupAt" geçersiz.');
  meta.remove('v3Setup');
  if (meta['spendEstimate'] != null && !_isAmt(meta['spendEstimate'])) meta.remove('spendEstimate');
  out['meta'] = meta;

  return NormalizeResult(Data(out), errors);
}
