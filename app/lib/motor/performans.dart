// Mel Capital — PERFORMANS MOTORU
//
// Uygulamanın akıcı kalmasını denetler. Para hesabı yapmaz; diğer motorların ve ekranın ne kadar
// sürdüğüne bakar. İki işi var:
//   1. Bütçeler ([PerfButce]): bir karenin süresi, motorların ve sayfa kurulumunun en uzun süresi,
//      bir sayfada izin verilen pahalı çizim sayısı. Testler bunları her derlemede ölçer; bütçe
//      aşılırsa derleme durur (test/performans_test.dart). Yeni bir özellik (yeni sekme bölümü,
//      yeni motor işlevi) eklenince aynı denetimden geçer.
//   2. Otomatik kalite ([KaliteDenetcisi]): uygulama çalışırken karelerin süresine bakar; takılma
//      sürerse görsel kaliteyi "hafif"e indirir, düzelince bir kez yeniden "yüksek"i dener.
// Ekrana bağlayan kısım lib/src/performans.dart'ta (kare sürelerini toplar, sayfalara geçerli
// kaliteyi söyler). Bu dosya Flutter'a bağlı değildir; testlerde tek başına çalışır.
//
// Neden var: 07.11.2026'da Melih'in bilgisayarındaki ölçümde hesap (uygulamanın kodu) ortalama
// 0,7 ms, çizim (ekran kartı) ortalama 23 ms çıktı. Sebep yazılardaki bulanık gölgeler ve her
// karede hesaplanan yumuşak kenar bulanıklığıydı: tek tek masum, yüzlercesi bir arada ağır.
// Aşağıdaki çizim bütçeleri (hepsi 0) bunun yeniden olmasını engeller.

import 'dart:math' as math;

/// Geçerli görsel kalite.
///   yuksek: fotoğraf geçişi yumuşak, Özet'te rakamlar sayarak yükselir, yazıların arkasında
///           fotoğrafın bulanık kopyası.
///   hafif:  fotoğraf anında değişir, rakamlar hemen görünür, yazıların arkasında yalnızca koyu ton.
enum GorselKalite { yuksek, hafif }

/// Ayarlar'daki seçim.
enum KaliteAyari { otomatik, yuksek, hafif }

KaliteAyari kaliteAyariOku(Object? v) => switch (v) {
      'yuksek' => KaliteAyari.yuksek,
      'hafif' => KaliteAyari.hafif,
      _ => KaliteAyari.otomatik,
    };

String kaliteAyariYaz(KaliteAyari a) => a.name;

/// Ayar ve otomatik karardan geçerli kalite.
GorselKalite gecerliKalite(KaliteAyari ayar, GorselKalite otomatik) => switch (ayar) {
      KaliteAyari.yuksek => GorselKalite.yuksek,
      KaliteAyari.hafif => GorselKalite.hafif,
      KaliteAyari.otomatik => otomatik,
    };

/// Hız bütçeleri. Süreler milisaniye; motor ve sayfa bütçeleri testlerin koştuğu hata ayıklama
/// modu ve büyük deneme verisi (3 yıl, ~5.000 harcama) içindir, gerçek uygulama birkaç kat hızlıdır.
/// Bütçeler ölçülen değerin birkaç katıdır: amaç küçük oynamaları değil, bir işin yanlışlıkla
/// ağırlaşmasını (iç içe döngü, her karede bulanıklık) yakalamak.
class PerfButce {
  const PerfButce._();

  /// Akıcı bir kare (60 Hz) ve "takıldı" denen kare (mikrosaniye).
  static const int kareUs = 16667;
  static const int yavasKareUs = 22000;
  static const int takilmaUs = 33000;

  // ---- Motorlar (ölçülen: Ctx 12–15, Plan 13 ay 20–55, yaklaşan 17, hareketler 3–5, arama 28,
  // öğrenme 27, kopya 5, JSON 15 ms)
  static const Map<String, double> motorMs = {
    'Ctx kurulumu (bütün motorlar)': 150,
    'Plan: 13 ayın kalemleri ve özetleri': 400,
    'Yaklaşan ödemeler': 200,
    'Hareketler listesi': 100,
    'Harcama arama': 300,
    'Kategori öğrenme dizini': 300,
    'Veri kopyası (her değişiklikte kayıt için)': 100,
    'Veri JSON (dosyaya yazılan)': 200,
    'Borç kapatma hesabı (üç yön)': 100,
  };

  // ---- Sayfalar (ölçülen: en ağır sekmenin ilk karesi ~0,7–1 sn, toplam ~1,7 sn)
  static const double sekmeIlkKareMs = 2500;
  static const double sekmeToplamMs = 5000;
  static const double degisiklikMs = 1500;

  // ---- Çizim: bir sayfada izin verilen pahalı çizim sayısı. Her biri her karede ayrı bir
  // bulanıklık işlemidir; hepsi 0.
  /// Bulanık gölgeli yazı (TextStyle.shadows içinde blurRadius > 0).
  static const int bulanikGolgeliYazi = 0;

  /// Canlı bulanıklık (BackdropFilter, ImageFiltered).
  static const int canliBulaniklik = 0;

  /// Yuvarlak dikdörtgen, hap ya da daire olmayan biçimde bulanık gölge (ShapeDecoration.shadows).
  static const int yolGolgesi = 0;
}

/// Otomatik kalite kararı. Kareler [pencere]'lik bloklar hâlinde değerlendirilir:
///   - yüksek kalitede art arda 2 blokta karelerin en az %20'si yavaşsa ([PerfButce.yavasKareUs]
///     üstü) "hafif"e inilir;
///   - hafifte art arda 8 blok temizse (yavaş kare en çok %5) bir kez "yüksek" yeniden denenir;
///   - ikinci kez inilirse oturum boyunca hafifte kalınır (gidip gelmesin).
/// Tek tük yavaş kare (sekme değişirken ilk kare gibi) kaliteyi düşürmez.
class KaliteDenetcisi {
  KaliteDenetcisi({this.pencere = 90});

  final int pencere;

  GorselKalite seviye = GorselKalite.yuksek;

  /// Kaç kez hafife inildi.
  int dusurme = 0;

  int _n = 0, _yavas = 0, _kotuBlok = 0, _iyiBlok = 0;

  /// Oturum boyunca hafifte kalınacak mı.
  bool get kilitli => dusurme >= 2;

  /// Bir karenin hesap ve çizim süresi (mikrosaniye). Seviye değiştiyse true.
  bool kare(int hesapUs, int cizimUs) {
    _n++;
    if (math.max(hesapUs, cizimUs) > PerfButce.yavasKareUs) _yavas++;
    if (_n < pencere) return false;
    final oran = _yavas / _n;
    _n = 0;
    _yavas = 0;
    if (seviye == GorselKalite.yuksek) {
      _kotuBlok = oran >= 0.20 ? _kotuBlok + 1 : 0;
      if (_kotuBlok >= 2) {
        seviye = GorselKalite.hafif;
        dusurme++;
        _kotuBlok = 0;
        _iyiBlok = 0;
        return true;
      }
    } else if (!kilitli) {
      _iyiBlok = oran <= 0.05 ? _iyiBlok + 1 : 0;
      if (_iyiBlok >= 8) {
        seviye = GorselKalite.yuksek;
        _iyiBlok = 0;
        return true;
      }
    }
    return false;
  }

  /// Baştan başlar (ayar "Otomatik"e yeniden alınınca).
  void sifirla() {
    seviye = GorselKalite.yuksek;
    dusurme = 0;
    _n = 0;
    _yavas = 0;
    _kotuBlok = 0;
    _iyiBlok = 0;
  }
}
