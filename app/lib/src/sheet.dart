// Düzenleme panelleri: sağdan açılan cam panel, form alanları ve "bu değişiklik uygulanırsa" önizlemesi.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/actions.dart';
import '../core/calc.dart';
import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'glass.dart';
import 'i18n.dart';
import 'state.dart';
import 'theme.dart';
import 'ui.dart';

/// Sağdan kayarak açılan düzenleme paneli.
Future<T?> showEditSheet<T>(BuildContext context, {required WidgetBuilder builder, double width = 580}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x73000000),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: SizedBox(
            width: math.min(width, MediaQuery.sizeOf(context).width - 32),
            child: Material(type: MaterialType.transparency, child: builder(context)),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero).animate(curve),
        child: FadeTransition(opacity: curve, child: child),
      );
    },
  );
}

/// Form çıktısı: hata ya da veriye uygulanacak değişiklik.
class Outcome {
  const Outcome.err(String this.error)
      : apply = null,
        focus = null,
        cardId = null,
        source = null;
  const Outcome.ok(void Function(Data d) this.apply, {this.focus, this.cardId, this.source}) : error = null;

  final String? error;
  final void Function(Data d)? apply;

  /// Önizlemede gösterilecek ay.
  final String? focus;
  final String? cardId;
  final String? source;
  bool get ok => error == null && apply != null;
}

/// Değişikliği uygular, paneli kapatır ve geri alınabilir bildirim gösterir.
void commitOutcome(BuildContext context, Outcome o, String message, {bool close = true}) {
  final st = AppScope.of(context);
  final s = S.of(context);
  final apply = o.apply;
  if (apply == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final snap = st.snapshot();
  final before = st.ctx.model;
  st.update(apply);
  final closed = closedDebts(st.data, before, st.ctx.model);
  if (close) Navigator.of(context).pop();
  final extra = closed.isEmpty ? '' : s.pick(' ${closed.map((x) => x.creditor).join(', ')} borcu kapandı! 🎉', ' ${closed.map((x) => x.creditor).join(', ')} is paid off! 🎉');
  showToast(messenger, s.lang, message + extra, undo: () => st.restore(snap));
}

/// Panelin iskeleti: başlık, kaydırılabilir alanlar, hata, önizleme ve düğmeler.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.actions = const [],
    this.leftActions = const [],
    this.error,
    this.impact,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final List<Widget> leftActions;
  final String? error;
  final Widget? impact;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      animate: false,
      blur: 26,
      darkness: 0.7,
      radius: 26,
      cut: 34,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 14, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: serif(31)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: sans(12.5, color: MC.muted, height: 1.4)),
                  ],
                ]),
              ),
              IconButton(
                tooltip: S.of(context).pick('Kapat', 'Close'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: MC.muted),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 10, 28, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ...children,
                if (impact != null) ...[const SizedBox(height: 14), impact!],
              ]),
            ),
          ),
          if (error != null && error!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
              child: Row(children: [
                const Icon(Icons.error_outline, color: MC.rose, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(error!, style: sans(13, color: MC.rose))),
              ]),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x1FFFFFFF)))),
            child: Row(children: [
              ...leftActions,
              const Spacer(),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Alanlar

class FieldBox extends StatelessWidget {
  const FieldBox({super.key, required this.label, required this.child, this.help, this.bottom = 14});

  final String label;
  final Widget child;
  final String? help;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: sans(12.5, weight: FontWeight.w600, color: MC.label)),
        const SizedBox(height: 6),
        child,
        if (help != null) ...[
          const SizedBox(height: 5),
          Text(help!, style: sans(11.5, color: MC.dim, height: 1.4)),
        ],
      ]),
    );
  }
}

/// İki alan yan yana (dar ekranda alt alta).
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 420) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, right]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ]);
    });
  }
}

class TextInput extends StatelessWidget {
  const TextInput({super.key, required this.controller, this.hint, this.autofocus = false, this.onChanged, this.onSubmitted, this.suffix, this.big = false, this.number = false, this.maxLines = 1});

  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? suffix;
  final bool big;
  final bool number;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        style: big ? serif(26) : sans(15),
        decoration: fieldDecoration(hint: hint, suffix: suffix),
      );
}

/// Kuruş tutarı için metin (2.500 · 2.500,50).
String moneyInput(int? k, String lang) {
  if (k == null) return '';
  return fmtNum(k, lang: lang);
}

/// Tarih alanı: dokununca takvim açılır.
class DateInput extends StatelessWidget {
  const DateInput({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final init = isDate(value) ? DateTime.parse(value) : clock();
        final picked = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: DateTime(2015),
          lastDate: DateTime(2045, 12, 31),
          locale: Locale(s.lang),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(primary: MC.gold, onPrimary: MC.ink, surface: const Color(0xFF1E1A16)),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged('${picked.year}-${two(picked.month)}-${two(picked.day)}');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: const Color(0x38000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x33FFFFFF))),
        child: Row(children: [
          Expanded(child: Text(isDate(value) ? '${fmtDate(value, s.lang)}, ${weekdayName(value, s.lang)}' : s.pick('Tarih seç', 'Pick a date'), style: sans(15))),
          const Icon(Icons.calendar_today_outlined, size: 17, color: MC.muted),
        ]),
      ),
    );
  }
}

/// Ay seçici: ay ve yıl.
class MonthInput extends StatelessWidget {
  const MonthInput({super.key, required this.value, required this.onChanged, this.allowEmpty = false});

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = AppScope.of(context);
    final cy = int.parse(currentMonth().substring(0, 4));
    var y0 = cy - 4, y1 = cy + 12;
    final v = isMonth(value) ? value : null;
    if (v != null) {
      final n = int.parse(v.substring(0, 4));
      y0 = math.min(y0, n);
      y1 = math.max(y1, n);
    }
    if (st.hasData && isMonth(st.data.balancesAsOf)) y0 = math.min(y0, int.parse(st.data.balancesAsOf.substring(0, 4)));
    final mo = v == null ? null : int.parse(v.substring(5, 7));
    final yr = v == null ? null : int.parse(v.substring(0, 4));
    final names = s.isTr ? kMonthsTr : kMonthsEn;
    void emit(int? m, int? y) {
      if (m == null && y == null) {
        onChanged(null);
      } else {
        onChanged('${y ?? cy}-${two(m ?? 1)}');
      }
    }

    return Row(children: [
      Expanded(
        flex: 3,
        child: GlassSelect<int>(
          value: mo ?? (allowEmpty ? 0 : null),
          items: [if (allowEmpty) (0, s.pick('Ay —', 'Month —')), for (var i = 1; i <= 12; i++) (i, names[i - 1])],
          onChanged: (m) => emit(m == 0 ? null : m, yr),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: GlassSelect<int>(
          value: yr ?? (allowEmpty ? 0 : null),
          items: [if (allowEmpty) (0, s.pick('Yıl —', 'Year —')), for (var y = y0; y <= y1; y++) (y, '$y')],
          onChanged: (y) => emit(mo, y == 0 ? null : y),
        ),
      ),
    ]);
  }
}

/// Hesaplar (bakiye sırasıyla), istenirse kredi kartları.
List<Account> accountsSorted(Data d) {
  const order = {'nakit': 0, 'vadesiz': 1, 'cuzdan': 2, 'on_odemeli': 3, 'birikim': 4, 'diger': 5};
  final list = d.accounts.toList();
  list.sort((a, b) {
    final pa = toK(a.balance) > 0 ? 0 : 1, pb = toK(b.balance) > 0 ? 0 : 1;
    if (pa != pb) return pa - pb;
    final t = (order[a.type] ?? 5) - (order[b.type] ?? 5);
    if (t != 0) return t;
    return accLabel(a, 'tr').compareTo(accLabel(b, 'tr'));
  });
  return list;
}

/// Ödeme kaynağı seçici ("acc:<id>" ya da "card:<id>"; boş = kaynak yok).
class SourceSelect extends StatelessWidget {
  const SourceSelect({super.key, required this.value, required this.onChanged, this.none, this.cards = true});

  final String? value;
  final ValueChanged<String?> onChanged;
  final String? none;
  final bool cards;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final items = <(String, String)>[
      if (none != null) ('', none!),
      for (final a in accountsSorted(d)) ('acc:${a.id}', '${accLabel(a, s.lang)} · ${money(toK(a.balance))}'),
      if (cards)
        for (final x in d.debts.where((x) => x.isCard))
          (
            'card:${x.id}',
            '${x.creditor} · ${ctx.model.debts[x.id]?.limit != null ? s.pick('boş ', 'available ') + money(ctx.model.debts[x.id]!.available ?? 0) : s.pick('limit yok', 'no limit')}',
          ),
    ];
    final v = value ?? '';
    final known = items.any((e) => e.$1 == v);
    return GlassSelect<String>(
      value: known ? v : (none != null ? '' : null),
      items: [
        ...items,
        if (!known && v.isNotEmpty) (v, sourceName(d, v, s.lang)),
      ],
      onChanged: (x) => onChanged(x == null || x.isEmpty ? null : x),
    );
  }
}

/// Seçenek düğmeleri (yan yana).
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x38000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x33FFFFFF))),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: InkWell(
              onTap: () => onChanged(o.$1),
              borderRadius: BorderRadius.circular(9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: o.$1 == value ? MC.gold : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                child: Text(o.$2,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: sans(13, weight: FontWeight.w600, color: o.$1 == value ? MC.ink : MC.text)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Kategoriler: hazır olanlar ve verideki kendi kategorilerin.
List<(String, String)> allCategories(Data? d, String lang) {
  final list = [
    for (final e in kCategories.entries)
      if (e.key != 'kart_asgari') (e.key, e.value.label.of(lang)),
  ];
  final seen = {...kCategories.keys};
  if (d != null) {
    for (final c in [...d.recurringExpenses.map((e) => e.category), ...d.spends.map((e) => e.category)]) {
      if (c.isNotEmpty && seen.add(c)) list.add((c, c));
    }
  }
  return list;
}

/// Kategori seçici: renkli düğmeler ve "+ Yeni".
class CategoryPicker extends StatefulWidget {
  const CategoryPicker({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  bool _new = false;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final cats = allCategories(st.hasData ? st.data : null, s.lang);
    Widget chip(String id, String label, {bool isNew = false}) {
      final on = isNew ? _new : (!_new && widget.value == id);
      final c = isNew ? MC.gold : catColor(id);
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (isNew) {
            setState(() => _new = true);
            return;
          }
          setState(() => _new = false);
          widget.onChanged(id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? c.withValues(alpha: 0.85) : c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.withValues(alpha: on ? 1 : 0.45)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!isNew) ...[Icon(kCategoryIcons[id] ?? Icons.label_outline, size: 14, color: on ? MC.ink : c), const SizedBox(width: 5)],
            Text(label, style: sans(12.5, weight: FontWeight.w600, color: on ? MC.ink : MC.text)),
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in cats) chip(c.$1, c.$2),
        chip('__new__', s.pick('+ Yeni', '+ New'), isNew: true),
      ]),
      if (_new) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          autofocus: true,
          style: sans(14.5),
          decoration: fieldDecoration(hint: s.pick('Yeni kategori adı', 'New category name')),
          onChanged: (v) {
            final label = v.trim();
            if (label.isEmpty) return;
            String? match;
            for (final e in kCategories.entries) {
              if (trLower(e.value.label.tr) == trLower(label) || trLower(e.value.label.en) == trLower(label)) match = e.key;
            }
            widget.onChanged(match ?? label);
          },
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- Önizleme

class ImpactLine {
  const ImpactLine(this.label, this.before, this.after, {this.upIsGood = true, this.warn});
  final String label;
  final int before;
  final int after;
  final bool upIsGood;

  /// Satırın altında kırmızı uyarı (ör. limit yetersiz).
  final String? warn;
}

/// Kaynağın (hesap ya da kart) önce/sonra satırı.
List<ImpactLine> sourceImpact(Ctx b, Ctx a, String? source, String lang) {
  String pick(String tr, String en) => lang == 'tr' ? tr : en;
  final aid = srcAcc(source);
  if (aid != null) {
    final ba = b.data.account(aid), aa = a.data.account(aid);
    if (ba != null && aa != null) return [ImpactLine(pick('${accLabel(aa, lang)} bakiyesi', '${accLabel(aa, lang)} balance'), toK(ba.balance), toK(aa.balance))];
  }
  final cid = srcCard(source);
  if (cid != null) {
    final bD = b.model.debts[cid], aD = a.model.debts[cid];
    final name = b.data.debt(cid)?.creditor ?? '';
    if (bD != null && aD != null && aD.limit != null) {
      final av = aD.available ?? 0;
      return [
        ImpactLine(pick('$name boş limit', '$name available'), bD.available ?? 0, av,
            warn: av < 0 ? pick('Limit yetersiz: ${fmtMoney(-av, lang: lang)} eksik.', 'Not enough limit: ${fmtMoney(-av, lang: lang)} short.') : null),
      ];
    }
  }
  return const [];
}

/// Kart borcu ve limitinin önce/sonra satırları.
List<ImpactLine> cardDebtImpact(Ctx b, Ctx a, String cardId, String lang) {
  String pick(String tr, String en) => lang == 'tr' ? tr : en;
  final bD = b.model.debts[cardId], aD = a.model.debts[cardId];
  if (bD == null || aD == null) return const [];
  final name = b.data.debt(cardId)?.creditor ?? '';
  return [
    ImpactLine(pick('$name borcu', '$name debt'), bD.current, aD.current, upIsGood: false),
    if (aD.limit != null) ImpactLine(pick('Kullanılabilir limit', 'Available limit'), bD.available ?? 0, aD.available ?? 0),
  ];
}

/// "Bu değişiklik uygulanırsa": formun değişikliği verinin kopyasında denenir.
class ImpactBox extends StatelessWidget {
  const ImpactBox({super.key, required this.outcome, this.noLiquid = false, this.noFree = false, this.extra});

  final Outcome? outcome;
  final bool noLiquid;
  final bool noFree;
  final List<ImpactLine> Function(Ctx before, Ctx after)? extra;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final o = outcome;
    final apply = o?.apply;
    if (o == null || apply == null || !st.hasData) return const SizedBox.shrink();
    final before = st.ctx;
    Ctx after;
    try {
      final copy = Data(deepCopy(st.data.j) as Json);
      apply(copy);
      after = Ctx(copy);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final lines = <ImpactLine>[];
    final focus = o.focus ?? before.cur;
    final b = before.sum(focus), a = after.sum(focus);
    if (!noFree) {
      if (a.income > 0 || b.income > 0) {
        lines.add(ImpactLine(s.pick('${monthLabel(focus, s.lang)} kalan bütçe', '${monthLabel(focus, s.lang)} budget left'), b.free, a.free));
      } else {
        lines.add(ImpactLine(s.pick('${monthLabel(focus, s.lang)} toplam çıkış', '${monthLabel(focus, s.lang)} total out'), b.total, a.total, upIsGood: false));
      }
    }
    if (!noLiquid && before.model.liquid != after.model.liquid) {
      lines.add(ImpactLine(s.pick('Hesaplarda toplam', 'Total in accounts'), before.model.liquid, after.model.liquid));
    }
    if (before.model.totalRemaining != after.model.totalRemaining) {
      lines.add(ImpactLine(s.pick('Toplam borç', 'Total debt'), before.model.totalRemaining, after.model.totalRemaining, upIsGood: false));
    }
    if (extra != null) lines.addAll(extra!(before, after));
    final warnIncome = !noFree && a.income > 0 && a.free < 0 && b.free >= 0;
    if (lines.isEmpty) return const SizedBox.shrink();
    return ImpactView(
      lines: lines,
      warn: warnIncome ? s.pick('${monthLabel(focus, s.lang)} ayında gelir, çıkışları karşılamıyor.', 'In ${monthLabel(focus, s.lang)} income does not cover the outgoings.') : null,
    );
  }
}

class ImpactView extends StatelessWidget {
  const ImpactView({super.key, required this.lines, this.warn});

  final List<ImpactLine> lines;
  final String? warn;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    Widget row(ImpactLine l) {
      final good = l.upIsGood ? l.after > l.before : l.after < l.before;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(l.label, style: sans(13, color: MC.muted))),
            if (l.after == l.before)
              Text('${money(l.after)} ${s.pick('(değişmez)', '(no change)')}', style: sans(13, weight: FontWeight.w600))
            else ...[
              Text(money(l.before), style: sans(13, color: MC.muted)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 14, color: MC.muted)),
              Text(money(l.after), style: sans(13.5, weight: FontWeight.w700, color: good ? MC.mint : MC.rose)),
            ],
          ]),
          if (l.warn != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(l.warn!, style: sans(12, color: MC.rose))),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: ShapeDecoration(
        color: const Color(0x2E000000),
        shape: SignatureBorder(cut: 12, radius: 12, side: BorderSide(color: MC.gold.withValues(alpha: 0.35))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.pick('Bu değişiklik uygulanırsa', 'If you save this'), style: sans(12, weight: FontWeight.w700, color: MC.gold, letterSpacing: 0.4)),
        for (final l in lines) row(l),
        if (warn != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(warn!, style: sans(12.5, color: MC.rose))),
      ]),
    );
  }
}
