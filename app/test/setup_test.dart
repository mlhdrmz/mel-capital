// Kurulum sihirbazının veri işlemleri ve yedek dosyası okuma.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/actions.dart';
import 'package:mel_capital/core/backup_file.dart';
import 'package:mel_capital/core/calc.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';

void main() {
  setUpAll(() => clock = () => DateTime(2026, 11, 10, 12));
  tearDownAll(() => clock = DateTime.now);

  test('yedek dosyası okunur; Mel Capital verisi olmayan dosya reddedilir', () {
    final text = File('assets/sample/ornek.json').readAsStringSync();
    final (data, error) = readBackupText(text, 'tr');
    expect(error, isNull);
    expect(Data(data!).accounts, isNotEmpty);
    expect(readBackupText('﻿$text', 'tr').$2, isNull);
    expect(readBackupText('{"data": $text}', 'tr').$2, isNull);
    expect(readBackupText('{bozuk', 'tr').$1, isNull);
    expect(readBackupText('{"merhaba": 1}', 'tr').$2, contains('Mel Capital verisi yok'));
    expect(readBackupText('[1, 2]', 'en').$2, contains('no Mel Capital data'));
  });

  test('kurulum: kart, kredi, gelir ve düzenli ödemeler eklenir', () {
    final d = emptyData();

    // Kart: son ödeme günü (5) geçti → bu ayki ödeme yapılmış sayılır, girilen borç değişmez.
    final card = addSetupCard(d, name: 'Axess', bank: 'akbank', debtK: 350000, limitK: 2000000, cutDay: 25, dueDay: 5);
    expect(d.payments.where((p) => p.kind == 'debt' && p.refId == card && p.month == '2026-11').length, 1);
    expect(Ctx(d).model.debts[card]!.current, 350000);
    expect(Ctx(d).model.cardAvail, 2000000 - 350000);

    // Son ödeme günü gelmemiş kart: işaret konmaz.
    final card2 = addSetupCard(d, name: 'Bonus', bank: 'garanti', debtK: 100000, dueDay: 20);
    expect(d.payments.any((p) => p.refId == card2), isFalse);

    // Kredi: sıradaki taksit ayı ödeme gününe göre.
    expect(nextInstallmentMonth(13), '2026-11');
    expect(nextInstallmentMonth(5), '2026-12');
    expect(nextInstallmentMonth(null), '2026-11');
    final loan = addSetupLoan(d, name: 'İhtiyaç kredisi', type: 'kredi', bank: 'isbank', monthlyK: 273000, count: 13, first: '2026-11', payDay: 13);
    expect(d.debt(loan)!.schedule.single.from, '2026-11');
    expect(d.debt(loan)!.schedule.single.to, '2027-11');
    expect(d.debt(loan)!.remaining, 2730 * 13);
    final kyk = addSetupLoan(d, name: 'KYK', type: 'kyk', bank: 'kyk', monthlyK: 125000, count: 3, first: '2026-12', payDay: 1, restK: 300000);
    expect(d.debt(kyk)!.remaining, 3000);

    // Gelir: bu aydan itibaren, süresiz.
    final inc = addSetupIncome(d, name: 'Maaş', k: 4500000, payDay: 15);
    expect(d.incomes.single.id, inc);
    expect(d.incomes.single.schedule.single.from, '2026-11');
    expect(d.incomes.single.schedule.single.to, isNull);

    // Düzenli ödemeler: günü geçenler bu ay ödenmiş sayılır.
    final sub = addSetupCost(d, name: 'Netflix', expense: false, group: 'video', k: 22999, day: 3, source: 'card:$card');
    final bill = addSetupCost(d, name: 'Elektrik', expense: false, group: 'fatura', k: 70000, day: 20);
    final rent = addSetupCost(d, name: 'Kira', expense: true, group: 'kira', k: 1250000, day: 1);
    expect(d.payments.any((p) => p.kind == 'sub' && p.refId == sub), isTrue);
    expect(d.payments.any((p) => p.kind == 'sub' && p.refId == bill), isFalse);
    expect(d.payments.any((p) => p.kind == 'expense' && p.refId == rent), isTrue);
    expect(d.recurringExpenses.single.startMonth, '2026-11');

    // Bakiyeler değişmez (işaretler hesaptan düşmez).
    expect(d.accounts.single.balance, 0);

    // Kaydedilen veri yeniden açılınca denetimden geçer; bu ay "gecikmiş" ödeme kalmaz.
    final n = normalizeData(jsonDecode(jsonEncode(d.j)));
    expect(n.errors, isEmpty);
    final ctx = Ctx(n.data!);
    expect(ctx.upcoming(31).where((u) => u.late), isEmpty);
  });
}
