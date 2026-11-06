// Ortak arayüz parçaları: tutar yazısı, düğmeler, satırlar, boş durum (logolar logos.dart'ta).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/util.dart';
import 'glass.dart';
import 'i18n.dart';
import 'state.dart';
import 'theme.dart';

export 'logos.dart';

const Map<String, IconData> kCategoryIcons = {
  'market': Icons.shopping_basket_outlined,
  'yemek': Icons.restaurant_outlined,
  'kafe': Icons.local_cafe_outlined,
  'ulasim': Icons.directions_car_outlined,
  'alisveris': Icons.shopping_bag_outlined,
  'fatura': Icons.receipt_outlined,
  'abonelik': Icons.autorenew,
  'transfer': Icons.swap_horiz,
  'nakit': Icons.payments_outlined,
  'kira': Icons.home_outlined,
  'eglence': Icons.theaters_outlined,
  'saglik': Icons.medical_services_outlined,
  'giyim': Icons.checkroom_outlined,
  'teknoloji': Icons.devices_outlined,
  'kisisel': Icons.spa_outlined,
  'egitim': Icons.school_outlined,
  'banka': Icons.account_balance_outlined,
  'kart_asgari': Icons.credit_card,
  'diger': Icons.more_horiz,
};

/// Tutar yazısı (gizli moda ve dile göre). [count] verilirse sayarak yükselir.
class MoneyText extends StatelessWidget {
  const MoneyText(this.k, {super.key, required this.style, this.count = false, this.signed = false, this.color});

  final int k;
  final TextStyle style;
  final bool count;
  final bool signed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final lang = S.of(context).lang;
    final base = numStyle(style).copyWith(color: color ?? style.color);
    String text(int v) {
      final s = fmtMoney(v, lang: lang, hidden: st.hidden);
      return signed && v > 0 && !st.hidden ? '+$s' : s;
    }

    if (!count || st.hidden) return Text(text(k), style: base, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: k.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        text(v.round() == k ? k : (v / 100).round() * 100),
        style: base,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

/// Sayfa iskeleti: kaydırılabilir içerik, başlık ve sağda düğmeler.
/// Telefon düzeni: dar ekranlarda alt menü, daha küçük kenar boşlukları ve başlıklar.
const double kPhoneWidth = 700;

bool isPhoneLayout(BuildContext context) => MediaQuery.sizeOf(context).width < kPhoneWidth;

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.eyebrow, required this.title, this.actions = const [], required this.children, this.leading});

  final String eyebrow;
  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneLayout(context);
    return SingleChildScrollView(
      padding: phone ? const EdgeInsets.fromLTRB(16, 6, 16, 96) : const EdgeInsets.fromLTRB(28, 14, 28, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              runSpacing: 14,
              spacing: 18,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 14)],
                    // Dar sütunda (dergi sahnesi) uzun başlık alt satıra iner
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(eyebrow, style: sans(11.5, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.6, shadows: kPhotoTextShadow)),
                          const SizedBox(height: 6),
                          Text(title, style: serif(phone ? 34 : 44, shadows: kPhotoTextShadow)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
          ),
          SizedBox(height: phone ? 14 : 20),
          ...children,
        ],
      ),
    );
  }
}

/// Altın (ana) düğme.
class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, this.icon, required this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: MC.gold,
      foregroundColor: MC.ink,
      disabledBackgroundColor: MC.gold.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 14, fontWeight: FontWeight.w600),
    );
    return icon == null
        ? FilledButton(onPressed: onTap, style: style, child: Text(label))
        : FilledButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 18), label: Text(label));
  }
}

/// Cam görünümlü ikinci düğme.
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.label, this.icon, required this.onTap, this.danger = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: danger ? MC.rose : MC.text,
      backgroundColor: const Color(0x38000000),
      side: BorderSide(color: danger ? MC.rose.withValues(alpha: 0.5) : const Color(0x40FFFFFF)),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 14, fontWeight: FontWeight.w600),
    );
    return icon == null
        ? OutlinedButton(onPressed: onTap, style: style, child: Text(label))
        : OutlinedButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 18), label: Text(label));
  }
}

/// Küçük metin düğmesi (panel başlığında).
class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, this.icon, required this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon ?? Icons.add, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: MC.gold,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Panel başlığı: serif başlık, altında açıklama, sağda düğme.
class PanelHead extends StatelessWidget {
  const PanelHead(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: serif(24)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: sans(12, color: MC.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Kategori simgesi: kategori renginde yuvarlak kare.
class CategoryMark extends StatelessWidget {
  const CategoryMark(this.category, {super.key, this.size = 40, this.icon});

  final String? category;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = catColor(category);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.withValues(alpha: 0.18),
        shape: SignatureBorder(cut: size * 0.24, radius: size * 0.3, side: BorderSide(color: c.withValues(alpha: 0.45))),
      ),
      child: Icon(icon ?? kCategoryIcons[category] ?? Icons.more_horiz, size: size * 0.5, color: c),
    );
  }
}

/// Liste satırı: solda simge, ortada başlık ve açıklama, sağda tutar.
class RowItem extends StatefulWidget {
  const RowItem({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.dim = false});

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dim;

  @override
  State<RowItem> createState() => _RowItemState();
}

class _RowItemState extends State<RowItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        color: _hover && widget.onTap != null ? const Color(0x0FFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: widget.dim ? 0.55 : 1,
        // Sağdaki parça satırın en çok %60'ını alır; dar ekranda sığmazsa küçülür, taşmaz.
        child: LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 13)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(14.5, weight: FontWeight.w600)),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(widget.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(12, color: MC.muted)),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth.isFinite ? c.maxWidth * 0.6 : double.infinity),
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: widget.trailing),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (widget.onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: content),
    );
  }
}

/// İnce ayırıcı çizgi.
class Hairline extends StatelessWidget {
  const Hairline({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 1, color: const Color(0x1FFFFFFF));
}

/// İlerleme çizgisi.
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.color = MC.gold, this.height = 6});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x24FFFFFF)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value.isNaN ? 0 : value.clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withValues(alpha: 0.85), color]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boş durum kartı.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.text, this.icon = Icons.inbox_outlined, this.actions = const []});

  final String title;
  final String text;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 30,
      cut: 30,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 34, color: MC.gold),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: serif(26)),
                const SizedBox(height: 6),
                Text(text, style: sans(13.5, color: MC.muted)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yan yana sütunlar; dar ekranda alt alta.
class TwoColumns extends StatelessWidget {
  const TwoColumns({super.key, required this.left, required this.right, this.leftFlex = 17, this.rightFlex = 10, this.breakpoint = 900});

  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) return Column(children: [left, const SizedBox(height: 14), right]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            const SizedBox(width: 14),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }
}

/// Rakam kutuları sırası; dar ekranda iki sütun.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final perRow = c.maxWidth < 700 ? 2 : children.length;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += perRow) {
          final chunk = children.sublist(i, (i + perRow).clamp(0, children.length));
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < perRow; j++) ...[
                if (j > 0) const SizedBox(width: 14),
                Expanded(child: j < chunk.length ? chunk[j] : const SizedBox.shrink()),
              ],
            ],
          ));
          if (i + perRow < children.length) rows.add(const SizedBox(height: 14));
        }
        return Column(children: rows);
      },
    );
  }
}

/// Kuruş cinsinden rakam kutusu.
class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.k, required this.sub, required this.color, this.valueColor, this.delay = Duration.zero, this.onTap, this.text, this.footer});

  final String label;
  final int k;
  final String sub;
  final Color color;
  final Color? valueColor;
  final Duration delay;
  final VoidCallback? onTap;

  /// Tutar yerine yazı (ör. "3 kart").
  final String? text;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final panel = GlassPanel(
      tint: color,
      delay: delay,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12.5, color: MC.label, weight: FontWeight.w600)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: text != null
                ? Text(text!, style: numStyle(serif(31, color: valueColor ?? MC.text)))
                : MoneyText(k, count: true, style: serif(31, color: valueColor ?? (k < 0 ? MC.rose : MC.text))),
          ),
          const SizedBox(height: 5),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11.5, color: MC.muted)),
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
    if (onTap == null) return panel;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: panel));
  }
}

/// Basit bilgi mesajı (alt köşede). [undo] verilirse "Geri al" düğmesi çıkar.
void toast(BuildContext context, String message, {VoidCallback? undo, int seconds = 3}) =>
    showToast(ScaffoldMessenger.of(context), S.of(context).lang, message, undo: undo, seconds: seconds);

/// Panel kapandıktan sonra da gösterilebilen bildirim (önceden alınmış [messenger] ile).
void showToast(
  ScaffoldMessengerState messenger,
  String lang,
  String message, {
  VoidCallback? undo,
  int seconds = 3,
  String? actionLabel,
  VoidCallback? action,
}) {
  messenger.hideCurrentSnackBar();
  final duration = Duration(seconds: undo == null ? seconds : (seconds < 6 ? 6 : seconds));
  // "Geri al" süresince telefondan gelen değişiklikler bekletilir (geri alma onları silmesin).
  if (undo != null) messenger.context.getInheritedWidgetOfExactType<AppScope>()?.notifier?.noteUndo(duration);
  messenger.showSnackBar(SnackBar(
    action: undo != null
        ? SnackBarAction(label: lang == 'tr' ? 'Geri al' : 'Undo', textColor: MC.gold, onPressed: undo)
        : (action != null && actionLabel != null ? SnackBarAction(label: actionLabel, textColor: MC.gold, onPressed: action) : null),
    content: Text(message, style: sans(13.5)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xF0171513),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    width: math.min(460, MediaQuery.sizeOf(messenger.context).width - 24),
    duration: duration,
  ));
}

/// Gizli modda metindeki tutarları (ör. "1.250 TL") gizler.
String maskTxt(String? text, bool hidden) {
  final t = text ?? '';
  return hidden ? t.replaceAll(RegExp(r'\d[\d.,]*\s?(TL|₺)'), '••• TL') : t;
}

/// Türkçe / English seçimi (ilk açılış ekranlarında).
class LangToggle extends StatelessWidget {
  const LangToggle({super.key, required this.lang, required this.onChanged});

  final String lang;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String code, String label) => TextButton(
          key: ValueKey<String>('start-lang-$code'),
          onPressed: () => onChanged(code),
          style: TextButton.styleFrom(
            foregroundColor: lang == code ? MC.ink : MC.text,
            backgroundColor: lang == code ? MC.gold : const Color(0x33000000),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(label),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [pill('tr', 'Türkçe'), const SizedBox(width: 6), pill('en', 'English')]);
  }
}
