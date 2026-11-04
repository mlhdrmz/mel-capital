// Logolar, eski uygulamadaki görünümüyle: beyaz plakada bankanın kendi logosu, alışveriş sitelerinin
// logoları ve abonelik/şirket logoları (Simple Icons simgeleri, marka renginde kısaltmalar, fatura türü
// simgeleri). Logosu olmayan alacaklılar (KYK, kişiler) altın zeminde kısaltmayla görünür.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../core/brands.dart';
import '../core/constants.dart';
import '../core/util.dart';
import 'theme.dart';

/// Logo dosyalarının en/boy oranı (assets/logos, assets/shops): plaka genişliği resim yüklenmeden
/// doğru çıksın, satırlar kaymasın.
const Map<String, double> kBankLogoAspect = {
  'akbank': 250 / 28,
  'denizbank': 250 / 56,
  'enpara': 287 / 96,
  'fibabanka': 300 / 64,
  'findeks': 461 / 96,
  'garanti': 330 / 61,
  'halkbank': 501 / 96,
  'isbank': 305 / 96,
  'odeabank': 354 / 66,
  'papara': 397 / 96,
  'qnb': 329 / 96,
  'teb': 221 / 96,
  'vakifbank': 793 / 96,
  'yapikredi': 551 / 96,
  'ziraat': 454 / 96,
};

const Map<String, double> kShopLogoAspect = {
  'amazon': 238 / 72,
  'hepsiburada': 260 / 44,
  'idefix': 135 / 72,
  'n11': 218 / 72,
  'pttavm': 260 / 66,
  'trendyol': 213 / 72,
};

/// Beyaz plakada logo (eski uygulamadaki .plate): [height] yüksekliğinde, logo en çok [maxLogoWidth]
/// genişlikte (uzun logolar bu genişliğe sığacak kadar küçülür).
class LogoPlate extends StatelessWidget {
  const LogoPlate({super.key, required this.asset, required this.aspect, this.height = 28, this.maxLogoWidth, this.shadow = true, this.label});

  final String asset;
  final double aspect;
  final double height;
  final double? maxLogoWidth;
  final bool shadow;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final padV = height / 7;
    final padH = height / 4;
    final imgH = height - 2 * padV;
    final imgW = math.min(imgH * aspect, maxLogoWidth ?? height * 3.1);
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height * 0.28),
        boxShadow: shadow ? const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))] : null,
      ),
      child: Image.asset(
        asset,
        width: imgW,
        height: imgH,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: label,
        excludeFromSemantics: label == null,
      ),
    );
  }
}

/// Banka logosu: beyaz plakada bankanın kendi logosu. Logosu olmayan alacaklılar (KYK, kişiler) altın
/// zeminde kısaltmayla, nakit yeşil para simgesiyle gösterilir. [size] plakanın yüksekliğidir.
class BankPlate extends StatelessWidget {
  const BankPlate({super.key, this.bankKey, this.name, this.size = 28, this.icon, this.shadow = true, this.maxLogoWidth});

  final String? bankKey;
  final String? name;
  final double size;
  final IconData? icon;
  final bool shadow;
  final double? maxLogoWidth;

  @override
  Widget build(BuildContext context) {
    final key = bankKey;
    final aspect = key == null ? null : kBankLogoAspect[key];
    if (icon == null && key != null && aspect != null) {
      return LogoPlate(asset: 'assets/logos/$key.webp', aspect: aspect, height: size, maxLogoWidth: maxLogoWidth, shadow: shadow, label: kBanks[key]?.name);
    }
    final cash = icon == Icons.payments_outlined;
    final radius = BorderRadius.circular(size * 0.28);
    if (icon != null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: cash ? MC.mint.withValues(alpha: 0.16) : MC.gold2, borderRadius: radius),
        child: Icon(icon, size: size * 0.52, color: cash ? MC.mint : MC.ink),
      );
    }
    final fs = size * 0.39;
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      padding: EdgeInsets.symmetric(horizontal: size * 0.27),
      decoration: BoxDecoration(color: MC.gold2, borderRadius: radius),
      // Genişlik yazı kadar (geniş bir alanın ortasında da plaka gibi kalır)
      child: Center(
        widthFactor: 1,
        child: Text(bankMono(key, name), maxLines: 1, style: sans(fs, weight: FontWeight.w700, color: MC.ink, letterSpacing: fs * 0.05, height: 1)),
      ),
    );
  }
}

/// Logosu olmayan alacaklının kısaltması: tanımlı kısaltma (KYK) ya da adın ilk üç harfi.
String bankMono(String? bankKey, String? name) {
  final fixed = bankKey == null ? null : kBanks[bankKey]?.mono;
  if (fixed != null) return fixed;
  final letters = (name ?? bankKey ?? '?').replaceAll(RegExp(r'[^0-9A-Za-zÇĞİÖŞÜçğıöşü]'), '');
  if (letters.isEmpty) return '?';
  return trUpper(letters.substring(0, math.min(3, letters.length)));
}

/// Alışveriş sitesinin logosu, beyaz zeminin üstüne [maxWidth]×[maxHeight] kutuya sığacak kadar.
/// Logosu olmayan site için null.
Widget? shopLogo(String id, {required double maxWidth, required double maxHeight}) {
  final aspect = kShopLogoAspect[id];
  if (aspect == null) return null;
  var w = math.min(maxWidth, maxHeight * aspect);
  var h = w / aspect;
  if (h > maxHeight) {
    h = maxHeight;
    w = h * aspect;
  }
  return Image.asset('assets/shops/$id.webp', width: w, height: h, fit: BoxFit.contain, filterQuality: FilterQuality.medium, excludeFromSemantics: true);
}

/// Alışveriş sitesinin logosu beyaz plakada (ürün linkinin yanında).
Widget? shopPlate(String id, {double height = 22}) {
  final aspect = kShopLogoAspect[id];
  if (aspect == null) return null;
  return LogoPlate(asset: 'assets/shops/$id.webp', aspect: aspect, height: height);
}

/// Abonelik, fatura ya da şirket logosu (eski uygulamadaki .blogo): bilinen markalar kendi simgesiyle
/// ya da marka renginde kısaltmayla, faturalar türüne göre simgeyle, geri kalanlar baş harflerle.
class BrandMark extends StatelessWidget {
  const BrandMark(this.name, {super.key, this.size = 30, this.round = false, this.look});

  final String? name;
  final double size;
  final bool round;

  /// Önceden seçilmiş görünüm (ör. harcamanın yerine göre bulunan marka).
  final BrandLook? look;

  @override
  Widget build(BuildContext context) {
    final l = look ?? brandLook(name);
    Color bg;
    Widget child;
    switch (l) {
      case BrandSvg(:final path, bg: final b, :final fg):
        bg = Color(b);
        child = SvgIcon(path, color: Color(fg), size: size * 0.57);
      case BrandText(:final text, bg: final b, :final ink):
        bg = Color(b);
        child = _badgeText(text, Color(ink));
      case BrandGeneric(:final path, :final color):
        bg = Color(color).withValues(alpha: 0.16);
        child = SvgIcon(path, color: Color(color), size: size * 0.54, stroke: 1.7);
      case BrandInitials(:final text, bg: final b):
        bg = Color(b);
        child = _badgeText(text, Colors.white);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(round ? size / 2 : size * 0.3),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _badgeText(String text, Color ink) {
    final fs = size * 0.34;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size * 0.08),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, style: sans(fs, weight: FontWeight.w700, color: ink, letterSpacing: -0.01 * fs, height: 1)),
      ),
    );
  }
}

/// Harcama satırının başı: adı ya da yeri bilinen bir markaysa logosu, değilse null (kategori simgesi kalır).
BrandLook? spendBrand(String name, String place) => brandOf(name) ?? (place.isEmpty ? null : brandOf(place));

/// 24×24 alanda çizilmiş SVG yolu (Simple Icons dolgulu, eski uygulamanın simgeleri çizgili).
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.data, {super.key, required this.color, this.size = 24, this.stroke});

  final String data;
  final Color color;
  final double size;
  final double? stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SvgPainter(svgPath(data), color, stroke));
}

final Map<String, Path> _paths = {};

/// SVG yol verisinden Flutter yolu (her yol bir kez çözülür).
Path svgPath(String data) => _paths.putIfAbsent(data, () {
      final p = Path();
      writeSvgPathDataToPath(data, _PathSink(p));
      return p;
    });

class _PathSink extends PathProxy {
  _PathSink(this.p);

  final Path p;

  @override
  void moveTo(double x, double y) => p.moveTo(x, y);

  @override
  void lineTo(double x, double y) => p.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) => p.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => p.close();
}

class _SvgPainter extends CustomPainter {
  _SvgPainter(this.path, this.color, this.stroke);

  final Path path;
  final Color color;
  final double? stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (stroke != null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke!
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgPainter old) => old.path != path || old.color != color || old.stroke != stroke;
}
