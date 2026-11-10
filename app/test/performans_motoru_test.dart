// Performans Motoru: otomatik kalite kararı, yazı gölgesi kuralı ve yumuşak kenar kafesi.

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/motor/performans.dart';
import 'package:mel_capital/src/bulanik.dart';
import 'package:mel_capital/src/sahne.dart';
import 'package:mel_capital/src/theme.dart';

void main() {
  /// [n] kare verir; her [her] karede biri yavaş (çizim [yavasMs]). Seviye kaç kez değişti.
  int ver(KaliteDenetcisi d, int n, {int her = 0, int yavasMs = 40}) {
    var degisim = 0;
    for (var i = 0; i < n; i++) {
      final yavas = her > 0 && i % her == 0;
      if (d.kare(700, yavas ? yavasMs * 1000 : 6000)) degisim++;
    }
    return degisim;
  }

  test('akıcı karelerde kalite yüksek kalır; tek tük yavaş kare (sekme değişimi) düşürmez', () {
    final d = KaliteDenetcisi();
    expect(ver(d, 2000), 0);
    expect(ver(d, 2000, her: 30), 0, reason: 'karelerin %3\'ü yavaş');
    expect(d.seviye, GorselKalite.yuksek);
  });

  test('takılma sürerse hafife iner (Melih\'in ölçümü: karelerin ~%24\'ü 33 ms\'den uzun)', () {
    final d = KaliteDenetcisi();
    expect(ver(d, 90, her: 4), 0, reason: 'tek kötü blok yetmez');
    expect(d.seviye, GorselKalite.yuksek);
    expect(ver(d, 90, her: 4), 1);
    expect(d.seviye, GorselKalite.hafif);
    expect(d.dusurme, 1);
  });

  test('düzelince bir kez yeniden yüksek denenir; yine takılırsa oturum boyunca hafifte kalır', () {
    final d = KaliteDenetcisi();
    ver(d, 180, her: 4);
    expect(d.seviye, GorselKalite.hafif);
    expect(ver(d, 90 * 7), 0, reason: '8 temiz blok dolmadan dönmez');
    expect(ver(d, 90), 1);
    expect(d.seviye, GorselKalite.yuksek);
    ver(d, 180, her: 4);
    expect(d.seviye, GorselKalite.hafif);
    expect(d.kilitli, isTrue);
    expect(ver(d, 90 * 40), 0, reason: 'kilitliyken geri dönmez');
    d.sifirla();
    expect(d.seviye, GorselKalite.yuksek);
    expect(d.kilitli, isFalse);
  });

  test('hesap (uygulamanın kodu) yavaşsa da sayılır', () {
    final d = KaliteDenetcisi();
    for (var i = 0; i < 180; i++) {
      d.kare(i.isEven ? 30000 : 500, 4000);
    }
    expect(d.seviye, GorselKalite.hafif);
  });

  test('ayar: otomatik, yüksek, hafif', () {
    expect(kaliteAyariOku(null), KaliteAyari.otomatik);
    expect(kaliteAyariOku('hafif'), KaliteAyari.hafif);
    expect(kaliteAyariOku(kaliteAyariYaz(KaliteAyari.yuksek)), KaliteAyari.yuksek);
    expect(gecerliKalite(KaliteAyari.otomatik, GorselKalite.hafif), GorselKalite.hafif);
    expect(gecerliKalite(KaliteAyari.yuksek, GorselKalite.hafif), GorselKalite.yuksek);
    expect(gecerliKalite(KaliteAyari.hafif, GorselKalite.yuksek), GorselKalite.hafif);
  });

  test('yazı gölgeleri bulanık değildir (her bulanık gölge her karede ayrı bir bulanıklık işi)', () {
    for (final g in [...kPhotoTextShadow, ...kBigTextShadow, ...kNetYaziGolgesi]) {
      expect(g.blurRadius, 0);
    }
  });

  test('yazı arkası: varsayılan orta; koyuluk hafif < orta < koyu', () {
    expect(yaziArkasiOku(null), YaziArkasi.orta);
    expect(yaziArkasiOku('koyu'), YaziArkasi.koyu);
    expect(yaziArkasiTonu(YaziArkasi.hafif), lessThan(yaziArkasiTonu(YaziArkasi.orta)));
    expect(yaziArkasiTonu(YaziArkasi.orta), lessThan(yaziArkasiTonu(YaziArkasi.koyu)));
    expect(yaziArkasiTonu(YaziArkasi.koyu), lessThanOrEqualTo(1));
  });

  test('yumuşak kenar kafesi: noktalar alanın içinde, dış kenar görünmez, iç tam görünür, üçgenler geçerli', () {
    for (final (boyut, yaricap, yumusaklik) in const [(Size(400, 200), 24.0, 16.0), (Size(120, 28), 14.0, 9.0), (Size(10, 6), 14.0, 9.0), (Size(300, 80), 20.0, 0.0)]) {
      final k = yumusakKafes(boyut, yaricap, yumusaklik);
      final n = k.alfalar.length;
      expect(k.konumlar.length, n * 2);
      for (var i = 0; i < n; i++) {
        expect(k.konumlar[i * 2], inInclusiveRange(-0.01, boyut.width + 0.01));
        expect(k.konumlar[i * 2 + 1], inInclusiveRange(-0.01, boyut.height + 0.01));
        expect(k.alfalar[i], inInclusiveRange(0.0, 1.0));
      }
      expect(k.ucgenler.length % 3, 0);
      expect(k.ucgenler.every((i) => i < n), isTrue);
      expect(k.alfalar.last, 1.0, reason: 'orta nokta tam görünür');
      if (yumusaklik > 0) expect(k.alfalar.first, 0.0, reason: 'dış kenar görünmez');
      // Üçgenlerin toplam alanı alanı geçmez ve boş değildir (üst üste binme ya da ters üçgen yok)
      var alan = 0.0;
      for (var t = 0; t < k.ucgenler.length; t += 3) {
        final a = k.ucgenler[t], b = k.ucgenler[t + 1], c = k.ucgenler[t + 2];
        final ax = k.konumlar[a * 2], ay = k.konumlar[a * 2 + 1];
        final bx = k.konumlar[b * 2], by = k.konumlar[b * 2 + 1];
        final cx = k.konumlar[c * 2], cy = k.konumlar[c * 2 + 1];
        alan += ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)).abs() / 2;
      }
      expect(alan, greaterThan(boyut.width * boyut.height * 0.6));
      expect(alan, lessThanOrEqualTo(boyut.width * boyut.height * 1.001));
    }
  });
}
