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

/// Garanti benzeri hesap hareketleri: en yeni üstte, etiket sütunu, "+/-" işaretli tutar, özette
/// "Bakiye" ve "Kullanılabilir Bakiye"; açıklamalarda tutara benzeyen sayılar (uydurma kişi ve hesap).
const List<List<String>> _hesapHareketleri = [
  [
    'T. Garanti Bankası A.Ş.',
    'www.garantibbva.com.tr',
    'Sayın AYŞE YILMAZ, 08 Kasım 2026 tarihi saat 10:00 itibarıyla 01/11/2026 - 08/11/2026 tarihleri arasındaki Hesap Hareketleri bilgileriniz aşağıdaki gibidir.',
    'Ad Soyad / Unvan\t: AYŞE YILMAZ',
    'IBAN\t: TR12 0006 2000 1110 0001 2345 67',
    'Bakiye\t:\t7.050,81 TL',
    'Kullanılabilir Bakiye\t:\t35.650,81 TL',
    '01/11/2026 - 08/11/2026 aralığında 12 kayıt bulunmuştur.',
    'Tarih\tAçıklama\tEtiket\tTutar\tBakiye',
    '07.11.2026\tYanımda Hesaptan Transfer, Yanımda Toplam: 28.600,00 TL\tYatırım\t+1.400,00 TL\t7.050,81 TL',
    '07.11.2026\t1234- 10.00USD-SPOTIFY P1-SATIŞ\tAlışveriş\t-341,63 TL\t5.650,81 TL',
    '07.11.2026\t1234- 12.00USD-ANTHROPIC* C-SATIŞ\tAlışveriş\t-412,80 TL\t5.992,44 TL',
    '06.11.2026\t1234- 179.99TL -Google One -SATIŞ\tAlışveriş\t-179,99 TL\t6.405,24 TL',
    '06.11.2026\tSATIŞ-517040*1234-YEMEKPAY *YEMEKSEPETİ\tAlışveriş\t-356,40 TL\t6.585,23 TL',
    '06.11.2026\tSATIŞ-517040*1234-MİGROS KADIKÖY\tAlışveriş\t-263,45 TL\t6.941,63 TL',
    '05.11.2026\tMehmet Kaya-FAST-CEP ŞUBE-1000000002\tPara Transferi\t-1.000,00 TL\t7.205,08 TL',
    '05.11.2026\tAYŞE YILMAZ-FAST-CEP ŞUBE-1000000001\tPara Transferi\t-2.000,00 TL\t8.205,08 TL',
    '05.11.2026\tKESİNTİ VE EKLERİ-\tDiğer\t-8,37 TL\t10.205,08 TL',
    '04.11.2026\tYanımda Hesaba Transfer, Yanımda Toplam: 30.000,00 TL\tYatırım\t-30.000,00 TL\t10.213,45 TL',
    // İşaretsiz tutar: yön yürüyen bakiyeden (döküm yeniden eskiye)
    '03.11.2026\tAESAŞ- 1000000001 2OF20260000000001\tKurum Ödemesi\t786,55 TL\t40.213,45 TL',
    '03.11.2026\tEKİM MAAŞ ÖDEMESİ\tMaaş\t+40.000,00 TL\t41.000,00 TL',
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

  test('hesap hareketleri (en yeni üstte): para kullanılabilir bakiyeden, yön işaretten ya da bakiyeden, kendi hesapların arası', () {
    final o = ekstreOku(_hesapHareketleri);
    expect(o.tur, EkstreTuru.hesap);
    expect(o.banka, 'garanti');
    expect(o.iban4, '4567');
    expect(o.kapanisBakiye, 3565081, reason: 'özetteki "Kullanılabilir Bakiye" (Yanımda dahil)');
    expect(o.donemSonu, '2026-11-08');
    expect(o.islemler.map((i) => '${i.tur} ${i.k} ${i.ad}'), [
      "aktarma 140000 Yanımda'dan",
      'cikis 34163 Spotify', // açıklamadaki "10.00USD" tutar sayılmaz
      'cikis 41280 Anthropic',
      'cikis 17999 Google One',
      'cikis 35640 Yemeksepeti',
      'cikis 26345 Migros',
      'cikis 100000 Mehmet Kaya', // başkasına FAST
      'aktarma 200000 Ayşe Yılmaz', // kendi adına FAST
      'cikis 837 Banka kesintisi',
      "aktarma 3000000 Yanımda'ya",
      'cikis 78655 AESAŞ', // işaretsiz: bakiye düştü
      'giris 4000000 Ekim Maaş Ödemesi',
    ]);
    String? kategori(String ad) => o.islemler.firstWhere((i) => i.ad == ad).kategori;
    expect(kategori('Mehmet Kaya'), 'transfer');
    expect(kategori('Banka kesintisi'), 'banka');
    expect(kategori('AESAŞ'), 'fatura');
    expect(kategori('Yemeksepeti'), 'yemek');
    expect(kategori('Google One'), 'abonelik');
    expect(o.islemler.firstWhere((i) => i.ad == 'Migros').etiket, 'Alışveriş');
  });

  test('kısa adlar: kart numarası, SATIŞ, döviz tutarı, aracı ve referanslar atılır; abonelikler tanınır', () {
    EkstreAdi a(String s) => ekstreAdi(s);
    expect(a('SATIŞ-517040*1234-IYZICO *AMAZONPRİME').ad, 'Amazon Prime');
    expect(a('SATIŞ-517040*1234-IYZICO *AMAZONPRİME').abonelik, 'video');
    expect(a('1234- 24.00USD-ANTHROPIC* C-SATIŞ').ad, 'Anthropic');
    expect(a('1234- 24.00USD-ANTHROPIC* C-SATIŞ').abonelik, 'yz');
    expect(a('1234- 179.99TL -Google One -SATIŞ').abonelik, 'bulut');
    expect(a('SATIŞ-517040*1234-YEMEKPAY *YEMEKSEPETİ').ad, 'Yemeksepeti');
    expect(a('SATIŞ-517040*1234-YEMEKPAY *YEMEKSEPETİ').abonelik, isNull);
    expect(a('SATIŞ-517040*1234-UBER EATS YEMEK').ad, 'Uber Eats');
    expect(a('ALİ VELİ--HVL-CEP ŞUBE').ad, 'Ali Veli');
    expect(a('VODAFO 5000000001 AB12345CD6789').ad, 'Vodafone');
    expect(a('İGDAŞ-TES500000000001-FAT40000000001A').ad, 'İGDAŞ');
    expect(a('00123/4567890 VERGİ').ad, 'Vergi');
    expect(a('FAİZ % 10,00000').ad, 'Faiz');
    expect(a('BİLİNMEYEN DÜKKAN 1234567 KADIKÖY').ad, 'Bilinmeyen Dükkan Kadıköy');
  });

  test('hesap hareketleri uygulanır: maaş yattı, fatura ve abonelik ödendi, kayıtsız abonelikler eklenir, aktarmalar harcama değil; ikinci kez eklenmez', () {
    final d = _sample();
    final o = ekstreOku(_hesapHareketleri);
    final h = ekstreHedefleri(d, o);
    expect(h.first.yeni, isTrue, reason: 'örnek veride Garanti hesabı yok');
    final e = ekstreEslestir(d, o, h.first);
    EkstreEslesme bul(String ad) => e.firstWhere((x) => x.islem.ad == ad);
    expect(bul('Spotify').abonelikId, 'spotify');
    expect(bul('AESAŞ').abonelikId, 'elektrik', reason: 'elektrik dağıtım şirketi ↔ "Elektrik" faturası');
    expect(bul('Ekim Maaş Ödemesi').gelirId, 'maas');
    expect(bul('Anthropic').yeniAbonelik, isTrue, reason: 'örnek veride kayıtlı değil');
    expect(bul('Google One').yeniAbonelik, isTrue);
    expect(bul('Yemeksepeti').yeniAbonelik, isFalse);
    expect(e.where((x) => x.islem.tur == 'aktarma').map((x) => x.durum).toSet(), {EslesmeDurumu.eklenmez});

    final once = _kopya(d);
    final id = ekstreUygula(d, o, h.first, _eklenecek(e));
    expect(uyumDenetimi(once, d), isEmpty);
    final src = 'acc:$id';
    final a = d.account(id)!;
    expect(a.bank, 'garanti');
    expect(a.j['iban4'], '4567');
    expect(toK(a.balance), 3565081);
    expect(toK(d.incomes.firstWhere((i) => i.id == 'maas').monthAmounts['2026-11']), 4000000);
    expect(d.transfers.where((t) => t.to == src && t.incomeRef != null).map((t) => toK(t.amount)), [4000000]);
    bool odendi(String sub) => d.payments.any((p) => p.kind == 'sub' && p.refId == sub && p.month == '2026-11' && p.fromAccount == src);
    expect(odendi('elektrik'), isTrue);
    expect(odendi('spotify'), isTrue);
    // Kayıtsız abonelikler: adı, grubu, tutarı, günü ve kaynağı ekstreden; bu ay ödendi
    final anthropic = d.subscriptions.firstWhere((x) => x.name == 'Anthropic');
    expect(anthropic.group, 'yz');
    expect(toK(anthropic.amount), 41280);
    expect(anthropic.j['day'], 7);
    expect(anthropic.j['source'], src);
    expect(odendi(anthropic.id), isTrue);
    final googleOne = d.subscriptions.firstWhere((x) => x.name == 'Google One');
    expect(googleOne.group, 'bulut');
    expect(odendi(googleOne.id), isTrue);
    expect(d.spends.where((s) => s.source == src).map((s) => '${s.name} ${toK(s.amount)} ${s.category}'),
        unorderedEquals(['Yemeksepeti 35640 yemek', 'Migros 26345 market', 'Mehmet Kaya 100000 transfer', 'Banka kesintisi 837 banka']));

    // Aynı döküm yeniden: hesap IBAN'ın son 4 hanesiyle bulunur, hiçbir işlem yeni değil, abonelik iki kez açılmaz
    final h2 = ekstreHedefleri(d, o);
    expect(h2.first.id, id);
    expect(_eklenecek(ekstreEslestir(d, o, h2.first)), isEmpty);
    expect(d.subscriptions.where((x) => x.name == 'Anthropic').length, 1);
  });

  test('PDF harfleri okuma sırasıyla: satır sonu, kelime boşluğu, sütun aralığı; noktalama ayrı satır olmaz', () {
    PdfHarf h(String c, double x, {double y = 700, double boy = 10}) => PdfHarf(c, x, y + boy, x + 6, y);
    final harfler = <PdfHarf>[
      h('A', 10), h('.', 16, y: 698, boy: 2), h('Ş', 22, boy: 13), h('.', 28, y: 698, boy: 2),
      h(' ', 34), h('B', 40),
      for (var i = 0; i < 5; i++) h('12,50'[i], 120 + i * 6.0, y: 699),
      const PdfHarf('\r', 0, 0, 0, 0), const PdfHarf('\n', 0, 0, 0, 0),
      h('X', 10, y: 680), h('Y', 16, y: 680),
    ];
    expect(satirlariKur(harfler), ['A.Ş. B\t12,50', 'XY']);
  });

  test('PDF harflerinden satırlar kurulur (okuma sırasında satır sonu yoksa): boşluklar ve sütunlar', () {
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
