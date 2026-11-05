// Sayfalar arasında ortak parçalar: hareket satırı, kart görseli, kredi satırı, paneller.

import 'package:flutter/material.dart';

import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../card_art.dart';
import '../glass.dart';
import '../i18n.dart';
import '../sheet.dart';
import '../sheets/debts.dart';
import '../sheets/money.dart';
import '../sheets/plans.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

// ---------------------------------------------------------------- Düzenleme panellerini açanlar

void openTransferSheet(BuildContext context, {Transfer? transfer, String? from, String? to}) =>
    showEditSheet<void>(context, builder: (_) => TransferSheet(transfer: transfer, from: from, to: to));
void openAccountSheet(BuildContext context, {String? bank, String? type, Account? account}) =>
    showEditSheet<void>(context, builder: (_) => AccountSheet(account: account, bank: bank, type: type));
void openCardSheet(BuildContext context, {String? bank, BankCard? card}) => showEditSheet<void>(context, builder: (_) => CardSheet(card: card, bank: bank));
void openDebtSheet(BuildContext context, {Debt? debt, String? type}) => showEditSheet<void>(context, builder: (_) => DebtSheet(debt: debt, type: type));
void openSpendSheet(BuildContext context, {Spend? spend, Json? prefill}) => showEditSheet<void>(context, builder: (_) => SpendSheet(spend: spend, prefill: prefill));
void openQuickSpendSheet(BuildContext context, {String? source}) => showEditSheet<void>(context, builder: (_) => QuickSpendSheet(source: source));
void openSubSheet(BuildContext context, {Subscription? sub, Json? prefill}) => showEditSheet<void>(context, builder: (_) => SubSheet(sub: sub, prefill: prefill));
void openBillAmountSheet(BuildContext context, Subscription sub, String month) =>
    showEditSheet<void>(context, builder: (_) => BillAmountSheet(sub: sub, month: month));
void openGoalSheet(BuildContext context, {Goal? goal, Json? prefill}) => showEditSheet<void>(context, builder: (_) => GoalSheet(goal: goal, prefill: prefill));
void openGoalSaveSheet(BuildContext context, Goal goal) => showEditSheet<void>(context, builder: (_) => ContributionSheet(goal: goal));
void openGoalBuySheet(BuildContext context, Goal goal) => openSpendSheet(context, prefill: {
      'goalId': goal.id,
      'name': goal.name,
      'amount': goal.target,
      'category': 'alisveris',
      'url': goal.url,
    });
void openPaySheet(BuildContext context, PlanItem item, String month) =>
    showEditSheet<void>(context, builder: (_) => PaySheet(kind: item.kind, refId: item.refId, month: item.fromMonth ?? month));
void openPayRef(BuildContext context, String kind, String refId, String month) =>
    showEditSheet<void>(context, builder: (_) => PaySheet(kind: kind, refId: refId, month: month));
void openCardPaySheet(BuildContext context, {Debt? debt}) => showEditSheet<void>(context, builder: (_) => CardPaySheet(debt: debt));
void openStatementSheet(BuildContext context, Debt debt, {String? month}) =>
    showEditSheet<void>(context, builder: (_) => StatementSheet(debt: debt, month: month));
void openCardBalanceSheet(BuildContext context, Debt debt) => showEditSheet<void>(context, builder: (_) => CardBalanceSheet(debt: debt));
void openFindeksSheet(BuildContext context, {Findeks? entry}) {
  int? index;
  if (entry != null) {
    final list = AppScope.of(context).data.findeks;
    for (var i = 0; i < list.length; i++) {
      if (list[i].date == entry.date) index = i;
    }
  }
  showEditSheet<void>(context, builder: (_) => FindeksSheet(index: index));
}

void openIncomeSheet(BuildContext context, {Income? income}) => showEditSheet<void>(context, builder: (_) => IncomeSheet(income: income));
void openOneOffIncomeSheet(BuildContext context, OneOffIncome income) => showEditSheet<void>(context, builder: (_) => OneOffIncomeSheet(income: income));
void openIncomeActualSheet(BuildContext context, Income income, String month) =>
    showEditSheet<void>(context, builder: (_) => IncomeActualSheet(income: income, month: month));
void openExpenseSheet(BuildContext context, {RecurringExpense? expense}) => showEditSheet<void>(context, builder: (_) => ExpenseSheet(expense: expense));
void openSpendSheetFor(BuildContext context, {String? source}) => openSpendSheet(context, prefill: {'source': source});

// ---------------------------------------------------------------- Kaynak etiketi

/// Ödeme kaynağı etiketi: banka plakası ve hesap/kart adı.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source, this.compact = false});

  final String? source;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final sb = sourceBank(d, source);
    final name = source == null || source!.isEmpty ? s.pick('kaynak yok', 'no source') : sourceName(d, source, s.lang);
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 150 : 210),
      padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
      decoration: BoxDecoration(
        color: const Color(0x2E000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sb != null && !sb.cash)
            BankPlate(bankKey: sb.key, name: sb.name, size: 16)
          else
            Icon(source == null ? Icons.help_outline : Icons.payments_outlined, size: 15, color: MC.muted),
          const SizedBox(width: 6),
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11.5, color: MC.muted))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Hareketler

/// Harcama satırının başı (eski uygulamadaki gibi): adı ya da yeri bilinen bir markaysa logosu,
/// değilse kategori simgesi. Logo kategori simgesinden biraz küçüktür; yazılar aynı hizada kalır.
Widget spendLead(String name, String place, String? category, {double size = 38}) {
  final b = spendBrand(name, place);
  if (b == null) return CategoryMark(category, size: size);
  return SizedBox.square(dimension: size, child: Center(child: BrandMark(name, look: b, size: size * 0.8)));
}

/// Abonelik ya da fatura satırının başı: logosu; markası bilinmiyorsa türüne göre simge ya da baş harfler.
Widget subLead(String name, {double size = 38}) =>
    SizedBox.square(dimension: size, child: Center(child: BrandMark(name, size: size * 0.8)));

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
        leading = spendLead(mv.name, mv.place, mv.cat);
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
      onTap: () {
        switch (mv.t) {
          case 'spend':
            for (final x in d.spends) {
              if (x.id == mv.id) return openSpendSheet(context, spend: x);
            }
          case 'transfer':
            for (final x in d.transfers) {
              if (x.id == mv.id) return openTransferSheet(context, transfer: x);
            }
          default:
            final kind = mv.kind, ref = mv.ref, month = mv.month;
            if (kind != null && ref != null && month != null) openPayRef(context, kind, ref, month);
        }
      },
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
    final darkInk = look.ink == 'dark';
    final soft = ink.withValues(alpha: 0.8);
    final kind = kindLabel.of(s.lang);
    final lowerName = trLower(name);
    final showKind = kind.isNotEmpty &&
        !lowerName.contains(trLower(kind)) &&
        !lowerName.contains('${trLower(kind.split(' ').first)} kart');
    final used = limitK != null && limitK! > 0 && debtK != null ? (debtK! / limitK!).clamp(0.0, 1.0).toDouble() : null;
    // Eski uygulamadaki kart: gerçek kart oranı (1,586), yuvarlak köşeler, logo solda, kart adı sağda.
    final height = width / 1.586;
    final radius = BorderRadius.circular(15);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BankPlate(bankKey: bankKey, name: name, size: 22),
            const SizedBox(width: 8),
            const Spacer(),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width * 0.64),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(name.isEmpty ? kind : name,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11.5, weight: FontWeight.w700, color: ink, letterSpacing: 0.46, height: 1.25)),
                if (showKind) ...[
                  const SizedBox(height: 2),
                  Text(trUpper(kind), maxLines: 1, style: sans(8.5, weight: FontWeight.w600, color: ink.withValues(alpha: 0.75), letterSpacing: 1.36)),
                ],
              ]),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          const CardChip(),
          const Spacer(),
          if (network != null)
            Text(network!, style: TextStyle(fontFamily: MC.sans, fontSize: 12, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, color: ink.withValues(alpha: 0.92))),
        ]),
        const Spacer(),
        if (midLabel.tr.isNotEmpty) Text(midLabel.of(s.lang), style: sans(10, color: soft, letterSpacing: 0.2)),
        if (midValue != null) MoneyText(midValue!, style: sans(width < 260 ? 16 : 18, weight: FontWeight.w700, color: ink, height: 1.2)),
        if (used != null) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 4,
              color: (darkInk ? Colors.black : Colors.white).withValues(alpha: 0.24),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(widthFactor: used, heightFactor: 1, child: ColoredBox(color: ink)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(s.pick('Borç ', 'Debt ') + (st.hidden ? '•••' : fmtNum(debtK!, lang: s.lang)), style: sans(10, color: ink.withValues(alpha: 0.9))),
              const Spacer(),
              Text('Limit ${st.hidden ? '•••' : fmtNum(limitK!, lang: s.lang)}', style: sans(10, color: ink.withValues(alpha: 0.9))),
            ],
          ),
        ],
      ],
    );
    Widget tile = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: CardArtPainter(c1: look.c1, c2: look.c2, pattern: look.pattern, darkInk: darkInk, accent: look.accent)),
            Padding(padding: EdgeInsets.fromLTRB(look.accent != null ? 19 : 15, 13, 15, 13), child: content),
            const IgnorePointer(child: CustomPaint(painter: CardShinePainter())),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: darkInk ? const Color(0x1A000000) : const Color(0x1FFFFFFF)),
                ),
              ),
            ),
            if (closed) ClosedRibbon(text: s.pick('KAPALI', 'CLOSED')),
          ],
        ),
      ),
    );
    if (closed) tile = ColorFiltered(colorFilter: kClosedCardFilter, child: tile);
    final d = debt;
    final c = card;
    final tap = onTap ??
        (c != null
            ? () => openCardSheet(context, card: c)
            : d != null
                ? () => openDebtSheet(context, debt: d)
                : null);
    if (tap == null) return tile;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: tap, child: tile));
  }
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
      leading: BankPlate(bankKey: bankKeyOf(debt), name: debt.creditor, size: 28),
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
