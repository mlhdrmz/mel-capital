import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'format.dart';
import 'i18n.dart';
import 'sahne.dart';
import 'state.dart';
import 'theme.dart';

/// "İmza köşe": sol üst köşesi kesik, diğer üç köşesi yuvarlak çerçeve.
class SignatureBorder extends ShapeBorder {
  const SignatureBorder({
    this.cut = 22,
    this.radius = 22,
    this.side = BorderSide.none,
  });

  final double cut;
  final double radius;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect r) {
    final limit = math.min(r.width, r.height) / 2;
    final c = math.min(cut, limit);
    final rad = math.min(radius, limit);
    final corner = Radius.circular(rad);
    return Path()
      ..moveTo(r.left, r.top + c)
      ..lineTo(r.left + c, r.top)
      ..lineTo(r.right - rad, r.top)
      ..arcToPoint(Offset(r.right, r.top + rad), radius: corner)
      ..lineTo(r.right, r.bottom - rad)
      ..arcToPoint(Offset(r.right - rad, r.bottom), radius: corner)
      ..lineTo(r.left + rad, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - rad), radius: corner)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      SignatureBorder(cut: cut * t, radius: radius * t, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is SignatureBorder &&
      other.cut == cut &&
      other.radius == radius &&
      other.side == side;

  @override
  int get hashCode => Object.hash(cut, radius, side);
}

/// Buzlu cam panel (F seçeneği): arkasındaki fotoğrafı bulanıklaştırır, sol üstten
/// ışık alır, istenirse anlamına göre renklenir (gelir yeşil, ödeme kırmızımsı...).
///
/// Açılırken "buğulanarak" belirir: bulanıklık, renk ve içerik birlikte gelir.
/// (Panelin üstüne saydamlık animasyonu konmaz; bulanıklık bozulurdu.)
class GlassPanel extends StatefulWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.tint,
    this.cut = 22,
    this.radius = 22,
    this.blur = 14,
    this.darkness = 0.38,
    this.delay = Duration.zero,
    this.animate = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double cut;
  final double radius;
  final double blur;
  final double darkness;
  final Duration delay;
  final bool animate;

  @override
  State<GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends State<GlassPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _appear;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + const Duration(milliseconds: 640);
    _controller = AnimationController(
      vsync: this,
      duration: total,
      value: widget.animate ? 0 : 1,
    );
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    _appear = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sahne = SahneScope.of(context);
    if (sahne == Sahne.dergi || sahne == Sahne.sayfa || sahne == Sahne.kemer || sahne == Sahne.pencere) {
      final pad = widget.padding.resolve(Directionality.of(context));
      final t = widget.tint;
      final Widget yuz;
      if (sahne == Sahne.pencere) {
        // Açılır pencere: düz koyu zemin, ince altın kenar, buğu yok
        yuz = DecoratedBox(
          decoration: ShapeDecoration(
            color: kPencereZemin,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.radius),
              side: BorderSide(color: t?.withValues(alpha: 0.6) ?? kAltinCizgi),
            ),
          ),
          child: Padding(padding: pad, child: widget.child),
        );
      } else if (sahne == Sahne.kemer) {
        // Kemer pencere: düz koyu zemin, ince altın çizgi; içerik kemerin altından başlar
        const kemer = 40.0;
        yuz = DecoratedBox(
          decoration: ShapeDecoration(
            color: kKemerZemin,
            shape: KemerBorder(kemer: kemer, side: BorderSide(color: t?.withValues(alpha: 0.7) ?? kAltinCizgi)),
          ),
          child: Padding(padding: pad.copyWith(top: pad.top + kemer * 0.75), child: widget.child),
        );
      } else if (t != null) {
        // Düz sayfada anlamlı rakam: solda renkli ince çizgi
        yuz = DecoratedBox(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: t.withValues(alpha: 0.85), width: 2))),
          child: Padding(padding: EdgeInsets.fromLTRB(14, math.max(0, pad.top - 4), 0, math.max(0, pad.bottom - 4)), child: widget.child),
        );
      } else {
        // Düz sayfada bölüm: üstte ince altın çizgi, kutu yok
        yuz = DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBolumCizgi))),
          child: Padding(padding: EdgeInsets.fromLTRB(0, pad.top, 0, pad.bottom), child: widget.child),
        );
      }
      return AnimatedBuilder(
        animation: _appear,
        child: yuz,
        builder: (context, child) {
          final v = _appear.value;
          return Transform.translate(offset: Offset(0, (1 - v) * 14), child: Opacity(opacity: v, child: child));
        },
      );
    }
    final shape = SignatureBorder(cut: widget.cut, radius: widget.radius);
    return AnimatedBuilder(
      animation: _appear,
      child: Padding(padding: widget.padding, child: widget.child),
      builder: (context, child) {
        final v = _appear.value;
        final sigma = math.max(0.01, widget.blur * v);
        return Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: CustomPaint(
                painter: _GlassPainter(
                  shape: shape,
                  tint: widget.tint,
                  darkness: widget.darkness,
                  strength: v,
                ),
                child: Opacity(opacity: v, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({
    required this.shape,
    required this.tint,
    required this.darkness,
    required this.strength,
  });

  final SignatureBorder shape;
  final Color? tint;
  final double darkness;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    final t = tint;
    final double k = strength.clamp(0.0, 1.0).toDouble();

    // 1) Koyu cam
    canvas.drawPath(
      path,
      Paint()..color = Color.fromRGBO(12, 10, 8, (t == null ? darkness : 0.30) * k),
    );

    // 2) Renk ya da sol üstten gelen parlaklık
    final gradient = t == null
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.10 * k),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.34],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.withValues(alpha: 0.30 * k),
              t.withValues(alpha: 0.06 * k),
              Color.fromRGBO(12, 10, 8, 0.40 * k),
            ],
            stops: const [0, 0.45, 0.75],
          );
    canvas.drawPath(path, Paint()..shader = gradient.createShader(rect));

    // 3) İnce kenar çizgisi
    final edge = t == null
        ? Colors.white.withValues(alpha: 0.08 * k)
        : t.withValues(alpha: 0.38 * k);
    canvas.drawPath(
      shape.getOuterPath(rect.deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );

    // 4) Sol üstten vuran ışık
    canvas.drawPath(
      shape.getOuterPath(rect.deflate(1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF0D6).withValues(alpha: 0.35 * k),
            const Color(0xFFFFF0D6).withValues(alpha: 0),
          ],
          stops: const [0, 0.38],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) =>
      oldDelegate.strength != strength ||
      oldDelegate.tint != tint ||
      oldDelegate.darkness != darkness ||
      oldDelegate.shape != shape;
}

/// Bulanıklık içermeyen öğeler (başlıklar, Özet rakamları) için giriş animasyonu.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _appear;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + const Duration(milliseconds: 560);
    _controller = AnimationController(vsync: this, duration: total)..forward();
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    _appear = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _appear,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(_appear),
        child: widget.child,
      ),
    );
  }
}

/// Sayarak yükselen tutar.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(
    this.value, {
    super.key,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final hidden = AppScope.of(context).hidden;
    final lang = S.of(context).lang;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        money(v, lang: lang, hidden: hidden),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: numStyle(style),
      ),
    );
  }
}

/// Üstteki rakam kutusu: etiket, sayan tutar, altında kısa açıklama.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.valueColor,
    this.delay = Duration.zero,
  });

  final String label;
  final double value;
  final String sub;
  final Color color;
  final Color? valueColor;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tint: color,
      delay: delay,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: sans(12.5, color: MC.label, weight: FontWeight.w600)),
          const SizedBox(height: 5),
          AnimatedMoney(value, style: serif(31, color: valueColor ?? MC.text)),
          const SizedBox(height: 5),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(11.5, color: MC.muted),
          ),
        ],
      ),
    );
  }
}

/// Liste satırlarındaki tarih kutusu (imza köşeli).
class DateChip extends StatelessWidget {
  const DateChip({super.key, required this.day, required this.month});

  final int day;
  final String month;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: SignatureBorder(
          cut: 10,
          radius: 10,
          side: BorderSide(color: MC.gold.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$day', style: sans(13.5, weight: FontWeight.w700, height: 1.1)),
          Text(
            month,
            style: sans(9.5,
                weight: FontWeight.w700,
                color: MC.muted,
                height: 1.15,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

/// Sayfa başlığı: küçük üst yazı + büyük başlık.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Reveal(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: sans(11.5,
                      color: MC.eyebrow,
                      weight: FontWeight.w700,
                      letterSpacing: 2.6,
                      shadows: kPhotoTextShadow),
                ),
                const SizedBox(height: 6),
                Text(title, style: serif(46, shadows: kPhotoTextShadow)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// "Önizleme" notu.
class PreviewNote extends StatelessWidget {
  const PreviewNote({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GlassPanel(
      cut: 12,
      radius: 14,
      darkness: 0.46,
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 18, color: MC.gold),
          const SizedBox(width: 10),
          Flexible(
            child: Text(s.t('preview'), style: sans(12.5, color: MC.muted)),
          ),
        ],
      ),
    );
  }
}
