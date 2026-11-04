import 'package:flutter/painting.dart';

import '../storage/photos.dart';

/// Web önizlemesi: fotoğraf adresten gelir.
ImageProvider? photoImage(PhotoSrc src) {
  final url = src.url;
  return url == null ? null : NetworkImage(url);
}
