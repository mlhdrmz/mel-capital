// Sayfalar arasında ortak parçalar: hareket satırı, kart görseli, kredi satırı, paneller.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

// ---------------------------------------------------------------- Düzenleme sayfaları (yer tutucu)

void _soon(BuildContext context) {
  final s = S.of(context);
  toast(context, s.pick('Bu düzenleme ekranı bir sonraki güncellemede geliyor.', 'This editor arrives in the next update.'));
}

void openTransferSheet(BuildContext context) => _soon(context);
void openAccountSheet(BuildContext context, {String? bank, String? type, Account? account}) => _soon(context);
void openCardSheet(BuildContext context, {String? bank, BankCard? card}) => _soon(context);
void openDebtSheet(BuildContext context, {Debt? debt, String? type}) => _soon(context);
void openSpendSheet(BuildContext context, {Spend? spend}) => _soon(context);
void openQuickSpendSheet(BuildContext context) => _soon(context);
void openSubSheet(BuildContext context, {Subscription? sub}) => _soon(context);
void openGoalSheet(BuildContext context, {Goal? goal}) => _soon(context);
void openPaySheet(BuildContext context, PlanItem item, String month) => _soon(context);

// ---------------------------------------------------------------- Hareketler

/// Harcama, aktarma ya da ödeme satırı.
class MovementRow extends StatelessWidget {
  const MovementRow({super.key, required this.mv, this.showDate = false, this.hideSource});

  final Movement mv;
  final bool showDate;
  final String? hideSource;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final bits = <String>[];
    Widget leading;
    switch (mv.t) {
      case 'spend':
        leading = CategoryMark(mv.cat, size: 38);
        final nm = normTxt(mv.name);
        if (mv.place.isNotEmpty && normTxt(mv.place) != nm) bits.add(mv.place);
        final cl = catLabel(mv.cat, s.lang);
        if (normTxt(cl) != nm) bits.add(cl);
        if (mv.src != null && mv.src != hideSource) bits.add(sourceName(d, mv.src, s.lang));
        if (mv.inst > 1) bits.add(s.pick('${mv.inst} taksit', '${mv.inst} instalments'));
      case 'transfer':
        leading = CategoryMark('transfer', size: 38, icon: mv.from == 'ext' ? Icons.south_west : Icons.swap_horiz);
        final from = mv.from == 'ext' ? s.pick('Dışarıdan', 'External') : sourceName(d, mv.from, s.lang);
        bits.add('$from → ${sourceName(d, mv.src, s.lang)}');
      default:
        leading = const CategoryMark('kart_asgari', size: 38, icon: Icons.check);
        bits.add(s.pick('Ödeme', 'Payment') + (mv.src != null ? ' · ${sourceName(d, mv.src, s.lang)}' : ''));
    }
    if (showDate) bits.insert(0, fmtDayShort(mv.date, s.lang));
    // Aktarma nötr; dışarıdan para girişi artı (yeşil); harcama ve ödeme eksi.
    final moneyIn = mv.t == 'transfer' && mv.from == 'ext';
    final neutral = mv.t == 'transfer' && !moneyIn;
    return RowItem(
      leading: leading,
      title: mv.name,
      subtitle: bits.join(' · '),
      trailing: MoneyText(
        mv.k,
        signed: moneyIn,
        style: sans(14.5, weight: FontWeight.w700),
        color: moneyIn ? MC.mint : (neutral ? MC.muted : null),
      ),
      onTap: mv.t == 'spend'
          ? () {
              final sp = d.spends.where((x) => x.id == mv.id);
              if (sp.isNotEmpty) openSpendSheet(context, spend: sp.first);
            }
          : null,
    );
  }
}

/// Bu ay seçili hesaplardan çıkan/giren her şey.
class MonthMovesPanel extends StatelessWidget {
  const MonthMovesPanel({super.key, required this.accIds});

  final Set<String> accIds;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final m = ctx.cur;
    final list = movements(ctx.data, s.lang)
        .where((x) => isDate(x.date) && monthOf(x.date) == m && (accIds.contains(x.src) || (x.t == 'transfer' && accIds.contains(x.from))))
        .toList();
    var outK = 0, inK = 0;
    for (final x in list) {
      if (x.t != 'transfer') {
        outK += x.k.abs();
        continue;
      }
      final fromIn = accIds.contains(x.from);
      final toIn = accIds.contains(x.src);
      if (fromIn && !toIn) {
        outK += x.k.abs();
      } else if (!fromIn && toIn) {
        inK += x.k.abs();
      }
    }
    final shown = list.take(14).toList();
    final sub = '${monthLabel(m, s.lang)} · ${s.pick('çıkan', 'out')} ${fmtMoney(outK, lang: s.lang, hidden: st.hidden)}'
        '${inK > 0 ? ' · ${s.pick('giren', 'in')} ${fmtMoney(inK, lang: s.lang, hidden: st.hidden)}' : ''}';
    return GlassPanel(
      delay: const Duration(milliseconds: 280),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Bu ay bu hesaptan', 'This month from here'), subtitle: sub),
          if (shown.isEmpty) Text(s.pick('Bu ay bu hesaptan hareket yok.', 'No movements this month.'), style: sans(13, color: MC.muted)),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Hairline(),
            MovementRow(mv: shown[i], showDate: true),
          ],
          if (list.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.pick('${list.length - shown.length} hareket daha; tamamı Harcamalar sayfasında.', '${list.length - shown.length} more in Spending.'),
                style: sans(12, color: MC.dim),
              ),
            ),
        ],
      ),
    );
  }
}

/// Son aktarmalar.
class TransfersPanel extends StatelessWidget {
  const TransfersPanel({super.key, this.filter, this.count = 6});

  final bool Function(Transfer t)? filter;
  final int count;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final list = d.transfers.where(filter ?? (_) => true).toList()
      ..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : (b.createdAt ?? '').compareTo(a.createdAt ?? '');
      });
    final shown = list.take(count).toList();
    return GlassPanel(
      delay: const Duration(milliseconds: 320),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Son aktarmalar', 'Recent transfers')),
          if (shown.isEmpty) Text(s.pick('Aktarma yok.', 'No transfers.'), style: sans(13, color: MC.muted)),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Hairline(),
            MovementRow(
              showDate: true,
              mv: Movement(
                t: 'transfer',
                id: shown[i].id,
                date: shown[i].date,
                at: shown[i].createdAt ?? '',
                k: toK(shown[i].amount),
                name: shown[i].external ? s.pick('Para girişi', 'Money in') : s.pick('Aktarma', 'Transfer'),
                src: shown[i].to,
                from: shown[i].from,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Kart görseli

Color hexColor(String? s, Color fallback) {
  if (s == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) return fallback;
  return Color(int.parse(s.substring(1), radix: 16) | 0xFF000000);
}

/// Kartın görünümü: renkler, yazı rengi ve desen (gerçek kartın kopyası değil, hatırlatıcı çizim).
class CardLook {
  const CardLook(this.c1, this.c2, this.ink, this.pattern, this.accent);

  factory CardLook.of(CardStyle? style, String? bankKey) {
    final b = bankKey == null ? null : kBanks[bankKey];
    final f1 = b?.c1 ?? const Color(0xFF3A3A3A);
    final f2 = b?.c2 ?? const Color(0xFF111111);
    if (style == null) return CardLook(f1, f2, 'light', 'lines', null);
    return CardLook(
      hexColor(style.c1, f1),
      hexColor(style.c2, f2),
      style.ink,
      style.pattern,
      style.accent == null ? null : hexColor(style.accent, MC.gold),
    );
  }

  final Color c1;
  final Color c2;
  final String ink;
  final String pattern;
  final Color? accent;

  Color get text => switch (ink) {
        'dark' => const Color(0xFF15120E),
        'gold' => const Color(0xFFF2D49B),
        _ => Colors.white,
      };
}

/// Banka ya da kredi kartının görseli.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.look,
    required this.bankKey,
    required this.name,
    required this.kindLabel,
    required this.midLabel,
    this.midValue,
    this.debtK,
    this.limitK,
    this.network,
    this.closed = false,
    this.onTap,
    this.debt,
    this.card,
    this.width = 290,
  });

  factory CardTile.forDebt({required Ctx ctx, required Debt debt, required String? bankKey}) {
    final info = ctx.model.debts[debt.id];
    final hasLimit = info?.limit != null;
    return CardTile(
      look: CardLook.of(null, bankKey),
      bankKey: bankKey,
      name: debt.creditor,
      kindLabel: const Lbl('Kredi kartı', 'Credit card'),
      midLabel: hasLimit ? const Lbl('Kullanılabilir', 'Available') : const Lbl('Kart borcu', 'Card debt'),
      midValue: hasLimit ? info!.available : info?.current,
      debtK: hasLimit ? info!.current : null,
      limitK: hasLimit ? info!.limit : null,
      debt: debt,
    );
  }

  factory CardTile.forCard({required Ctx ctx, required BankCard card}) {
    final d = ctx.data;
    final debt = card.debtId == null ? null : d.debt(card.debtId);
    final info = debt == null ? null : ctx.model.debts[debt.id];
    final acct = card.accountId == null ? null : d.account(card.accountId);
    Lbl mid = const Lbl('', '');
    int? value;
    int? debtK;
    int? limitK;
    if (!card.active) {
      if (info != null) {
        mid = info.current > 0 ? const Lbl('Yapılandırma, kalan', 'Restructured, remaining') : const Lbl('Kapandı', 'Closed');
        value = info.current;
      } else {
        mid = const Lbl('Kapalı kart', 'Closed card');
      }
    } else if (card.kind == 'kredi' && info != null) {
      final hasLimit = info.limit != null;
      mid = hasLimit ? const Lbl('Kullanılabilir', 'Available') : const Lbl('Kart borcu', 'Card debt');
      value = hasLimit ? info.available : info.current;
      debtK = hasLimit ? info.current : null;
      limitK = info.limit;
    } else if (card.kind == 'kredi') {
      mid = const Lbl('Borç kaydı bağlı değil', 'No debt linked');
    } else if (acct != null) {
      mid = Lbl(acct.name, acct.name);
      value = toK(acct.balance);
    }
    return CardTile(
      look: CardLook.of(card.style, card.bank),
      bankKey: card.bank,
      name: card.name,
      kindLabel: kCardKinds[card.kind] ?? const Lbl('Kart', 'Card'),
      midLabel: mid,
      midValue: value,
      debtK: debtK,
      limitK: limitK,
      network: card.network,
      closed: !card.active,
      card: card,
    );
  }

  final CardLook look;
  final String? bankKey;
  final String name;
  final Lbl kindLabel;
  final Lbl midLabel;
  final int? midValue;
  final int? debtK;
  final int? limitK;
  final String? network;
  final bool closed;
  final VoidCallback? onTap;
  final double width;

  /// Dokununca açılacak kayıt.
  final Debt? debt;
  final BankCard? card;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = AppScope.of(context);
    final ink = look.text;
    final soft = ink.withValues(alpha: 0.78);
    final kind = kindLabel.of(s.lang);
    final lowerName = trLower(name);
    final showKind = kind.isNotEmpty &&
        !lowerName.contains(trLower(kind)) &&
        !lowerName.contains('${trLower(kind.split(' ').first)} kart');
    final used = limitK != null && limitK! > 0 && debtK != null ? (debtK! / limitK!).clamp(0.0, 1.0).toDouble() : null;
    const shape = SignatureBorder(cut: 26, radius: 18, side: BorderSide(color: Color(0x38FFFFFF)));
    final tile = SizedBox(
      width: width,
      height: width * 0.6,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [look.c1, look.c2]),
          shape: shape,
          shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 26, offset: Offset(0, 12))],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: CustomPaint(
            painter: CardPatternPainter(look.pattern, ink, look.accent),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BankPlate(bankKey: bankKey, name: name, size: 24),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(name.isEmpty ? kind : name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(13.5, weight: FontWeight.w700, color: ink)),
                      ),
                      if (showKind) Text(kind, style: sans(10.5, color: soft)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const _Chip(),
                      const Spacer(),
                      if (network != null) Text(network!, style: sans(12, weight: FontWeight.w700, color: soft, letterSpacing: 0.4)),
                    ],
                  ),
                  const Spacer(),
                  if (midLabel.tr.isNotEmpty) Text(midLabel.of(s.lang), style: sans(11, color: soft, letterSpacing: 0.3)),
                  if (midValue != null) MoneyText(midValue!, style: serif(27, color: ink)),
                  if (used != null) ...[
                    const SizedBox(height: 5),
                    ProgressLine(used, color: used > 0.9 ? MC.rose : ink, height: 3),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(s.pick('Borç ', 'Debt ') + (st.hidden ? '•••' : fmtNum(debtK!, lang: s.lang)), style: sans(10.5, color: soft)),
                        const Spacer(),
                        Text('Limit ${st.hidden ? '•••' : fmtNum(limitK!, lang: s.lang)}', style: sans(10.5, color: soft)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final body = closed
        ? Stack(
            children: [
              Opacity(opacity: 0.5, child: tile),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(6)),
                  child: Text(s.pick('KAPALI', 'CLOSED'), style: sans(10.5, weight: FontWeight.w700, letterSpacing: 1.2)),
                ),
              ),
            ],
          )
        : tile;
    final d = debt;
    final c = card;
    final tap = onTap ??
        (c != null
            ? () => openCardSheet(context, card: c)
            : d != null
                ? () => openDebtSheet(context, debt: d)
                : null);
    if (tap == null) return body;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: tap, child: body));
  }
}

class _Chip extends StatelessWidget {
  const _Chip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 25,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1D9A4), Color(0xFFC59B52), Color(0xFFE9CC8C)],
        ),
        border: Border.all(color: const Color(0x55000000), width: 0.6),
      ),
      child: CustomPaint(painter: _ChipLines()),
    );
  }
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
    canvas.drawLine(Offset(size.width * 0.36, 0), Offset(size.width * 0.36, size.height), p);
    canvas.drawLine(Offset(size.width * 0.64, 0), Offset(size.width * 0.64, size.height), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kart deseni: çizgiler, dalgalar, noktalar, halkalar, geometrik, ışık, konfeti.
class CardPatternPainter extends CustomPainter {
  CardPatternPainter(this.pattern, this.ink, this.accent);

  final String pattern;
  final Color ink;
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..color = ink.withValues(alpha: 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = ink.withValues(alpha: 0.08);
    switch (pattern) {
      case 'lines':
        for (var x = -h; x < w; x += 14) {
          canvas.drawLine(Offset(x, h), Offset(x + h, 0), line);
        }
      case 'waves':
        for (var i = 0; i < 6; i++) {
          final path = Path();
          final y0 = h * (0.35 + i * 0.12);
          path.moveTo(0, y0);
          for (var x = 0.0; x <= w; x += 6) {
            path.lineTo(x, y0 + math.sin((x / w) * math.pi * 2.4 + i * 0.6) * h * 0.06);
          }
          canvas.drawPath(path, line);
        }
      case 'dots':
        for (var y = 10.0; y < h; y += 13) {
          for (var x = (y ~/ 13).isEven ? 8.0 : 14.5; x < w; x += 13) {
            canvas.drawCircle(Offset(x, y), 1.4, fill);
          }
        }
      case 'rings':
        for (var r = 26.0; r < w; r += 22) {
          canvas.drawCircle(Offset(w * 0.92, h * 1.02), r, line);
        }
      case 'geo':
        final pg = Paint()..color = ink.withValues(alpha: 0.07);
        canvas.drawPath(Path()..moveTo(w * 0.45, h)..lineTo(w, h * 0.18)..lineTo(w, h)..close(), pg);
        canvas.drawPath(Path()..moveTo(w * 0.7, h)..lineTo(w, h * 0.55)..lineTo(w, h)..close(), pg);
        canvas.drawPath(Path()..moveTo(w * 0.62, 0)..lineTo(w * 0.86, 0)..lineTo(w * 0.5, h * 0.62)..close(), pg);
      case 'glow':
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0.75, -0.8),
              radius: 0.9,
              colors: [ink.withValues(alpha: 0.28), ink.withValues(alpha: 0)],
            ).createShader(Offset.zero & size),
        );
      case 'confetti':
        final rnd = math.Random(7);
        final cp = Paint()
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 38; i++) {
          final x = rnd.nextDouble() * w, y = rnd.nextDouble() * h, a = rnd.nextDouble() * math.pi;
          cp.color = (i % 3 == 0 ? (accent ?? MC.gold) : ink).withValues(alpha: 0.16);
          canvas.drawLine(Offset(x, y), Offset(x + math.cos(a) * 6, y + math.sin(a) * 6), cp);
        }
    }
    final acc = accent;
    if (acc != null) {
      canvas.drawRect(Rect.fromLTWH(0, h - 5, w, 5), Paint()..color = acc.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(covariant CardPatternPainter old) => old.pattern != pattern || old.ink != ink || old.accent != accent;
}

// ---------------------------------------------------------------- Kredi satırı

class LoanRow extends StatelessWidget {
  const LoanRow({super.key, required this.debt});

  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final info = ctx.model.debts[debt.id];
    if (info == null) return const SizedBox.shrink();
    final thisM = info.months[ctx.cur];
    final monthly = thisM != null && thisM.planned > 0
        ? thisM.planned
        : (info.nextPlanned != null ? (info.months[info.nextPlanned]?.planned ?? 0) : 0);
    final left = info.installmentsLeft(ctx.cur);
    final closed = info.current == 0;
    final bits = <String>[];
    if (monthly > 0) bits.add('${fmtMoney(monthly, lang: s.lang, hidden: st.hidden)} / ${s.pick('ay', 'mo')}');
    if (left > 0) bits.add(s.pick('$left taksit kaldı', '$left instalments left'));
    if (info.lastPlanned != null && !closed) bits.add(s.pick('bitiş ', 'ends ') + monthLabel(info.lastPlanned, s.lang));
    if (debt.payDay != null) bits.add(dayOfMonthText(debt.payDay!, s.lang));
    final linked = linkedExpenses(ctx.data, debt.id);
    if (debt.schedule.isEmpty && linked.isNotEmpty) {
      final names = linked.map((r) => r.name).join(', ');
      bits.add(s.pick('ödemesi "$names" giderinde', 'paid through "$names"'));
    }
    final p = info.gross > 0 ? ((info.gross - info.current) / info.gross).clamp(0.0, 1.0).toDouble() : 1.0;
    final type = (kDebtTypes[debt.type] ?? const Lbl('Borç', 'Debt')).of(s.lang);
    return RowItem(
      leading: BankPlate(bankKey: bankKeyOf(debt), name: debt.creditor, size: 38),
      title: '${debt.creditor.isEmpty ? s.pick('Borç', 'Debt') : debt.creditor} · $type${closed ? ' · ${s.pick('Kapandı', 'Closed')}' : ''}',
      subtitle: [
        bits.isEmpty ? s.pick('Ödeme planı yok', 'No payment plan') : bits.join(' · '),
        if (debt.schedule.isNotEmpty && info.unplanned > 0)
          s.pick('Kalan taksitlerin toplamı borcundan ${fmtMoney(info.unplanned, lang: s.lang, hidden: st.hidden)} az; son taksiti kontrol et.',
              'Remaining instalments add up to ${fmtMoney(info.unplanned, lang: s.lang, hidden: st.hidden)} less than the debt; check the last one.'),
      ].join('\n'),
      trailing: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(s.pick('Kalan · %${(p * 100).round()} ödendi', 'Left · ${(p * 100).round()}% paid'), style: sans(11, color: MC.muted)),
            const SizedBox(height: 2),
            MoneyText(info.current, style: sans(16, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            ProgressLine(p, color: MC.mint, height: 4),
          ],
        ),
      ),
      onTap: () => openDebtSheet(context, debt: debt),
    );
  }
}
