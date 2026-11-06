// Ekstre Motoru: banka ve belge türü tanıma, özet ve işlem okuma, kart/hesap bulma, eşleştirme,
// uygulama ve uyum. Bütün ekstreler uydurmadır (gerçek kişi, kart ya da hesap bilgisi yok).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/motor/motorlar.dart';
import 'package:mel_capital/src/sheets/ekstre.dart' show kOrnekEkstreSatirlari;

Data _sample() {
  final raw = jsonDecode(File('assets/sample/ornek.json').readAsStringSync());
  final n = normalizeData(raw);
  expect(n.errors, isEmpty);
  return n.data!;
}

Data _kopya(Data d) => Data(deepCopy(d.j) as Json);

/// Başka bir düzen: başlık ve değer aynı hücrede, ödemeler "+" ile, puan sütunu var.
const List<List<String>> _garantiBenzeri = [
  [
    'Türkiye Garanti Bankası A.Ş.',
    'Bonus Platinum   Kart Numarası: 4000 12** **** 7788',
    'Hesap Kesim Tarihi: 05/11/2026',
    'Son Ödeme Tarihi: 15/11/2026',
    'Dönem Borcu: 3.210,40 TL',
    'Asgari Ödeme Tutarı: 642,08 TL',
    'Kart Limiti: 20.000,00 TL',
    '10/10/2026\tA101 YENİ MAHALLE\t125,90\t0,63',
    '15/10/2026\tÖDEME - TEŞEKKÜR EDERİZ\t2.000,00 +',
    '18/10/2026\tAMAZON TR\t2/4\t500,00\t2,50',
    '21/10/2026\tFAİZ\t12,40',
    'garantibbva.com.tr  444 0 333',
  ],
];

/// Hesap dökümü: yürüyen bakiye sütunuyla.
const List<List<String>> _hesapDokumu = [
  [
    'ENPARA BANK A.Ş.\tHESAP HAREKETLERİ',
    'IBAN: TR12 0001 5001 5800 7300 0012 34',
    'Tarih\tAçıklama\tTutar\tBakiye',
    '01.11.2026\tDevreden Bakiye\t\t5.000,00',
    '03.11.2026\tPOS MİGROS\t-250,00\t4.750,00',
    '05.11.2026\tGELEN EFT MAAŞ\t45.000,00\t49.750,00',
    '07.11.2026\tKREDİ KARTI ÖDEME\t-1.000,00\t48.750,00',
    'www.enpara.com\t0850 222 0 667',
  ],
];

List<EkstreEslesme> _eklenecek(List<EkstreEslesme> e) => [for (final x in e) if (x.durum == EslesmeDurumu.yeni) x];

void main() {
  setUpAll(() => clock = () => DateTime(2026, 11, 20, 12));
  tearDownAll(() => clock = DateTime.now);

  test('banka işaretlerinden tanınır; ortak kart adı (Bonus) tek başına yetmez', () {
    expect(bankaBul(normTxt('AKBANK T.A.Ş. www.akbank.com 444 25 25')).$1, 'akbank');
    expect(bankaBul(normTxt('Türkiye Garanti Bankası A.Ş. Bonus')).$1, 'garanti');
    expect(bankaBul(normTxt('DenizBank A.Ş. Bonus kart')).$1, 'denizbank');
    expect(bankaBul(normTxt('Bonus kart ekstresi')).$1, isNull);
    expect(bankaBul(normTxt('Hiçbir bankaya benzemeyen bir metin')).$1, isNull);
  });

  test('kart ekstresi: tür, banka, son 4 hane, özet ve işlemler', () {
    final o = ekstreOku(kOrnekEkstreSatirlari);
    expect(o.tur, EkstreTuru.kart);
    expect(o.banka, 'akbank');
    expect(o.son4, '4821');
    expect(o.urun, 'Axess');
    expect(o.kesim, '2026-11-03');
    expect(o.sonOdeme, '2026-11-13');
    expect(o.ekstreAyi, '2026-11');
    expect(o.donemBorcu, 256000);
    expect(o.asgari, 51200);
    expect(o.limit, 1500000);
    expect(o.kullanilabilir, 1244000);
    expect(o.guncelBorc, 256000);
    expect(o.islemler.map((i) => i.tur), ['odeme', 'harcama', 'harcama', 'harcama', 'harcama', 'harcama']);
    final migros = o.islemler[1];
    expect(migros.tarih, '2026-10-12');
    expect(migros.k, 41235);
    final teknosa = o.islemler[4];
    expect(teknosa.taksitNo, 1);
    expect(teknosa.taksitSayisi, 3);
    expect(teknosa.k, 100000);
    expect(o.eksikler, isEmpty);
  });

  test('başka düzen: başlık ve değer aynı satırda, ödeme "+", puan sütunu, taksit, faiz', () {
    final o = ekstreOku(_garantiBenzeri);
    expect(o.tur, EkstreTuru.kart);
    expect(o.banka, 'garanti');
    expect(o.son4, '7788');
    expect(o.kesim, '2026-11-05');
    expect(o.sonOdeme, '2026-11-15');
    expect(o.donemBorcu, 321040);
    expect(o.asgari, 64208);
    expect(o.limit, 2000000);
    final turler = {for (final i in o.islemler) i.aciklama: i.tur};
    expect(turler.values.toList(), ['harcama', 'odeme', 'harcama', 'ucret']);
    expect(o.islemler[0].k, 12590, reason: 'puan sütunu tutar sayılmaz');
    expect(o.islemler[2].taksitNo, 2);
    expect(o.islemler[2].taksitSayisi, 4);
    expect(o.islemler[2].k, 50000);
  });

  test('hesap dökümü: yön yürüyen bakiyeden, son bakiye, IBAN son 4', () {
    final o = ekstreOku(_hesapDokumu);
    expect(o.tur, EkstreTuru.hesap);
    expect(o.banka, 'enpara');
    expect(o.iban4, '1234');
    expect(o.acilisBakiye, 500000);
    expect(o.kapanisBakiye, 4875000);
    expect(o.donemSonu, '2026-11-07');
    expect(o.islemler.map((i) => '${i.tur} ${i.k}'), ['cikis 25000', 'giris 4500000', 'cikis 100000']);
  });

  test('ekstre olmayan ya da yazısız PDF okunmuş sayılmaz', () {
    expect(ekstreOku(const [[]]).okundu, isFalse);
    expect(ekstreOku(const [
      ['Fatura', 'Toplam 120,00 TL']
    ]).okundu, isFalse);
  });

  test('kart: banka ile kendiliğinden bulunur, eklenir, uyum bozulmaz; aynı ekstre ikinci kez eklenmez', () {
    final d = _sample();
    final o = ekstreOku(kOrnekEkstreSatirlari);
    final hedefler = ekstreHedefleri(d, o);
    expect(hedefler.first.id, 'akbank-axess');
    expect(hedefler.first.kesin, isTrue);
    expect(hedefler.last.yeni, isTrue);

    final e = ekstreEslestir(d, o, hedefler.first);
    final once = _kopya(d);
    final ekle = _eklenecek(e);
    expect(ekle, isNotEmpty);
    ekstreUygula(d, o, hedefler.first, ekle);
    expect(uyumDenetimi(once, d), isEmpty);

    final kart = d.debt('akbank-axess')!;
    expect(kart.j['last4'], '4821');
    expect(kart.balanceDate, '2026-11-03');
    expect(toK(kart.limit), 1500000);
    expect(kart.statements.any((s) => s.month == '2026-11' && toK(s.total) == 256000), isTrue);
    // Güncel borç kesimdeki borçtan başlar; ekstredeki (kesimden önceki) işlemler ayrıca eklenmez
    final info = Ctx(d).model.debts['akbank-axess']!;
    expect(info.initial, 256000);
    expect(info.snap, '2026-11-03');
    var sonra = 0;
    for (final s in d.spends) {
      if (s.source != 'card:akbank-axess') continue;
      if (s.date.compareTo('2026-11-03') > 0 || (s.date == '2026-11-03' && (s.createdAt ?? '').compareTo('2026-11-03T23:59:59.999Z') > 0)) sonra += toK(s.amount);
    }
    expect(info.purchAdd, sonra);
    // Taksitli alışveriş toplam tutarla ve 3 taksitle girildi
    final teknosa = d.spends.firstWhere((s) => s.name.startsWith('Teknosa'));
    expect(toK(teknosa.amount), 300000);
    expect(teknosa.installments, 3);
    expect(teknosa.firstMonth, '2026-11');

    // Aynı ekstre yeniden: artık son 4 haneyle bulunur, hiçbir işlem yeni değil
    final h2 = ekstreHedefleri(d, o);
    expect(h2.first.id, 'akbank-axess');
    expect(h2.first.neden, 'son 4 hane');
    final e2 = ekstreEslestir(d, o, h2.first);
    expect(_eklenecek(e2), isEmpty);
  });

  test('kart yoksa yeni kart açılır', () {
    final d = _sample();
    final o = ekstreOku(_garantiBenzeri);
    final hedefler = ekstreHedefleri(d, o);
    expect(hedefler.single.yeni, isTrue, reason: 'örnek veride Garanti kartı yok');
    final once = _kopya(d);
    final id = ekstreUygula(d, o, hedefler.single, _eklenecek(ekstreEslestir(d, o, hedefler.single)));
    expect(uyumDenetimi(once, d), isEmpty);
    final kart = d.debt(id)!;
    expect(kart.isCard, isTrue);
    expect(kart.bank, 'garanti');
    expect(kart.j['last4'], '7788');
    expect(kart.statementDay, 5);
    expect(kart.dueDay, 15);
  });

  test('hesap: bulunur, eksik hareketler eklenir, bakiye dökümle başlar', () {
    final d = _sample();
    final o = ekstreOku(_hesapDokumu);
    final hedefler = ekstreHedefleri(d, o);
    expect(hedefler.first.id, 'enpara-vadesiz');
    expect(hedefler.first.kesin, isTrue);
    var sonra = 0;
    for (final s in d.spends) {
      if (s.source == 'acc:enpara-vadesiz' && s.date.compareTo('2026-11-07') > 0) sonra -= toK(s.amount);
    }
    for (final t in d.transfers) {
      if (t.date.compareTo('2026-11-07') <= 0) continue;
      if (t.to == 'acc:enpara-vadesiz') sonra += toK(t.amount);
      if (t.from == 'acc:enpara-vadesiz') sonra -= toK(t.amount);
    }
    for (final p in d.payments) {
      if (p.viaRefId == null && p.fromAccount == 'acc:enpara-vadesiz' && (p.paidDate ?? '').compareTo('2026-11-07') > 0) sonra -= toK(p.paidAmount);
    }
    final once = _kopya(d);
    ekstreUygula(d, o, hedefler.first, _eklenecek(ekstreEslestir(d, o, hedefler.first)));
    expect(uyumDenetimi(once, d), isEmpty);
    final a = d.account('enpara-vadesiz')!;
    expect(toK(a.balance), 4875000 + sonra);
    expect(a.j['iban4'], '1234');
    expect(d.transfers.any((t) => t.from == 'ext' && t.to == 'acc:enpara-vadesiz' && toK(t.amount) == 4500000), isTrue);
    expect(d.spends.any((s) => s.source == 'acc:enpara-vadesiz' && s.category == 'kart_asgari' && toK(s.amount) == 100000), isTrue);
    // İkinci kez: hepsi zaten var
    expect(_eklenecek(ekstreEslestir(d, o, ekstreHedefleri(d, o).first)), isEmpty);
  });

  test('elle girilmiş harcama "zaten var" ya da "bu o mu?" olur', () {
    final d = _sample();
    saveSpend(d, <String, dynamic>{
      'date': '2026-10-12', 'name': 'Migros', 'place': '', 'category': 'market', 'amount': 412.35,
      'source': 'card:akbank-axess', 'installments': 1, 'firstMonth': '2026-11', 'note': '', 'url': '',
    });
    saveSpend(d, <String, dynamic>{
      'date': '2026-10-21', 'name': 'Kahve', 'place': '', 'category': 'kafe', 'amount': 185,
      'source': 'card:akbank-axess', 'installments': 1, 'firstMonth': '2026-11', 'note': '', 'url': '',
    });
    final o = ekstreOku(kOrnekEkstreSatirlari);
    final e = ekstreEslestir(d, o, ekstreHedefleri(d, o).first);
    final migros = e.firstWhere((x) => x.islem.aciklama.contains('MİGROS'));
    expect(migros.durum, EslesmeDurumu.var_);
    final starbucks = e.firstWhere((x) => x.islem.aciklama.contains('STARBUCKS'));
    expect(starbucks.durum, EslesmeDurumu.supheli, reason: 'aynı tutar, 2 gün fark, adı farklı');
    final odeme = e.firstWhere((x) => x.islem.tur == 'odeme');
    expect(odeme.durum, EslesmeDurumu.eklenmez);
  });

  test('PDF harflerinden satırlar kurulur: boşluklar ve sütunlar', () {
    PdfHarf h(String c, double x, double y) => PdfHarf(c, x, y + 10, x + 6, y);
    final harfler = <PdfHarf>[
      // Aynı satır (y=700): "AB CD" sonra sütun aralığı, "12,00"
      h('A', 10, 700), h('B', 16, 700), h('C', 26, 700.4), h('D', 32, 700),
      for (var i = 0; i < 5; i++) h('12,00'[i], 100 + i * 6.0, 699.8),
      // Alt satır (y=680)
      h('X', 10, 680), h('Y', 16, 680),
    ];
    expect(satirlariKur(harfler), ['AB CD\t12,00', 'XY']);
  });
}
