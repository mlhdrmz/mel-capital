// Web önizlemesi: fotoğraflar indirilmez. `?foto=1` ile eski telefon uygulamasındaki gibi doğrudan Unsplash
// adresleri kullanılır (tasarım kontrolü için); yoksa gömülü kapaklar görünür.

import '../core/model.dart';
import '../core/photos.dart';
import 'photos.dart';

class WebPhotoStore implements PhotoStore {
  final Map<String, PhotoSrc> _avail = {};

  @override
  void Function()? onChange;

  @override
  Map<String, PhotoSrc> get available => Map.unmodifiable(_avail);

  @override
  int get missing => 0;

  @override
  bool get busy => false;

  @override
  Future<void> start(PhotoSize size) async {
    _avail
      ..clear()
      ..addAll({for (final p in kPhotos) p.id: PhotoSrc(url: size.url(p.id))});
    onChange?.call();
  }

  @override
  Future<Json?> readLegacyPrefs() async => null;

  @override
  void dispose() => onChange = null;
}

PhotoStore? createPlatformPhotoStore({bool network = false}) => network ? WebPhotoStore() : null;
