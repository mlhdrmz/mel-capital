// Mel Capital — veri modeli.
//
// Veri, eski Mel Capital ile aynı JSON biçimindedir (sürüm 4); böylece eski veri dosyası ve
// yedekler aynen açılır, telefon eşitlemesi de aynı paketle çalışır. Her kayıt türü, JSON
// nesnesinin üstünde sıfır maliyetli bir "extension type" sarmalayıcıdır: bilinmeyen alanlar
// korunur, değişiklikler doğrudan JSON'a yazılır.

typedef Json = Map<String, dynamic>;

String _s(Json j, String k) {
  final v = j[k];
  return v == null ? '' : v.toString();
}

String? _so(Json j, String k) {
  final v = j[k];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

double _d(Json j, String k) {
  final v = j[k];
  return v is num ? v.toDouble() : 0;
}

double? _do(Json j, String k) {
  final v = j[k];
  return v is num ? v.toDouble() : null;
}

int? _io(Json j, String k) {
  final v = j[k];
  return v is num ? v.toInt() : null;
}

List<T> _list<T>(Json j, String k) {
  final v = j[k];
  if (v is List) return v.cast<T>();
  final fresh = <Json>[];
  j[k] = fresh;
  return fresh.cast<T>();
}

Map<String, double> _amounts(Json j, String k) {
  final v = j[k];
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
  };
}

/// Bütün veri.
extension type Data(Json j) {
  int get version => _io(j, 'version') ?? 4;
  String get balancesAsOf => _s(j, 'balancesAsOf');
  set balancesAsOf(String v) => j['balancesAsOf'] = v;
  List<Debt> get debts => _list<Debt>(j, 'debts');
  List<RecurringExpense> get recurringExpenses => _list<RecurringExpense>(j, 'recurringExpenses');
  List<Income> get incomes => _list<Income>(j, 'incomes');
  List<OneOffIncome> get oneOffIncomes => _list<OneOffIncome>(j, 'oneOffIncomes');
  List<Spend> get spends => _list<Spend>(j, 'spends');
  List<Transfer> get transfers => _list<Transfer>(j, 'transfers');
  List<Subscription> get subscriptions => _list<Subscription>(j, 'subscriptions');
  List<Goal> get goals => _list<Goal>(j, 'goals');
  List<GoalContribution> get goalContributions => _list<GoalContribution>(j, 'goalContributions');
  List<Payment> get payments => _list<Payment>(j, 'payments');
  List<Findeks> get findeks => _list<Findeks>(j, 'findeks');
  List<Account> get accounts => _list<Account>(j, 'accounts');
  List<BankCard> get cards => _list<BankCard>(j, 'cards');
  List<MonthClose> get monthCloses => _list<MonthClose>(j, 'monthCloses');
  Json? get findeksReport => j['findeksReport'] is Map ? (j['findeksReport'] as Map).cast<String, dynamic>() : null;
  Json get meta {
    final v = j['meta'];
    if (v is Map<String, dynamic>) return v;
    final m = v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    j['meta'] = m;
    return m;
  }

  Debt? debt(String? id) {
    for (final x in debts) {
      if (x.id == id) return x;
    }
    return null;
  }

  Account? account(String? id) {
    for (final x in accounts) {
      if (x.id == id) return x;
    }
    return null;
  }

  Subscription? subscription(String? id) {
    for (final x in subscriptions) {
      if (x.id == id) return x;
    }
    return null;
  }

  RecurringExpense? expense(String? id) {
    for (final x in recurringExpenses) {
      if (x.id == id) return x;
    }
    return null;
  }

  Goal? goal(String? id) {
    for (final x in goals) {
      if (x.id == id) return x;
    }
    return null;
  }

  MonthClose? closeOf(String m) {
    for (final c in monthCloses) {
      if (c.month == m) return c;
    }
    return null;
  }

  bool get hasRecords =>
      debts.length + recurringExpenses.length + spends.length + payments.length + findeks.length +
          incomes.length + goals.length + cards.length + transfers.length + subscriptions.length >
      0;
}

/// Taksit/gelir planı satırı: from–to aylarında aylık tutar.
extension type Sched(Json j) {
  String get from => _s(j, 'from');
  String? get to => _so(j, 'to');
  double get amount => _d(j, 'amount');
}

/// Kart ekstresi (son ödeme ayı → ekstre borcu, asgari).
extension type Statement(Json j) {
  String get month => _s(j, 'month');
  double get total => _d(j, 'total');
  double? get minimum => _do(j, 'minimum');
}

/// Borç: kredi kartı, kredi, yapılandırma, KYK...
extension type Debt(Json j) {
  String get id => _s(j, 'id');
  String get creditor => _s(j, 'creditor');
  set creditor(String v) => j['creditor'] = v;
  String get bank => _s(j, 'bank');
  String get type => _s(j, 'type');
  bool get isCard => type == 'kredi_karti';
  double get remaining => _d(j, 'remaining');
  set remaining(double v) => j['remaining'] = v;
  double? get limit => _do(j, 'limit');
  List<Sched> get schedule => _list<Sched>(j, 'schedule');
  List<Statement> get statements => _list<Statement>(j, 'statements');
  String get note => _s(j, 'note');
  int? get payDay => _io(j, 'payDay');
  int? get statementDay => _io(j, 'statementDay');
  int? get dueDay => _io(j, 'dueDay');
  String? get balanceDate => _so(j, 'balanceDate');
  String? get balanceAt => _so(j, 'balanceAt');
  String get payPlan => j['payPlan'] == 'tamami' ? 'tamami' : 'asgari';

  /// Aylık faiz oranı, yüzde (ör. 3.49). İsteğe bağlı; yalnızca borç kapatma hesabında kullanılır.
  double? get rate {
    final v = _do(j, 'rate');
    return v != null && v > 0 && v <= 100 ? v : null;
  }
}

extension type RecurringExpense(Json j) {
  String get id => _s(j, 'id');
  String get name => _s(j, 'name');
  String get category => _s(j, 'category');
  double get amount => _d(j, 'amount');
  String get startMonth => _s(j, 'startMonth');
  String? get endMonth => _so(j, 'endMonth');
  int? get day => _io(j, 'day');
  List<String> get linkedDebtIds {
    final v = j['linkedDebtIds'];
    return v is List ? v.map((e) => e.toString()).toList() : const [];
  }

  String get note => _s(j, 'note');

  bool activeIn(String m) =>
      startMonth.length == 7 && startMonth.compareTo(m) <= 0 && (endMonth == null || m.compareTo(endMonth!) <= 0);
}

extension type Income(Json j) {
  String get id => _s(j, 'id');
  String get name => _s(j, 'name');
  List<Sched> get schedule => _list<Sched>(j, 'schedule');
  int? get payDay => _io(j, 'payDay');
  String get note => _s(j, 'note');
  Map<String, double> get monthAmounts => _amounts(j, 'monthAmounts');

  /// Gelirin yattığı hesap ("acc:<kimlik>"): "Maaşın yattı mı?" onayı tutarı bu hesaba ekler.
  String? get account {
    final v = j['account'];
    return v is String && v.startsWith('acc:') && v.length > 4 ? v : null;
  }

  /// Gelir eklenirken brüt seçildi mi (plan her zaman hesaba yatan net tutarla çalışır; brüt bilgi içindir).
  bool get gross => j['basis'] == 'brut';
  double? get grossAmount => _do(j, 'grossAmount');

  /// Her ay farklı yatar: henüz yatmamış aylarda son yatan tutar tahmini olarak kullanılır.
  bool get variable => j['variable'] == true;
}

extension type OneOffIncome(Json j) {
  String get id => _s(j, 'id');
  String get name => _s(j, 'name');
  double get amount => _d(j, 'amount');
  String get date => _s(j, 'date');
}

extension type Account(Json j) {
  String get id => _s(j, 'id');
  String get bank => _s(j, 'bank');
  String get name => _s(j, 'name');
  String get type => _s(j, 'type');
  bool get isCash => type == 'nakit';
  double get balance => _d(j, 'balance');
  set balance(double v) => j['balance'] = v;
  String? get asOf => _so(j, 'asOf');
  String get note => _s(j, 'note');
}

extension type Spend(Json j) {
  String get id => _s(j, 'id');
  String get date => _s(j, 'date');
  String get name => _s(j, 'name');
  String get place => _s(j, 'place');
  String get category => j['category'] == null || _s(j, 'category').isEmpty ? 'diger' : _s(j, 'category');
  double get amount => _d(j, 'amount');
  String? get source => _so(j, 'source');
  int get installments => _io(j, 'installments') ?? 1;
  String? get firstMonth => _so(j, 'firstMonth');
  String get note => _s(j, 'note');
  String get url => _s(j, 'url');
  String? get goalId => _so(j, 'goalId');
  String? get createdAt => _so(j, 'createdAt');
  String? get batch => _so(j, 'batch');
  String? get updatedAt => _so(j, 'updatedAt');
}

extension type Transfer(Json j) {
  String get id => _s(j, 'id');
  String get date => _s(j, 'date');
  String get from => _s(j, 'from');
  String get to => _s(j, 'to');
  double get amount => _d(j, 'amount');
  String get note => _s(j, 'note');
  String? get createdAt => _so(j, 'createdAt');
  String? get incomeRef => _so(j, 'incomeRef');
  bool get external => from == 'ext';
}

extension type Subscription(Json j) {
  String get id => _s(j, 'id');
  String get name => _s(j, 'name');
  String get group => _s(j, 'group');
  bool get isBill => group == 'fatura';
  double? get amount => _do(j, 'amount');
  String get period => j['period'] == 'yil' ? 'yil' : 'ay';
  int? get day => _io(j, 'day');
  String? get source => _so(j, 'source');
  bool get active => j['active'] != false;
  String get note => _s(j, 'note');
  Map<String, double> get monthAmounts => _amounts(j, 'monthAmounts');
}

extension type Goal(Json j) {
  String get id => _s(j, 'id');
  String get name => _s(j, 'name');
  double get target => _d(j, 'target');
  String get emoji => _s(j, 'emoji').isEmpty ? '🎯' : _s(j, 'emoji');
  String get priority => const {'yuksek', 'orta', 'dusuk'}.contains(j['priority']) ? j['priority'] as String : 'orta';
  double? get monthlyPlan => _do(j, 'monthlyPlan');
  String get status => j['status'] == 'bought' ? 'bought' : 'active';
  bool get isActive => status == 'active';
  String? get boughtAt => _so(j, 'boughtAt');
  String? get boughtVia => _so(j, 'boughtVia');
  double? get boughtPrice => _do(j, 'boughtPrice');
  String get url => _s(j, 'url');
  String get note => _s(j, 'note');
}

extension type GoalContribution(Json j) {
  String get id => _s(j, 'id');
  String get goalId => _s(j, 'goalId');
  double get amount => _d(j, 'amount');
  String get month => _s(j, 'month');
  String? get date => _so(j, 'date');
}

extension type Payment(Json j) {
  String get id => _s(j, 'id');
  String get kind => _s(j, 'kind');
  String get refId => _s(j, 'refId');
  String get month => _s(j, 'month');
  double get paidAmount => _d(j, 'paidAmount');
  String? get paidDate => _so(j, 'paidDate');
  String? get viaRefId => _so(j, 'viaRefId');
  String? get fromAccount => _so(j, 'fromAccount');
  String? get createdAt => _so(j, 'createdAt');
}

extension type Findeks(Json j) {
  String get date => _s(j, 'date');
  double get score => _d(j, 'score');
  int? get lateCount => _io(j, 'lateCount');
  String? get band => _so(j, 'band');
}

extension type CardStyle(Json j) {
  String get c1 => _s(j, 'c1');
  String get c2 => _s(j, 'c2');
  String get ink => _s(j, 'ink').isEmpty ? 'light' : _s(j, 'ink');
  String get pattern => _s(j, 'pattern').isEmpty ? 'none' : _s(j, 'pattern');
  String? get accent => _so(j, 'accent');
}

/// Fiziksel kart (banka kartı, kredi kartı, ön ödemeli).
extension type BankCard(Json j) {
  String get id => _s(j, 'id');
  String get bank => _s(j, 'bank');
  String get name => _s(j, 'name');
  String get kind => _s(j, 'kind');
  String? get accountId => _so(j, 'accountId');
  String? get debtId => _so(j, 'debtId');
  bool get active => j['status'] != 'kapali';
  String? get network => _so(j, 'network');
  CardStyle get style {
    final v = j['style'];
    if (v is Map<String, dynamic>) return CardStyle(v);
    final m = v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    j['style'] = m;
    return CardStyle(m);
  }

  String get note => _s(j, 'note');
}

extension type Carry(Json j) {
  String get kind => _s(j, 'kind');
  String get refId => _s(j, 'refId');
  String get from => _s(j, 'from');
}

/// Ay kapatma kaydı.
extension type MonthClose(Json j) {
  String get month => _s(j, 'month');
  String? get closedAt => _so(j, 'closedAt');
  bool get carryCash => j['carryCash'] != false;
  List<Carry> get carry => _list<Carry>(j, 'carry');
}
