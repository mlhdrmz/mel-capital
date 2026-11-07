// Plan'da "ödendi" işareti ile hesaplardaki para, borçlar ve ay özeti birlikte hareket eder mi?
// Örnek verinin bu ayki her ödenmemiş kalemi tek tek işaretlenir, sonra işaret kaldırılır.
// Sonuç CI çıktısında "ODEME" satırlarıyla da görünür.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/motor/motorlar.dart';

Data _sample() {
  final raw = jsonDecode(File('assets/sample/ornek.json').readAsStringSync());
  return normalizeData(raw).data!;
}

Data _kopya(Data d) => Data(deepCopy(d.j) as Json);

void main() {
  setUpAll(() => clock = () => DateTime(2026, 11, 20, 12));
  tearDownAll(() => clock = DateTime.now);

  test('Plan: ödendi işareti hesaptaki parayı, borcu ve ay özetini birlikte değiştirir; işaret kalkınca geri gelir', () {
    final d0 = _sample();
    final c0 = Ctx(d0);
    final m = c0.cur;
    final rapor = <String>[];
    var denenen = 0;
    for (final it in c0.items(m)) {
      if (it.pay != null || it.planned <= 0) continue;
      denenen++;
      final d = _kopya(d0);
      final once = Ctx(d);
      final eski = _kopya(d);
      final from = markPaid(d, once.model, it, m);
      expect(uyumDenetimi(eski, d), isEmpty, reason: it.name);
      final sonra = Ctx(d);
      final nakit = sonra.model.liquid - once.model.liquid;
      final satir = '${it.kind} "${it.name}"${it.viaCard ? ' (karttan)' : ''}';
      if (from != null) {
        // Hesaptan ödendi: o hesap ve hesaplardaki toplam para (Özet) ödenen kadar azalır
        expect(nakit, -it.planned, reason: '$satir: hesaplardaki para ödenen kadar azalmalı');
        final acc = srcAcc(from)!;
        expect(toK(d.account(acc)!.balance), toK(eski.account(acc)!.balance) - it.planned, reason: '$satir: $acc');
      } else {
        expect(nakit, 0, reason: '$satir: hesap seçilmediyse para değişmez');
      }
      String borc = '';
      if (it.viaCard) {
        // Karttan ödenen abonelik: kartın borcuna eklenir, boş limit azalır (Melih'in kararı)
        final cid = srcCard(d.subscription(it.refId)!.source)!;
        final a = once.model.debts[cid]!.current, b = sonra.model.debts[cid]!.current;
        expect(b - a, it.planned, reason: '$satir: kart borcuna eklenmeli');
        expect(sonra.model.cardAvail, once.model.cardAvail - it.planned, reason: '$satir: boş limit azalmalı');
        borc = ', kart borcu ${fromK(b - a)} TL arttı';
      }
      if (it.kind == 'debt') {
        final a = once.model.debts[it.refId]!.current, b = sonra.model.debts[it.refId]!.current;
        expect(b, lessThan(a), reason: '$satir: borç azalmalı');
        borc = ', borç ${fromK(a - b)} TL azaldı';
      }
      // Plan: kalem ödendi görünür, ayın ödenen toplamı artar
      final yeni = sonra.items(m).firstWhere((x) => x.kind == it.kind && x.refId == it.refId);
      expect(yeni.pay, isNotNull, reason: satir);
      expect(sonra.sum(m).paid, once.sum(m).paid + it.planned, reason: satir);
      // İşaret kalkınca para ve borç geri gelir
      final eski2 = _kopya(d);
      removePaymentFor(d, it.kind, it.refId, m);
      expect(uyumDenetimi(eski2, d), isEmpty, reason: '$satir: işaret kaldırma');
      final geri = Ctx(d);
      expect(geri.model.liquid, once.model.liquid, reason: '$satir: işaret kalkınca para geri gelmeli');
      expect(geri.model.cardDebt, once.model.cardDebt, reason: '$satir: işaret kalkınca kart borcu geri gelmeli');
      if (it.kind == 'debt') expect(geri.model.debts[it.refId]!.current, once.model.debts[it.refId]!.current, reason: satir);
      rapor.add('ODEME $satir ${fromK(it.planned)} TL: ${from == null ? 'hesaptan düşülmedi' : '${sourceName(d, from, 'tr')} −${fromK(it.planned)} TL'}$borc');
    }
    debugPrint(rapor.join('\n'));
    expect(denenen, greaterThan(3));
  });

  test('ödeme tutarı ya da hesabı değişince eski ödeme geri eklenir, yenisi düşülür', () {
    final d = _sample();
    final c = Ctx(d);
    final it = c.items(c.cur).firstWhere((x) => x.kind == 'expense' && x.pay == null && x.planned > 0);
    final once = c.model.liquid;
    savePayment(d, kind: it.kind, refId: it.refId, month: c.cur, k: 100000, date: todayISO(), from: 'acc:akbank-vadesiz');
    expect(Ctx(d).model.liquid, once - 100000);
    // Tutar ve hesap değişir: eskisi geri, yenisi düşülür
    savePayment(d, kind: it.kind, refId: it.refId, month: c.cur, k: 40000, date: todayISO(), from: 'acc:enpara-vadesiz');
    expect(Ctx(d).model.liquid, once - 40000);
    removePaymentFor(d, it.kind, it.refId, c.cur);
    expect(Ctx(d).model.liquid, once);
  });

  test('hesabı bilinmeyen kalem: seçilen hesaptan düşülür, sonraki ay o hesap kullanılır; "hesaptan düşme" seçilirse para değişmez', () {
    final d = _sample();
    // Hiç ödenmemiş, hesabı seçilmemiş yeni bir sabit gider
    saveExpense(d, <String, dynamic>{
      'name': 'Aidat', 'category': 'kira', 'amount': 1500, 'startMonth': '2026-11', 'endMonth': null, 'day': 25,
      'linkedDebtIds': <String>[], 'note': '',
    });
    final c = Ctx(d);
    final it = c.items(c.cur).firstWhere((x) => x.name == 'Aidat');
    expect(defaultPayFrom(d, it), isNull, reason: 'hesabı bilinmiyor: Plan sorar');
    final eski = _kopya(d);
    expect(markPaid(d, c.model, it, c.cur, from: 'acc:enpara-vadesiz'), 'acc:enpara-vadesiz');
    expect(uyumDenetimi(eski, d), isEmpty);
    expect(toK(d.account('enpara-vadesiz')!.balance), toK(eski.account('enpara-vadesiz')!.balance) - 150000);
    // Sonraki ay: aynı hesap varsayılan
    final c2 = Ctx(d);
    final sonraki = c2.items(addM(c2.cur, 1)).firstWhere((x) => x.name == 'Aidat');
    expect(defaultPayFrom(d, sonraki), 'acc:enpara-vadesiz');
    // "Hesaptan düşme": para değişmez
    final d2 = _kopya(eski);
    final c3 = Ctx(d2);
    expect(markPaid(d2, c3.model, c3.items(c3.cur).firstWhere((x) => x.name == 'Aidat'), c3.cur, hesapsiz: true), isNull);
    expect(Ctx(d2).model.liquid, c3.model.liquid);
  });

  test('karttan ödenen abonelik: kesimden sonraki ödeme kart borcuna eklenir, kesimden önceki (ekstrede olan) eklenmez', () {
    final d = _sample();
    final kart = d.debt('akbank-axess')!;
    final once = Ctx(d).model.debts['akbank-axess']!.current;
    // Kesimden önce (bakiye tarihinden önce) işaretlenmiş ödeme: kartın girilen borcunda zaten var
    savePayment(d, kind: 'sub', refId: 'netflix', month: '2026-10', k: 22999, date: '2026-10-02');
    expect(Ctx(d).model.debts['akbank-axess']!.current, once, reason: 'bakiye tarihi ${kart.balanceDate}');
    // Kesimden sonra: borca eklenir
    savePayment(d, kind: 'sub', refId: 'netflix', month: '2026-11', k: 22999, date: '2026-11-15');
    expect(Ctx(d).model.debts['akbank-axess']!.current, once + 22999);
  });
}
