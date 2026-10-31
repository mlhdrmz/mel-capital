import 'store.dart';
import 'store_memory.dart';

/// Web: dosya yok, bellekte çalışılır.
Store createPlatformStore() => MemoryStore();
