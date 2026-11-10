// Mel Capital — sahneler: okunabilirlik için dört sayfa düzeni (dikdörtgen + buğulu cam yerine).
//
//   dergi  Solda düz koyu bir sayfa, fotoğraf sağda bütün (telefonda fotoğraf üstte, sayfa altta).
//   kemer  Paneller fotoğrafın önünde kemer biçimli, düz koyu pencereler.
//   sakin  Kutu yok; yazılar fotoğrafın üstünde, yalnızca tam arkalarında yumuşak kenarlı hafif
//          bulanıklık ([Hale]).
//   sayfa  Fotoğraf üstte; sayfa alttan açılan düz koyu bir yaprakta.
//   pencere Açılır pencereler, düzenleme panelleri ve ipuçları: düz koyu zemin, ince altın kenar.
//
// Her sekme bir sahnede açılır ([kSekmeSahnesi]). Paneller (GlassPanel, Kpi) bulundukları sahneye
// göre çizilir: dergi ve sayfada düz bölüm (ince altın çizgi), kemerde kemer pencere, sakinde kutu
// yok, yalnızca arkasında yumuşak kenarlı güçlü bulanıklık ve koyu ton ([HaleZemini]; koyuluğu
// Ayarlar'dan seçilir: [YaziArkasi]).
//
// Melih'in kararı (06.11.2026): siyah sayfalar kalktı; bütün sekmeler ve giriş ekranları "sakin"
// (Özet gibi, fotoğraf görünür). Açılır pencereler "pencere" kalır. Dergi, kemer ve sayfa
// kodda duruyor; istenirse yeniden kullanılabilir.

import 'package:flutter/material.dart';

import 'background.dart' show PhotoBar;
import 'bulanik.dart';
import 'performans.dart';
import 'state.dart';
import 'theme.dart' show kNetYaziGolgesi;
import 'ui.dart' show isPhoneLayout;

enum Sahne { dergi, kemer, sakin, sayfa, pencere }

/// Hangi sekme hangi sahnede.
const Map<AppTab, Sahne> kSekmeSahnesi = {
  AppTab.ozet: Sahne.sakin,
  AppTab.bankalar: Sahne.sakin,
  AppTab.harcamalar: Sahne.sakin,
  AppTab.plan: Sahne.sakin,
  AppTab.borclar: Sahne.sakin,
  AppTab.alisveris: Sahne.sakin,
  AppTab.ayarlar: Sahne.sakin,
};

/// Düz sayfanın rengi (espresso).
const Color kSahneZemin = Color(0xFF15110D);

/// Açılır pencerenin rengi (sayfadan bir ton açık, karartılmış ekranın üstünde ayrılsın).
const Color kPencereZemin = Color(0xFF1B1612);

/// Kemer pencerenin rengi ve çizgisi.
const Color kKemerZemin = Color(0xEB16110D);
const Color kAltinCizgi = Color(0x8CE3BF7C);

/// Düz bölümlerin üstündeki ince altın çizgi.
const Color kBolumCizgi = Color(0x59E3BF7C);

/// Sahnenin altındaki widget'lara hangi sahnede olduklarını söyler.
class SahneScope extends InheritedWidget {
  const SahneScope({super.key, required this.sahne, required super.child});

  final Sahne sahne;

  static Sahne? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SahneScope>()?.sahne;

  @override
  bool updateShouldNotify(SahneScope oldWidget) => oldWidget.sahne != sahne;
}

/// Sekmeler dışındaki ekranların sahnesi.
const Sahne kTanitimSahnesi = Sahne.sakin;
const Sahne kKarsilamaSahnesi = Sahne.sakin;
const Sahne kKurulumSahnesi = Sahne.sakin;
const Sahne kOnarimSahnesi = Sahne.sakin;

/// Telefonda Özet'te fotoğrafçının adı sayfanın en altında, içerikle birlikte akar (büyük rakamların
/// üstüne binmesin). Diğer sayfalarda alt menünün üstünde durur.
bool fotoBilgisiSayfada(Sahne? sahne, bool phone, {bool ozet = false}) => phone && ozet && sahne == Sahne.sakin;

/// Dergi sahnesinde (bilgisayar) soldaki sayfanın genişliği.
double dergiGenisligi(double ekran) => (ekran * 0.5).clamp(600.0, 820.0).toDouble();

/// Fotoğrafın üstte göründüğü sahnelerde (sayfa; telefonda dergi) fotoğraf penceresinin yüksekliği.
double fotoPenceresi(Size ekran, bool phone) => phone ? 150 : (ekran.height * 0.24).clamp(140.0, 260.0).toDouble();

/// Fotoğraf bu sahnede üstte mi (fotoğrafçının adı da oraya konur)?
bool fotoUstte(Sahne? sahne, bool phone) => sahne == Sahne.sayfa || (phone && sahne == Sahne.dergi);

/// Arka plan katmanı: dergi sahnesinde (bilgisayar) soldaki düz sayfa. Fotoğrafın hemen üstüne konur.
class SahneZemini extends StatelessWidget {
  const SahneZemini({super.key, required this.sahne});

  final Sahne? sahne;

  @override
  Widget build(BuildContext context) {
    if (sahne != Sahne.dergi || isPhoneLayout(context)) return const SizedBox.shrink();
    final w = dergiGenisligi(MediaQuery.sizeOf(context).width);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: w, height: double.infinity, child: const ColoredBox(color: kSahneZemin)),
    );
  }
}

/// Sayfanın sahnesine göre yerleşimi.
class SahneDuzeni extends StatelessWidget {
  const SahneDuzeni({super.key, required this.sahne, required this.child});

  final Sahne sahne;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneLayout(context);
    final scoped = SahneScope(sahne: sahne, child: child);
    if (fotoUstte(sahne, phone)) {
      final h = fotoPenceresi(MediaQuery.sizeOf(context), phone);
      return Column(children: [
        SizedBox(
          height: h,
          child: Align(
            alignment: phone ? Alignment.bottomLeft : Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(phone ? 8 : 0, 0, phone ? 0 : 10, 10),
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: phone ? 300 : 360), child: const PhotoBar()),
            ),
          ),
        ),
        Expanded(child: sahne == Sahne.sayfa ? _Yaprak(phone: phone, child: scoped) : ColoredBox(color: kSahneZemin, child: scoped)),
      ]);
    }
    if (sahne == Sahne.dergi) {
      // Sayfa kendi genişliğini ekranın genişliği sanmasın (geniş ekran düzenine geçip taşmasın)
      final mq = MediaQuery.of(context);
      final w = dergiGenisligi(mq.size.width);
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: w,
          child: MediaQuery(data: mq.copyWith(size: Size(w, mq.size.height)), child: scoped),
        ),
      );
    }
    return scoped;
  }
}

/// Alttan açılan yaprak: üst köşeleri yuvarlak, üstünde ince altın çizgi ve tutamak.
class _Yaprak extends StatelessWidget {
  const _Yaprak({required this.phone, required this.child});

  final bool phone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(phone ? 32 : 40);
    return CustomPaint(
      foregroundPainter: _YaprakCizgisi(r.x),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: r),
        child: ColoredBox(
          color: kSahneZemin,
          child: Stack(children: [
            Padding(padding: const EdgeInsets.only(top: 22), child: child),
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _YaprakCizgisi extends CustomPainter {
  const _YaprakCizgisi(this.r);

  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r));
    canvas.drawPath(
      p.shift(const Offset(0, 0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x80E3BF7C),
    );
  }

  @override
  bool shouldRepaint(_YaprakCizgisi oldDelegate) => oldDelegate.r != r;
}

/// Kemer: üst kenarı elips yayı olan pencere biçimi (yayın yüksekliği [kemer]).
class KemerBorder extends ShapeBorder {
  const KemerBorder({this.kemer = 40, this.side = BorderSide.none});

  final double kemer;
  final BorderSide side;

  double _h(Rect r) => kemer.clamp(0.0, r.height / 2).clamp(0.0, r.width * 0.18).toDouble();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final h = _h(rect);
    return Path()
      ..moveTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top + h)
      ..arcTo(Rect.fromLTWH(rect.left, rect.top, rect.width, h * 2), 3.141592653589793, 3.141592653589793, false)
      ..lineTo(rect.right, rect.bottom)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final h = _h(rect);
    final r = rect.deflate(side.width / 2);
    // Alt kenar çizilmez: kemer zemine oturur
    final p = Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, r.top + h)
      ..arcTo(Rect.fromLTWH(r.left, r.top, r.width, h * 2), 3.141592653589793, 3.141592653589793, false)
      ..lineTo(r.right, r.bottom);
    canvas.drawPath(p, side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => KemerBorder(kemer: kemer * t, side: side.scale(t));
}

/// Yazıların arkasının koyuluğu (Ayarlar → Dil ve görünüm; varsayılan orta).
enum YaziArkasi { hafif, orta, koyu }

YaziArkasi yaziArkasiOku(Object? v) => switch (v) {
      'hafif' => YaziArkasi.hafif,
      'koyu' => YaziArkasi.koyu,
      _ => YaziArkasi.orta,
    };

/// Koyu tonun gücü (0–1): hafifte fotoğrafın renkleri belirgin, koyuda neredeyse düz koyu.
double yaziArkasiTonu(YaziArkasi a) => switch (a) {
      YaziArkasi.hafif => 0.34,
      YaziArkasi.orta => 0.54,
      YaziArkasi.koyu => 0.78,
    };

/// Hale: yazının tam arkasında, kenarları yumuşakça kaybolan bulanıklık ve koyu ton.
/// Yazının çevresine kutu konmaz; yalnızca fotoğrafın üstündeki yazı okunsun diye.
class Hale extends StatelessWidget {
  const Hale({super.key, required this.child, this.yatay = 14, this.dikey = 8});

  /// Sakin sahnedeyse [Hale] ile sarar, değilse olduğu gibi bırakır.
  static Widget sakinde(BuildContext context, Widget child, {double yatay = 14, double dikey = 8}) =>
      SahneScope.of(context) == Sahne.sakin ? Hale(yatay: yatay, dikey: dikey, child: child) : child;

  final Widget child;
  final double yatay;
  final double dikey;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        left: -yatay,
        right: -yatay,
        top: -dikey,
        bottom: -dikey,
        child: const IgnorePointer(child: _HaleArka()),
      ),
      child,
    ]);
  }
}

/// Yazı arkasının çizimi: fotoğrafın (önceden hazırlanmış) bulanık kopyası ve üstünde koyu ton,
/// kenarları yumuşak ([BulanikZemin]). Koyuluk Ayarlar'daki "Yazıların arkası" seçimine, bulanık
/// kopyanın çizilip çizilmeyeceği görsel kaliteye bağlıdır. Burada bulanıklık hesaplanmaz.
class _HaleArka extends StatelessWidget {
  const _HaleArka({this.genis = false});

  /// Bölüm (panel) için: kenar yumuşaması daha geniş.
  final bool genis;

  @override
  Widget build(BuildContext context) {
    final ton = yaziArkasiTonu(yaziArkasiOku(AppScope.of(context).settings['yaziArkasi']));
    return BulanikZemin(
      yaricap: genis ? 24 : 14,
      yumusaklik: genis ? 16 : 9,
      ton: ton,
      resimli: KaliteScope.of(context) == GorselKalite.yuksek,
    );
  }
}

/// Sakin sahnede bölüm (panel) zemini: kutu ya da kenar çizgisi yok; içeriğin arkasında kenarları
/// yumuşakça kaybolan güçlü bulanıklık ve koyu ton. Fotoğraf bölümlerin arasında net görünür.
/// Yazılara bulanık gölge konmaz (her biri her karede ayrı bir bulanıklık işidir); okunabilirliği
/// arkası sağlar. Yalnızca "hafif" koyulukta yazılara bulanık olmayan ince bir gölge eklenir.
class HaleZemini extends StatelessWidget {
  const HaleZemini({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hafif = yaziArkasiOku(AppScope.of(context).settings['yaziArkasi']) == YaziArkasi.hafif;
    return Stack(clipBehavior: Clip.none, children: [
      const Positioned(
        left: -12,
        right: -12,
        top: -10,
        bottom: -10,
        child: IgnorePointer(child: _HaleArka(genis: true)),
      ),
      hafif ? DefaultTextStyle.merge(style: const TextStyle(shadows: kNetYaziGolgesi), child: child) : child,
    ]);
  }
}
