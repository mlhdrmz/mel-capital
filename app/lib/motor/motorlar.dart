// Mel Capital — motorlar: uygulamanın bütün hesapları ve veri değişiklikleri.
//
//   cekirdek.dart  Çekirdek (Hareket Defteri): hareketler, hesap bakiyeleri, aktarmalar, bankalar
//   gelir.dart     Gelir Motoru: maaş ve diğer gelirler, "Maaşın yattı mı?"
//   gider.dart     Gider Motoru: harcamalar, abonelikler, faturalar, sabit giderler
//   borc.dart      Borç Motoru: kartlar, boş limit, ekstreler, krediler, Findeks
//   plan.dart      Plan Motoru: aylık özet, harcanabilir para, devir, ödemeler, istek listesi
//   ekstre.dart    Ekstre Motoru: PDF ekstreyi okur, bankayı ve kartı/hesabı bulur, eşleştirir, ekler
//   uyum.dart      Uyum denetimi: motorların birbirini tuttuğunu denetler
//
// Kurallar: sayfalar hesap yapmaz, motorlara sorar; veri yalnızca AppState.update içinde
// motorların işlevleriyle değişir; hesap bakiyesine yalnızca Çekirdek'teki accAdjust yazar.

export 'borc.dart';
export 'cekirdek.dart';
export 'ekstre.dart';
export 'gelir.dart';
export 'gider.dart';
export 'plan.dart';
export 'uyum.dart';
