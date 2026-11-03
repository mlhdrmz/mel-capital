// Kutlama: bir borç kapandığında ya da hedefe ulaşıldığında ekranın üstünden konfeti yağar.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Konfetiyi verilen katmanda gösterir (panel kapanmadan önce alınmış [overlay] ile de çalışır).
void celebrateOn(OverlayState overlay) {
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Confetti(onDone: () => entry.remove()));
  overlay.insert(entry);
}

void celebrate(BuildContext context) => celebrateOn(Overlay.of(context, rootOverlay: true));

class _Confetti extends StatefulWidget {
  const _Confetti({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _Piece {
  _Piece(math.Random r)
      : x = r.nextDouble(),
        delay = r.nextDouble() * 0.35,
        speed = 0.75 + r.nextDouble() * 0.6,
        drift = (r.nextDouble() - 0.5) * 0.25,
        spin = (r.nextDouble() - 0.5) * 14,
        size = 5 + r.nextDouble() * 7,
        color = _colors[r.nextInt(_colors.length)],
        round = r.nextBool();

  final double x, delay, speed, drift, spin, size;
  final Color color;
  final bool round;

  static const _colors = [MC.gold, MC.gold2, MC.mint, MC.sky, MC.rose, MC.violet, Color(0xFFFFF0D6)];
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final List<_Piece> _pieces = List.generate(140, (_) => _Piece(math.Random()));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value)),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 60);
      final x = (p.x + p.drift * local + math.sin(local * 9 + p.x * 20) * 0.015) * size.width;
      final fade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * p.spin);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
