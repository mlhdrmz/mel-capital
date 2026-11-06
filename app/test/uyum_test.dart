// Uyum testi: motorların her işlemi, hesapları, maaş girişlerini, ödemeleri ve kimlikleri
// birbiriyle uyumlu bırakmalı. Her adımdan sonra uyumDenetimi boş dönmeli; bozuk bir değişikliği
// de yakalamalı.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/motor/motorlar.dart';

Data _sample() {
  final raw = jsonDecode(File('assets/sample/ornek.json').readAsStringSync());
  final n = normalizeData(raw);
  expect(n.errors, isEmpty);
  return n.data!;
}

/// Bir işlemi uygular ve uyumu denetler; işlemden sonraki sorunları döndürür.
List<String> _dene(Data d, void Function(Data d) islem) {
  final once = Data(deepCopy(d.j) as Json);
  islem(d);
  return uyumDenetimi(once, d);
}

void _adim(Data d, String ad, void Function(Data d) islem) {
  expect(_dene(d, islem), isEmpty, reason: ad);
}

Json _harcama(String source, double tutar, {int taksit = 1, String? firstMonth}) => <String, dynamic>{
      'date': '2026-10-20',
      'name': 'Deneme',
      'place': '',
      'category': 'market',
      'amount': tutar,
      'source': source,
      'installments': taksit,
      'firstMonth': firstMonth,
      'note': '',
      'url': '',
    };

void main() {
  setUpAll(() => clock = () => DateTime(2026, 10, 20, 12));
  tearDownAll(() => clock = DateTime.now);

  test('Gider Motoru: harcama ekle, düzenle, sil; hızlı giriş; kartla taksit', () {
    final d = _sample();
    late String id;
    _adim(d, 'hesaptan harcama', (d) => id = saveSpend(d, _harcama('acc:akbank-vadesiz', 120.5)));
    _adim(d, 'harcamanın hesabı değişti', (d) => saveSpend(d, {'amount': 99, 'source': 'acc:enpara-vadesiz'}, id: id));
    _adim(d, 'harcama silindi', (d) => deleteSpend(d, id));
    _adim(d, 'hızlı giriş', (d) => saveQuickSpends(d, [('Simit', 1500, 'market'), ('Otobüs', 2700, 'ulasim')], date: '2026-10-20', source: 'acc:akbank-vadesiz'));
    _adim(d, 'kartla taksitli', (d) => saveSpend(d, _harcama('card:akbank-axess', 3000, taksit: 3, firstMonth: nextStatementMonth(d.debt('akbank-axess'), '2026-10-20'))));
  });

  test('Çekirdek: aktarma ekle, düzenle, sil; dışarıdan giriş; bakiye düzeltme', () {
    final d = _sample();
    _adim(d, 'aktarma', (d) => saveTransfer(d, from: 'acc:akbank-vadesiz', to: 'acc:enpara-vadesiz', k: 50000, date: '2026-10-20'));
    final id = d.transfers.last.id;
    _adim(d, 'aktarma düzenlendi', (d) => saveTransfer(d, id: id, from: 'acc:enpara-vadesiz', to: 'acc:akbank-vadesiz', k: 20000, date: '2026-10-19'));
    _adim(d, 'aktarma silindi', (d) => deleteTransfer(d, id));
    _adim(d, 'dışarıdan giriş', (d) => saveTransfer(d, from: 'ext', to: 'acc:akbank-vadesiz', k: 100000, date: '2026-10-20'));
    final a = d.account('akbank-vadesiz')!;
    _adim(d, 'bakiye elle düzeltildi', (d) => saveAccount(d, id: a.id, bank: a.bank, name: a.name, type: a.type, balanceK: 1234500));
  });

  test('Gelir Motoru: maaş yattı, tutar değişti, geri alındı, gelir silindi', () {
    final d = _sample();
    late String id;
    _adim(d, 'gelir eklendi', (d) => id = saveIncome(d, name: 'Maaş', payDay: 15, account: 'acc:akbank-vadesiz', schedule: [
          <String, dynamic>{'from': '2026-10', 'to': null, 'amount': 45000},
        ]));
    _adim(d, 'maaş yattı', (d) => setIncomeActual(d, id, '2026-10', k: 4500000, date: '2026-10-15', to: 'acc:akbank-vadesiz'));
    _adim(d, 'tutar değişti, başka hesaba', (d) => setIncomeActual(d, id, '2026-10', k: 4600000, date: '2026-10-15', to: 'acc:enpara-vadesiz'));
    _adim(d, 'yattı geri alındı', (d) => setIncomeActual(d, id, '2026-10'));
    _adim(d, 'yine yattı', (d) => setIncomeActual(d, id, '2026-10', k: 4500000, date: '2026-10-15', to: 'acc:akbank-vadesiz'));
    _adim(d, 'gelir silindi (giriş hesapta kalır)', (d) => deleteIncome(d, id));
  });

  test('Plan ve Borç motorları: bu ayın bütün kalemleri ödenir, kart ödenir, ay kapanır', () {
    final d = _sample();
    final m = currentMonth();
    for (final it in Ctx(d).items(m).where((it) => it.pay == null && it.planned > 0).toList()) {
      _adim(d, 'ödendi: ${it.name}', (d) => markPaid(d, buildModel(d, m), it, m));
    }
    _adim(d, 'kart ödemesi hesaptan', (d) => payCard(d, 'akbank-axess', m, 50000, '2026-10-20', 'acc:akbank-vadesiz'));
    _adim(d, 'ödeme yeniden yazıldı', (d) => savePayment(d, kind: 'debt', refId: 'akbank-axess', month: m, k: 70000, date: '2026-10-20', from: 'acc:enpara-vadesiz'));
    _adim(d, 'kart bakiyesi', (d) => setCardBalance(d, 'akbank-axess', debtK: 250000, limitK: 1500000));
    _adim(d, 'ekstre', (d) => saveStatement(d, 'akbank-axess', month: addM(m, 1), totalK: 250000, minK: 50000, cutDay: 3, dueDay: 13, payPlan: 'asgari'));
    _adim(d, 'ay kapandı', (d) => closeMonth(d, buildModel(d, m), m, carry: const [], carryCash: true, withSnapshot: true));
    _adim(d, 'ay yeniden açıldı', (d) => reopenMonth(d, m));
  });

  test('Silmeler: abonelik, sabit gider ve borç silinince ödenen para hesaba dönmez', () {
    final d = _sample();
    final m = currentMonth();
    late String sub;
    _adim(d, 'abonelik', (d) => sub = saveSubscription(d, <String, dynamic>{
          'name': 'Deneme TV', 'group': 'dijital', 'amount': 199, 'period': 'ay', 'day': 5, 'source': 'acc:akbank-vadesiz', 'active': true, 'note': '',
        }));
    _adim(d, 'abonelik ödendi', (d) => savePayment(d, kind: 'sub', refId: sub, month: m, k: 19900, date: '2026-10-05', from: 'acc:akbank-vadesiz'));
    final bal = toK(d.account('akbank-vadesiz')!.balance);
    _adim(d, 'abonelik silindi', (d) => deleteSubscription(d, sub));
    expect(toK(d.account('akbank-vadesiz')!.balance), bal);
    for (final x in d.recurringExpenses.toList()) {
      _adim(d, 'sabit gider silindi: ${x.name}', (d) => deleteExpense(d, x.id));
    }
    for (final x in d.debts.toList()) {
      _adim(d, 'borç silindi: ${x.creditor}', (d) => deleteDebt(d, x.id));
    }
  });

  test('istek listesi: birikim ayrılır, alınınca harcama olur', () {
    final d = _sample();
    late String g;
    _adim(d, 'istek', (d) => g = saveGoal(d, <String, dynamic>{'name': 'Kulaklık', 'target': 3000, 'priority': 'orta', 'monthlyPlan': 1000, 'url': '', 'note': ''}));
    _adim(d, 'birikim', (d) => addContribution(d, g, 100000, currentMonth()));
    _adim(d, 'alındı', (d) => saveSpend(d, _harcama('acc:akbank-vadesiz', 2900), goalId: g));
  });

  test('uyum denetimi bozuk değişiklikleri yakalar', () {
    final d = _sample();
    // Harcama eklenmiş ama hesaptan düşülmemiş
    final s1 = _dene(d, (d) => d.spends.add(Spend(_harcama('acc:akbank-vadesiz', 50)..['id'] = 'bozuk-1')));
    expect(s1.single, startsWith('Hesap uyumu'));
    // Bakiye hareketsiz değişmiş
    final s2 = _dene(d, (d) => d.account('enpara-vadesiz')!.balance += 10);
    expect(s2.single, startsWith('Hesap uyumu'));
    // Aynı kimlik iki kez
    final s3 = _dene(d, (d) => d.spends.add(Spend(_harcama('', 1)..['id'] = 'bozuk-1')));
    expect(s3.single, startsWith('Kimlik uyumu'));
    // Maaş girişi gelirin tutarını tutmuyor
    final id = saveIncome(d, name: 'Prim', schedule: const []);
    final s4 = _dene(d, (d) => d.transfers.add(Transfer(<String, dynamic>{
          'id': 'akt-bozuk', 'date': '2026-10-20', 'from': 'ext', 'to': '', 'amount': 100, 'note': '', 'incomeRef': '$id|2026-10',
        })));
    expect(s4.single, startsWith('Maaş uyumu'));
  });
}
