// Borç kapatma hesabı (Borç Motoru: kapatmaHesapla, kapatmaIcinAylik, kapatmaBorclari).
// Bütün borçlar uydurmadır. Tutarlar kuruş (100000 = 1.000 TL).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/motor/motorlar.dart';

KapatmaBorcu kredi(String id, int taksit, int adet, {double oran = 0, int? kalanK}) =>
    KapatmaBorcu(id: id, ad: id, kart: false, kalanK: kalanK ?? taksit * adet, taksitler: List<int>.filled(adet, taksit), oran: oran);

KapatmaBorcu kart(String id, int kalanK, {double oran = 0}) => KapatmaBorcu(id: id, ad: id, kart: true, kalanK: kalanK, oran: oran);

void main() {
  setUpAll(() => clock = () => DateTime(2026, 11, 20, 12));
  tearDownAll(() => clock = DateTime.now);

  test('faizsiz kredi: plan olduğu gibi yürür; toplu ödeme son taksitlerden düşer; aylık tutar erken bitirir', () {
    final b = [kredi('k', 100000, 10)];
    final temel = kapatmaHesapla(b);
    expect(temel.bitti, isTrue);
    expect(temel.bitisAy, 9);
    expect(temel.toplamK, 1000000);
    expect(temel.faizK, 0);
    expect(temel.ilkZorunluK, 100000);
    expect(temel.aylar.length, 10);
    expect(temel.kapanis['k'], 9);
    // 2.500 TL toplu: 2,5 taksit düşer → 2 ay erken, son taksit yarım
    final toplu = kapatmaHesapla(b, topluK: 250000);
    expect(toplu.bitisAy, 7);
    expect(toplu.toplamK, 1000000);
    expect(toplu.aylar.first.odemeK, 350000);
    expect(toplu.aylar.last.odemeK, 50000);
    // Ayda 2.000 TL: 5 ayda biter
    final aylik = kapatmaHesapla(b, aylikK: 200000);
    expect(aylik.bitisAy, 4);
    expect(aylik.toplamK, 1000000);
    // Taksitin altında tutar: taksitler yine de ödenir
    expect(kapatmaHesapla(b, aylikK: 50000).bitisAy, 9);
  });

  test('hedef süre: gereken en küçük aylık tutar (TL\'ye yuvarlı)', () {
    final b = [kredi('k', 100000, 10)];
    expect(kapatmaIcinAylik(b, 10), 0, reason: 'plan zaten 10 ayda bitiyor');
    expect(kapatmaIcinAylik(b, 24), 0);
    expect(kapatmaIcinAylik(b, 5), 200000);
    expect(kapatmaIcinAylik(b, 4), 250000);
    expect(kapatmaIcinAylik(b, 3), 333400, reason: '3 × 3.334 TL ≥ 10.000 TL > 3 × 3.333 TL');
    expect(kapatmaIcinAylik(b, 1), 1000000);
    expect(kapatmaIcinAylik(b, 0), isNull);
    expect(kapatmaIcinAylik(const <KapatmaBorcu>[], 5), isNull);
    // Bulunan tutar gerçekten yetiyor, 1 TL azı yetmiyor
    for (final ay in [2, 3, 6, 7]) {
      final k = kapatmaIcinAylik(b, ay)!;
      expect(kapatmaHesapla(b, aylikK: k).bitisAy, lessThan(ay));
      expect(kapatmaHesapla(b, aylikK: k - 100, enCokAy: ay).bitti, isFalse);
    }
  });

  test('faizli kredi: plan aynı toplamla biter; erken ödeme faizden kazandırır', () {
    final b = [kredi('k', 100000, 10, oran: 2)];
    final temel = kapatmaHesapla(b);
    expect(temel.bitti, isTrue);
    expect(temel.bitisAy, 9);
    expect(temel.toplamK, closeTo(1000000, 2), reason: 'taksitlerin toplamı');
    // Anapara (bugünkü değer) ≈ 9.162 TL; kalan taksitlerin içindeki faiz ≈ 838 TL
    expect(temel.faizK, closeTo(1000000 - 916224, 5));
    final aylik = kapatmaHesapla(b, aylikK: 200000);
    expect(aylik.bitisAy, 4);
    expect(aylik.toplamK, lessThan(temel.toplamK));
    expect(aylik.toplamK, greaterThan(916224));
    expect(aylik.toplamK - 916224, closeTo(aylik.faizK, 5), reason: 'ödenen = anapara + işleyen faiz');
    // Hepsi bu ay ödenirse yalnızca anapara ödenir
    final hepsi = kapatmaHesapla(b, topluK: 1000000);
    expect(hepsi.bitisAy, 0);
    expect(hepsi.toplamK, closeTo(916224, 2));
  });

  test('kart: her ay asgari (%20, en az 100 TL); oran varsa faiz işler', () {
    final temel = kapatmaHesapla([kart('c', 500000)]);
    expect(temel.bitti, isTrue);
    expect(temel.ilkZorunluK, 100000);
    expect(temel.toplamK, 500000);
    expect(temel.aylar[1].odemeK, 80000);
    expect(temel.aylar.last.odemeK, lessThanOrEqualTo(kKapatmaAsgariTabanK));
    final faizli = kapatmaHesapla([kart('c', 500000, oran: 4)]);
    expect(faizli.bitti, isTrue);
    expect(faizli.toplamK, greaterThan(500000));
    expect(faizli.toplamK - 500000, closeTo(faizli.faizK, 30));
    // Ayda 2.500 TL ayrılırsa iki ayda biter
    expect(kapatmaHesapla([kart('c', 500000)], aylikK: 250000).bitisAy, 1);
  });

  test('sıra: faizi yüksek olana ya da en küçük borca; kapanan borcun parası sıradakine geçer', () {
    final b = [kredi('kucuk', 100000, 3, oran: 1), kredi('faizli', 50000, 12, oran: 3)];
    final faiz = kapatmaHesapla(b, aylikK: 250000);
    final kucuk = kapatmaHesapla(b, aylikK: 250000, sira: KapatmaSirasi.kucuk);
    expect(faiz.bitti, isTrue);
    expect(kucuk.bitti, isTrue);
    expect(kucuk.kapanis['kucuk'], 1, reason: 'artan para küçük borca');
    expect(faiz.kapanis['kucuk'], 2, reason: 'artan para faizliye; küçük borç planıyla kapanır');
    expect(faiz.toplamK, lessThanOrEqualTo(kucuk.toplamK), reason: 'faizliyi önce kapatmak daha az faiz öder');
    // Her ay ayrılan tutar aşılmaz (son ay hariç tam o kadar ödenir)
    for (final a in faiz.aylar.take(faiz.aylar.length - 1)) {
      expect(a.odemeK, 250000);
    }
    expect(faiz.aylar.last.odemeK, lessThanOrEqualTo(250000));
    // İkisi de plandan (11 ay) erken biter
    expect(kapatmaHesapla(b).bitisAy, 11);
    expect(faiz.bitisAy, lessThan(11));
  });

  test('planı olmayan borç: yalnızca zorunlu ödemelerle bitmez; ayrılan parayla biter', () {
    final b = [const KapatmaBorcu(id: 'p', ad: 'p', kart: false, kalanK: 500000)];
    final temel = kapatmaHesapla(b);
    expect(temel.bitti, isFalse);
    expect(temel.bitisAy, isNull);
    expect(temel.aylar, isEmpty);
    expect(kapatmaHesapla(b, aylikK: 100000).bitisAy, 4);
    expect(kapatmaIcinAylik(b, 5), 100000);
    // Planın kapsamadığı kısım: taksitler bitince kalan, ayrılan parayla ödenir
    final yarim = [kredi('y', 100000, 3, kalanK: 500000)];
    expect(kapatmaHesapla(yarim).bitti, isFalse);
    expect(kapatmaHesapla(yarim).toplamK, 300000);
    final s = kapatmaHesapla(yarim, aylikK: 100000);
    expect(s.bitisAy, 4);
    expect(s.toplamK, 500000);
  });

  test('örnek veri: açık borçların hepsi hesaba girer; taksitler kalan borcu geçmez', () {
    final d = normalizeData(jsonDecode(File('assets/sample/ornek.json').readAsStringSync())).data!;
    final ctx = Ctx(d);
    final b = kapatmaBorclari(ctx);
    final acik = ctx.model.debts.values.where((x) => x.current > 0).toList();
    expect(b.length, acik.length);
    expect(b, isNotEmpty);
    final toplam = sumK(b, (KapatmaBorcu x) => x.kalanK);
    expect(toplam, sumK(acik, (DebtInfo x) => x.current));
    for (final x in b) {
      expect(x.kart, d.debt(x.id)!.isCard);
      expect(sumK(x.taksitler, (int a) => a), lessThanOrEqualTo(x.kalanK), reason: x.ad);
      if (x.kart) expect(x.taksitler, isEmpty);
    }
    // Hepsi bu ay ödenirse bu ay biter ve (oran girilmediği için) tam borç kadar ödenir
    final hepsi = kapatmaHesapla(b, topluK: toplam);
    expect(hepsi.bitisAy, 0);
    expect(hepsi.toplamK, toplam);
    // Hedef süre: bulunan tutarla süre içinde biter
    final k = kapatmaIcinAylik(b, 12)!;
    expect(kapatmaHesapla(b, aylikK: k, enCokAy: 12).bitti, isTrue);
  });

  test('faiz oranı alanı: isteğe bağlı; geçersiz değer yok sayılır', () {
    expect(Debt(<String, dynamic>{'rate': 3.49}).rate, 3.49);
    expect(Debt(<String, dynamic>{'rate': 2}).rate, 2.0);
    expect(Debt(<String, dynamic>{}).rate, isNull);
    expect(Debt(<String, dynamic>{'rate': 0}).rate, isNull);
    expect(Debt(<String, dynamic>{'rate': -1}).rate, isNull);
    expect(Debt(<String, dynamic>{'rate': 'abc'}).rate, isNull);
    // Kayıt yüklenirken alan korunur
    final raw = jsonDecode(File('assets/sample/ornek.json').readAsStringSync()) as Map<String, dynamic>;
    ((raw['debts'] as List).first as Map<String, dynamic>)['rate'] = 4.25;
    final d = normalizeData(raw).data!;
    expect(d.debts.first.rate, 4.25);
    expect(kapatmaBorclari(Ctx(d)).firstWhere((x) => x.id == d.debts.first.id).oran, 4.25);
  });
}
