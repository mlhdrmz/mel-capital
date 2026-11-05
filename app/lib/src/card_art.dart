// Kart görseli, eski Mel Capital'deki gibi: gerçek kartın kopyası değil, kartın kendi renkleri, deseni ve
// kenar şeridiyle hatırlatıcı bir çizim. Eski uygulamanın CSS desenleri (çizgi, dalga, nokta, halka, geometri,
// parıltı, konfeti), açısıyla birlikte aynen çizilir; üstte hafif bir parlama vardır.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// CSS'teki "linear-gradient(<açı>deg, …)" çizgisi: başlangıç noktası, yönü ve uzunluğu.
class CssLine {
  CssLine(Size size, double deg) {
    final a = deg * math.pi / 180;
    dir = Offset(math.sin(a), -math.cos(a));
    length = (size.width * math.sin(a)).abs() + (size.height * math.cos(a)).abs();
    start = size.center(Offset.zero) - dir * (length / 2);
  }

  late final Offset dir;
  late final double length;
  late final Offset start;

  Offset at(double fraction) => start + dir * (length * fraction);

  /// Çizgiye dik, [from]–[to] (0–1) arasındaki şerit (kutunun dışına taşar; kırpılarak çizilir).
  Path band(double from, double to, double reach) {
    final perp = Offset(-dir.dy, dir.dx) * reach;
    final a = at(from), b = at(to);
    return Path()
      ..moveTo((a - perp).dx, (a - perp).dy)
      ..lineTo((a + perp).dx, (a + perp).dy)
      ..lineTo((b + perp).dx, (b + perp).dy)
      ..lineTo((b - perp).dx, (b - perp).dy)
      ..close();
  }

  ui.Gradient gradient(List<Color> colors, List<double> stops) => ui.Gradient.linear(at(0), at(1), colors, stops);
}

/// Kartın zemini: iki renkli eğim (135°), desen ve soldaki renk şeridi.
class CardArtPainter extends CustomPainter {
  CardArtPainter({required this.c1, required this.c2, required this.pattern, required this.darkInk, this.accent, this.patternOn = true});

  final Color c1;
  final Color c2;
  final String pattern;

  /// Koyu yazılı kart (desenler siyahla çizilir).
  final bool darkInk;
  final Color? accent;

  /// Küçük kart örneğinde yalnızca zemin.
  final bool patternOn;

  Color _p(double alpha) => (darkInk ? Colors.black : Colors.white).withValues(alpha: alpha);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = CssLine(size, 135).gradient([c1, c2], const [0, 1]));
    if (patternOn) _pattern(canvas, size);
    final acc = accent;
    if (acc != null && patternOn) canvas.drawRect(Rect.fromLTWH(0, 0, 7, size.height), Paint()..color = acc);
  }

  void _pattern(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final reach = size.longestSide * 2;
    switch (pattern) {
      case 'lines':
        // repeating-linear-gradient(160deg, p .07 0 2px, transparent 2px 14px)
        final line = CssLine(size, 160);
        final paint = Paint()
          ..color = _p(0.07)
          ..strokeWidth = 2;
        final perp = Offset(-line.dir.dy, line.dir.dx) * reach;
        for (var t = 1.0; t < line.length; t += 14) {
          final o = line.start + line.dir * t;
          canvas.drawLine(o - perp, o + perp, paint);
        }
      case 'waves':
        // Sağ alttan üç yay (dıştan içe çizilir; içteki en belirgin)
        void oval(double cx, double cy, double rx, double ry, double a) =>
            canvas.drawOval(Rect.fromCenter(center: Offset(cx * w, cy * h), width: rx * w * 2, height: ry * h * 2), Paint()..color = _p(a));
        oval(1.05, 1.75, 1.3 * 0.70, 0.9 * 0.70, 0.07);
        oval(1.05, 1.50, 1.3 * 0.52, 0.9 * 0.52, 0.11);
        oval(1.05, 1.25, 1.3 * 0.34, 0.9 * 0.34, 0.16);
      case 'dots':
        // 11 piksellik nokta ızgarası, sol üstten sağ alta doğru belirginleşir
        final mask = CssLine(size, 120);
        for (var y = 5.5; y < h; y += 11) {
          for (var x = 5.5; x < w; x += 11) {
            final o = Offset(x, y);
            final f = ((o - mask.start).dx * mask.dir.dx + (o - mask.start).dy * mask.dir.dy) / mask.length;
            final m = ((f - 0.25) / 0.75).clamp(0.0, 1.0);
            if (m <= 0) continue;
            canvas.drawCircle(o, 1.4, Paint()..color = _p(0.18 * m));
          }
        }
      case 'rings':
        // Sağ üstte (88% 12%) 11 piksel aralıklı halkalar
        final c = Offset(w * 0.88, h * 0.12);
        final ring = Paint()
          ..color = _p(0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1;
        canvas.drawCircle(c, 0.8, Paint()..color = _p(0.1));
        for (var r = 11.5; r < size.longestSide * 1.2; r += 11) {
          canvas.drawCircle(c, r, ring);
        }
      case 'geo':
        canvas.drawPath(CssLine(size, 135).band(0.58, 0.66, reach), Paint()..color = _p(0.12));
        canvas.drawPath(CssLine(size, 45).band(0.72, 0.80, reach), Paint()..color = _p(0.09));
        canvas.drawPath(CssLine(size, 160).band(0.80, 1.2, reach), Paint()..color = _p(0.07));
      case 'glow':
        void glow(Offset at, double rx, double ry, Color color, double end) {
          canvas.save();
          canvas.translate(at.dx, at.dy);
          canvas.scale(rx, ry);
          canvas.drawRect(
            const Rect.fromLTRB(-1, -1, 1, 1),
            Paint()..shader = ui.Gradient.radial(Offset.zero, 1, [color, color.withValues(alpha: 0)], [0, end]),
          );
          canvas.restore();
        }

        glow(Offset.zero, 1.1 * w, 0.85 * h, Colors.white.withValues(alpha: 0.4), 0.55);
        glow(Offset(w, h), 0.9 * w, 0.7 * h, Colors.black.withValues(alpha: 0.14), 0.6);
      case 'confetti':
        // Sağ alt çeyrekte renkli şeritler
        final box = Rect.fromLTRB(w * 0.5, h * 0.48, w, h);
        canvas.save();
        canvas.clipRect(box);
        canvas.translate(box.left, box.top);
        final s = box.size;
        final r = s.longestSide * 2;
        canvas.drawPath(CssLine(s, 135).band(0.54, 0.61, r), Paint()..color = const Color(0xFFE3101C));
        canvas.drawPath(CssLine(s, 160).band(0.68, 0.74, r), Paint()..color = const Color(0xFF0A9BD8));
        canvas.drawPath(CssLine(s, 115).band(0.78, 0.84, r), Paint()..color = const Color(0xFFFFC72C));
        canvas.drawPath(CssLine(s, 200).band(0.80, 0.87, r), Paint()..color = const Color(0xFF79B62A));
        canvas.drawPath(CssLine(s, 20).band(0.86, 0.91, r), Paint()..color = const Color(0xFF8D3FB5));
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CardArtPainter old) =>
      old.c1 != c1 || old.c2 != c2 || old.pattern != pattern || old.darkInk != darkInk || old.accent != accent || old.patternOn != patternOn;
}

/// Kartın üstündeki hafif parlama (115°).
class CardShinePainter extends CustomPainter {
  const CardShinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = CssLine(size, 115);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = line.gradient(const [Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x21FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF)], const [0, 0.35, 0.48, 0.62, 1]),
    );
  }

  @override
  bool shouldRepaint(CardShinePainter old) => false;
}

/// Kartın çipi (eski uygulamadaki gibi).
class CardChip extends StatelessWidget {
  const CardChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6E3A1), Color(0xFFC99A3C), Color(0xFFF1D58A)],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: const Color(0x33000000)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0x66503708)),
        ),
      ),
    );
  }
}

/// "KAPALI" şeridi: kartın sağ altında çapraz.
class ClosedRibbon extends StatelessWidget {
  const ClosedRibbon({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -38,
      bottom: 18,
      child: Transform.rotate(
        angle: -35 * math.pi / 180,
        child: Container(
          color: const Color(0xD90A0908),
          padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 3),
          child: Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.44, color: Color(0xFFF3ECE0))),
        ),
      ),
    );
  }
}

/// Kapalı kart: renkleri soluk ve koyu (eski uygulamada grayscale(.8) brightness(.78)).
const ColorFilter kClosedCardFilter = ColorFilter.matrix(<double>[
  0.78 * (0.2 + 0.8 * 0.2126 + 0.8 * 0 + 0.8 * 0), 0.78 * (0.8 * 0.7152), 0.78 * (0.8 * 0.0722), 0, 0,
  0.78 * (0.8 * 0.2126), 0.78 * (0.2 + 0.8 * 0.7152), 0.78 * (0.8 * 0.0722), 0, 0,
  0.78 * (0.8 * 0.2126), 0.78 * (0.8 * 0.7152), 0.78 * (0.2 + 0.8 * 0.0722), 0, 0,
  0, 0, 0, 1, 0,
]);
