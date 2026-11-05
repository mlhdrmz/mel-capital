import 'package:flutter/material.dart';

/// Mel Capital renkleri ve yazı tipleri.
class MC {
  MC._();

  static const Color bg = Color(0xFF0C0B0A);
  static const Color text = Color(0xFFF3ECE0);
  static const Color muted = Color(0xFFE6DDCF);
  static const Color dim = Color(0xFFCBC1B2);
  static const Color label = Color(0xFFEFE8DC);
  static const Color eyebrow = Color(0xFFFFE7B8);
  static const Color gold = Color(0xFFE3BF7C);
  static const Color gold2 = Color(0xFFD9AE68);
  static const Color ink = Color(0xFF1B1306);
  static const Color mint = Color(0xFF8FD9A6);
  static const Color rose = Color(0xFFEF968C);
  static const Color sky = Color(0xFF8FC3E6);
  static const Color violet = Color(0xFFB7A2F2);
  static const Color teal = Color(0xFF6FD3C6);
  static const Color danger = Color(0xFFC42B1C);

  static const String sans = 'Inter';
  static const String serif = 'Cormorant';

  /// Rakamlar: tutarlar ve büyük sayılar (kullanıcının seçimi: Manrope).
  static const String numbers = 'Manrope';
}

/// Fotoğraf üzerindeki yazıların okunması için hafif gölge.
const List<Shadow> kPhotoTextShadow = [
  Shadow(color: Color(0xF2000000), blurRadius: 2),
  Shadow(color: Color(0xE6000000), offset: Offset(0, 1), blurRadius: 3),
  Shadow(color: Color(0xBF000000), blurRadius: 16),
];

/// Büyük rakamlar için daha güçlü gölge (Özet).
const List<Shadow> kBigTextShadow = [
  Shadow(color: Color(0xE6000000), blurRadius: 3),
  Shadow(color: Color(0xCC000000), offset: Offset(0, 2), blurRadius: 6),
  Shadow(color: Color(0xB3000000), blurRadius: 30),
  Shadow(color: Color(0x73000000), blurRadius: 60),
];

TextStyle serif(double size,
        {Color color = MC.text,
        FontWeight weight = FontWeight.w600,
        List<Shadow>? shadows,
        double height = 1.05}) =>
    TextStyle(
      fontFamily: MC.serif,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      shadows: shadows,
    );

TextStyle sans(double size,
        {Color color = MC.text,
        FontWeight weight = FontWeight.w400,
        List<Shadow>? shadows,
        double? letterSpacing,
        double height = 1.35}) =>
    TextStyle(
      fontFamily: MC.sans,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      shadows: shadows,
      letterSpacing: letterSpacing,
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MC.gold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: MC.gold,
    onPrimary: MC.ink,
    surface: const Color(0xFF171513),
    onSurface: MC.text,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: MC.sans,
    scaffoldBackgroundColor: MC.bg,
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: Color(0xF0171513),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      textStyle: TextStyle(fontFamily: MC.sans, fontSize: 12, color: MC.text),
    ),
  );
}

/// Rakam yazısı: tutarlar ve büyük sayılar Manrope ile, eşit genişlikte rakamlarla. Başlık yazı tipiyle
/// (Cormorant) verilmiş büyük rakamlar biraz küçültülür: Manrope'un rakamları daha iri, yerleşim bozulmasın.
TextStyle numStyle(TextStyle base) {
  final fromSerif = base.fontFamily == MC.serif;
  final size = base.fontSize;
  return base.copyWith(
    fontFamily: MC.numbers,
    fontSize: fromSerif && size != null ? size * 0.9 : size,
    fontWeight: fromSerif ? FontWeight.w600 : base.fontWeight,
    letterSpacing: fromSerif && size != null ? -0.01 * size : base.letterSpacing,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
