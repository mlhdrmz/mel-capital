// Mel Capital — EKSTRE MOTORU
//
// Bankadan alınan PDF ekstreyi (kredi kartı ekstresi ya da hesap dökümü) okur ve uygulamaya ekler.
//   1. [ekstreOku]: PDF'ten çıkan satırlardan belgenin türünü (kart / hesap), bankayı, kartın son 4
//      hanesini, ekstre özetini (kesim, son ödeme, dönem borcu, asgari, limit; hesapta bakiye) ve
//      işlemleri çıkarır. Bankaya özel kalıp gerekmez: bankalar ortak başlıklar kullanır, banka
//      ise değişmeyen işaretlerinden (unvan, internet adresi, telefon, kart programı) tanınır.
//   2. [ekstreHedefleri]: ekstrenin hangi kart ya da hesaba ait olduğunu bulur (son 4 hane, banka,
//      kart adı, limit); yoksa yeni kart/hesap önerir.
//   3. [ekstreEslestir]: işlemleri uygulamadakilerle karşılaştırır: yeni, zaten var, "bu o mu?".
//   4. [ekstreUygula]: seçilenleri Gider Motoru ve Çekirdek üzerinden ekler; ekstreyi son güncel
//      durum sayar (kart borcu ve limit kesim tarihindeki hâliyle; hesap bakiyesi dökümün
//      kullanılabilir bakiyesiyle ve sonrasında uygulamaya girilen hareketlerle). Kayıtlı olmayan
//      abonelikler (bilinen markalar: [ekstreAdi]) aboneliklere eklenir.
// İşlemler kısa adlarıyla eklenir ([ekstreAdi]: "SATIŞ-517040*1234-IYZICO *AMAZONPRİME" → "Amazon
// Prime").
// Hiçbir şey tahminle eklenmez: okunamayanlar [EkstreOkuma.eksikler]'de kullanıcıya söylenir.
// Kart numarasının yalnızca son 4 hanesi (kart kaydında "last4"), IBAN'ın son 4 hanesi (hesapta
// "iban4") saklanır; tam numara hiçbir yerde tutulmaz.

import 'dart:math' as math;

import '../core/brands.dart' show brandIndex;
import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'borc.dart';
import 'cekirdek.dart';
import 'gelir.dart';
import 'gider.dart';
import 'plan.dart';

// ---------------------------------------------------------------- Okuma sonucu

enum EkstreTuru { kart, hesap, bilinmiyor }

/// Ekstredeki bir işlem satırı.
class EkstreIslem {
  const EkstreIslem({
    required this.tarih,
    required this.aciklama,
    required this.k,
    required this.tur,
    this.taksitNo,
    this.taksitSayisi,
    this.etiket,
    this.kategori,
    this.arti = false,
    this.ham = '',
  });

  /// YYYY-AA-GG
  final String tarih;
  final String aciklama;

  /// Kuruş, her zaman artı. Yönü [tur] ve [arti] söyler.
  final int k;

  /// harcama | ucret | odeme | iade (kart); cikis | giris | aktarma (hesap; aktarma: kendi
  /// hesapların arası, ör. "Yanımda" ya da kendi adına havale)
  final String tur;
  final int? taksitNo;
  final int? taksitSayisi;

  /// Bankanın verdiği etiket (ör. "Alışveriş", "Kurum Ödemesi", "Maaş").
  final String? etiket;

  /// Etiketten çıkan kategori (yoksa harcama adından tahmin edilir).
  final String? kategori;

  /// Para girdi mi (hesaba giriş, karta ödeme ya da iade).
  final bool arti;
  final String ham;

  bool get taksitli => (taksitSayisi ?? 1) > 1;

  /// Uygulamaya eklenebilir mi (kart ödemeleri, iadeler ve kendi hesapların arası eklenmez).
  bool get eklenebilir => tur == 'harcama' || tur == 'ucret' || tur == 'cikis' || tur == 'giris';

  /// Kısa adı (ör. "Google One"); panelde ve eklenen kayıtlarda bu görünür.
  String get ad => ekstreAdi(aciklama).ad;

  /// Bilinen bir abonelikse grubu ([kSubGroups] anahtarı), değilse null.
  String? get abonelikGrubu => ekstreAdi(aciklama).abonelik;
}

/// Bir işlemin kısa adı ve ne olduğu.
class EkstreAdi {
  const EkstreAdi(this.ad, {this.abonelik, this.kategori});
  final String ad;

  /// Abonelikse grubu ([kSubGroups] anahtarı).
  final String? abonelik;

  /// Bilinen işyerinin kategorisi ([kCategories] anahtarı).
  final String? kategori;
}

class _Bilinen {
  const _Bilinen(this.desen, this.ad, {this.abonelik, this.kategori});

  /// Boşluksuz, küçük harfli, Türkçe harfsiz açıklamada aranır.
  final String desen;
  final String ad;
  final String? abonelik;
  final String? kategori;
}

/// Ekstrelerde sık görülen işyerleri: kısa ad, abonelikse grubu ve kategori. Özel olanlar genelden
/// önce (ör. "ubereats" "uber"den, "amazonprime" "amazon"dan önce).
const List<_Bilinen> _bilinenler = [
  // Yapay zekâ
  _Bilinen(r'anthropic|claude', 'Anthropic', abonelik: 'yz', kategori: 'abonelik'),
  _Bilinen(r'openai|chatgpt', 'ChatGPT', abonelik: 'yz', kategori: 'abonelik'),
  _Bilinen(r'midjourney', 'Midjourney', abonelik: 'yz', kategori: 'abonelik'),
  _Bilinen(r'perplexity', 'Perplexity', abonelik: 'yz', kategori: 'abonelik'),
  _Bilinen(r'cursor\.?(sh|com|ai)|anysphere', 'Cursor', abonelik: 'yz', kategori: 'abonelik'),
  // Bulut, video, müzik
  _Bilinen(r'googleone', 'Google One', abonelik: 'bulut', kategori: 'abonelik'),
  _Bilinen(r'icloud', 'iCloud+', abonelik: 'bulut', kategori: 'abonelik'),
  _Bilinen(r'dropbox', 'Dropbox', abonelik: 'bulut', kategori: 'abonelik'),
  _Bilinen(r'youtube', 'YouTube Premium', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'amazonprime|primevideo|amznprime', 'Amazon Prime', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'netflix', 'Netflix', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'disney', 'Disney+', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'exxen', 'Exxen', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'blutv', 'BluTV', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'hbomax', 'HBO Max', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'mubi', 'MUBI', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'beinconnect|todtv', 'TOD', abonelik: 'video', kategori: 'abonelik'),
  _Bilinen(r'spotify', 'Spotify', abonelik: 'muzik', kategori: 'abonelik'),
  _Bilinen(r'applemusic', 'Apple Music', abonelik: 'muzik', kategori: 'abonelik'),
  _Bilinen(r'storytel', 'Storytel', abonelik: 'muzik', kategori: 'abonelik'),
  _Bilinen(r'audible', 'Audible', abonelik: 'muzik', kategori: 'abonelik'),
  // İş, güvenlik, oyun, yayıncı
  _Bilinen(r'microsoft365|office365', 'Microsoft 365', abonelik: 'is', kategori: 'abonelik'),
  _Bilinen(r'adobe', 'Adobe', abonelik: 'is', kategori: 'abonelik'),
  _Bilinen(r'canva', 'Canva', abonelik: 'is', kategori: 'abonelik'),
  _Bilinen(r'notion', 'Notion', abonelik: 'is', kategori: 'abonelik'),
  _Bilinen(r'github', 'GitHub', abonelik: 'is', kategori: 'abonelik'),
  _Bilinen(r'linkedin', 'LinkedIn Premium', abonelik: 'is', kategori: 'abonelik'),
  _Bilinen(r'duolingo', 'Duolingo', abonelik: 'diger', kategori: 'abonelik'),
  _Bilinen(r'nordvpn', 'NordVPN', abonelik: 'guvenlik', kategori: 'abonelik'),
  _Bilinen(r'surfshark', 'Surfshark', abonelik: 'guvenlik', kategori: 'abonelik'),
  _Bilinen(r'expressvpn', 'ExpressVPN', abonelik: 'guvenlik', kategori: 'abonelik'),
  _Bilinen(r'xbox|gamepass', 'Xbox Game Pass', abonelik: 'oyun', kategori: 'abonelik'),
  _Bilinen(r'patreon', 'Patreon', abonelik: 'yayin', kategori: 'abonelik'),
  _Bilinen(r'twitch', 'Twitch', abonelik: 'yayin', kategori: 'abonelik'),
  // Abonelik olmayanlar
  _Bilinen(r'googleplay', 'Google Play', kategori: 'eglence'),
  _Bilinen(r'steam', 'Steam', kategori: 'eglence'),
  _Bilinen(r'playstation|sonyinteractive', 'PlayStation', kategori: 'eglence'),
  _Bilinen(r'yemeksepeti|yemekpay', 'Yemeksepeti', kategori: 'yemek'),
  _Bilinen(r'ubereats', 'Uber Eats', kategori: 'yemek'),
  _Bilinen(r'trendyolyemek|trendyolgo', 'Trendyol Go', kategori: 'yemek'),
  _Bilinen(r'getir', 'Getir'),
  _Bilinen(r'trendyol', 'Trendyol', kategori: 'alisveris'),
  _Bilinen(r'hepsiburada', 'Hepsiburada', kategori: 'alisveris'),
  _Bilinen(r'amazon|amzn', 'Amazon', kategori: 'alisveris'),
  _Bilinen(r'temu', 'Temu', kategori: 'alisveris'),
  _Bilinen(r'aliexpress', 'AliExpress', kategori: 'alisveris'),
  _Bilinen(r'migros', 'Migros', kategori: 'market'),
  _Bilinen(r'carrefour', 'CarrefourSA', kategori: 'market'),
  _Bilinen(r'^a101', 'A101', kategori: 'market'),
  _Bilinen(r'starbucks', 'Starbucks', kategori: 'kafe'),
  _Bilinen(r'^uber|bitaksi', 'Uber', kategori: 'ulasim'),
  // Faturalar (kayıtlı faturayla eşleşir; eşleşmezse harcama olarak eklenir)
  _Bilinen(r'^vodafo', 'Vodafone', kategori: 'fatura'),
  _Bilinen(r'^turkcell', 'Turkcell', kategori: 'fatura'),
  _Bilinen(r'turktelekom|^ttnet', 'Türk Telekom', kategori: 'fatura'),
  _Bilinen(r'superonline', 'Superonline', kategori: 'fatura'),
  _Bilinen(r'^aesas', 'AESAŞ', kategori: 'fatura'),
  _Bilinen(r'^bedas', 'BEDAŞ', kategori: 'fatura'),
  _Bilinen(r'^ayedas', 'AYEDAŞ', kategori: 'fatura'),
  _Bilinen(r'^enerjisa', 'Enerjisa', kategori: 'fatura'),
  _Bilinen(r'^iski', 'İSKİ', kategori: 'fatura'),
  _Bilinen(r'^igdas', 'İGDAŞ', kategori: 'fatura'),
];

/// Bankanın kendi kalemleri (boşluklu düz metinde aranır).
const List<_Bilinen> _bankaKalemleri = [
  _Bilinen(r'^kesinti', 'Banka kesintisi', kategori: 'banka'),
  _Bilinen(r'yanimda hesaptan', "Yanımda'dan"),
  _Bilinen(r'yanimda hesaba', "Yanımda'ya"),
  _Bilinen(r'ucret iadesi', 'Ücret iadesi'),
  _Bilinen(r'(^| )(vergi|bsmv|kkdf)( |$)', 'Vergi', kategori: 'banka'),
  _Bilinen(r'(^| )faiz( |$)', 'Faiz', kategori: 'banka'),
  _Bilinen(r'hesap isletim', 'Hesap işletim ücreti', kategori: 'banka'),
  _Bilinen(r'kart aidat|yillik uyelik', 'Kart aidatı', kategori: 'banka'),
  _Bilinen(r'nakit cekim|para cekme|(^| )atm( |$)', 'Nakit çekim', kategori: 'nakit'),
];

/// Kısa adda atılan sözcükler (ödeme aracıları, işlem türü, şirket ekleri).
const Set<String> _atilanSozcukler = {
  'satis', 'pos', 'islem', 'islemi', 'iyzico', 'yemekpay', 'paytr', 'param', 'sipay', 'paypal', 'stripe', 'paddle.net', 'paddle',
  'a.s', 'a.s.', 'as', 'ltd', 'ltd.', 'sti', 'sti.', 'tic', 'tic.', 'san', 'san.', 'mobil', 'cep', 'sube', 'internet sube',
};

final Map<String, EkstreAdi> _adOnbellek = {};

/// İşlemin kısa adı: bilinen işyeriyse kendi adı (abonelik grubu ve kategorisiyle), değilse kart
/// numarası, "SATIŞ", döviz tutarı, ödeme aracısı, havale/FAST kuyruğu ve referans numaraları atılmış,
/// baş harfleri büyük açıklama.
EkstreAdi ekstreAdi(String aciklama) {
  final hazir = _adOnbellek[aciklama];
  if (hazir != null) return hazir;
  if (_adOnbellek.length > 2000) _adOnbellek.clear();
  return _adOnbellek[aciklama] = _adiBul(aciklama);
}

EkstreAdi _adiBul(String aciklama) {
  final kelimeler = _adSozcukleri(aciklama);
  // Bilinen işyerleri: kart numarası, "SATIŞ", aracı ve referanslar atıldıktan sonra, boşluksuz
  final bitisik = normTxt(kelimeler.join('')).replaceAll(' ', '');
  for (final b in _bilinenler) {
    if (RegExp(b.desen).hasMatch(bitisik)) return EkstreAdi(b.ad, abonelik: b.abonelik, kategori: b.kategori);
  }
  final duz = normTxt(aciklama.replaceAll('\t', ' '));
  for (final b in _bankaKalemleri) {
    if (RegExp(b.desen).hasMatch(duz)) return EkstreAdi(b.ad, kategori: b.kategori);
  }
  final kisa = kelimeler.where((k) => k.length > 1).take(4).join(' ');
  // Türkçe harf yoksa "I" Latin harfidir ("ONLINE" → "Online", "Onlıne" değil)
  final turkce = RegExp('[İıŞşĞğÇçÖöÜü]').hasMatch(aciklama);
  return EkstreAdi(_basHarfler(kisa.isEmpty ? _temizAciklama(aciklama) : kisa, turkce: turkce));
}

/// Açıklamanın ad sözcükleri: kart numarası parçaları, döviz tutarı, havale/FAST kuyruğu, ödeme
/// aracıları, işlem sözcükleri ve referans numaraları atılır.
List<String> _adSozcukleri(String aciklama) {
  var t = aciklama.replaceAll('\t', ' ');
  // Kart numarası parçaları ("517040*1234") ve baştaki kartın son 4 hanesi ("1234- ")
  t = t.replaceAll(RegExp(r'\d{4,6}\*+\d{0,4}'), ' ');
  t = t.replaceAll(RegExp(r'^\s*\d{4}\s*-'), ' ');
  // Döviz ya da TL tutarı ("24.00USD", "179.99TL")
  t = t.replaceAll(RegExp(r'\d+[.,]\d{2}\s?(USD|EUR|GBP|TL|TRY|usd|eur|gbp|tl|try)'), ' ');
  // Havale / FAST / EFT kuyruğu: yalnızca karşı tarafın adı kalır
  t = t.replaceAll(RegExp(r'-+\s*(FAST|HVL|EFT|HAVALE|fast|hvl|eft|havale)(?![A-Za-z]).*$'), ' ');
  final out = <String>[];
  for (final w in t.split(RegExp(r'[\s\-–*/_|,;:]+'))) {
    final k = w.trim();
    if (k.isEmpty) continue;
    if (_atilanSozcukler.contains(normTxt(k))) continue;
    // Referans numaraları: 4 ya da daha çok rakam içeren sözcükler
    if (RegExp(r'\d').allMatches(k).length >= 4) continue;
    if (!RegExp(r'[0-9A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(k)) continue;
    out.add(k);
  }
  return out;
}

/// Hepsi büyük ya da hepsi küçük harfli yazının sözcüklerinin baş harfi büyük ("MİGROS KADIKÖY" →
/// "Migros Kadıköy"); karışık yazı olduğu gibi kalır. [turkce] değilse Latin kurallarıyla.
String _basHarfler(String t, {bool turkce = true}) {
  final s = t.trim();
  if (s.isEmpty) return 'Harcama';
  final buyuk = turkce ? trUpper : (String x) => x.toUpperCase();
  final kucuk = turkce ? trLower : (String x) => x.toLowerCase();
  if (s != buyuk(s) && s != kucuk(s)) return s;
  return s.split(' ').map((w) => w.isEmpty ? w : '${buyuk(w.substring(0, 1))}${kucuk(w.substring(1))}').join(' ');
}

class EkstreOkuma {
  EkstreTuru tur = EkstreTuru.bilinmiyor;
  String? banka;
  int bankaPuani = 0;

  /// Bankanın tanındığı işaretler (açıklama için).
  List<String> bankaIzleri = [];

  /// Kart programının adı (ör. Axess).
  String? urun;
  String? son4;
  String? iban4;

  // Kart ekstresi
  String? kesim;
  String? sonOdeme;
  int? donemBorcu;
  int? asgari;
  int? limit;
  int? kullanilabilir;
  int? toplamBorc;

  // Hesap dökümü
  String? donemSonu;
  int? acilisBakiye;
  int? kapanisBakiye;

  List<EkstreIslem> islemler = [];

  /// Okunamayan ya da emin olunamayan bilgiler (kullanıcıya gösterilir).
  List<String> eksikler = [];

  /// Kartın güncel borcu (kesim tarihinde): limit ve kullanılabilir varsa farkı, yoksa toplam borç,
  /// o da yoksa dönem borcu.
  int? get guncelBorc {
    final l = limit, a = kullanilabilir;
    if (l != null && a != null && l >= a) return l - a;
    return toplamBorc ?? donemBorcu;
  }

  /// Ekstre (son ödeme) ayı.
  String? get ekstreAyi => sonOdeme != null ? sonOdeme!.substring(0, 7) : (kesim != null ? addM(kesim!.substring(0, 7), 1) : null);

  bool get okundu =>
      tur != EkstreTuru.bilinmiyor &&
      (islemler.isNotEmpty || donemBorcu != null || kapanisBakiye != null);
}

// ---------------------------------------------------------------- Bankaların işaretleri

class _Iz {
  const _Iz(this.metin, this.puan);
  final String metin;
  final int puan;
}

/// Türkiye'deki bankaların ekstrelerde değişmeyen işaretleri (küçük harf, Türkçe harfsiz).
/// Unvan ve internet adresi güçlü, telefon orta, kart programı zayıf (bazıları birden fazla
/// bankada kullanılır: Bonus, World).
const Map<String, List<_Iz>> kBankaIzleri = {
  'akbank': [_Iz('akbank t.a.s', 6), _Iz('akbank.com', 6), _Iz('4442525', 4), _Iz('axess', 3), _Iz('wings', 2), _Iz('akbank', 3)],
  'garanti': [_Iz('garanti bankasi', 6), _Iz('garantibbva', 6), _Iz('4440333', 4), _Iz('miles&smiles', 2), _Iz('shop&fly', 2), _Iz('bonus', 1), _Iz('garanti', 3)],
  'yapikredi': [_Iz('yapi ve kredi bankasi', 6), _Iz('yapikredi.com', 6), _Iz('4440444', 4), _Iz('adios', 2), _Iz('worldpuan', 2), _Iz('world', 1), _Iz('yapi kredi', 3)],
  'isbank': [_Iz('turkiye is bankasi', 6), _Iz('isbank.com', 6), _Iz('08507240724', 4), _Iz('maximiles', 2), _Iz('maxipuan', 2), _Iz('maximum', 2), _Iz('is bankasi', 3)],
  'ziraat': [_Iz('ziraat bankasi', 6), _Iz('ziraatbank.com', 6), _Iz('08502200000', 4), _Iz('bankkart', 3)],
  'halkbank': [_Iz('halk bankasi', 6), _Iz('halkbank.com', 6), _Iz('08502220400', 4), _Iz('paraf', 3), _Iz('halkbank', 3)],
  'vakifbank': [_Iz('vakiflar bankasi', 6), _Iz('vakifbank.com', 6), _Iz('08502220724', 4), _Iz('rail&miles', 2), _Iz('vakifbank', 3)],
  'qnb': [_Iz('qnb bank', 6), _Iz('qnb finansbank', 6), _Iz('qnb.com.tr', 6), _Iz('08502220900', 4), _Iz('cardfinans', 3)],
  'enpara': [_Iz('enpara bank', 6), _Iz('enpara.com', 6), _Iz('08502220667', 4), _Iz('enpara', 3)],
  'denizbank': [_Iz('denizbank a.s', 6), _Iz('denizbank.com', 6), _Iz('08502220800', 4), _Iz('denizbank', 3), _Iz('bonus', 1)],
  'teb': [_Iz('turk ekonomi bankasi', 6), _Iz('teb.com.tr', 6), _Iz('08502000666', 4), _Iz('cepteteb', 3), _Iz('bonus', 1)],
  'fibabanka': [_Iz('fibabanka a.s', 6), _Iz('fibabanka.com', 6), _Iz('4448888', 4), _Iz('fibabanka', 3)],
  'odeabank': [_Iz('odea bank', 6), _Iz('odeabank.com', 6), _Iz('odeabank', 3), _Iz('bonus', 1)],
  'papara': [_Iz('papara elektronik para', 6), _Iz('papara.com', 6), _Iz('papara', 3)],
};

/// Bilinen kart programları (kartın adı için).
const List<String> kKartUrunleri = [
  'Axess', 'Wings', 'Bonus', 'Miles&Smiles', 'Shop&Fly', 'World', 'Adios', 'Crystal', 'Maximum', 'Maximiles',
  'MaxiPara', 'Bankkart', 'Paraf', 'Parafly', 'CardFinans', 'Worldcard', 'Rail&Miles', 'Advantage',
];

/// Bankayı bulur: (banka, puan, işaretler). Açık farkla önde değilse banka null döner.
(String?, int, List<String>) bankaBul(String duzMetin) {
  final m = duzMetin;
  // Telefon numaraları: boşluk ya da tireyle ayrılmış rakam dizileri
  final numaralar = {
    for (final x in RegExp(r'\d[\d \-]{5,16}\d').allMatches(m)) x.group(0)!.replaceAll(RegExp(r'[^0-9]'), ''),
  };
  bool numaraVar(String t) => numaralar.any((n) => n == t || (n.endsWith(t) && n.length <= t.length + 2));
  final puanlar = <String, int>{};
  final izler = <String, List<String>>{};
  kBankaIzleri.forEach((banka, liste) {
    for (final iz in liste) {
      final var_ = RegExp(r'^\d+$').hasMatch(iz.metin) ? numaraVar(iz.metin) : m.contains(iz.metin);
      if (var_) {
        puanlar[banka] = (puanlar[banka] ?? 0) + iz.puan;
        izler.putIfAbsent(banka, () => []).add(iz.metin);
      }
    }
  });
  if (puanlar.isEmpty) return (null, 0, const []);
  final sirali = puanlar.entries.toList()..sort((a, b) => b.value - a.value);
  final ilk = sirali.first;
  final ikinci = sirali.length > 1 ? sirali[1].value : 0;
  // En az bir güçlü işaret (unvan, adres ya da telefon) ve ikinciden belirgin fark
  if (ilk.value < 4 || ilk.value - ikinci < 3) return (null, ilk.value, izler[ilk.key] ?? const []);
  return (ilk.key, ilk.value, izler[ilk.key]!);
}

// ---------------------------------------------------------------- Okuma

final RegExp _tarihRe = RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?!\d)');
final RegExp _tutarRe = RegExp(
    r'([-+]?)(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})(?![\d]|[.,/]\d)\s*(?:TL|TRY|₺)?\s*([-+](?=\s*(?:\t|$))|\(?[ABab]\)?(?![A-Za-z0-9çğıöşüÇĞİÖŞÜ]))?');

/// "03.11.2026" → "2026-11-03" (geçersizse null).
String? tarihCevir(String s) {
  final m = _tarihRe.firstMatch(s);
  if (m == null) return null;
  final g = int.parse(m.group(1)!), a = int.parse(m.group(2)!);
  var y = int.parse(m.group(3)!);
  if (y < 100) y += 2000;
  if (a < 1 || a > 12 || g < 1 || g > 31 || y < 2000 || y > 2100) return null;
  return '$y-${two(a)}-${two(g)}';
}

/// "1.234,56" ya da "1,234.56" → kuruş.
int? tutarCevir(String s) {
  final t = s.trim();
  if (t.length < 4) return null;
  final dec = t[t.length - 3];
  if (dec != ',' && dec != '.') return null;
  final tam = t.substring(0, t.length - 3).replaceAll(RegExp(r'[.,]'), '');
  final kurus = t.substring(t.length - 2);
  final v = int.tryParse('$tam$kurus');
  return v;
}

class _Tutar {
  const _Tutar(this.k, this.eksi, this.arti, this.basla, this.bitis);
  final int k;
  final bool eksi;

  /// Açıkça "+" yazılmış.
  final bool arti;
  final int basla;
  final int bitis;

  int get isaretli => eksi ? -k : k;
}

List<_Tutar> _tutarlar(String satir) {
  final out = <_Tutar>[];
  for (final m in _tutarRe.allMatches(satir)) {
    final k = tutarCevir(m.group(2)!);
    if (k == null) continue;
    // Tarihin parçası mı? (ör. 03.11.20)
    final once = m.start > 0 ? satir[m.start - 1] : ' ';
    if (RegExp(r'[0-9./]').hasMatch(once)) continue;
    final on = m.group(1) ?? '';
    final son = (m.group(3) ?? '').replaceAll(RegExp(r'[()]'), '').toUpperCase();
    out.add(_Tutar(k, on == '-' || son == '-' || son == 'A', on == '+' || son == '+', m.start, m.end));
  }
  return out;
}

/// Bir satırın (tarihten sonrası) hücreleri: yalnızca tutardan oluşan hücreler ve yazı hücreleri.
/// Hücre yoksa ya da tutar/yazı hücresi bulunmazsa null (satır düz metin olarak okunur).
(List<String>, List<_Tutar>)? _hucrele(String govde) {
  final hs = govde.split('\t').map((h) => h.trim()).where((h) => h.isNotEmpty).toList();
  if (hs.length < 2) return null;
  final yazilar = <String>[];
  final tutarlar = <_Tutar>[];
  for (final h in hs) {
    // Yalnızca tarihten oluşan hücre (ör. işlem tarihinden sonra gelen hesaba geçiş tarihi)
    if (tarihCevir(h) != null && h.replaceAll(_tarihRe, '').trim().isEmpty) continue;
    final t = _tutarlar(h);
    final kalan = h.replaceAll(_tutarRe, '').replaceAll(RegExp(r'TL|TRY|₺|\s'), '');
    if (t.length == 1 && kalan.isEmpty) {
      tutarlar.add(t.first);
    } else {
      yazilar.add(h);
    }
  }
  if (tutarlar.isEmpty || yazilar.isEmpty) return null;
  return (yazilar, tutarlar);
}

String _duz(String s) => normTxt(s.replaceAll('\t', ' '));

/// Bir başlığın değerini bulur: aynı hücrede başlıktan sonra, aynı satırın sonraki hücrelerinde
/// ya da alttaki satırda aynı sütunda.
T? _deger<T>(List<String> satirlar, List<String> basliklar, T? Function(String) oku, {bool sonrakiSatir = true}) {
  for (var i = 0; i < satirlar.length; i++) {
    final hucreler = satirlar[i].split('\t');
    for (var c = 0; c < hucreler.length; c++) {
      final h = _duz(hucreler[c]);
      String? bulunan;
      var tam = false;
      for (final b in basliklar) {
        if (b.startsWith('=') ? h.replaceAll(RegExp(r'[\s:]+$'), '') == b.substring(1) : h.contains(b)) {
          bulunan = b.startsWith('=') ? b.substring(1) : b;
          tam = b.startsWith('=');
          break;
        }
      }
      if (bulunan == null) continue;
      // Aynı hücrede başlıktan sonrası
      final ham = hucreler[c];
      final idx = _duz(ham).indexOf(bulunan);
      final kalan = idx >= 0 && idx + bulunan.length <= ham.length ? ham.substring(math.min(ham.length, idx + bulunan.length)) : '';
      final v1 = oku(kalan);
      if (v1 != null) return v1;
      // Aynı satırın sonraki hücreleri (başka bir başlığa gelene kadar)
      for (var d = c + 1; d < hucreler.length; d++) {
        final v = oku(hucreler[d]);
        if (v != null) return v;
        if (RegExp(r'[a-zçğıöşü]{4,}', caseSensitive: false).hasMatch(hucreler[d])) break;
      }
      if (!sonrakiSatir || tam) continue;
      // Alttaki satırlar: aynı sütun, yoksa ilk değer
      for (var j = i + 1; j <= i + 2 && j < satirlar.length; j++) {
        final alt = satirlar[j].split('\t');
        if (alt.length == hucreler.length) {
          final v = oku(alt[c]);
          if (v != null) return v;
        } else if (hucreler.length == 1) {
          final v = oku(satirlar[j]);
          if (v != null) return v;
        }
      }
    }
  }
  return null;
}

String? _ilkTarih(String s) => tarihCevir(s);

int? _ilkTutar(String s) {
  final t = _tutarlar(s);
  return t.isEmpty ? null : t.first.k;
}

const List<String> _kartBasliklari = [
  'hesap kesim tarihi', 'son odeme tarihi', 'donem borcu', 'asgari odeme', 'kart limiti', 'kullanilabilir limit',
  'kredi karti', 'ekstre', 'odenecek tutar', 'donem ici',
];
const List<String> _hesapBasliklari = [
  'iban', 'hesap hareketleri', 'hesap ozeti', 'hesap dokumu', 'bakiye', 'vadesiz', 'hesap no', 'alacak', 'musteri no',
];

/// Özet satırları (açıklaması bunlarla başlayan): işlem sayılmaz.
final RegExp _ozetSatiri = RegExp(
    r'^(onceki donem|devreden|donem borcu|toplam|asgari|hesap kesim|son odeme|kart limiti|kullanilabilir|acilis bakiye|kapanis bakiye|onceki bakiye|bakiye$)');

int? _ilkBakiye(String s) {
  final t = _tutarlar(s);
  return t.isEmpty ? null : t.first.isaretli;
}

/// Hesap sahibinin adı (kendi hesaplarına aktarmaları tanımak için; hiçbir yere kaydedilmez).
String? _sahipAdi(List<String> satirlar) {
  String? ad = _deger(satirlar, const ['unvan', 'ad soyad', 'musteri adi', 'hesap sahibi'], (s) {
    final t = s.replaceAll(RegExp(r'^[\s:/]+'), '').trim();
    return RegExp(r'[a-zA-ZçğıöşüÇĞİÖŞÜ]{2,}').hasMatch(t) ? t : null;
  }, sonrakiSatir: false);
  if (ad == null) {
    for (final l in satirlar) {
      final m = RegExp(r'(?:Sayın|SAYIN)\s+([^,\t]{3,60}),').firstMatch(l);
      if (m != null) {
        ad = m.group(1);
        break;
      }
    }
  }
  final n = normTxt(ad);
  return n.length >= 5 && n.contains(' ') ? n : null;
}

/// "30/10/2026 - 06/11/2026" gibi dönemin son günü.
String? _donemSonu(List<String> satirlar) {
  for (final l in satirlar) {
    final m = RegExp(r'(\d{1,2}[./]\d{1,2}[./]\d{4})\s*-\s*(\d{1,2}[./]\d{1,2}[./]\d{4})').firstMatch(l);
    if (m != null) {
      final a = tarihCevir(m.group(1)!), b = tarihCevir(m.group(2)!);
      if (a != null && b != null && a.compareTo(b) <= 0) return b;
    }
  }
  return null;
}

/// Kendi hesapların arası (birikim hesabı, "Yanımda", yatırım, kendi adına havale): harcama değil.
bool _icAktarma(String da, String? sahip) {
  if (RegExp(r'maas').hasMatch(da)) return false;
  if (RegExp(r'yanimda|hesaplar arasi|virman|kendi hesab|vadeli hesab|birikim hesab|(^| )yatirim( |$)').hasMatch(da)) return true;
  return sahip != null && da.contains(sahip);
}

/// Bankanın etiketinden ya da açıklamadan kategori (bilinmiyorsa null: adından tahmin edilir).
String? _etiketKategorisi(String? etiket, String aciklama) {
  final e = _duz(etiket ?? '');
  final a = _duz(aciklama);
  if (RegExp(r'kredi karti|kart odeme|kk odeme').hasMatch(a)) return 'kart_asgari';
  if (RegExp(r'kesinti|masraf|ucret|komisyon|vergi|bsmv').hasMatch(a) || RegExp(r'faiz|komisyon|vergi|ucret').hasMatch(e)) return 'banka';
  if (RegExp(r'kurum odeme|fatura|telekom|elektrik|dogalgaz').hasMatch(e)) return 'fatura';
  if (RegExp(r'atm|nakit cekim|para cekme').hasMatch(a) || RegExp(r'nakit|atm').hasMatch(e)) return 'nakit';
  if (RegExp(r'para transfer|havale|eft').hasMatch(e) || RegExp(r'(^| )(eft|havale|fast)( |-|$)').hasMatch(a)) return 'transfer';
  return null;
}

/// PDF satırlarından ekstreyi okur. [sayfalar]: sayfa sayfa satırlar (büyük boşluklar '\t').
EkstreOkuma ekstreOku(List<List<String>> sayfalar) {
  final o = EkstreOkuma();
  final satirlar = [for (final s in sayfalar) ...s].where((x) => x.trim().isNotEmpty).toList();
  if (satirlar.isEmpty) {
    o.eksikler.add('PDF\'te okunabilir yazı yok (resim olabilir).');
    return o;
  }
  final duzMetin = _duz(satirlar.join(' \n '));

  // Tür
  var kart = 0, hesap = 0;
  for (final b in _kartBasliklari) {
    if (duzMetin.contains(b)) kart++;
  }
  for (final b in _hesapBasliklari) {
    if (duzMetin.contains(b)) hesap++;
  }
  if (kart >= 3 && kart >= hesap) {
    o.tur = EkstreTuru.kart;
  } else if (hesap >= 2) {
    o.tur = EkstreTuru.hesap;
  } else if (kart >= 2) {
    o.tur = EkstreTuru.kart;
  }

  // Banka
  final (banka, puan, izler) = bankaBul(duzMetin);
  o.banka = banka;
  o.bankaPuani = puan;
  o.bankaIzleri = izler;
  if (banka == null) o.eksikler.add('Banka kesin tanınamadı.');

  // Kart numarasının son 4 hanesi (maskeli numara) ve kart programı
  final son4 = RegExp(r'[*xX•]{4}[ -]?(\d{4})(?!\d)').firstMatch(satirlar.join(' '));
  o.son4 = son4?.group(1);
  for (final u in kKartUrunleri) {
    if (RegExp('(?<![a-z])${RegExp.escape(u.toLowerCase())}(?![a-z])').hasMatch(duzMetin)) {
      o.urun = u;
      break;
    }
  }
  final iban = RegExp(r'TR\s?\d{2}(?:\s?[\d*xX•]){20,24}').firstMatch(satirlar.join(' '));
  if (iban != null) {
    final r = iban.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
    if (r.length >= 4) o.iban4 = r.substring(r.length - 4);
  }

  if (o.tur == EkstreTuru.kart) {
    o.kesim = _deger(satirlar, const ['hesap kesim tarihi', 'kesim tarihi', 'ekstre tarihi', 'hesap kesim'], _ilkTarih);
    o.sonOdeme = _deger(satirlar, const ['son odeme tarihi', 'son odeme'], _ilkTarih);
    o.donemBorcu = _deger(satirlar, const ['donem borcu', 'odenecek tutar', 'ekstre borcu', 'hesap ozeti borcu'], _ilkTutar);
    o.asgari = _deger(satirlar, const ['asgari odeme tutari', 'asgari odeme', 'minimum odeme'], _ilkTutar);
    o.limit = _deger(satirlar, const ['kart limiti', 'kredi karti limiti', 'toplam limit', 'kart limitiniz'], _ilkTutar);
    o.kullanilabilir = _deger(satirlar, const ['kullanilabilir limit', 'kullanilabilir'], _ilkTutar);
    o.toplamBorc = _deger(satirlar, const ['toplam borc', 'guncel borc', 'toplam kart borcu'], _ilkTutar);
    if (o.kesim == null) o.eksikler.add('Hesap kesim tarihi okunamadı.');
    if (o.sonOdeme == null) o.eksikler.add('Son ödeme tarihi okunamadı.');
    if (o.donemBorcu == null) o.eksikler.add('Dönem borcu okunamadı.');
    o.islemler = _kartIslemleri(satirlar);
  } else if (o.tur == EkstreTuru.hesap) {
    o.acilisBakiye = _deger(satirlar, const ['devreden bakiye', 'onceki bakiye', 'acilis bakiyesi', 'donem basi bakiye'], _ilkBakiye);
    final (islemler, sonBakiye, sonTarih) = _hesapIslemleri(satirlar, o.acilisBakiye, _sahipAdi(satirlar));
    o.islemler = islemler;
    // Hesabın parası: önce özetteki "Kullanılabilir Bakiye" (Melih'in kararı: alt hesaplardaki para,
    // ör. Yanımda, de içinde), yoksa özetteki bakiye, o da yoksa en yeni işlemin bakiyesi
    o.kapanisBakiye = _deger(satirlar, const ['kullanilabilir bakiye'], _ilkBakiye) ??
        _deger(satirlar, const ['kapanis bakiyesi', 'donem sonu bakiye', 'guncel bakiye', 'son bakiye', '=bakiye', '=hesap bakiyesi'], _ilkBakiye) ??
        sonBakiye;
    o.donemSonu = _donemSonu(satirlar) ?? sonTarih;
    if (o.kapanisBakiye == null) o.eksikler.add('Dökümün son bakiyesi okunamadı.');
  } else {
    o.eksikler.add('Bu belge kredi kartı ekstresine ya da hesap dökümüne benzemiyor.');
  }
  return o;
}

String _temizAciklama(String s) {
  var t = s.replaceAll('\t', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'^[-–:]+|[-–:]+$'), '').trim();
  return t;
}

final RegExp _taksitRe = RegExp(r'(?<![\d/.])(\d{1,2})\s?/\s?(\d{1,2})(?![\d/.])');
final RegExp _harfRe = RegExp(r'[a-zA-ZçğıöşüÇĞİÖŞÜ]');

/// Satırın tarihten sonrası: (açıklama, etiket, tutarlar). Sütunlu satırda tutarlar yalnızca tutar
/// hücrelerinden alınır (açıklamadaki "24.00USD" ya da "Toplam: 7.272,58" tutar sayılmaz).
(String, String?, List<_Tutar>) _satirParcalari(String govde) {
  final hc = _hucrele(govde);
  if (hc != null) {
    final (yazilar, tutarlar) = hc;
    return (yazilar.first, yazilar.length > 1 ? yazilar.sublist(1).join(' ') : null, tutarlar);
  }
  final tutarlar = _tutarlar(govde);
  if (tutarlar.isEmpty) return ('', null, tutarlar);
  var aciklama = govde.substring(0, tutarlar.first.basla);
  final ikinciTarih = _tarihRe.firstMatch(aciklama.trim());
  if (ikinciTarih != null && ikinciTarih.start < 3) aciklama = aciklama.trim().substring(ikinciTarih.end);
  return (aciklama, null, tutarlar);
}

/// Kart ekstresinin işlem satırları: tarihle başlayan, tutarla biten satırlar.
List<EkstreIslem> _kartIslemleri(List<String> satirlar) {
  final out = <EkstreIslem>[];
  for (final satir in satirlar) {
    final s = satir.trim();
    final tm = _tarihRe.firstMatch(s);
    if (tm == null || tm.start > 2) continue;
    final tarih = tarihCevir(tm.group(0)!);
    if (tarih == null) continue;
    final govde = s.substring(tm.end);
    var (aciklama, etiket, tutarlar) = _satirParcalari(govde);
    if (tutarlar.isEmpty) continue;
    // Taksit: "2/6" (açıklamada ya da ayrı sütunda)
    int? no, sayi;
    for (final metin in [aciklama, etiket ?? '']) {
      final tk = _taksitRe.firstMatch(metin);
      if (tk == null) continue;
      final a = int.parse(tk.group(1)!), b = int.parse(tk.group(2)!);
      if (b >= 2 && b <= 36 && a >= 1 && a <= b) {
        no = a;
        sayi = b;
        if (identical(metin, aciklama)) aciklama = aciklama.replaceRange(tk.start, tk.end, ' ');
        break;
      }
    }
    aciklama = _temizAciklama(aciklama.replaceAll(RegExp(r'taksit(li)?', caseSensitive: false), ''));
    if (!_harfRe.hasMatch(aciklama)) continue;
    final da = _duz(aciklama);
    if (_ozetSatiri.hasMatch(da)) continue;
    // Puan sütunu (bonus, worldpuan, maxipuan...): çok küçük son sayı puandır
    var secilen = tutarlar.last;
    if (tutarlar.length >= 2) {
      final onceki = tutarlar[tutarlar.length - 2];
      final puanli = RegExp(r'puan|bonus|chip|mil\b|miles').hasMatch(_duz(govde)) && tutarlar.last.k < onceki.k;
      if (puanli || tutarlar.last.k * 20 < onceki.k) secilen = onceki;
    }
    String tur;
    if (RegExp(r'odeme|tahsilat|hesaptan aktarim|otomatik odeme|odemeniz').hasMatch(da)) {
      tur = 'odeme';
    } else if (RegExp(r'iade|iptal').hasMatch(da) || ((secilen.eksi || secilen.arti) && !RegExp(r'faiz|ucret').hasMatch(da))) {
      // Kart ekstresinde işaretli tutar (eksi ya da artı) borçtan düşer: iade
      tur = secilen.arti && !secilen.eksi && !RegExp(r'iade|iptal').hasMatch(da) ? 'harcama' : 'iade';
    } else if (RegExp(r'faiz|bsmv|kkdf|ucret|aidat|komisyon|gecikme').hasMatch(da)) {
      tur = 'ucret';
    } else {
      tur = 'harcama';
    }
    out.add(EkstreIslem(
      tarih: tarih,
      aciklama: aciklama,
      k: secilen.k,
      tur: tur,
      taksitNo: no,
      taksitSayisi: sayi,
      etiket: etiket,
      kategori: tur == 'ucret' ? 'banka' : ekstreAdi(aciklama).kategori,
      arti: tur == 'odeme' || tur == 'iade',
      ham: s,
    ));
  }
  return out;
}

class _HesapSatiri {
  const _HesapSatiri(this.tarih, this.aciklama, this.etiket, this.miktar, this.bakiye, this.ham);
  final String tarih;
  final String aciklama;
  final String? etiket;
  final _Tutar miktar;
  final int? bakiye;
  final String ham;
}

/// Hesap dökümünün işlem satırları. Yön: açık işaret (+/-), yoksa yürüyen bakiye (döküm eskiden
/// yeniye ya da yeniden eskiye sıralı olabilir), o da yoksa açıklama. Son bakiye en yeni işlemin.
(List<EkstreIslem>, int?, String?) _hesapIslemleri(List<String> satirlar, int? acilis, String? sahip) {
  var acilisBakiye = acilis;
  final rows = <_HesapSatiri>[];
  for (final satir in satirlar) {
    final s = satir.trim();
    final tm = _tarihRe.firstMatch(s);
    if (tm == null || tm.start > 2) continue;
    final tarih = tarihCevir(tm.group(0)!);
    if (tarih == null) continue;
    final (ham, etiket, tutarlar) = _satirParcalari(s.substring(tm.end));
    if (tutarlar.isEmpty) continue;
    final aciklama = _temizAciklama(ham);
    final da = _duz(aciklama);
    if (_ozetSatiri.hasMatch(da)) {
      if (RegExp(r'^(devreden|onceki bakiye|acilis)').hasMatch(da)) acilisBakiye ??= tutarlar.last.isaretli;
      continue;
    }
    if (!_harfRe.hasMatch(aciklama)) continue;
    final miktar = tutarlar.length >= 2 ? tutarlar[tutarlar.length - 2] : tutarlar.first;
    final bakiye = tutarlar.length >= 2 ? tutarlar.last.isaretli : null;
    rows.add(_HesapSatiri(tarih, aciklama, etiket, miktar, bakiye, s));
  }
  if (rows.isEmpty) return (const <EkstreIslem>[], null, null);
  final artan = rows.first.tarih.compareTo(rows.last.tarih) <= 0;
  final out = <EkstreIslem>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final da = _duz('${r.aciklama} ${r.etiket ?? ''}');
    bool giris;
    if (r.miktar.arti) {
      giris = true;
    } else if (r.miktar.eksi) {
      giris = false;
    } else {
      final onceki = artan ? (i > 0 ? rows[i - 1].bakiye : acilisBakiye) : (i + 1 < rows.length ? rows[i + 1].bakiye : acilisBakiye);
      final b = r.bakiye;
      if (onceki != null && b != null && (b - onceki).abs() == r.miktar.k) {
        giris = b > onceki;
      } else {
        giris = RegExp(r'maas|gelen|yatan|alacak|iade|faiz geliri').hasMatch(da);
      }
    }
    out.add(EkstreIslem(
      tarih: r.tarih,
      aciklama: r.aciklama,
      k: r.miktar.k,
      tur: _icAktarma(da, sahip) ? 'aktarma' : (giris ? 'giris' : 'cikis'),
      etiket: r.etiket,
      kategori: giris ? null : (_etiketKategorisi(r.etiket, r.aciklama) ?? ekstreAdi(r.aciklama).kategori),
      arti: giris,
      ham: r.ham,
    ));
  }
  final son = artan ? rows.last : rows.first;
  return (out, son.bakiye, son.tarih);
}

// ---------------------------------------------------------------- Hedef: hangi kart ya da hesap

class EkstreHedefi {
  const EkstreHedefi({required this.kart, this.id, required this.ad, this.kesin = false, this.neden = ''});

  /// true: kredi kartı (borç kaydı), false: hesap.
  final bool kart;

  /// null: yeni kayıt açılacak.
  final String? id;
  final String ad;

  /// Son 4 hane ya da tek aday: soru sormadan eklenir.
  final bool kesin;
  final String neden;

  bool get yeni => id == null;
  String get kaynak => kart ? 'card:$id' : 'acc:$id';
}

/// Ekstrenin gidebileceği kayıtlar, en olası önce. Sonuncusu her zaman "yeni kayıt" önerisidir.
List<EkstreHedefi> ekstreHedefleri(Data d, EkstreOkuma o) {
  final out = <EkstreHedefi>[];
  final bankaAdi = o.banka == null ? 'Banka' : bankName(o.banka, 'tr');
  if (o.tur == EkstreTuru.kart) {
    final kartlar = d.debts.where((x) => x.isCard).toList();
    final son4 = o.son4;
    if (son4 != null) {
      for (final x in kartlar) {
        if (x.j['last4'] == son4) out.add(EkstreHedefi(kart: true, id: x.id, ad: x.creditor, kesin: true, neden: 'son 4 hane'));
      }
    }
    if (out.isEmpty) {
      final ayni = kartlar.where((x) => o.banka != null && bankKeyOf(x) == o.banka && (son4 == null || x.j['last4'] == null)).toList();
      int puan(Debt x) {
        var p = 0;
        if (o.urun != null && normTxt(x.creditor).contains(normTxt(o.urun))) p += 2;
        if (o.limit != null && x.limit != null && toK(x.limit) == o.limit) p += 2;
        return p;
      }

      ayni.sort((a, b) => puan(b) - puan(a));
      for (var i = 0; i < ayni.length; i++) {
        final x = ayni[i];
        final tek = ayni.length == 1 || (i == 0 && puan(x) > puan(ayni[1]));
        out.add(EkstreHedefi(kart: true, id: x.id, ad: x.creditor, kesin: tek, neden: tek ? 'bankadaki kart' : ''));
      }
      // Bankası tanınmadıysa bütün kartlar seçilebilir (hiçbiri kesin değil)
      if (o.banka == null) {
        for (final x in kartlar) {
          out.add(EkstreHedefi(kart: true, id: x.id, ad: x.creditor));
        }
      }
    }
    out.add(EkstreHedefi(kart: true, ad: '$bankaAdi ${o.urun ?? 'kredi kartı'}'.trim()));
    return out;
  }
  if (o.tur == EkstreTuru.hesap) {
    final hesaplar = d.accounts.where((a) => !a.isCash).toList();
    final iban4 = o.iban4;
    if (iban4 != null) {
      for (final a in hesaplar) {
        if (a.j['iban4'] == iban4) out.add(EkstreHedefi(kart: false, id: a.id, ad: accLabel(a, 'tr'), kesin: true, neden: 'IBAN'));
      }
    }
    if (out.isEmpty) {
      final ayni = hesaplar.where((a) => o.banka != null && a.bank == o.banka && (iban4 == null || a.j['iban4'] == null)).toList()
        ..sort((a, b) => (a.type == 'vadesiz' ? 0 : 1) - (b.type == 'vadesiz' ? 0 : 1));
      for (var i = 0; i < ayni.length; i++) {
        final tek = ayni.length == 1;
        out.add(EkstreHedefi(kart: false, id: ayni[i].id, ad: accLabel(ayni[i], 'tr'), kesin: tek, neden: tek ? 'bankadaki hesap' : ''));
      }
      if (o.banka == null) {
        for (final a in hesaplar) {
          out.add(EkstreHedefi(kart: false, id: a.id, ad: accLabel(a, 'tr')));
        }
      }
    }
    out.add(EkstreHedefi(kart: false, ad: o.banka == 'papara' ? 'Papara' : '$bankaAdi vadesiz'));
  }
  return out;
}

// ---------------------------------------------------------------- Eşleştirme

enum EslesmeDurumu { yeni, var_, supheli, eklenmez }

class EkstreEslesme {
  const EkstreEslesme(this.islem, this.durum,
      {this.kayitId, this.kayitAdi, this.kayitTarihi, this.abonelikId, this.gelirId, this.yeniAbonelik = false});
  final EkstreIslem islem;
  final EslesmeDurumu durum;

  /// Uygulamada kayıtlı olmayan bilinen bir abonelik: aboneliklere eklenir ve o ay ödendi olur.
  final bool yeniAbonelik;

  /// Abonelik ya da fatura ödemesi: harcama yerine o ayki "ödendi" işareti konur.
  final String? abonelikId;

  /// Maaş: o ayki gelir "yattı" olarak işaretlenir (hesaba giriş Gelir Motoru'ndan).
  final String? gelirId;

  /// Eşleşen uygulama kaydı (harcama, aktarma ya da ödeme).
  final String? kayitId;
  final String? kayitAdi;
  final String? kayitTarihi;
}

int _gunFarki(String a, String b) {
  final da = DateTime.tryParse(a), db = DateTime.tryParse(b);
  if (da == null || db == null) return 999;
  return da.difference(db).inDays.abs();
}

bool _benzerAd(String a, String b) {
  final x = normTxt(a), y = normTxt(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x.contains(y) || y.contains(x)) return true;
  final ka = x.split(' ').where((w) => w.length >= 3).toSet();
  final kb = y.split(' ').where((w) => w.length >= 3).toSet();
  return ka.intersection(kb).isNotEmpty;
}

/// İşlemleri uygulamadaki kayıtlarla karşılaştırır.
List<EkstreEslesme> ekstreEslestir(Data d, EkstreOkuma o, EkstreHedefi h) {
  final out = <EkstreEslesme>[];
  final kullanilan = <String>{};
  final src = h.yeni ? null : h.kaynak;
  for (final i in o.islemler) {
    if (!i.eklenebilir) {
      out.add(EkstreEslesme(i, EslesmeDurumu.eklenmez));
      continue;
    }
    // Aday kayıtlar: (kimlik, ad, tarih, kuruş)
    final adaylar = <(String, String, String, int)>[];
    if (src != null) {
      for (final s in d.spends) {
        if (s.source != src) continue;
        final k = toK(s.amount);
        final n = math.max(1, s.installments);
        final birTaksit = n > 1 ? (k / n).round() : k;
        if (k == i.k || (i.taksitli && (birTaksit - i.k).abs() <= n)) adaylar.add((s.id, s.name.isEmpty ? s.place : s.name, s.date, k));
      }
      if (!h.kart) {
        for (final t in d.transfers) {
          final yon = i.tur == 'giris' ? t.to == src : t.from == src;
          if (yon && toK(t.amount) == i.k) adaylar.add((t.id, t.note.isEmpty ? 'Aktarma' : t.note, t.date, i.k));
        }
        for (final p in d.payments) {
          if (i.tur == 'cikis' && p.viaRefId == null && p.fromAccount == src && toK(p.paidAmount) == i.k && p.paidDate != null) {
            adaylar.add((p.id, 'Ödeme', p.paidDate!, i.k));
          }
        }
      }
    }
    // Kaynağı boş girilmiş harcamalar da aday (yalnızca "bu o mu?")
    final kaynaksiz = <(String, String, String, int)>[
      for (final s in d.spends)
        if (s.source == null && toK(s.amount) == i.k && _gunFarki(s.date, i.tarih) <= 3) (s.id, s.name, s.date, toK(s.amount)),
    ];
    (String, String, String, int)? en;
    var enGun = 999;
    for (final a in adaylar) {
      if (kullanilan.contains(a.$1)) continue;
      final g = _gunFarki(a.$3, i.tarih);
      if (g < enGun) {
        en = a;
        enGun = g;
      }
    }
    final e = en;
    if (e != null && enGun <= 3 && (_benzerAd(e.$2, i.aciklama) || _benzerAd(e.$2, i.ad) || enGun <= 1)) {
      kullanilan.add(e.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.var_, kayitId: e.$1, kayitAdi: e.$2, kayitTarihi: e.$3));
    } else if (e != null && enGun <= 7) {
      kullanilan.add(e.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.supheli, kayitId: e.$1, kayitAdi: e.$2, kayitTarihi: e.$3));
    } else if (i.taksitli && (i.taksitNo ?? 1) > 1 && e != null) {
      // Eski bir taksitli alışverişin bu ayki taksiti: alışveriş zaten girilmiş
      kullanilan.add(e.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.var_, kayitId: e.$1, kayitAdi: e.$2, kayitTarihi: e.$3));
    } else {
      final ay = monthOf(i.tarih);
      final sub = i.tur == 'cikis' || i.tur == 'harcama' ? _abonelikBul(d, i) : null;
      final inc = i.tur == 'giris' ? _gelirBul(d, i, src) : null;
      final kalanKaynaksiz = kaynaksiz.where((k) => !kullanilan.contains(k.$1)).toList();
      if (sub != null) {
        final odendi = d.payments.any((p) => p.kind == 'sub' && p.refId == sub.id && p.month == ay && p.viaRefId == null);
        out.add(odendi
            ? EkstreEslesme(i, EslesmeDurumu.var_, kayitId: sub.id, kayitAdi: sub.name)
            : EkstreEslesme(i, EslesmeDurumu.yeni, abonelikId: sub.id, kayitAdi: sub.name));
      } else if (inc != null) {
        final yatti = inc.monthAmounts.containsKey(ay);
        out.add(yatti
            ? EkstreEslesme(i, EslesmeDurumu.var_, kayitId: inc.id, kayitAdi: inc.name)
            : EkstreEslesme(i, EslesmeDurumu.yeni, gelirId: inc.id, kayitAdi: inc.name));
      } else if (kalanKaynaksiz.isNotEmpty) {
        final k = kalanKaynaksiz.first;
        kullanilan.add(k.$1);
        out.add(EkstreEslesme(i, EslesmeDurumu.supheli, kayitId: k.$1, kayitAdi: k.$2, kayitTarihi: k.$3));
      } else if (i.abonelikGrubu != null && !i.taksitli && (i.tur == 'cikis' || i.tur == 'harcama')) {
        out.add(EkstreEslesme(i, EslesmeDurumu.yeni, yeniAbonelik: true, kayitAdi: i.ad));
      } else {
        out.add(EkstreEslesme(i, EslesmeDurumu.yeni));
      }
    }
  }
  return out;
}

/// Fatura şirketleri: abonelik adındaki fatura türüyle eşleşir (ör. "Elektrik" ↔ AESAŞ, BEDAŞ).
const Map<String, List<String>> _faturaSirketleri = {
  'elektrik': ['aesas', 'bedas', 'ayedas', 'enerjisa', 'ck enerji', 'ck bogazici', 'toroslar', 'gediz', 'uludag elektrik', 'elektrik'],
  'dogalgaz': ['igdas', 'baskentgaz', 'izmirgaz', 'aksa', 'enerya', 'dogalgaz'],
  'su': ['iski', 'aski', 'izsu', 'buski', 'asat', 'maski', 'su idaresi'],
  'internet': ['turkst', 'superonline', 'ttnet', 'turk telekom', 'turknet', 'millenicom'],
  'telefon': ['vodafo', 'turkcell', 'turk telekom'],
  'vodafone': ['vodafo'],
};

/// Ekstredeki ödemenin uygulamadaki aboneliği ya da faturası (adından, markasından ya da fatura
/// şirketinden).
Subscription? _abonelikBul(Data d, EkstreIslem i) {
  final a = _duz(i.aciklama);
  final bitisik = a.replaceAll(' ', '');
  final marka = brandIndex(i.aciklama) ?? brandIndex(i.ad);
  final kisa = normTxt(i.ad);
  for (final s in d.subscriptions) {
    if (!s.active) continue;
    final ad = normTxt(s.name);
    if (ad.isEmpty) continue;
    final ilk = ad.split(' ').first;
    if (ilk.length >= 4 && bitisik.contains(ilk)) return s;
    if (kisa.length >= 4 && ad.length >= 4 && (ad.contains(kisa) || kisa.contains(ad))) return s;
    if (marka != null && brandIndex(s.name) == marka) return s;
    for (final e in _faturaSirketleri.entries) {
      if (RegExp('(^| )${e.key}( |\$)').hasMatch(ad) && e.value.any(a.contains)) return s;
    }
  }
  return null;
}

/// Ekstredeki maaşın uygulamadaki geliri (o ay planlı tutarı en yakın olan; başka hesaba yatan
/// gelir sayılmaz).
Income? _gelirBul(Data d, EkstreIslem i, String? src) {
  if (!RegExp(r'maas').hasMatch(_duz('${i.aciklama} ${i.etiket ?? ''}'))) return null;
  final ay = monthOf(i.tarih);
  Income? en;
  var fark = 0;
  for (final inc in d.incomes) {
    if (src != null && inc.account != null && inc.account != src) continue;
    final plan = schedK(inc.schedule, ay);
    if (plan <= 0 && !inc.monthAmounts.containsKey(ay)) continue;
    final f = (plan - i.k).abs();
    if (en == null || f < fark) {
      en = inc;
      fark = f;
    }
  }
  return en;
}

// ---------------------------------------------------------------- Uygulama

/// Seçimlere göre ekstreyi uygular. [ekle]: eklenecek eşleşmeler (yeni olanlar ve "ayrı ekle"
/// denen şüpheliler). Hedef yeni ise kart ya da hesap açılır. Hedefin kimliğini döndürür.
String ekstreUygula(Data d, EkstreOkuma o, EkstreHedefi h, List<EkstreEslesme> ekle) {
  if (h.kart) return _kartUygula(d, o, h, ekle);
  return _hesapUygula(d, o, h, ekle);
}

/// Kayıtsız bir aboneliği açar (adı, tutarı ve günü ekstreden) ya da bu uygulamada az önce açılanı
/// verir; o ay zaten ödendiyse null (ikinci çekim harcama olarak eklenir).
String? _yeniAbonelik(Data d, EkstreIslem i, String src, Map<String, String> acilanlar) {
  var id = acilanlar[i.ad];
  if (id == null) {
    id = saveSubscription(d, <String, dynamic>{
      'name': i.ad,
      'group': i.abonelikGrubu ?? 'diger',
      'amount': fromK(i.k),
      'period': 'ay',
      'day': dayOf(i.tarih),
      'source': src,
      'active': true,
      'note': 'Ekstreden',
    });
    acilanlar[i.ad] = id;
  }
  final ay = monthOf(i.tarih);
  final odendi = d.payments.any((p) => p.kind == 'sub' && p.refId == id && p.month == ay && p.viaRefId == null);
  return odendi ? null : id;
}

String _kartUygula(Data d, EkstreOkuma o, EkstreHedefi h, List<EkstreEslesme> ekle) {
  final ay = o.ekstreAyi;
  final kesimGunu = o.kesim == null ? null : dayOf(o.kesim!);
  final sonGun = o.sonOdeme == null ? null : dayOf(o.sonOdeme!);
  var id = h.id;
  if (id == null) {
    id = saveDebt(d, <String, dynamic>{
      'creditor': h.ad,
      'type': 'kredi_karti',
      'bank': o.banka ?? '',
      'remaining': 0,
      'limit': o.limit == null ? null : fromK(o.limit!),
      'schedule': <dynamic>[],
      'note': '',
      'payDay': null,
      'statementDay': kesimGunu,
      'dueDay': sonGun,
      'balanceDate': null,
      'payPlan': 'asgari',
    });
  }
  final debt = d.debt(id)!;
  if (o.son4 != null && debt.j['last4'] == null) debt.j['last4'] = o.son4;
  final idx = learnIndex(d);
  final acilanlar = <String, String>{};
  for (final e in ekle) {
    final i = e.islem;
    final abonelik = e.abonelikId ?? (e.yeniAbonelik ? _yeniAbonelik(d, i, 'card:$id', acilanlar) : null);
    if (abonelik != null) {
      // Karttan ödenen abonelik: o ayki ödendi işareti (borç ekstrede zaten var)
      savePayment(d, kind: 'sub', refId: abonelik, month: monthOf(i.tarih), k: i.k, date: i.tarih);
      continue;
    }
    final n = i.taksitSayisi ?? 1;
    final no = i.taksitNo ?? 1;
    final ilkAy = ay == null ? null : addM(ay, -(no - 1));
    final ad = i.ad;
    saveSpend(d, <String, dynamic>{
      'date': i.tarih,
      'name': ad,
      'place': '',
      'category': i.kategori ?? smartCategory(d, ad, idx),
      'amount': fromK(n > 1 ? i.k * n : i.k),
      'source': 'card:$id',
      'installments': n,
      'firstMonth': ilkAy ?? nextStatementMonth(debt, i.tarih),
      'note': 'Ekstreden',
      'url': '',
      // Ekstredeki işlem kesimden öncedir: kart bakiyesine ayrıca eklenmesin
      'createdAt': '${i.tarih}T00:00:00.000Z',
    });
  }
  // Ekstre son güncel durumdur: borç ve limit kesim tarihindeki hâliyle
  final borc = o.guncelBorc;
  if (borc != null) {
    debt.j.addAll(<String, dynamic>{
      'remaining': fromK(borc),
      if (o.limit != null) 'limit': fromK(o.limit!),
      'balanceDate': o.kesim ?? todayISO(),
      'balanceAt': '${o.kesim ?? todayISO()}T23:59:59.999Z',
    });
  }
  if (ay != null && o.donemBorcu != null) {
    saveStatement(d, id,
        month: ay,
        totalK: o.donemBorcu!,
        minK: o.asgari,
        cutDay: kesimGunu ?? debt.statementDay,
        dueDay: sonGun ?? debt.dueDay,
        payPlan: debt.payPlan);
  }
  return id;
}

String _hesapUygula(Data d, EkstreOkuma o, EkstreHedefi h, List<EkstreEslesme> ekle) {
  var id = h.id;
  if (id == null) {
    saveAccount(d,
        bank: o.banka ?? '',
        name: h.ad,
        type: o.banka == 'papara' ? 'cuzdan' : 'vadesiz',
        balanceK: 0);
    id = d.accounts.last.id;
  }
  final a = d.account(id)!;
  if (o.iban4 != null && a.j['iban4'] == null) a.j['iban4'] = o.iban4;
  final src = 'acc:$id';
  final idx = learnIndex(d);
  final acilanlar = <String, String>{};
  for (final e in ekle) {
    final i = e.islem;
    final ad = i.ad;
    final gelir = e.gelirId;
    final abonelik = e.abonelikId ?? (e.yeniAbonelik ? _yeniAbonelik(d, i, src, acilanlar) : null);
    if (gelir != null) {
      // Maaş: gelir "yattı" olur, hesaba girişi Gelir Motoru yazar
      setIncomeActual(d, gelir, monthOf(i.tarih), k: i.k, date: i.tarih, to: src);
    } else if (abonelik != null) {
      savePayment(d, kind: 'sub', refId: abonelik, month: monthOf(i.tarih), k: i.k, date: i.tarih, from: src);
    } else if (i.tur == 'giris') {
      saveTransfer(d, from: 'ext', to: src, k: i.k, date: i.tarih, note: ad);
    } else {
      var kategori = i.kategori ?? smartCategory(d, ad, idx);
      if (kategori == 'diger' && normTxt(i.etiket).contains('alisveris')) kategori = 'alisveris';
      saveSpend(d, <String, dynamic>{
        'date': i.tarih,
        'name': ad,
        'place': '',
        'category': kategori,
        'amount': fromK(i.k),
        'source': src,
        'installments': 1,
        'firstMonth': null,
        'note': 'Ekstreden',
        'url': '',
        'createdAt': '${i.tarih}T00:00:00.000Z',
      });
    }
  }
  // Döküm son güncel durumdur: son bakiye + dökümden sonra uygulamaya girilen hareketler
  final kapanis = o.kapanisBakiye;
  if (kapanis != null) {
    final son = o.donemSonu ?? todayISO();
    var sonra = 0;
    for (final s in d.spends) {
      if (s.source == src && s.date.compareTo(son) > 0) sonra -= toK(s.amount);
    }
    for (final t in d.transfers) {
      if (t.date.compareTo(son) <= 0) continue;
      if (t.to == src) sonra += toK(t.amount);
      if (t.from == src) sonra -= toK(t.amount);
    }
    for (final p in d.payments) {
      if (p.viaRefId == null && p.fromAccount == src && (p.paidDate ?? '').compareTo(son) > 0) sonra -= toK(p.paidAmount);
    }
    bakiyeyiDuzelt(d, id, kapanis + sonra);
  }
  return id;
}

// ---------------------------------------------------------------- PDF satırları

/// PDF'teki bir harf ve kutusu (PDF koordinatları: y yukarı doğru artar).
class PdfHarf {
  const PdfHarf(this.c, this.sol, this.ust, this.sag, this.alt);
  final String c;
  final double sol;
  final double ust;
  final double sag;
  final double alt;
  double get orta => (ust + alt) / 2;
  double get yukseklik => (ust - alt).abs();
}

/// Bir sayfanın harflerinden satırları kurar. Harfler PDF'in okuma sırasıyla gelir (PDFium satır
/// sonlarını '\r\n', kelime aralarını ' ' olarak verir): satırlar oradan bölünür; sütunlar arasındaki
/// büyük boşluk '\t' olur. Okuma sırasında satır sonu yoksa harflerin yerlerinden satır kurulur.
List<String> satirlariKur(List<PdfHarf> harfler) {
  if (!harfler.any((h) => h.c == '\n' || h.c == '\r')) return _geometrikSatirlar(harfler);
  final out = <String>[];
  final b = StringBuffer();
  PdfHarf? onceki;
  var bosluk = false;
  void bitir() {
    final t = b.toString().trim();
    if (t.isNotEmpty) out.add(t);
    b.clear();
    onceki = null;
    bosluk = false;
  }

  for (final h in harfler) {
    if (h.c == '\n' || h.c == '\r') {
      bitir();
      continue;
    }
    if (h.c.trim().isEmpty) {
      bosluk = true;
      continue;
    }
    final o = onceki;
    if (o != null) {
      final aralik = h.sol - o.sag;
      final yuk = math.max(o.yukseklik, h.yukseklik);
      if (aralik > math.max(yuk * 1.5, 6)) {
        b.write('\t');
      } else if (bosluk) {
        b.write(' ');
      }
    } else if (bosluk && b.isNotEmpty) {
      b.write(' ');
    }
    b.write(h.c);
    onceki = h;
    bosluk = false;
  }
  bitir();
  return out;
}

/// Okuma sırasında satır sonu olmayan PDF'ler: aynı yükseklikteki harfler soldan sağa birleşir.
List<String> _geometrikSatirlar(List<PdfHarf> harfler) {
  final hs = harfler.where((h) => h.c.trim().isNotEmpty && h.yukseklik > 0).toList()
    ..sort((a, b) {
      final c = b.orta.compareTo(a.orta);
      return c != 0 ? c : a.sol.compareTo(b.sol);
    });
  final satirlar = <List<PdfHarf>>[];
  for (final h in hs) {
    List<PdfHarf>? bulunan;
    for (final s in satirlar.reversed.take(3)) {
      final ref = s.first;
      if ((ref.orta - h.orta).abs() <= math.max(ref.yukseklik, h.yukseklik) * 0.45) {
        bulunan = s;
        break;
      }
    }
    if (bulunan == null) {
      satirlar.add([h]);
    } else {
      bulunan.add(h);
    }
  }
  final out = <String>[];
  for (final s in satirlar) {
    s.sort((a, b) => a.sol.compareTo(b.sol));
    final yuk = s.map((h) => h.yukseklik).reduce(math.max);
    final b = StringBuffer();
    PdfHarf? onceki;
    for (final h in s) {
      if (onceki != null) {
        final bosluk = h.sol - onceki.sag;
        if (bosluk > yuk * 1.6) {
          b.write('\t');
        } else if (bosluk > yuk * 0.18) {
          b.write(' ');
        }
      }
      b.write(h.c);
      onceki = h;
    }
    out.add(b.toString());
  }
  return out;
}
