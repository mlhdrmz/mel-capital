import 'store.dart';
import 'store_io.dart';

/// Windows ve telefon: dosyalara yazılır.
Store createPlatformStore() => FileStore();
