// Mel Capital — Performans Motoru'nun ekrana bağlanan kısmı (motor: lib/motor/performans.dart).
//
// [Performans] karelerin sürelerini toplar ve motordaki [KaliteDenetcisi]'ye verir. Geçerli görsel
// kalite [KaliteScope] ile sayfalara iletilir: arka plan (fotoğraf geçişi), rakamların sayarak
// yükselmesi ve yazıların arkasındaki bulanık kopya buna bakar. Yeni bir efekt eklenince o da
// [KaliteScope.of] ile "hafif"te kapanmalıdır.

import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../motor/performans.dart';
import 'state.dart';

export '../motor/performans.dart' show GorselKalite, KaliteAyari, kaliteAyariOku, kaliteAyariYaz;

class Performans extends ChangeNotifier {
  Performans._();
  static final Performans i = Performans._();

  final KaliteDenetcisi denetci = KaliteDenetcisi();
  bool _dinliyor = false;

  /// "Otomatik" ayarda geçerli seviye.
  GorselKalite get otomatik => denetci.seviye;

  /// Kare sürelerini dinlemeye başlar (bir kez). Motor süreleri toplu hâlde, yaklaşık saniyede
  /// bir verir; dinlemenin kendisi yük getirmez.
  void baslat() {
    if (_dinliyor) return;
    _dinliyor = true;
    SchedulerBinding.instance.addTimingsCallback(_al);
  }

  void _al(List<FrameTiming> liste) {
    var degisti = false;
    for (final x in liste) {
      if (denetci.kare(x.buildDuration.inMicroseconds, x.rasterDuration.inMicroseconds)) degisti = true;
    }
    if (degisti) notifyListeners();
  }

  /// Otomatik kararı baştan başlatır.
  void sifirla() {
    denetci.sifirla();
    notifyListeners();
  }
}

/// Geçerli görsel kalite (Ayarlar'daki seçim + otomatik karar).
class KaliteScope extends InheritedWidget {
  const KaliteScope({super.key, required this.kalite, required this.ayar, required super.child});

  final GorselKalite kalite;
  final KaliteAyari ayar;

  /// Bulunduğu yerdeki kalite (kapsam yoksa yüksek).
  static GorselKalite of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KaliteScope>()?.kalite ?? GorselKalite.yuksek;

  @override
  bool updateShouldNotify(KaliteScope oldWidget) => oldWidget.kalite != kalite || oldWidget.ayar != ayar;
}

/// Uygulamanın köküne konur: ayarı ve otomatik kararı dinler, altına [KaliteScope] koyar.
class KaliteKapsami extends StatefulWidget {
  const KaliteKapsami({super.key, required this.child});

  final Widget child;

  @override
  State<KaliteKapsami> createState() => _KaliteKapsamiState();
}

class _KaliteKapsamiState extends State<KaliteKapsami> {
  @override
  void initState() {
    super.initState();
    Performans.i.baslat();
  }

  @override
  Widget build(BuildContext context) {
    final ayar = kaliteAyariOku(AppScope.of(context).settings['kalite']);
    return AnimatedBuilder(
      animation: Performans.i,
      child: widget.child,
      builder: (context, child) => KaliteScope(kalite: gecerliKalite(ayar, Performans.i.otomatik), ayar: ayar, child: child!),
    );
  }
}
