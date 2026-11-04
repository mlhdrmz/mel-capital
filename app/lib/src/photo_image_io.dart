import 'dart:io';

import 'package:flutter/painting.dart';

import '../storage/photos.dart';

/// İndirilmiş fotoğrafın görüntüsü (dosyadan; dosya yoksa adresten).
ImageProvider? photoImage(PhotoSrc src) {
  final path = src.path;
  if (path != null) return FileImage(File(path));
  final url = src.url;
  return url == null ? null : NetworkImage(url);
}
