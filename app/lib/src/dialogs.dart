// Onay ve metin soran küçük pencereler.

import 'package:flutter/material.dart';

import 'glass.dart';
import 'i18n.dart';
import 'theme.dart';
import 'ui.dart';

/// Ortadaki cam pencere.
Future<T?> showGlassDialog<T>(BuildContext context, {required WidgetBuilder builder, double maxWidth = 480}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x8C000000),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(type: MaterialType.transparency, child: builder(context)),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// "Emin misin?" sorusu. Onaylanırsa true.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String text,
  String? ok,
  bool danger = false,
}) async {
  final s = S.of(context);
  final result = await showGlassDialog<bool>(
    context,
    builder: (context) => GlassPanel(
      animate: false,
      blur: 22,
      darkness: 0.62,
      radius: 26,
      cut: 26,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: serif(28)),
          const SizedBox(height: 10),
          Text(text, style: sans(14, color: MC.muted, height: 1.45)),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              GlassButton(label: s.pick('Vazgeç', 'Cancel'), onTap: () => Navigator.of(context).pop(false)),
              danger
                  ? GlassButton(label: ok ?? s.pick('Sil', 'Delete'), danger: true, onTap: () => Navigator.of(context).pop(true))
                  : GoldButton(label: ok ?? s.pick('Tamam', 'OK'), onTap: () => Navigator.of(context).pop(true)),
            ],
          ),
        ],
      ),
    ),
  );
  return result == true;
}

/// Tek satır metin sorar (ör. profil adı). Vazgeçilirse null.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? text,
  String initial = '',
  String? hint,
  String? ok,
}) {
  final s = S.of(context);
  final controller = TextEditingController(text: initial);
  return showGlassDialog<String>(
    context,
    builder: (context) {
      void submit() => Navigator.of(context).pop(controller.text.trim());
      return GlassPanel(
        animate: false,
        blur: 22,
        darkness: 0.62,
        radius: 26,
        cut: 26,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: serif(28)),
            if (text != null) ...[
              const SizedBox(height: 8),
              Text(text, style: sans(13.5, color: MC.muted, height: 1.45)),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: sans(16),
              onSubmitted: (_) => submit(),
              decoration: fieldDecoration(hint: hint),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                GlassButton(label: s.pick('Vazgeç', 'Cancel'), onTap: () => Navigator.of(context).pop()),
                GoldButton(label: ok ?? s.pick('Kaydet', 'Save'), onTap: submit),
              ],
            ),
          ],
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

/// Metin kutusu görünümü (cam üstünde koyu alan).
InputDecoration fieldDecoration({String? hint, String? suffix, String? label}) {
  const edge = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: Color(0x33FFFFFF)),
  );
  return InputDecoration(
    hintText: hint,
    labelText: label,
    suffixText: suffix,
    hintStyle: sans(15, color: MC.dim),
    labelStyle: sans(14, color: MC.muted),
    suffixStyle: sans(14, color: MC.muted),
    filled: true,
    fillColor: const Color(0x38000000),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: edge,
    enabledBorder: edge,
    focusedBorder: edge.copyWith(borderSide: const BorderSide(color: MC.gold, width: 1.4)),
  );
}

/// Açılır seçim kutusu (cam üstünde koyu alan).
class GlassSelect<T> extends StatelessWidget {
  const GlassSelect({super.key, required this.value, required this.items, required this.onChanged, this.width});

  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x38000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.any((e) => e.$1 == value) ? value : null,
          isExpanded: true,
          dropdownColor: const Color(0xF2201C18),
          borderRadius: BorderRadius.circular(12),
          iconEnabledColor: MC.muted,
          style: sans(14.5),
          items: [
            for (final e in items)
              DropdownMenuItem<T>(value: e.$1, child: Text(e.$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}
