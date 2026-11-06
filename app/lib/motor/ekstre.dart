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
//      durum sayar (kart borcu ve limit kesim tarihindeki hâliyle; hesap bakiyesi dökümün son
//      bakiyesiyle ve sonrasında uygulamaya girilen hareketlerle).
// Hiçbir şey tahminle eklenmez: okunamayanlar [EkstreOkuma.eksikler]'de kullanıcıya söylenir.
// Kart numarasının yalnızca son 4 hanesi (kart kaydında "last4"), IBAN'ın son 4 hanesi (hesapta
// "iban4") saklanır; tam numara hiçbir yerde tutulmaz.

import 'dart:math' as math;

import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'borc.dart';
import 'cekirdek.dart';
import 'gider.dart';

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
    this.ham = '',
  });

  /// YYYY-AA-GG
  final String tarih;
  final String aciklama;

  /// Kuruş, her zaman artı. Yönü [tur] söyler.
  final int k;

  /// harcama | ucret | odeme | iade (kart); cikis | giris (hesap)
  final String tur;
  final int? taksitNo;
  final int? taksitSayisi;
  final String ham;

  bool get taksitli => (taksitSayisi ?? 1) > 1;

  /// Uygulamaya harcama olarak eklenebilir mi (kart ödemeleri ve iadeler bakiyede zaten var).
  bool get eklenebilir => tur == 'harcama' || tur == 'ucret' || tur == 'cikis' || tur == 'giris';
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
  const _Tutar(this.k, this.eksi, this.basla, this.bitis);
  final int k;
  final bool eksi;
  final int basla;
  final int bitis;
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
    out.add(_Tutar(k, on == '-' || son == '-' || son == 'A', m.start, m.end));
  }
  return out;
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
      for (final b in basliklar) {
        if (h.contains(b)) {
          bulunan = b;
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
      if (!sonrakiSatir) continue;
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

/// Özet satırları: işlem sayılmaz.
final RegExp _ozetSatiri = RegExp(
    r'onceki donem|devreden|donem borcu|toplam|asgari|hesap kesim|son odeme|kart limiti|kullanilabilir|acilis bakiye|kapanis bakiye|onceki bakiye|^bakiye$');

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
    o.acilisBakiye = _deger(satirlar, const ['devreden bakiye', 'onceki bakiye', 'acilis bakiyesi', 'donem basi bakiye'], _ilkTutar);
    final (islemler, sonBakiye, sonTarih) = _hesapIslemleri(satirlar, o.acilisBakiye);
    o.islemler = islemler;
    o.kapanisBakiye = _deger(satirlar, const ['kapanis bakiyesi', 'donem sonu bakiye', 'guncel bakiye', 'son bakiye'], _ilkTutar) ?? sonBakiye;
    o.donemSonu = _deger(satirlar, const ['donem sonu', 'bitis tarihi', 'son tarih'], _ilkTarih) ?? sonTarih;
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
    final tutarlar = _tutarlar(govde);
    if (tutarlar.isEmpty) continue;
    final duzGovde = _duz(govde);
    if (_ozetSatiri.hasMatch(duzGovde)) continue;
    // Puan sütunu (bonus, worldpuan, maxipuan...) varsa son tutar puandır
    var secilen = tutarlar.last;
    if (tutarlar.length >= 2) {
      final onceki = tutarlar[tutarlar.length - 2];
      final puanli = RegExp(r'puan|bonus|chip|mil\b|miles').hasMatch(duzGovde) && tutarlar.last.k < onceki.k;
      // Puan çoğu zaman tutarın binde beşi kadardır: çok küçük son sayı puandır
      if (puanli || tutarlar.last.k * 20 < onceki.k) secilen = onceki;
    }
    // Açıklama: tarihten sonra ilk tutara kadar (ikinci tarih varsa o da atlanır)
    var aciklama = govde.substring(0, tutarlar.first.basla);
    final ikinciTarih = _tarihRe.firstMatch(aciklama);
    if (ikinciTarih != null && ikinciTarih.start < 3) aciklama = aciklama.substring(ikinciTarih.end);
    // Taksit: "2/6" ya da "2. taksit / 6"
    int? no, sayi;
    final tk = RegExp(r'(?<![\d/.])(\d{1,2})\s?/\s?(\d{1,2})(?![\d/.])').firstMatch(aciklama);
    if (tk != null) {
      final a = int.parse(tk.group(1)!), b = int.parse(tk.group(2)!);
      if (b >= 2 && b <= 36 && a >= 1 && a <= b) {
        no = a;
        sayi = b;
        aciklama = aciklama.replaceRange(tk.start, tk.end, ' ');
      }
    }
    aciklama = _temizAciklama(aciklama.replaceAll(RegExp(r'taksit(li)?', caseSensitive: false), ''));
    if (!RegExp(r'[a-zA-ZçğıöşüÇĞİÖŞÜ]').hasMatch(aciklama)) continue;
    final da = _duz(aciklama);
    String tur;
    if (RegExp(r'odeme|tahsilat|hesaptan aktarim|otomatik odeme|odemeniz').hasMatch(da)) {
      tur = 'odeme';
    } else if (RegExp(r'iade|iptal').hasMatch(da) || (secilen.eksi && !RegExp(r'faiz|ucret').hasMatch(da))) {
      tur = 'iade';
    } else if (RegExp(r'faiz|bsmv|kkdf|ucret|aidat|komisyon|gecikme').hasMatch(da)) {
      tur = 'ucret';
    } else {
      tur = 'harcama';
    }
    if (aciklama.isEmpty) aciklama = tur == 'odeme' ? 'Ödeme' : 'Harcama';
    out.add(EkstreIslem(tarih: tarih, aciklama: aciklama, k: secilen.k, tur: tur, taksitNo: no, taksitSayisi: sayi, ham: s));
  }
  return out;
}

/// Hesap dökümünün işlem satırları. Yön, yürüyen bakiyeden (varsa) ya da işaretten bulunur.
(List<EkstreIslem>, int?, String?) _hesapIslemleri(List<String> satirlar, int? acilis) {
  final out = <EkstreIslem>[];
  int? onceki = acilis;
  int? sonBakiye;
  String? sonTarih;
  for (final satir in satirlar) {
    final s = satir.trim();
    final tm = _tarihRe.firstMatch(s);
    if (tm == null || tm.start > 2) continue;
    final tarih = tarihCevir(tm.group(0)!);
    if (tarih == null) continue;
    final govde = s.substring(tm.end);
    final tutarlar = _tutarlar(govde);
    if (tutarlar.isEmpty) continue;
    final duzGovde = _duz(govde);
    if (_ozetSatiri.hasMatch(duzGovde)) {
      if (RegExp(r'devreden|onceki bakiye|acilis').hasMatch(duzGovde)) onceki = tutarlar.last.k * (tutarlar.last.eksi ? -1 : 1);
      continue;
    }
    var aciklama = govde.substring(0, tutarlar.first.basla);
    final ikinciTarih = _tarihRe.firstMatch(aciklama);
    if (ikinciTarih != null && ikinciTarih.start < 3) aciklama = aciklama.substring(ikinciTarih.end);
    aciklama = _temizAciklama(aciklama);
    if (!RegExp(r'[a-zA-ZçğıöşüÇĞİÖŞÜ]').hasMatch(aciklama)) continue;
    int tutar;
    bool giris;
    if (tutarlar.length >= 2) {
      final bakiye = tutarlar.last.k * (tutarlar.last.eksi ? -1 : 1);
      final miktar = tutarlar[tutarlar.length - 2];
      tutar = miktar.k;
      if (onceki != null && (bakiye - onceki).abs() == tutar) {
        giris = bakiye > onceki;
      } else {
        giris = !miktar.eksi && !RegExp(r'odeme|harcama|pos|cekim|eft gonder|havale gonder|giden|fatura|ucret|komisyon').hasMatch(_duz(aciklama));
      }
      onceki = bakiye;
      sonBakiye = bakiye;
    } else {
      final miktar = tutarlar.first;
      tutar = miktar.k;
      giris = !miktar.eksi && RegExp(r'gelen|maas|yatan|alacak|iade|faiz geliri').hasMatch(_duz(aciklama));
    }
    if (aciklama.isEmpty) aciklama = giris ? 'Para girişi' : 'Harcama';
    sonTarih = tarih;
    out.add(EkstreIslem(tarih: tarih, aciklama: aciklama, k: tutar, tur: giris ? 'giris' : 'cikis', ham: s));
  }
  return (out, sonBakiye, sonTarih);
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
  const EkstreEslesme(this.islem, this.durum, {this.kayitId, this.kayitAdi, this.kayitTarihi});
  final EkstreIslem islem;
  final EslesmeDurumu durum;

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
    if (e != null && enGun <= 3 && (_benzerAd(e.$2, i.aciklama) || enGun <= 1)) {
      kullanilan.add(e.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.var_, kayitId: e.$1, kayitAdi: e.$2, kayitTarihi: e.$3));
    } else if (e != null && enGun <= 7) {
      kullanilan.add(e.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.supheli, kayitId: e.$1, kayitAdi: e.$2, kayitTarihi: e.$3));
    } else if (i.taksitli && (i.taksitNo ?? 1) > 1 && e != null) {
      // Eski bir taksitli alışverişin bu ayki taksiti: alışveriş zaten girilmiş
      kullanilan.add(e.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.var_, kayitId: e.$1, kayitAdi: e.$2, kayitTarihi: e.$3));
    } else if (kaynaksiz.where((k) => !kullanilan.contains(k.$1)).isNotEmpty) {
      final k = kaynaksiz.firstWhere((k) => !kullanilan.contains(k.$1));
      kullanilan.add(k.$1);
      out.add(EkstreEslesme(i, EslesmeDurumu.supheli, kayitId: k.$1, kayitAdi: k.$2, kayitTarihi: k.$3));
    } else {
      out.add(EkstreEslesme(i, EslesmeDurumu.yeni));
    }
  }
  return out;
}

// ---------------------------------------------------------------- Uygulama

/// Seçimlere göre ekstreyi uygular. [ekle]: eklenecek eşleşmeler (yeni olanlar ve "ayrı ekle"
/// denen şüpheliler). Hedef yeni ise kart ya da hesap açılır. Hedefin kimliğini döndürür.
String ekstreUygula(Data d, EkstreOkuma o, EkstreHedefi h, List<EkstreEslesme> ekle) {
  if (h.kart) return _kartUygula(d, o, h, ekle);
  return _hesapUygula(d, o, h, ekle);
}

String _ad(String aciklama) {
  final t = aciklama.trim();
  if (t.isEmpty) return 'Harcama';
  // Büyük harfli banka yazısını okunur yap: "MIGROS KADIKOY" → "Migros Kadıköy" değil, "Migros Kadikoy"
  final buyuk = t == t.toUpperCase();
  if (!buyuk) return t;
  return t.split(' ').map((w) => w.isEmpty ? w : '${w[0]}${trLower(w.substring(1))}').join(' ');
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
  for (final e in ekle) {
    final i = e.islem;
    final n = i.taksitSayisi ?? 1;
    final no = i.taksitNo ?? 1;
    final ilkAy = ay == null ? null : addM(ay, -(no - 1));
    final ad = _ad(i.aciklama);
    saveSpend(d, <String, dynamic>{
      'date': i.tarih,
      'name': ad,
      'place': '',
      'category': i.tur == 'ucret' ? 'banka' : smartCategory(d, ad, idx),
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
  for (final e in ekle) {
    final i = e.islem;
    final ad = _ad(i.aciklama);
    if (i.tur == 'giris') {
      saveTransfer(d, from: 'ext', to: src, k: i.k, date: i.tarih, note: ad);
    } else {
      final da = normTxt(ad);
      final kategori = RegExp(r'kredi karti|kart odeme|kk odeme').hasMatch(da)
          ? 'kart_asgari'
          : RegExp(r'eft|havale|fast').hasMatch(da)
              ? 'transfer'
              : RegExp(r'atm|nakit cekim|para cekme').hasMatch(da)
                  ? 'nakit'
                  : smartCategory(d, ad, idx);
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

/// Bir sayfanın harflerinden satırları kurar: aynı yükseklikteki harfler soldan sağa birleşir;
/// küçük boşluklar ' ', sütun aralığı kadar büyük boşluklar '\t' olur.
List<String> satirlariKur(List<PdfHarf> harfler) {
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
