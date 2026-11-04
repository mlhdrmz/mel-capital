// Arka plan fotoğraflarının bulunduğu yer. Bilgisayarda ve telefonda fotoğraflar internet varken bir kez
// ekranın çözünürlüğünde indirilir ve saklanır; sonra internetsiz görünür. Web önizlemesinde doğrudan
// Unsplash adresleri kullanılır.

import '../core/model.dart';

/// Kullanılabilir bir fotoğraf: dosya yolu (indirilmiş) ya da adres (web) ve ortalama parlaklığı (0–1,
/// bilinmiyorsa -1).
class PhotoSrc {
  const PhotoSrc({this.path, this.url, this.lum = -1});
  final String? path;
  final String? url;
  final double lum;
}

/// İndirilecek boyut: bilgisayarda ekranın genişliği (1920, 2560 ya da 3840), telefonda ekranın kendisi
/// (dikey, kırpılmış).
class PhotoSize {
  const PhotoSize.desktop(this.width)
      : height = 0,
        phone = false;
  const PhotoSize.phone(this.width, this.height) : phone = true;
  final int width;
  final int height;
  final bool phone;

  /// Bilgisayar: ekranın büyük kenarı (fiziksel piksel) → 1920, 2560 ya da 3840 (eski uygulamadaki gibi).
  factory PhotoSize.forScreen({required double width, required double height, required double dpr, required bool phone}) {
    if (phone) {
      // Eski telefon uygulaması: ekran (en çok 2× yoğunluk), 80 pikselin katı, en çok 2400
      final d = dpr < 1 ? 1.0 : (dpr > 2 ? 2.0 : dpr);
      int r(double n) {
        final v = (n * d / 80).round() * 80;
        return v < 320 ? 320 : (v > 2400 ? 2400 : v);
      }

      final w = width < height ? width : height;
      final h = width < height ? height : width;
      return PhotoSize.phone(r(w), r(h));
    }
    final big = (width > height ? width : height) * dpr;
    return PhotoSize.desktop(big >= 3000 ? 3840 : (big >= 2000 ? 2560 : 1920));
  }

  /// Unsplash adresi.
  String url(String id) => phone
      ? 'https://images.unsplash.com/photo-$id?w=$width&h=$height&fit=crop&crop=entropy&q=70&fm=jpg'
      : 'https://images.unsplash.com/photo-$id?ixlib=rb-4.1.0&w=$width&fit=max&q=82&fm=jpg';
}

abstract class PhotoStore {
  /// Bu cihazda kullanılabilen fotoğraflar (kimlik → kaynak).
  Map<String, PhotoSrc> get available;

  /// İstenip henüz inmemiş fotoğraf sayısı.
  int get missing;

  /// İndirme sürüyor mu.
  bool get busy;

  /// Yeni fotoğraf inince ya da liste değişince çağrılır.
  void Function()? onChange;

  /// Kayıtlı fotoğrafları bulur; eksikleri arka planda indirmeye başlar (internet yoksa sonra yeniden dener).
  Future<void> start(PhotoSize size);

  /// Eski Mel Capital'in fotoğraf tercihleri (gizlenenler, favoriler, akşam teması); yalnızca okunur.
  Future<Json?> readLegacyPrefs();

  void dispose();
}
