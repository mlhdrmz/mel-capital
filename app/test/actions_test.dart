// Veri değişikliklerinin (harcama, aktarma, ödeme, hesap) bakiyeleri ve borçları doğru
// değiştirdiğini ve geri alındığında her şeyin eski haline döndüğünü denetler.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/motor/motorlar.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';

Data _sample() {
  final raw = jsonDecode(File('assets/sample/ornek.json').readAsStringSync());
  final n = normalizeData(raw);
  expect(n.errors, isEmpty);
  return n.data!;
}

int _bal(Data d, String id) => toK(d.account(id)!.balance);

void main() {
  setUpAll(() => clock = () => DateTime(2026, 10, 20, 12));
  tearDownAll(() => clock = DateTime.now);

  test('harcama: hesaptan düşer, düzenlenince ve silinince geri eklenir', () {
    final d = _sample();
    final before = _bal(d, 'akbank-vadesiz');
    final id = saveSpend(d, {
      'date': '2026-10-20',
      'name': 'Kahve',
      'place': '',
      'category': 'kafe',
      'amount': 85.5,
      'source': 'acc:akbank-vadesiz',
      'installments': 1,
      'firstMonth': null,
      'note': '',
      'url': '',
    });
    expect(_bal(d, 'akbank-vadesiz'), before - 8550);
    saveSpend(d, {'amount': 100, 'source': 'acc:enpara-vadesiz'}, id: id);
    expect(_bal(d, 'akbank-vadesiz'), before);
    final enpara = _bal(d, 'enpara-vadesiz');
    deleteSpend(d, id);
    expect(_bal(d, 'enpara-vadesiz'), enpara + 10000);
    expect(d.spends.any((x) => x.id == id), isFalse);
  });

  test('kartla taksitli harcama: limit düşer, taksitler aylara dağılır', () {
    final d = _sample();
    final ctx0 = Ctx(d);
    final avail0 = ctx0.model.debts['akbank-axess']!.available!;
    final first = nextStatementMonth(d.debt('akbank-axess'), '2026-10-20');
    saveSpend(d, {
      'date': '2026-10-20',
      'name': 'Kulaklık',
      'place': '',
      'category': 'teknoloji',
      'amount': 3000,
      'source': 'card:akbank-axess',
      'installments': 3,
      'firstMonth': first,
      'note': '',
      'url': '',
    });
    final ctx1 = Ctx(d);
    expect(ctx1.model.debts['akbank-axess']!.available, avail0 - 300000);
    expect(ctx1.model.liquid, ctx0.model.liquid);
  });

  test('hızlı giriş satırları ayrıştırılır', () {
    final d = _sample();
    final rows = parseQuickLines(d, 'kahve 85\nmarket 340,50\nsimit 15, otobüs 27\n12 su\nbozuk');
    expect(rows.map((r) => r.name).toList(), ['kahve', 'market', 'simit', 'otobüs', 'su', 'Harcama']);
    expect(rows.map((r) => r.k).toList(), [8500, 34050, 1500, 2700, 1200, 0]);
    expect(rows.last.ok, isFalse);
    final before = _bal(d, 'elde-nakit');
    saveQuickSpends(d, [for (final r in rows.where((r) => r.ok)) (r.name, r.k, r.cat)], date: '2026-10-20', source: 'acc:elde-nakit');
    expect(_bal(d, 'elde-nakit'), before - 8500 - 34050 - 1500 - 2700 - 1200);
  });

  test('aktarma: iki hesabı değiştirir, silinince geri alınır', () {
    final d = _sample();
    final a0 = _bal(d, 'akbank-vadesiz'), e0 = _bal(d, 'enpara-vadesiz');
    saveTransfer(d, from: 'acc:akbank-vadesiz', to: 'acc:enpara-vadesiz', k: 50000, date: '2026-10-20');
    expect(_bal(d, 'akbank-vadesiz'), a0 - 50000);
    expect(_bal(d, 'enpara-vadesiz'), e0 + 50000);
    final id = d.transfers.last.id;
    saveTransfer(d, id: id, from: 'ext', to: 'acc:enpara-vadesiz', k: 20000, date: '2026-10-20');
    expect(_bal(d, 'akbank-vadesiz'), a0);
    expect(_bal(d, 'enpara-vadesiz'), e0 + 20000);
    deleteTransfer(d, id);
    expect(_bal(d, 'enpara-vadesiz'), e0);
  });

  test('kart borcu ödemesi borcu düşürür, hesaptan çıkar', () {
    final d = _sample();
    final ctx0 = Ctx(d);
    final cur0 = ctx0.model.debts['enpara-kk']!.current;
    final m = cardPayMonth(ctx0, d.debt('enpara-kk')!);
    payCard(d, 'enpara-kk', m, 50000, '2026-10-20', 'acc:akbank-vadesiz');
    final ctx1 = Ctx(d);
    expect(ctx1.model.debts['enpara-kk']!.current, cur0 - 50000);
    expect(ctx1.model.liquid, ctx0.model.liquid - 50000);
  });

  test('ödendi işareti: konur, kaldırılır, bakiye geri gelir', () {
    final d = _sample();
    final ctx0 = Ctx(d);
    final it = ctx0.items('2026-10').firstWhere((x) => x.kind == 'expense' && x.refId == 'kira' && !x.carry);
    if (it.pay != null) removePaymentFor(d, 'expense', 'kira', '2026-10');
    final liq0 = Ctx(d).model.liquid;
    final it2 = Ctx(d).items('2026-10').firstWhere((x) => x.kind == 'expense' && x.refId == 'kira' && !x.carry);
    final from = markPaid(d, Ctx(d).model, it2, '2026-10');
    final ctx1 = Ctx(d);
    expect(ctx1.items('2026-10').firstWhere((x) => x.refId == 'kira').pay, isNotNull);
    if (from != null) expect(ctx1.model.liquid, liq0 - it2.planned);
    removePaymentFor(d, 'expense', 'kira', '2026-10');
    expect(Ctx(d).model.liquid, liq0);
  });

  test('ödeme düzenleme: tutar ve hesap yeniden yazılır', () {
    final d = _sample();
    final liq0 = Ctx(d).model.liquid;
    savePayment(d, kind: 'debt', refId: 'kyk', month: '2026-11', k: 125000, date: '2026-10-20', from: 'acc:akbank-vadesiz');
    expect(Ctx(d).model.liquid, liq0 - 125000);
    savePayment(d, kind: 'debt', refId: 'kyk', month: '2026-11', k: 100000, date: '2026-10-20', from: 'acc:akbank-vadesiz');
    expect(Ctx(d).model.liquid, liq0 - 100000);
    expect(d.payments.where((p) => p.refId == 'kyk' && p.month == '2026-11').length, 1);
  });

  test('hesap eklenir, düzenlenir, silinince kart bağlantısı kalkar', () {
    final d = _sample();
    saveAccount(d, bank: 'akbank', name: 'Birikim', type: 'birikim', balanceK: 123456);
    final a = d.accounts.last;
    expect(toK(a.balance), 123456);
    saveAccount(d, id: a.id, bank: 'akbank', name: 'Birikim', type: 'birikim', balanceK: -500);
    expect(toK(d.account(a.id)!.balance), -500);
    deleteAccount(d, 'akbank-vadesiz');
    expect(d.account('akbank-vadesiz'), isNull);
    expect(d.cards.where((c) => c.accountId == 'akbank-vadesiz'), isEmpty);
  });

  test('abonelik dondurulur ve aylık toplamdan çıkar', () {
    final d = _sample();
    final m0 = Ctx(d).model.subsMonthly;
    expect(toggleSubscription(d, 'spotify'), isFalse);
    expect(Ctx(d).model.subsMonthly, m0 - 9900);
    expect(toggleSubscription(d, 'spotify'), isTrue);
    expect(Ctx(d).model.subsMonthly, m0);
  });
}
