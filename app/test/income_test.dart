// Maaş ile banka bağlantısı ve "Ödedin mi?": maaş yattığı onaylanınca seçili hesaba eklenir, hesap hatırlanır;
// onaylanmamış maaş beklenen gelir sayılır; değişken maaşın yatmamış ayları son yatan tutarla tahmin edilir;
// ödendiği onaylanmamış abonelik harcamaya sayılmaz.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/motor/motorlar.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';

Data _sample() {
  final n = normalizeData(jsonDecode(File('assets/sample/ornek.json').readAsStringSync()));
  expect(n.errors, isEmpty);
  return n.data!;
}

int _bal(Data d, String id) => toK(d.account(id)!.balance);

Income _salary(Data d) => d.incomes.firstWhere((x) => x.name == 'Maaş');

void main() {
  setUp(() => clock = () => DateTime(2026, 10, 20, 12));
  tearDown(() => clock = DateTime.now);

  test('maaş yattı: seçili hesaba eklenir, hesap hatırlanır, kaldırılınca geri düşer', () {
    final d = _sample();
    final inc = _salary(d);
    final before = _bal(d, 'akbank-vadesiz');
    expect(Ctx(d).pendingIncomes().map((i) => i.id), [inc.id], reason: '15\'inde yatacaktı, henüz onaylanmadı');

    setIncomeActual(d, inc.id, '2026-10', k: 4500000, date: '2026-10-15', to: 'acc:akbank-vadesiz');
    expect(_bal(d, 'akbank-vadesiz'), before + 4500000);
    expect(inc.account, 'acc:akbank-vadesiz');
    expect(d.transfers.where((t) => t.incomeRef == '${inc.id}|2026-10').length, 1);
    expect(Ctx(d).pendingIncomes(), isEmpty);

    // Aynı ay yeniden kaydedilince bakiye iki kez eklenmez
    setIncomeActual(d, inc.id, '2026-10', k: 4600000, date: '2026-10-15', to: 'acc:akbank-vadesiz');
    expect(_bal(d, 'akbank-vadesiz'), before + 4600000);

    setIncomeActual(d, inc.id, '2026-10');
    expect(_bal(d, 'akbank-vadesiz'), before);
    expect(d.transfers.where((t) => t.incomeRef == '${inc.id}|2026-10'), isEmpty);
  });

  test('onaylanmamış maaş "ay sonuna kadar serbest"ten düşmez; onaylanınca hesaba geçer', () {
    final d = _sample();
    final inc = _salary(d);
    final s1 = Ctx(d).sum('2026-10');
    expect(s1.incomeRest, 4500000);
    setIncomeActual(d, inc.id, '2026-10', k: 4500000, date: '2026-10-15', to: 'acc:akbank-vadesiz');
    final s2 = Ctx(d).sum('2026-10');
    expect(s2.incomeRest, 0);
    expect(s2.safe, s1.safe, reason: 'para gelirden hesaba geçti; serbest para değişmez');
  });

  test('değişken maaş: yatmamış aylar son yatan tutarla, tahmini', () {
    final d = _sample();
    final inc = _salary(d);
    inc.j['variable'] = true;
    final oct = Ctx(d).sum('2026-10').incomeItems.firstWhere((i) => i.id == inc.id);
    expect(oct.est, isTrue);
    expect(oct.k, 4580000, reason: 'Eylül\'de yatan 45.800 TL');
    setIncomeActual(d, inc.id, '2026-10', k: 5200000, date: '2026-10-15', to: 'acc:akbank-vadesiz');
    final ctx = Ctx(d);
    final oct2 = ctx.sum('2026-10').incomeItems.firstWhere((i) => i.id == inc.id);
    expect([oct2.est, oct2.k], [false, 5200000]);
    final dec = ctx.sum('2026-12').incomeItems.firstWhere((i) => i.id == inc.id);
    expect([dec.est, dec.k], [true, 5200000]);
    // Değişken olmayan maaş plandaki tutarla
    inc.j['variable'] = false;
    final dec2 = Ctx(d).sum('2026-12').incomeItems.firstWhere((i) => i.id == inc.id);
    expect([dec2.est, dec2.k], [false, 4500000]);
  });

  test('gelir kaydı: hesap, net/brüt ve değişken saklanır, veri düzeltmesinde kaybolmaz', () {
    final d = _sample();
    final id = saveIncome(d,
        name: 'Prim',
        payDay: 28,
        schedule: [
          {'from': '2026-10', 'to': null, 'amount': 30000},
        ],
        account: 'acc:enpara-vadesiz',
        gross: true,
        grossK: 4000000,
        variable: true);
    final again = normalizeData(jsonDecode(jsonEncode(d.j)));
    expect(again.errors, isEmpty);
    final x = again.data!.incomes.firstWhere((i) => i.id == id);
    expect([x.account, x.gross, x.grossAmount, x.variable], ['acc:enpara-vadesiz', true, 40000.0, true]);
    // Net seçilince brüt tutar silinir
    saveIncome(d, id: id, name: 'Prim', payDay: 28, schedule: [
      {'from': '2026-10', 'to': null, 'amount': 30000},
    ]);
    final y = d.incomes.firstWhere((i) => i.id == id);
    expect([y.account, y.gross, y.grossAmount, y.variable], [null, false, null, false]);
  });

  test('ödendiği onaylanmamış abonelik harcamaya sayılmaz', () {
    final d = _sample();
    final ctx = Ctx(d);
    final lines = subSpendsIn(ctx, '2026-10');
    for (final l in lines) {
      expect(ctx.model.pay('sub', l.id, '2026-10'), isNotNull, reason: '${l.name} ödenmeden harcama sayıldı');
    }
    // Günü geçmiş, ödenmemiş abonelik zilde "Ödedin mi?" olarak görünür
    final late = ctx.upcoming(7).where((u) => u.late && u.item.kind == 'sub').map((u) => u.item.refId).toSet();
    final unpaid = d.subscriptions.where((x) => x.active && (x.day ?? 99) < 20 && ctx.model.pay('sub', x.id, '2026-10') == null && subAmountK(x, '2026-10') > 0);
    expect(late, containsAll(unpaid.map((x) => x.id)));
  });
}
