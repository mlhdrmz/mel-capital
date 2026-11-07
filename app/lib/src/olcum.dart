// Mel Capital — kare ölçümü: uygulama takılıyorsa nerede takıldığını kullanıcının kendi
// bilgisayarında görmek için (Ayarlar → Performans ölçümü). Açıkken her karenin hesap (uygulamanın
// kodu, UI iş parçacığı) ve çizim (ekran kartı, raster iş parçacığı) süresi toplanır. Kapalıyken
// hiçbir şey toplanmaz.

import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class KareOlcumu extends ChangeNotifier {
  KareOlcumu._();
  static final KareOlcumu i = KareOlcumu._();

  bool _acik = false;
  bool get acik => _acik;

  /// (hesap µs, çizim µs)
  final List<(int, int)> _kareler = [];
  final Stopwatch _sonHaber = Stopwatch();

  void baslat() {
    _kareler.clear();
    if (!_acik) {
      SchedulerBinding.instance.addTimingsCallback(_al);
      _acik = true;
    }
    notifyListeners();
  }

  void durdur() {
    if (_acik) SchedulerBinding.instance.removeTimingsCallback(_al);
    _acik = false;
    notifyListeners();
  }

  void sifirla() {
    _kareler.clear();
    notifyListeners();
  }

  void _al(List<FrameTiming> liste) {
    for (final x in liste) {
      _kareler.add((x.buildDuration.inMicroseconds, x.rasterDuration.inMicroseconds));
    }
    if (_kareler.length > 20000) _kareler.removeRange(0, _kareler.length - 20000);
    // Ayarlar açıkken sayfa en çok saniyede bir yenilensin (yenilemenin kendisi de kare çizer)
    if (!_sonHaber.isRunning || _sonHaber.elapsedMilliseconds > 1000) {
      _sonHaber
        ..reset()
        ..start();
      notifyListeners();
    }
  }

  int get kare => _kareler.length;

  /// Hesabı ya da çizimi [esikMs]'den uzun süren kareler.
  int takilan(int esikMs) => _kareler.where((k) => math.max(k.$1, k.$2) > esikMs * 1000).length;

  double get enUzunHesap => _kareler.isEmpty ? 0 : _kareler.map((k) => k.$1).reduce(math.max) / 1000;
  double get enUzunCizim => _kareler.isEmpty ? 0 : _kareler.map((k) => k.$2).reduce(math.max) / 1000;
  double get ortHesap => _kareler.isEmpty ? 0 : _kareler.fold<int>(0, (a, k) => a + k.$1) / _kareler.length / 1000;
  double get ortCizim => _kareler.isEmpty ? 0 : _kareler.fold<int>(0, (a, k) => a + k.$2) / _kareler.length / 1000;

  /// En uzun [n] kare: (hesap ms, çizim ms).
  List<(double, double)> enUzunlar(int n) {
    final l = [..._kareler]..sort((a, b) => math.max(b.$1, b.$2) - math.max(a.$1, a.$2));
    return [for (final k in l.take(n)) (k.$1 / 1000, k.$2 / 1000)];
  }
}
