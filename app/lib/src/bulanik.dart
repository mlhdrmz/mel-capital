// Mel Capital — bulanık kopya: yazıların arkasındaki bulanıklık için arka plan fotoğrafının küçük,
// bulanık bir kopyası.
//
// Eskiden her bölümün ve yazının arkasında canlı bulanıklık (BackdropFilter) vardı: ekranda bir şey
// kıpırdadığında (fotoğraf geçişi, sayan rakam) hepsi her karede baştan hesaplanıyor, Windows'ta
// sayfa değişirken uygulama takılıyordu. Şimdi fotoğraf değişince bulanık kopya bir kez hazırlanır
// ([bulanikKopyaHazirla]); bölümler arkalarına bu kopyanın ekranda kendilerine denk gelen yerini,
// kenarları yumuşakça kaybolarak çizer ([BulanikZemin]). Görünüm aynı, yük çok az.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'background.dart' show kPhotoAlignment;

/// Arka planın bulanık kopyası ve fotoğrafın kendi boyutu (ekrana nasıl yerleştiğini hesaplamak için).
class BulanikArka {
  const BulanikArka(this.anahtar, this.resim, this.kaynak);

  /// Hangi fotoğrafın kopyası.
  final String anahtar;
  final ui.Image resim;

  /// Fotoğrafın (çözülmüş) boyutu.
  final Size kaynak;
}

/// Şu an arka planda görünen fotoğrafın bulanık kopyası (henüz hazır değilse null).
final ValueNotifier<BulanikArka?> kBulanikArka = ValueNotifier<BulanikArka?>(null);

String? _istenen;

/// Hazırlanmış kopyalar (en son kullanılanlar; sekmelerin fotoğrafları): sekme değişince kopya
/// yeniden hazırlanmaz.
final Map<String, BulanikArka> _kopyalar = {};
const int _enCokKopya = 12;
final Map<String, Future<BulanikArka?>> _hazirlaniyor = {};

/// Kopyanın genişliği (piksel) ve bu genişlikteki bulanıklık. Ekranda kabaca 8–12 noktalık
/// bulanıklık eder (eski iki katlı bulanıklık kadar).
const double _kopyaGenisligi = 400;
const double _kopyaBulanikligi = 2.4;

/// Arka planda [resim] gösterilmeye başlayınca çağrılır: kopyayı (hazır değilse) bir kez hazırlar ve
/// gösterir. Bu arada başka bir fotoğrafa geçildiyse eskisinin kopyası gösterilmez.
Future<void> bulanikKopyaHazirla(String anahtar, ImageProvider resim, ImageConfiguration ayar) async {
  if (_istenen == anahtar) return;
  _istenen = anahtar;
  // Çizim sırasında çağrılır: değişiklik bu kare bittikten sonra
  final kopya = _kopyalar[anahtar] ?? await _kopya(anahtar, resim, ayar);
  await Future<void>.value();
  if (kopya == null || _istenen != anahtar) return;
  _kullanildi(anahtar);
  kBulanikArka.value = kopya;
}

/// Kopyayı önceden hazırlar (gösterilmeden): sekmelerin fotoğrafları için, geçiş anında iş kalmasın.
Future<void> bulanikKopyaOnceden(String anahtar, ImageProvider resim, ImageConfiguration ayar) async {
  if (_kopyalar.containsKey(anahtar)) return;
  await _kopya(anahtar, resim, ayar);
}

Future<BulanikArka?> _kopya(String anahtar, ImageProvider resim, ImageConfiguration ayar) =>
    _hazirlaniyor[anahtar] ??= _hazirla(anahtar, resim, ayar).whenComplete(() => _hazirlaniyor.remove(anahtar));

Future<BulanikArka?> _hazirla(String anahtar, ImageProvider resim, ImageConfiguration ayar) async {
  final kaynak = await _coz(resim, ayar);
  if (kaynak == null) return null;
  try {
    final kopya = BulanikArka(anahtar, await _bulaniklastir(kaynak), Size(kaynak.width.toDouble(), kaynak.height.toDouble()));
    _kopyalar[anahtar] = kopya;
    _kullanildi(anahtar);
    return kopya;
  } finally {
    kaynak.dispose();
  }
}

/// En son kullanılanı sona alır; fazlası (gösterilmeyenlerden en eskisi) bırakılır.
void _kullanildi(String anahtar) {
  final k = _kopyalar.remove(anahtar);
  if (k != null) _kopyalar[anahtar] = k;
  while (_kopyalar.length > _enCokKopya) {
    final eski = _kopyalar.keys.firstWhere((x) => x != kBulanikArka.value?.anahtar && x != _istenen, orElse: () => '');
    if (eski.isEmpty) break;
    final atilan = _kopyalar.remove(eski)!;
    // Bu karede hâlâ çiziliyor olabilir: bir sonraki kareden sonra bırakılır
    WidgetsBinding.instance.addPostFrameCallback((_) => atilan.resim.dispose());
  }
}

Future<ui.Image?> _coz(ImageProvider resim, ImageConfiguration ayar) {
  final bitti = Completer<ui.Image?>();
  final akis = resim.resolve(ayar);
  late final ImageStreamListener dinleyici;
  dinleyici = ImageStreamListener((bilgi, _) {
    if (!bitti.isCompleted) bitti.complete(bilgi.image.clone());
    bilgi.dispose();
    akis.removeListener(dinleyici);
  }, onError: (_, __) {
    if (!bitti.isCompleted) bitti.complete(null);
    akis.removeListener(dinleyici);
  });
  akis.addListener(dinleyici);
  return bitti.future;
}

Future<ui.Image> _bulaniklastir(ui.Image kaynak) async {
  final oran = _kopyaGenisligi / kaynak.width;
  final w = math.max(1, (kaynak.width * oran).round());
  final h = math.max(1, (kaynak.height * oran).round());
  final kayit = ui.PictureRecorder();
  final tuval = Canvas(kayit);
  final boya = Paint()
    ..filterQuality = FilterQuality.medium
    ..imageFilter = ui.ImageFilter.blur(sigmaX: _kopyaBulanikligi, sigmaY: _kopyaBulanikligi, tileMode: TileMode.clamp);
  tuval.drawImageRect(
    kaynak,
    Rect.fromLTWH(0, 0, kaynak.width.toDouble(), kaynak.height.toDouble()),
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    boya,
  );
  final resim = kayit.endRecording();
  try {
    return await resim.toImage(w, h);
  } finally {
    resim.dispose();
  }
}

/// Bulunduğu alana arka planın bulanık kopyasını çizer: ekranda tam altındaki yeri, köşeleri
/// yuvarlak ve kenarları [yumusaklik] kadar yumuşakça kaybolarak. Kopya hazır değilse hiçbir şey
/// çizmez.
class BulanikZemin extends StatelessWidget {
  const BulanikZemin({super.key, this.yaricap = 18, this.yumusaklik = 6});

  final double yaricap;
  final double yumusaklik;

  @override
  Widget build(BuildContext context) {
    final ekran = MediaQuery.sizeOf(context);
    return ValueListenableBuilder<BulanikArka?>(
      valueListenable: kBulanikArka,
      builder: (context, kopya, _) => _BulanikBoya(kopya: kopya, ekran: ekran, yaricap: yaricap, yumusaklik: yumusaklik),
    );
  }
}

class _BulanikBoya extends LeafRenderObjectWidget {
  const _BulanikBoya({required this.kopya, required this.ekran, required this.yaricap, required this.yumusaklik});

  final BulanikArka? kopya;
  final Size ekran;
  final double yaricap;
  final double yumusaklik;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBulanik(kopya: kopya, ekran: ekran, yaricap: yaricap, yumusaklik: yumusaklik);

  @override
  void updateRenderObject(BuildContext context, _RenderBulanik renderObject) {
    renderObject
      ..kopya = kopya
      ..ekran = ekran
      ..yaricap = yaricap
      ..yumusaklik = yumusaklik;
  }
}

class _RenderBulanik extends RenderBox {
  _RenderBulanik({required BulanikArka? kopya, required Size ekran, required double yaricap, required double yumusaklik})
      : _kopya = kopya,
        _ekran = ekran,
        _yaricap = yaricap,
        _yumusaklik = yumusaklik;

  BulanikArka? _kopya;
  set kopya(BulanikArka? v) {
    if (identical(v, _kopya)) return;
    _kopya = v;
    markNeedsPaint();
  }

  Size _ekran;
  set ekran(Size v) {
    if (v == _ekran) return;
    _ekran = v;
    markNeedsPaint();
  }

  double _yaricap;
  set yaricap(double v) {
    if (v == _yaricap) return;
    _yaricap = v;
    markNeedsPaint();
  }

  double _yumusaklik;
  set yumusaklik(double v) {
    if (v == _yumusaklik) return;
    _yumusaklik = v;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final k = _kopya;
    if (k == null || size.isEmpty || _ekran.isEmpty) return;
    // Arka plan fotoğrafı ekranı kaplar (BoxFit.cover, kPhotoAlignment): fotoğrafın hangi parçası
    // ekranın neresine düşüyor
    final yerlesim = applyBoxFit(BoxFit.cover, k.kaynak, _ekran);
    final hedef = kPhotoAlignment.inscribe(yerlesim.destination, Offset.zero & _ekran);
    final parca = kPhotoAlignment.inscribe(yerlesim.source, Offset.zero & k.kaynak);
    if (parca.width <= 0 || parca.height <= 0) return;
    final olcek = hedef.width / parca.width;
    final kx = k.kaynak.width / k.resim.width;
    final ky = k.kaynak.height / k.resim.height;
    // Bu alanın ekrandaki yeri: kopya, ekrandaki fotoğrafla tam üst üste gelsin
    final ekranda = localToGlobal(Offset.zero);
    final tx = offset.dx - ekranda.dx + hedef.left - parca.left * olcek;
    final ty = offset.dy - ekranda.dy + hedef.top - parca.top * olcek;
    final m = Float64List(16)
      ..[0] = olcek * kx
      ..[5] = olcek * ky
      ..[10] = 1
      ..[12] = tx
      ..[13] = ty
      ..[15] = 1;
    final boya = Paint()
      ..shader = ImageShader(k.resim, TileMode.clamp, TileMode.clamp, m, filterQuality: FilterQuality.low)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, _yumusaklik);
    final alan = (offset & size).deflate(math.min(_yumusaklik, size.shortestSide / 4));
    context.canvas.drawRRect(RRect.fromRectAndRadius(alan, Radius.circular(_yaricap)), boya);
  }
}
