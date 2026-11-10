// Mel Capital — bulanık kopya: yazıların arkasındaki bulanıklık için arka plan fotoğrafının küçük,
// bulanık bir kopyası.
//
// Kural (Performans Motoru bütçesi): sayfalarda her karede bulanıklık HESAPLANMAZ. Canlı bulanıklık
// (BackdropFilter), bulanık yazı gölgesi ve kenar yumuşatmak için MaskFilter kullanılmaz; hepsi
// her karede ekran kartına ayrı bir bulanıklık işi çıkarır ve Windows'ta uygulamayı takar
// (07.11.2026 ölçümü: çizim ortalama 23 ms). Bunun yerine:
//   - fotoğraf değişince bulanık kopya bir kez hazırlanır ([bulanikKopyaHazirla]) ve saklanır;
//   - bölümler arkalarına kopyanın ekranda kendilerine denk gelen yerini çizer ([BulanikZemin]);
//   - yumuşak kenar, köşe noktalarının görünürlüğüyle çizilen bir kafestir ([yumusakKafes]).

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

/// Kopyanın genişliği (piksel) ve bu genişlikteki bulanıklık. Ekranda kabaca 20–25 noktalık
/// güçlü bir bulanıklık eder: fotoğrafın ayrıntısı yazıyla yarışmaz, yalnızca renkleri kalır.
const double _kopyaGenisligi = 320;
const double _kopyaBulanikligi = 4.0;

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

/// Yumuşak kenarlı yuvarlak dikdörtgenin kafesi: köşe noktaları (x, y çiftleri), her noktanın
/// görünürlüğü (0: dış kenar, 1: iç) ve üçgenler. Kenar [yumusaklik] kadar içeride tam görünür
/// olur; arada yumuşak geçer (smoothstep). Bulanıklık hesaplanmaz: ekran kartı yalnızca birkaç yüz
/// üçgen çizer.
({Float32List konumlar, Float32List alfalar, Uint16List ucgenler}) yumusakKafes(Size boyut, double yaricap, double yumusaklik, {int kose = 6}) {
  final f = math.max(0.0, math.min(yumusaklik, boyut.shortestSide / 2 - 0.5));
  // Dıştan içe halkalar (kenar yumuşaması yoksa tek halka)
  final adimlar = f <= 0 ? const [1.0] : const [0.0, 0.25, 0.5, 0.75, 1.0];
  final m = 4 * (kose + 1); // bir halkadaki nokta sayısı
  final n = adimlar.length * m + 1;
  final konum = Float32List(n * 2);
  final alfa = Float32List(n);
  // Köşeler saat yönünde: sol üst, sağ üst, sağ alt, sol alt (y aşağı doğru artar)
  const bas = [math.pi, 1.5 * math.pi, 0.0, 0.5 * math.pi];
  for (var h = 0; h < adimlar.length; h++) {
    final t = adimlar[h];
    final d = f * t;
    final w = boyut.width - 2 * d, hh = boyut.height - 2 * d;
    final rad = math.max(0.0, math.min(yaricap + f - d, math.min(w, hh) / 2));
    final a = f <= 0 ? 1.0 : t * t * (3 - 2 * t);
    final mx = [d + rad, d + w - rad, d + w - rad, d + rad];
    final my = [d + rad, d + rad, d + hh - rad, d + hh - rad];
    for (var c = 0; c < 4; c++) {
      for (var s = 0; s <= kose; s++) {
        final aci = bas[c] + (math.pi / 2) * s / kose;
        final i = h * m + c * (kose + 1) + s;
        konum[i * 2] = mx[c] + rad * math.cos(aci);
        konum[i * 2 + 1] = my[c] + rad * math.sin(aci);
        alfa[i] = a;
      }
    }
  }
  final orta = n - 1;
  konum[orta * 2] = boyut.width / 2;
  konum[orta * 2 + 1] = boyut.height / 2;
  alfa[orta] = 1;
  final ucgen = <int>[];
  // Halkalar arası şeritler
  for (var h = 0; h + 1 < adimlar.length; h++) {
    for (var i = 0; i < m; i++) {
      final a0 = h * m + i, a1 = h * m + (i + 1) % m, b0 = a0 + m, b1 = a1 + m;
      ucgen
        ..addAll([a0, a1, b0])
        ..addAll([a1, b1, b0]);
    }
  }
  // En içteki halkadan ortaya yelpaze
  final ic = (adimlar.length - 1) * m;
  for (var i = 0; i < m; i++) {
    ucgen.addAll([ic + i, ic + (i + 1) % m, orta]);
  }
  return (konumlar: konum, alfalar: alfa, ucgenler: Uint16List.fromList(ucgen));
}

/// Yazıların arkası: bulunduğu alana arka planın bulanık kopyasını (ekranda tam altındaki yeri) ve
/// üstüne koyu tonu çizer; köşeleri yuvarlak, kenarları [yumusaklik] kadar yumuşakça kaybolur.
///
/// Hiç bulanıklık hesaplanmaz: kopya önceden hazırdır, yumuşak kenar köşe noktalarının
/// görünürlüğüyle (drawVertices) çizilir. Kopya hazır değilse ya da [resimli] değilse (görsel kalite
/// "hafif") yalnızca koyu ton çizilir.
class BulanikZemin extends StatelessWidget {
  const BulanikZemin({super.key, this.yaricap = 18, this.yumusaklik = 10, this.ton = 0.5, this.resimli = true});

  final double yaricap;
  final double yumusaklik;

  /// Koyu tonun gücü (0: yok, 1: düz koyu).
  final double ton;
  final bool resimli;

  @override
  Widget build(BuildContext context) {
    final ekran = MediaQuery.sizeOf(context);
    return ValueListenableBuilder<BulanikArka?>(
      valueListenable: kBulanikArka,
      builder: (context, kopya, _) =>
          _BulanikBoya(kopya: resimli ? kopya : null, ekran: ekran, yaricap: yaricap, yumusaklik: yumusaklik, ton: ton),
    );
  }
}

class _BulanikBoya extends LeafRenderObjectWidget {
  const _BulanikBoya({required this.kopya, required this.ekran, required this.yaricap, required this.yumusaklik, required this.ton});

  final BulanikArka? kopya;
  final Size ekran;
  final double yaricap;
  final double yumusaklik;
  final double ton;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBulanik(kopya: kopya, ekran: ekran, yaricap: yaricap, yumusaklik: yumusaklik, ton: ton);

  @override
  void updateRenderObject(BuildContext context, _RenderBulanik renderObject) {
    renderObject
      ..kopya = kopya
      ..ekran = ekran
      ..yaricap = yaricap
      ..yumusaklik = yumusaklik
      ..ton = ton;
  }
}

/// Koyu tonun rengi (espresso siyahı).
const int _tonRengi = 0x0C0A08;

class _RenderBulanik extends RenderBox {
  _RenderBulanik({required BulanikArka? kopya, required Size ekran, required double yaricap, required double yumusaklik, required double ton})
      : _kopya = kopya,
        _ekran = ekran,
        _yaricap = yaricap,
        _yumusaklik = yumusaklik,
        _ton = ton;

  BulanikArka? _kopya;
  set kopya(BulanikArka? v) {
    if (identical(v, _kopya)) return;
    _kopya = v;
    _resimBoyasi = null;
    _resimKafesiniBirak();
    markNeedsPaint();
  }

  Size _ekran;
  set ekran(Size v) {
    if (v == _ekran) return;
    _ekran = v;
    _resimKafesiniBirak();
    markNeedsPaint();
  }

  double _yaricap;
  set yaricap(double v) {
    if (v == _yaricap) return;
    _yaricap = v;
    _kafesiBirak();
    markNeedsPaint();
  }

  double _yumusaklik;
  set yumusaklik(double v) {
    if (v == _yumusaklik) return;
    _yumusaklik = v;
    _kafesiBirak();
    markNeedsPaint();
  }

  double _ton;
  set ton(double v) {
    if (v == _ton) return;
    _ton = v;
    _tonKafesi?.dispose();
    _tonKafesi = null;
    markNeedsPaint();
  }

  // Kafes boyuta bağlıdır; koyu tonun kafesi boyut değişmedikçe, fotoğrafın kafesi alan ekranda
  // yer değiştirmedikçe (kaydırma) yeniden kurulmaz.
  ({Float32List konumlar, Float32List alfalar, Uint16List ucgenler})? _kafes;
  Size? _kafesBoyutu;
  ui.Vertices? _tonKafesi;
  ui.Vertices? _resimKafesi;
  Offset? _resimYeri;
  Paint? _resimBoyasi;
  final Paint _beyaz = Paint()..color = const Color(0xFFFFFFFF);

  void _kafesiBirak() {
    _kafes = null;
    _tonKafesi?.dispose();
    _tonKafesi = null;
    _resimKafesiniBirak();
  }

  void _resimKafesiniBirak() {
    _resimKafesi?.dispose();
    _resimKafesi = null;
    _resimYeri = null;
  }

  @override
  void dispose() {
    _kafesiBirak();
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// Fotoğrafın kafesi: her köşe noktası, bulanık kopyada ekranda tam altına düşen noktayı gösterir.
  ui.Vertices? _resimKafesiKur(BulanikArka k, Offset ekranda) {
    if (_resimKafesi != null && _resimYeri == ekranda) return _resimKafesi;
    _resimKafesiniBirak();
    // Arka plan fotoğrafı ekranı kaplar (BoxFit.cover, kPhotoAlignment): fotoğrafın hangi parçası
    // ekranın neresine düşüyor
    final yerlesim = applyBoxFit(BoxFit.cover, k.kaynak, _ekran);
    final hedef = kPhotoAlignment.inscribe(yerlesim.destination, Offset.zero & _ekran);
    final parca = kPhotoAlignment.inscribe(yerlesim.source, Offset.zero & k.kaynak);
    if (parca.width <= 0 || parca.height <= 0 || hedef.width <= 0) return null;
    final olcek = hedef.width / parca.width; // fotoğraf pikseli → ekran noktası
    final kx = k.resim.width / k.kaynak.width, ky = k.resim.height / k.kaynak.height; // fotoğraf → kopya
    final kafes = _kafes!;
    final n = kafes.alfalar.length;
    final doku = Float32List(n * 2);
    final renk = Int32List(n);
    for (var i = 0; i < n; i++) {
      final gx = ekranda.dx + kafes.konumlar[i * 2], gy = ekranda.dy + kafes.konumlar[i * 2 + 1];
      doku[i * 2] = ((gx - hedef.left) / olcek + parca.left) * kx;
      doku[i * 2 + 1] = ((gy - hedef.top) / olcek + parca.top) * ky;
      renk[i] = ((kafes.alfalar[i] * 255).round() << 24) | 0xFFFFFF;
    }
    _resimYeri = ekranda;
    return _resimKafesi = ui.Vertices.raw(ui.VertexMode.triangles, kafes.konumlar, textureCoordinates: doku, colors: renk, indices: kafes.ucgenler);
  }

  ui.Vertices _tonKafesiKur() {
    final hazir = _tonKafesi;
    if (hazir != null) return hazir;
    final kafes = _kafes!;
    final n = kafes.alfalar.length;
    final renk = Int32List(n);
    for (var i = 0; i < n; i++) {
      renk[i] = ((kafes.alfalar[i] * _ton.clamp(0.0, 1.0) * 255).round() << 24) | _tonRengi;
    }
    return _tonKafesi = ui.Vertices.raw(ui.VertexMode.triangles, kafes.konumlar, colors: renk, indices: kafes.ucgenler);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    if (_kafes == null || _kafesBoyutu != size) {
      _kafesiBirak();
      _kafes = yumusakKafes(size, _yaricap, _yumusaklik);
      _kafesBoyutu = size;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final k = _kopya;
    if (k != null && !_ekran.isEmpty) {
      final kafes = _resimKafesiKur(k, localToGlobal(Offset.zero));
      if (kafes != null) {
        final boya = _resimBoyasi ??= Paint()
          ..shader = ImageShader(k.resim, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage, filterQuality: FilterQuality.low);
        // Kaynak: fotoğraf, hedef: köşe noktasının rengi → fotoğraf × noktanın görünürlüğü
        canvas.drawVertices(kafes, BlendMode.srcIn, boya);
      }
    }
    if (_ton > 0) canvas.drawVertices(_tonKafesiKur(), BlendMode.modulate, _beyaz);
    canvas.restore();
  }
}
