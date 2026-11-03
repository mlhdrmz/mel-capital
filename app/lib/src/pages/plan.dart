import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/actions.dart';
import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../celebrate.dart';
import '../glass.dart';
import '../i18n.dart';
import '../sheet.dart';
import '../sheets/plans.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';
import 'common.dart';
import 'harcamalar.dart' show Monogram;

const Color kIncomeColor = Color(0xFF9FD7A5);

/// Kısa tutar (takvim ve grafik için): 12,5B · 1,2M.
String shortMoney(int k, String lang, bool hidden) {
  if (hidden) return '•••';
  final tl = k.abs() / 100;
  String one(double v) {
    if (v >= 100) return v.round().toString();
    final r = (v * 10).round() / 10;
    final t = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
    return lang == 'tr' ? t.replaceAll('.', ',') : t;
  }

  final s = tl >= 1e6
      ? '${one(tl / 1e6)}M'
      : tl >= 1000
          ? '${one(tl / 1000)}${lang == 'tr' ? 'B' : 'k'}'
          : tl.round().toString();
  return (k < 0 ? '−' : '') + s;
}

/// "6 Kasım'da" / "on November 6".
String dayMonthLoc(int day, String m, String lang) {
  if (!isMonth(m)) return lang == 'tr' ? 'belirtilmemiş' : 'not set';
  if (lang == 'tr') return '$day ${kMonthsLocTr[int.parse(m.substring(5, 7)) - 1]}';
  return 'on ${monthName(m, lang)} $day';
}

/// Plan kaleminin alt satırı.
String itemSub(Ctx ctx, PlanItem it, String m, String lang, bool hidden) {
  String money(int k) => fmtMoney(k, lang: lang, hidden: hidden);
  String pick(String tr, String en) => lang == 'tr' ? tr : en;
  String base() {
    final d = ctx.data;
    if (it.kind == 'debt') {
      final debt = d.debt(it.refId);
      final info = ctx.model.debts[it.refId];
      if (debt == null || info == null) return '';
      if (it.card) {
        final st = it.st;
        if (st != null) {
          final parts = [pick('Ekstre ', 'Statement ') + money(toK(st.total))];
          if (debt.payPlan == 'tamami') {
            parts.add(pick('tamamı ödenecek', 'paid in full'));
          } else if (st.minimum != null) {
            parts.add(pick('asgari ', 'minimum ') + money(toK(st.minimum)));
          }
          if (debt.dueDay != null) parts.add(pick('son ödeme ', 'due ') + dayMonth(debt.dueDay, m, lang));
          return parts.join(' · ');
        }
        if (it.pay != null) return pick('Ekstre girilmedi', 'No statement entered');
        final pct = (kMinPayRate * 100).round();
        final parts = [
          debt.statementDay != null
              ? pick('Ekstre ${dayMonthLoc(debt.statementDay!, cutMonthOf(debt, m), lang)} kesilir', 'Statement cut ${dayMonthLoc(debt.statementDay!, cutMonthOf(debt, m), lang)}')
              : pick('Ekstre bekleniyor', 'Statement expected'),
          pick("tahmini asgari (borcun %$pct'si)", 'estimated minimum ($pct% of the debt)'),
        ];
        if (debt.dueDay != null) parts.add(pick('son ödeme ', 'due ') + dayMonth(debt.dueDay, m, lang));
        if (it.instK > 0) parts.add(pick('taksitler ', 'instalments ') + money(it.instK));
        return parts.join(' · ');
      }
      final left = info.installmentsLeft(m);
      final bits = [(kDebtTypes[debt.type] ?? const Lbl('Borç', 'Debt')).of(lang)];
      if (left > 0) bits.add(pick('$left taksit kaldı', '$left instalments left'));
      if (info.lastPlanned != null) bits.add(pick('bitiş ', 'ends ') + monthLabel(info.lastPlanned, lang));
      return bits.join(' · ');
    }
    if (it.kind == 'sub') {
      final s = d.subscription(it.refId);
      if (s == null) return pick('Abonelik', 'Subscription');
      final bits = [s.isBill ? pick('Fatura', 'Bill') : pick('Abonelik', 'Subscription')];
      if (s.isBill) {
        bits.add(it.monthSet ? pick('${monthName(m, lang)} faturası', '${monthName(m, lang)} bill') : pick('tahmini; gelince tutarı gir', 'estimated; enter the amount when it arrives'));
      } else if (s.period == 'yil' && s.amount != null) {
        bits.add(pick('yıllık ${money(toK(s.amount))}, aylık payı', 'yearly ${money(toK(s.amount))}, monthly share'));
      }
      if (s.source != null) bits.add(sourceName(d, s.source, lang));
      return bits.join(' · ');
    }
    final linked = [for (final id in it.linked) d.debt(id)].whereType<Debt>().map((x) => x.creditor).toList();
    return catLabel(it.category, lang) + (linked.isEmpty ? '' : ' · ${linked.join(', ')}');
  }

  final b = base();
  return it.carry ? pick('${monthName(it.fromMonth, lang)} ayından taşındı · $b', 'moved from ${monthName(it.fromMonth, lang)} · $b') : b;
}

/// Ödendi işaretini koyar ya da kaldırır (geri alınabilir).
void togglePay(BuildContext context, PlanItem it, String m) {
  final st = AppScope.of(context);
  final s = S.of(context);
  if (it.carriedOut) return;
  final pm = it.fromMonth ?? m; // taşınan kalemin ödemesi asıl ayına yazılır
  final snap = st.snapshot();
  if (it.pay != null) {
    st.update((d) => removePaymentFor(d, it.kind, it.refId, pm));
    toast(context, s.pick('"Ödendi" işareti kaldırıldı.', '"Paid" mark removed.'), undo: () => st.restore(snap));
    return;
  }
  if (it.planned <= 0) {
    openPaySheet(context, it, m);
    return;
  }
  final before = st.ctx.model;
  String? from;
  st.update((d) => from = markPaid(d, before, it, pm));
  final closed = closedDebts(st.data, before, st.ctx.model);
  final fromTxt = from != null
      ? s.pick(' ${sourceName(st.data, from, s.lang)} hesabından düşüldü.', ' Taken from ${sourceName(st.data, from, s.lang)}.')
      : s.pick(' Hesap seçmek için satıra dokun.', ' Tap the row to pick an account.');
  final closedTxt = closed.isEmpty
      ? ''
      : s.pick(' ${closed.map((x) => x.creditor).join(', ')} borcu kapandı!', ' ${closed.map((x) => x.creditor).join(', ')} is paid off!');
  toast(context, s.pick('Ödendi.', 'Paid.') + fromTxt + closedTxt, undo: () => st.restore(snap), seconds: 6);
  if (closed.isNotEmpty) celebrate(context);
}

// ---------------------------------------------------------------- Sayfa

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  String? _month;
  int? _day;
  int _range = 12;
  bool _defs = false;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    final cur = ctx.cur;
    final base = ctx.model.base;
    var m = _month ?? ctx.defaultPlanMonth();
    if (m.compareTo(base) < 0) m = base;
    final sum = ctx.sum(m);
    final nm = addM(m, 1);
    final closed = sum.close;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final its = sum.items.toList()
      ..sort((a, b) {
        final c = (a.day ?? 32) - (b.day ?? 32);
        return c != 0 ? c : b.planned - a.planned;
      });
    final live = its.where((it) => !it.carriedOut && it.planned > 0).toList();
    final openN = live.where((it) => it.pay == null).length;
    final hasInc = sum.income > 0 || sum.carryIn != 0;
    final statusText = closed != null
        ? s.pick('kapatıldı', 'closed')
        : m.compareTo(cur) < 0
            ? s.pick('kapatılmadı', 'not closed')
            : m == cur
                ? s.pick('bu ay', 'this month')
                : s.pick('ileri ay', 'coming month');
    final paidP = sum.total > 0 ? sum.paid / sum.total : 0.0;

    void go(String month) => setState(() {
          _month = month;
          _day = null;
        });

    final header = <Widget>[
      _IconBtn(icon: Icons.chevron_left, tip: s.pick('Önceki ay', 'Previous month'), onTap: m.compareTo(base) <= 0 ? null : () => go(addM(m, -1))),
      _IconBtn(icon: Icons.chevron_right, tip: s.pick('Sonraki ay', 'Next month'), onTap: () => go(nm)),
      if (m != cur) GlassButton(label: s.pick('Bu ay', 'This month'), onTap: () => go(cur)),
      closed != null
          ? GlassButton(label: s.pick('Kapatmayı geri al', 'Reopen month'), icon: Icons.undo, onTap: () => openCloseMonthSheet(context, m, reopen: true))
          : GoldButton(label: s.pick('Ayı kapat', 'Close the month'), icon: Icons.lock_outline, onTap: () => openCloseMonthSheet(context, m)),
    ];

    return PageFrame(
      eyebrow: '${s.pick('PLAN', 'PLAN')} · ${s.isTr ? trUpper(statusText) : statusText.toUpperCase()}',
      title: monthLabel(m, s.lang),
      actions: header,
      children: [
        if (closed != null)
          _Strip(
            color: MC.mint,
            icon: Icons.lock_outline,
            text: [
              s.pick('${monthLabel(m, s.lang)} kapatıldı', '${monthLabel(m, s.lang)} is closed'),
              if (closed.carry.isNotEmpty) s.pick('${closed.carry.length} kalem ${monthName(nm, s.lang)} ayına taşındı', '${closed.carry.length} items moved to ${monthName(nm, s.lang)}'),
              if (closed.carryCash && hasInc) s.pick('${money(sum.free)} ${monthName(nm, s.lang)} ayına devredildi', '${money(sum.free)} carried over to ${monthName(nm, s.lang)}'),
            ].join(' · '),
            action: SmallButton(label: s.pick('${monthName(nm, s.lang)} planı', '${monthName(nm, s.lang)} plan'), icon: Icons.chevron_right, onTap: () => go(nm)),
          )
        else if (m.compareTo(cur) < 0 && openN > 0)
          _Strip(
            color: MC.gold,
            icon: Icons.info_outline,
            text: s.pick(
              'Bu ay kapatılmadı: $openN kalem ödenmedi olarak duruyor. Ödediklerini işaretle, kalanları "Ayı kapat" ile ${monthName(nm, s.lang)} ayına taşıyabilirsin.',
              'This month is not closed: $openN items are still open. Mark what you paid; move the rest to ${monthName(nm, s.lang)} with "Close the month".',
            ),
          ),
        KpiRow(children: [
          Kpi(
            label: s.pick('Gelir', 'Income'),
            k: sum.income + sum.carryIn,
            sub: sum.carryIn != 0 ? s.pick('Devreden ${money(sum.carryIn)} dahil', 'Including ${money(sum.carryIn)} carried over') : s.pick('${sum.incomeItems.length} kalem', '${sum.incomeItems.length} items'),
            color: MC.mint,
            delay: const Duration(milliseconds: 40),
          ),
          Kpi(
            label: s.pick('Ödemeler', 'Payments'),
            k: sum.total,
            sub: sum.estK > 0 ? s.pick('Tahmini kart asgarisi ${money(sum.estK)} dahil', 'Including estimated card minimum ${money(sum.estK)}') : s.pick('${live.length} kalem', '${live.length} items'),
            color: MC.rose,
            delay: const Duration(milliseconds: 80),
          ),
          Kpi(
            label: s.pick('Ödenen', 'Paid'),
            k: sum.paid,
            sub: s.pick('%${(paidP * 100).round()} tamamlandı', '${(paidP * 100).round()}% done'),
            color: MC.sky,
            delay: const Duration(milliseconds: 120),
            footer: ProgressLine(paidP, color: MC.mint, height: 4),
          ),
          Kpi(
            label: s.pick('Kalan ödeme', 'Left to pay'),
            k: sum.unpaid,
            sub: openN > 0 ? s.pick('$openN kalem bekliyor', '$openN items open') : (live.isNotEmpty ? s.pick('Hepsi ödendi', 'All paid') : s.pick('Kalem yok', 'Nothing due')),
            color: MC.gold,
            delay: const Duration(milliseconds: 160),
          ),
          if (m == cur && sum.safe != null)
            Kpi(
              label: s.pick('Ay sonuna kadar serbest', 'Free until month end'),
              k: sum.safe!,
              sub: s.pick(
                'Hesaplarda ${money(ctx.model.liquid)}${(sum.incomeRest ?? 0) > 0 ? ' · yatacak ${money(sum.incomeRest!)}' : ''} · ödenecek ${money(sum.unpaid)}',
                'In accounts ${money(ctx.model.liquid)}${(sum.incomeRest ?? 0) > 0 ? ' · coming in ${money(sum.incomeRest!)}' : ''} · to pay ${money(sum.unpaid)}',
              ),
              color: sum.safe! < 0 ? MC.rose : MC.violet,
              delay: const Duration(milliseconds: 200),
            )
          else
            Kpi(
              label: s.pick('Serbest kalan', 'Left free'),
              k: hasInc ? sum.free : 0,
              text: hasInc ? null : '—',
              sub: hasInc
                  ? (sum.estSpend > 0
                      ? s.pick('Tahmini harcama ${money(sum.estSpend)} düşüldü', 'Estimated spending ${money(sum.estSpend)} deducted')
                      : s.pick('Harcamalar ${money(sum.spent)}${sum.savings > 0 ? ' · birikim ${money(sum.savings)}' : ''} düşüldü', 'Spending ${money(sum.spent)}${sum.savings > 0 ? ' · savings ${money(sum.savings)}' : ''} deducted'))
                  : s.pick('Gelir girilmedi', 'No income entered'),
              color: hasInc && sum.free < 0 ? MC.rose : MC.violet,
              delay: const Duration(milliseconds: 200),
            ),
        ]),
        const SizedBox(height: 14),
        TwoColumns(
          leftFlex: 13,
          rightFlex: 10,
          left: GlassPanel(
            delay: const Duration(milliseconds: 220),
            radius: 30,
            cut: 30,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PanelHead(s.pick('Ödeme takvimi', 'Payment calendar'), subtitle: s.pick('Güne dokun · yuvarlak: ödendi · satır: düzenle', 'Tap a day · circle: paid · row: edit')),
              _Calendar(ctx: ctx, sum: sum, month: m, selected: _day, onSelect: (dd) => setState(() => _day = _day == dd ? null : dd)),
            ]),
          ),
          right: GlassPanel(
            delay: const Duration(milliseconds: 260),
            radius: 30,
            cut: 30,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PanelHead(s.pick('Aylık bilanço', 'Monthly balance'), subtitle: monthLabel(m, s.lang)),
              _Balance(ctx: ctx, sum: sum),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        _GroupsGrid(ctx: ctx, sum: sum, month: m, items: its),
        const SizedBox(height: 14),
        TwoColumns(
          leftFlex: 1,
          rightFlex: 1,
          left: _MonthsTable(
            ctx: ctx,
            selected: m,
            range: _range,
            onRange: (v) => setState(() => _range = v),
            onPick: go,
          ),
          right: Column(children: [
            GlassPanel(
              delay: const Duration(milliseconds: 320),
              radius: 30,
              cut: 30,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PanelHead(s.pick('Gelir ve çıkışlar', 'Income and outgoings'), subtitle: s.pick('Çubuğa dokun: o ayın planı', 'Tap a bar to open that month')),
                _FlowChart(ctx: ctx, months: _rangeMonths(ctx), selected: m, onPick: go),
              ]),
            ),
            const SizedBox(height: 14),
            GlassPanel(
              delay: const Duration(milliseconds: 360),
              radius: 30,
              cut: 30,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PanelHead(s.pick('Net değer', 'Net worth'), subtitle: s.pick('Hesaplardaki para − tüm borçlar', 'Money in accounts − all debts')),
                _NetWorth(ctx: ctx),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        _Definitions(ctx: ctx, month: m, open: _defs, onToggle: () => setState(() => _defs = !_defs)),
        if (d.debts.isEmpty && d.incomes.isEmpty && d.recurringExpenses.isEmpty && d.subscriptions.isEmpty) ...[
          const SizedBox(height: 14),
          EmptyCard(
            icon: Icons.calendar_month_outlined,
            title: s.pick('Plan boş', 'The plan is empty'),
            text: s.pick('Gelirini, sabit giderlerini, aboneliklerini ve borçlarını ekledikçe her ayın ödemeleri burada kendiliğinden dizilir.',
                'As you add your income, fixed costs, subscriptions and debts, each month\'s payments line up here by themselves.'),
          ),
        ],
      ],
    );
  }

  List<String> _rangeMonths(Ctx ctx) {
    final from = maxMonth(ctx.cur, ctx.model.base);
    return [for (var i = 0; i < _range; i++) addM(from, i)];
  }
}

/// Ayı kapatır ya da geri açar.
void openCloseMonthSheet(BuildContext context, String month, {bool reopen = false}) {
  final st = AppScope.of(context);
  final s = S.of(context);
  if (reopen) {
    reopenMonthDialog(context, month);
    return;
  }
  final nm = addM(month, 1);
  if (st.data.closeOf(nm) != null) {
    toast(context, s.pick('${monthLabel(nm, s.lang)} zaten kapalı. Önce onu geri aç.', '${monthLabel(nm, s.lang)} is already closed. Reopen it first.'));
    return;
  }
  showEditSheet<void>(context, builder: (_) => CloseMonthSheet(month: month), width: 640);
}

// ---------------------------------------------------------------- Parçalar

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          foregroundColor: MC.text,
          disabledForegroundColor: MC.dim.withValues(alpha: 0.4),
          backgroundColor: const Color(0x38000000),
          side: const BorderSide(color: Color(0x40FFFFFF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          fixedSize: const Size(46, 46),
        ),
      );
}

class _Strip extends StatelessWidget {
  const _Strip({required this.color, required this.icon, required this.text, this.action});

  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassPanel(
        tint: color,
        radius: 20,
        cut: 20,
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: sans(13.5, height: 1.4))),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ]),
      ),
    );
  }
}

/// Ödeme satırı: tarih, simge, ad ve açıklama, tutar, ödendi düğmesi.
class PayRow extends StatelessWidget {
  const PayRow({super.key, required this.ctx, required this.item, required this.month});

  final Ctx ctx;
  final PlanItem item;
  final String month;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final it = item;
    final m = month;
    final pay = it.pay;
    final paid = pay != null;
    final amtK = pay?.k ?? it.planned;
    final todayD = dayOf(todayISO());
    final late = !paid && !it.carriedOut && it.planned > 0 && (m.compareTo(ctx.cur) < 0 || (m == ctx.cur && it.day != null && it.day! < todayD));
    String sub;
    if (it.carriedOut) {
      sub = s.pick('${monthName(addM(m, 1), s.lang)} ayına taşındı', 'moved to ${monthName(addM(m, 1), s.lang)}');
    } else if (pay != null) {
      final bits = [s.pick('Ödendi', 'Paid')];
      if (isDate(pay.paidDate)) bits.add(fmtDayShort(pay.paidDate, s.lang));
      String? fa;
      for (final p in pay.list) {
        if (p.fromAccount != null) {
          fa = p.fromAccount;
          break;
        }
      }
      if (fa != null) bits.add(sourceName(ctx.data, fa, s.lang));
      if (it.planned > 0 && amtK != it.planned && !it.pending && !it.est) bits.add(s.pick('plan ', 'plan ') + fmtMoney(it.planned, lang: s.lang, hidden: st.hidden));
      sub = bits.join(' · ');
    } else {
      sub = itemSub(ctx, it, m, s.lang, st.hidden);
    }
    final mo = int.parse(m.substring(5, 7)) - 1;
    Widget lead;
    if (it.bank != null) {
      lead = BankPlate(bankKey: it.bank, name: it.name, size: 30);
    } else if (it.kind == 'sub' || it.kind == 'expense') {
      lead = Monogram(name: it.name, group: it.kind == 'sub' ? ctx.data.subscription(it.refId)?.group : null, size: 38);
    } else {
      lead = BankPlate(name: it.name, size: 30);
    }
    final amount = it.est && !paid
        ? Tooltip(
            message: s.pick("Ekstre girilmedi; borcun %${(kMinPayRate * 100).round()}'si kadar asgari ödeme tahmini", 'No statement yet; estimated minimum of ${(kMinPayRate * 100).round()}% of the debt'),
            child: Text('(${fmtMoney(it.planned, lang: s.lang, hidden: st.hidden)})', style: sans(14.5, weight: FontWeight.w700, color: MC.muted)),
          )
        : MoneyText(amtK, style: sans(14.5, weight: FontWeight.w700, color: paid ? MC.muted : MC.text));
    return Opacity(
      opacity: it.carriedOut ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
            width: 40,
            child: Column(children: [
              Text(it.day?.toString() ?? '–', style: serif(21, color: late ? MC.rose : MC.text)),
              Text((s.isTr ? kMonthsShortTr : kMonthsShortEn)[mo].toUpperCase(), style: sans(9.5, color: MC.muted, letterSpacing: 0.8)),
            ]),
          ),
          const SizedBox(width: 10),
          lead,
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: it.carriedOut ? null : () => openPaySheet(context, it, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(14.5, weight: FontWeight.w600, color: paid ? MC.muted : MC.text)),
                    ),
                    if (late || it.carry)
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (late) _Tag(text: s.pick('gecikti', 'late'), color: MC.rose),
                            if (it.carry) _Tag(text: s.pick('taşındı', 'moved'), color: MC.gold),
                          ]),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(12, color: MC.muted)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          amount,
          if (it.pending && !paid)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _SmallIcon(icon: Icons.receipt_long_outlined, tip: s.pick('Ekstre gir', 'Enter statement'), onTap: () {
                final debt = ctx.data.debt(it.refId);
                if (debt != null) openStatementSheet(context, debt, month: it.fromMonth ?? m);
              }),
            ),
          if (it.bill && !paid)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _SmallIcon(icon: Icons.edit_note, tip: s.pick('Bu ayın fatura tutarını gir', 'Enter this month\'s bill'), onTap: () {
                final sub = ctx.data.subscription(it.refId);
                if (sub != null) openBillAmountSheet(context, sub, it.fromMonth ?? m);
              }),
            ),
          const SizedBox(width: 8),
          if (it.carriedOut) const SizedBox(width: 34) else _Tick(on: paid, onTap: () => togglePay(context, it, m)),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(text, style: sans(10.5, weight: FontWeight.w700, color: color)),
      );
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        style: IconButton.styleFrom(
          foregroundColor: MC.text,
          backgroundColor: const Color(0x26000000),
          side: const BorderSide(color: Color(0x30FFFFFF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          fixedSize: const Size(32, 32),
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
        ),
      );
}

/// Ödendi düğmesi: boş halka → dolu yeşil onay.
class _Tick extends StatelessWidget {
  const _Tick({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Tooltip(
      message: on ? s.pick('Ödendi işaretini kaldır', 'Remove the paid mark') : s.pick('Ödendi olarak işaretle', 'Mark as paid'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? MC.mint : const Color(0x26000000),
              border: Border.all(color: on ? MC.mint : const Color(0x66FFFFFF), width: 1.6),
              boxShadow: on ? [BoxShadow(color: MC.mint.withValues(alpha: 0.35), blurRadius: 12)] : null,
            ),
            child: Icon(Icons.check, size: 19, color: on ? MC.ink : const Color(0x55FFFFFF)),
          ),
        ),
      ),
    );
  }
}

/// Gelir satırı.
class IncomeRow extends StatelessWidget {
  const IncomeRow({super.key, required this.ctx, required this.month, this.item, this.carryK});

  final Ctx ctx;
  final String month;
  final IncomeItem? item;
  final int? carryK;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final m = month;
    final mo = int.parse(m.substring(5, 7)) - 1;
    final inc = item;
    final k = inc?.k ?? carryK ?? 0;
    final String name;
    final String sub;
    if (inc == null) {
      name = s.pick('${monthName(addM(m, -1), s.lang)} ayından devreden', 'Carried over from ${monthName(addM(m, -1), s.lang)}');
      sub = s.pick('Önceki ay kapatılırken devredildi', 'Carried over when the previous month was closed');
    } else {
      name = inc.name.isEmpty ? s.pick('Gelir', 'Income') : inc.name;
      sub = inc.oneOff
          ? s.pick('Tek seferlik gelir', 'One-off income')
          : inc.actual
              ? s.pick('${monthName(m, s.lang)} ayında yatan', 'Received in ${monthName(m, s.lang)}') +
                  (inc.planned > 0 && inc.planned != inc.k ? ' · plan ${fmtMoney(inc.planned, lang: s.lang, hidden: AppScope.of(context).hidden)}' : '')
              : s.pick('Düzenli gelir', 'Regular income');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Text(inc == null ? '1' : (inc.payDay?.toString() ?? '–'), style: serif(21)),
            Text((s.isTr ? kMonthsShortTr : kMonthsShortEn)[mo].toUpperCase(), style: sans(9.5, color: MC.muted, letterSpacing: 0.8)),
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: kIncomeColor.withValues(alpha: 0.16),
            shape: SignatureBorder(cut: 9, radius: 11, side: BorderSide(color: kIncomeColor.withValues(alpha: 0.5))),
          ),
          child: inc == null ? const Icon(Icons.redo, size: 18, color: kIncomeColor) : Text('₺', style: serif(22, color: kIncomeColor)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: inc == null
                ? null
                : inc.oneOff
                    ? () {
                        for (final o in ctx.data.oneOffIncomes) {
                          if (o.id == inc.id) return openOneOffIncomeSheet(context, o);
                        }
                      }
                    : () => openIncomeSheet(context, income: _incomeById(ctx.data, inc.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(14.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12, color: MC.muted)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        MoneyText(k, signed: true, style: sans(14.5, weight: FontWeight.w700), color: k < 0 ? MC.rose : MC.mint),
        const SizedBox(width: 8),
        if (inc != null && !inc.oneOff && m.compareTo(addM(currentMonth(), 1)) <= 0)
          Builder(builder: (context) {
            final full = _incomeById(ctx.data, inc.id);
            if (isPhoneLayout(context)) {
              return _SmallIcon(
                icon: inc.actual ? Icons.task_alt : Icons.download_done,
                tip: inc.actual ? s.pick('Yattı', 'Received') : s.pick('Bu ay yatan', 'Received'),
                onTap: () {
                  if (full != null) openIncomeActualSheet(context, full, m);
                },
              );
            }
            return SizedBox(
              width: 104,
              child: Align(
                alignment: Alignment.centerRight,
                child: SmallButton(
                  label: inc.actual ? s.pick('Yattı', 'Received') : s.pick('Bu ay yatan', 'Received'),
                  icon: inc.actual ? Icons.check : Icons.south_west,
                  onTap: full == null ? null : () => openIncomeActualSheet(context, full, m),
                ),
              ),
            );
          })
        else
          SizedBox(width: isPhoneLayout(context) ? 34 : 104),
      ]),
    );
  }
}

Income? _incomeById(Data d, String id) {
  for (final x in d.incomes) {
    if (x.id == id) return x;
  }
  return null;
}

// ---------------------------------------------------------------- Takvim

class _DayInfo {
  int out = 0;
  int inc = 0;
  final Set<String> groups = {};
  int n = 0;
  int open = 0;
  bool late = false;
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.ctx, required this.sum, required this.month, required this.selected, required this.onSelect});

  final Ctx ctx;
  final MonthSummary sum;
  final String month;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final m = month;
    final nD = daysInMonth(m);
    final first = (weekdayIndex('$m-01') + 6) % 7; // Pazartesi = 0
    final today = m == ctx.cur ? dayOf(todayISO()) : 0;
    final days = <int, _DayInfo>{};
    final noDay = <PlanItem>[];
    for (final it in sum.items) {
      if (it.carriedOut || !(it.planned > 0 || it.pay != null)) continue;
      final day = it.day;
      if (day == null) {
        noDay.add(it);
        continue;
      }
      final c = days.putIfAbsent(math.min(day, nD), _DayInfo.new);
      c.out += it.pay?.k ?? it.planned;
      c.groups.add(it.group);
      c.n++;
      if (it.pay == null) {
        c.open++;
        if (m.compareTo(ctx.cur) < 0 || (today > 0 && day < today)) c.late = true;
      }
    }
    for (final i in sum.incomeItems) {
      final pd = i.payDay;
      if (pd == null) continue;
      final c = days.putIfAbsent(math.min(pd, nD), _DayInfo.new);
      c.inc += i.k;
      c.groups.add('gelir');
    }
    final sel = selected != null && selected! <= nD ? selected : null;
    final weekNames = s.isTr ? const ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'] : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    Color dot(String g) => g == 'gelir' ? kIncomeColor : (kGroups[g]?.color ?? MC.muted);

    final cells = <Widget>[
      for (final w in weekNames) Center(child: Text(w, style: sans(11, color: MC.muted, weight: FontWeight.w600))),
      for (var i = 0; i < first; i++) const SizedBox(),
      for (var dd = 1; dd <= nD; dd++) _dayCell(context, st, s, dd, days[dd], today, sel, (first + dd - 1) % 7 >= 5, dot),
    ];
    Widget detail;
    if (sel != null) {
      final its = sum.items.where((it) => !it.carriedOut && it.day != null && math.min(it.day!, nD) == sel && (it.planned > 0 || it.pay != null)).toList();
      final incs = sum.incomeItems.where((i) => i.payDay != null && math.min(i.payDay!, nD) == sel).toList();
      final iso = '$m-${two(sel)}';
      detail = _CalDetail(
        title: '${dayMonth(sel, m, s.lang)} · ${weekdayName(iso, s.lang)}',
        onClose: () => onSelect(sel),
        children: [
          for (final i in incs) IncomeRow(ctx: ctx, month: m, item: i),
          for (final it in its) PayRow(ctx: ctx, item: it, month: m),
          if (incs.isEmpty && its.isEmpty) Text(s.pick('Bu gün için planlı kalem yok.', 'Nothing planned for this day.'), style: sans(13, color: MC.muted)),
        ],
      );
    } else if (noDay.isNotEmpty) {
      detail = _CalDetail(
        title: s.pick('Günü belirtilmemiş · ${noDay.length} kalem', 'No day set · ${noDay.length} items'),
        children: [for (final it in noDay) PayRow(ctx: ctx, item: it, month: m)],
      );
    } else {
      detail = Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(s.pick('Bir güne dokun: o günün ödemeleri burada açılır; tutarı, tarihi ve hesabı düzenleyebilirsin.', 'Tap a day to see its payments here; you can edit the amount, date and account.'),
            style: sans(12.5, color: MC.muted)),
      );
    }
    final legend = <(String, Color)>[
      (s.pick('Gelir', 'Income'), kIncomeColor),
      (s.pick('Kira ve faturalar', 'Rent and bills'), kGroups['sabit']!.color),
      (s.pick('Abonelikler', 'Subscriptions'), kGroups['abonelik']!.color),
      (s.pick('Taksitler', 'Instalments'), kGroups['taksit']!.color),
      (s.pick('Kartlar', 'Cards'), kGroups['kart']!.color),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, c) {
        final w = ((c.maxWidth - 6 * 6) / 7).floorToDouble();
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < cells.length; i++) SizedBox(width: w, height: i < 7 ? 20 : math.max(54, w * 0.72), child: cells[i]),
          ],
        );
      }),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (final l in legend)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: l.$2, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(l.$1, style: sans(11.5, color: MC.muted)),
          ]),
      ]),
      detail,
    ]);
  }

  Widget _dayCell(BuildContext context, AppState st, S s, int dd, _DayInfo? c, int today, int? sel, bool weekend, Color Function(String) dot) {
    final has = c != null;
    final done = c != null && c.n > 0 && c.open == 0;
    final late = c != null && c.late && sum.close == null;
    final on = dd == sel;
    final isToday = dd == today;
    final border = on
        ? MC.gold
        : isToday
            ? MC.gold.withValues(alpha: 0.6)
            : late
                ? MC.rose.withValues(alpha: 0.6)
                : const Color(0x1FFFFFFF);
    return InkWell(
      onTap: () => onSelect(dd),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: isPhoneLayout(context) ? const EdgeInsets.fromLTRB(4, 4, 4, 4) : const EdgeInsets.fromLTRB(7, 5, 7, 5),
        decoration: ShapeDecoration(
          color: on
              ? MC.gold.withValues(alpha: 0.22)
              : done
                  ? MC.mint.withValues(alpha: 0.10)
                  : has
                      ? const Color(0x33000000)
                      : const Color(0x14000000),
          shape: SignatureBorder(cut: 8, radius: 10, side: BorderSide(color: border, width: on || isToday ? 1.4 : 1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Günün noktaları: hücre darsa sığdığı kadar
          LayoutBuilder(builder: (context, box) {
            final room = box.maxWidth.isFinite ? ((box.maxWidth - 17) / 8).floor() : 4;
            final groups = c == null ? const <String>[] : c.groups.take(room < 0 ? 0 : (room > 4 ? 4 : room)).toList();
            return Row(children: [
              Text('$dd', style: sans(12.5, weight: FontWeight.w700, color: weekend ? MC.dim : MC.text)),
              const Spacer(),
              for (final g in groups)
                Container(margin: const EdgeInsets.only(left: 2), width: 6, height: 6, decoration: BoxDecoration(color: dot(g), shape: BoxShape.circle)),
            ]);
          }),
          const Spacer(),
          if (c != null && c.out > 0)
            Text(shortMoney(c.out, s.lang, st.hidden), maxLines: 1, style: sans(11, weight: FontWeight.w600, color: late ? MC.rose : (done ? MC.mint : MC.text))),
          if (c != null && c.inc > 0) Text('+${shortMoney(c.inc, s.lang, st.hidden)}', maxLines: 1, style: sans(11, weight: FontWeight.w600, color: kIncomeColor)),
        ]),
      ),
    );
  }
}

class _CalDetail extends StatelessWidget {
  const _CalDetail({required this.title, required this.children, this.onClose});

  final String title;
  final List<Widget> children;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const ShapeDecoration(
        color: Color(0x2A000000),
        shape: SignatureBorder(cut: 14, radius: 14, side: BorderSide(color: Color(0x26FFFFFF))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: sans(13.5, weight: FontWeight.w700))),
          if (onClose != null) SmallButton(label: s.pick('Kapat', 'Close'), icon: Icons.close, onTap: onClose),
        ]),
        ...children,
      ]),
    );
  }
}

// ---------------------------------------------------------------- Bilanço

class _Balance extends StatelessWidget {
  const _Balance({required this.ctx, required this.sum});

  final Ctx ctx;
  final MonthSummary sum;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final sm = sum;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    String nf(int k) => st.hidden ? '•••' : fmtNum(k, lang: s.lang);
    final lines = <Widget>[];
    void line(Color? color, String name, String value, {String? items, Color? valueColor, bool bold = false}) {
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (color != null) Padding(padding: const EdgeInsets.only(top: 5, right: 8), child: Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: sans(13.5, weight: bold ? FontWeight.w700 : FontWeight.w600)),
              if (items != null && items.isNotEmpty) Text(items, style: sans(11.5, color: MC.muted, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(value, style: bold ? serif(24, color: valueColor ?? MC.gold) : sans(13.5, weight: FontWeight.w700, color: valueColor ?? MC.text)),
        ]),
      ));
    }

    line(
      kIncomeColor,
      s.pick('Gelir', 'Income'),
      '+${money(sm.income)}',
      items: sm.incomeItems.isEmpty ? s.pick('Gelir girilmedi', 'No income entered') : sm.incomeItems.map((i) => '${i.name} ${nf(i.k)}').join(' · '),
      valueColor: MC.mint,
    );
    if (sm.carryIn != 0) {
      line(MC.gold, s.pick('${monthName(addM(sm.month, -1), s.lang)} ayından devreden', 'Carried over from ${monthName(addM(sm.month, -1), s.lang)}'),
          '${sm.carryIn > 0 ? '+' : ''}${money(sm.carryIn)}');
    }
    final planGroups = [
      ('sabit', s.pick('Kira ve faturalar', 'Rent and bills')),
      ('abonelik', s.pick('Abonelikler', 'Subscriptions')),
      ('taksit', s.pick('Borç taksitleri', 'Debt instalments')),
      ('kart', s.pick('Kart ödemeleri', 'Card payments')),
    ];
    for (final (key, label) in planGroups) {
      final its = sm.items.where((i) => i.group == key && (i.planned > 0 || i.pay != null) && !i.carriedOut).toList();
      if (its.isEmpty) continue;
      final est = its.any((i) => i.est);
      int kk(PlanItem i) => i.pay?.k ?? i.planned;
      line(
        kGroups[key]!.color,
        label + (est ? s.pick(' (tahmini asgari dahil)', ' (incl. estimated minimum)') : ''),
        '−${money(sumK(its, kk))}',
        items: its.map((i) => '${i.name} ${i.est ? '(${nf(i.planned)})' : nf(kk(i))}${i.pay != null ? ' ✓' : ''}').join(' · '),
      );
    }
    if (sm.carriedK > 0) {
      line(null, s.pick('${monthName(addM(sm.month, 1), s.lang)} ayına taşınan', 'Moved to ${monthName(addM(sm.month, 1), s.lang)}'), money(sm.carriedK),
          items: s.pick('Bu ayın toplamına katılmaz', 'Not counted in this month'), valueColor: MC.muted);
    }
    if (sm.spent > 0 || sm.spentCard > 0) {
      line(kGroups['harcama']!.color, s.pick('Harcamalar (hesaptan / nakit)', 'Spending (accounts / cash)'), '−${money(sm.spent)}',
          items: sm.spentCard > 0 ? s.pick('Kartla yapılan ${nf(sm.spentCard)} TL kartın ekstresiyle ödenir', '${nf(sm.spentCard)} TL by card is paid with the statement') : null);
    }
    if (sm.estSpend > 0) {
      final e = ctx.est;
      final basis = e.basisMonths.map((x) => monthShortLabel(x, s.lang)).join(', ');
      line(
        kGroups['harcama']!.color.withValues(alpha: 0.55),
        s.pick('Tahmini günlük harcama', 'Estimated everyday spending'),
        '−${money(sm.estSpend)}',
        items: (e.manual ? s.pick('Senin girdiğin tutar', 'The amount you entered') : s.pick('Son ayların ortalaması ($basis)', 'Average of recent months ($basis)')) +
            s.pick(' · hesaptan ve nakit, kira hariç', ' · accounts and cash, rent excluded'),
      );
    }
    if (sm.savings > 0) {
      line(kGroups['birikim']!.color, s.pick('Birikim', 'Savings') + (sm.savingsPlanned > 0 ? s.pick(' (planlanan)', ' (planned)') : ''), '−${money(sm.savings)}');
    }
    final hasInc = sm.income > 0 || sm.carryIn != 0;
    lines.add(const Padding(padding: EdgeInsets.only(top: 12), child: Hairline()));
    line(
      null,
      hasInc ? s.pick('Serbest kalan', 'Left free') : s.pick('Toplam çıkış', 'Total out'),
      money(hasInc ? sm.free : sm.total + sm.spent + sm.estSpend),
      bold: true,
      valueColor: hasInc && sm.free < 0 ? MC.rose : MC.gold,
    );
    if (sm.month == ctx.cur && sm.safe != null) {
      line(
        null,
        s.pick('Ay sonuna kadar serbest', 'Free until month end'),
        money(sm.safe!),
        bold: true,
        valueColor: sm.safe! < 0 ? MC.rose : MC.gold,
        items: s.pick(
          'Hesaplarda ${money(ctx.model.liquid)}${(sm.incomeRest ?? 0) > 0 ? ' + yatacak gelir ${money(sm.incomeRest!)}' : ''} − bu ayın kalan ödemeleri ${money(sm.unpaid)}',
          'In accounts ${money(ctx.model.liquid)}${(sm.incomeRest ?? 0) > 0 ? ' + income to come ${money(sm.incomeRest!)}' : ''} − this month\'s open payments ${money(sm.unpaid)}',
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }
}

// ---------------------------------------------------------------- Gruplar

class _GroupsGrid extends StatelessWidget {
  const _GroupsGrid({required this.ctx, required this.sum, required this.month, required this.items});

  final Ctx ctx;
  final MonthSummary sum;
  final String month;
  final List<PlanItem> items;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = ctx.data;
    final m = month;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    Widget group({
      required String title,
      required Color tint,
      required List<PlanItem> rows,
      required Widget add,
      required String empty,
      String? hint,
      Duration delay = Duration.zero,
    }) {
      final lv = rows.where((it) => !it.carriedOut).toList();
      final tot = sumK(lv, (PlanItem it) => it.pay?.k ?? it.planned);
      final paid = sumK(lv.where((it) => it.pay != null), (PlanItem it) => it.pay!.k);
      return GlassPanel(
        tint: tint,
        darkness: 0.44,
        delay: delay,
        radius: 30,
        cut: 30,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PanelHead(
            title,
            subtitle: rows.isEmpty ? null : s.pick('${lv.length} kalem · ${money(tot)}${paid > 0 ? ' · ödenen ${money(paid)}' : ''}', '${lv.length} items · ${money(tot)}${paid > 0 ? ' · paid ${money(paid)}' : ''}'),
            trailing: add,
          ),
          if (rows.isEmpty) Text(empty, style: sans(13, color: MC.muted)),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Hairline(),
            PayRow(ctx: ctx, item: rows[i], month: m),
          ],
          if (hint != null && hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(hint, style: sans(11.5, color: MC.dim, height: 1.4))),
        ]),
      );
    }

    final incRows = [...sum.incomeItems]..sort((a, b) => (a.payDay ?? 32) - (b.payDay ?? 32));
    final income = GlassPanel(
      tint: MC.mint,
      darkness: 0.44,
      delay: const Duration(milliseconds: 280),
      radius: 30,
      cut: 30,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PanelHead(
          s.pick('Gelir', 'Income'),
          subtitle: incRows.isEmpty && sum.carryIn == 0 ? null : s.pick('Toplam ${money(sum.income + sum.carryIn)}', 'Total ${money(sum.income + sum.carryIn)}'),
          trailing: SmallButton(label: s.pick('Gelir', 'Income'), onTap: () => openIncomeSheet(context)),
        ),
        if (sum.carryIn != 0) IncomeRow(ctx: ctx, month: m, carryK: sum.carryIn),
        for (final i in incRows) IncomeRow(ctx: ctx, month: m, item: i),
        if (incRows.isEmpty && sum.carryIn == 0)
          Text(s.pick('Maaş gibi düzenli gelirini ekle; plan buna göre hesaplanır.', 'Add regular income like your salary; the plan is worked out from it.'), style: sans(13, color: MC.muted)),
      ]),
    );
    final fixed = group(
      title: s.pick('Kira ve sabit giderler', 'Rent and fixed costs'),
      tint: MC.sky,
      rows: items.where((it) => it.group == 'sabit').toList(),
      add: SmallButton(label: s.pick('Gider', 'Cost'), onTap: () => openExpenseSheet(context)),
      empty: s.pick("Kira gibi her ay aynı olan giderleri ekle. Faturalar Abonelikler'de.", 'Add costs that are the same each month, like rent. Bills live under Subscriptions.'),
      delay: const Duration(milliseconds: 300),
    );
    final subs = group(
      title: s.pick('Abonelikler ve faturalar', 'Subscriptions and bills'),
      tint: MC.teal,
      rows: items.where((it) => it.group == 'abonelik').toList(),
      add: SmallButton(label: s.pick('Abonelik', 'Subscription'), onTap: () => openSubSheet(context)),
      empty: s.pick('Bu ay hesaba katılan abonelik yok.', 'No subscriptions counted this month.'),
      hint: d.subscriptions.any((x) => x.active && srcCard(x.source) != null)
          ? s.pick('Karttan ödenen abonelikler, kartın o ayki ekstresi girilince ekstrenin içinde sayılır.', 'Subscriptions paid by card are counted inside the card statement once it is entered.')
          : null,
      delay: const Duration(milliseconds: 320),
    );
    final debts = group(
      title: s.pick('Borç ve kart ödemeleri', 'Debt and card payments'),
      tint: MC.rose,
      rows: items.where((it) => it.group == 'taksit' || it.group == 'kart').toList(),
      add: SmallButton(label: s.pick('Borç', 'Debt'), onTap: () => openDebtSheet(context)),
      empty: s.pick('Bu ay borç ya da kart ödemesi yok.', 'No debt or card payments this month.'),
      hint: sum.estK > 0
          ? s.pick(
              "Parantezdeki tutarlar ekstre girilmediği için borcun %${(kMinPayRate * 100).round()}'si kadar tahmini asgari ödemedir. Farklı ödersen satıra dokunup tutarı gir.",
              'Amounts in brackets are an estimated minimum of ${(kMinPayRate * 100).round()}% of the debt, as no statement was entered. If you pay a different amount, tap the row and enter it.')
          : null,
      delay: const Duration(milliseconds: 340),
    );
    return Column(children: [
      TwoColumns(leftFlex: 1, rightFlex: 1, left: income, right: fixed),
      const SizedBox(height: 14),
      TwoColumns(leftFlex: 1, rightFlex: 1, left: subs, right: debts),
    ]);
  }
}

// ---------------------------------------------------------------- Önümüzdeki aylar

class _MonthsTable extends StatelessWidget {
  const _MonthsTable({required this.ctx, required this.selected, required this.range, required this.onRange, required this.onPick});

  final Ctx ctx;
  final String selected;
  final int range;
  final ValueChanged<int> onRange;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final from = maxMonth(ctx.cur, ctx.model.base);
    final sums = [for (var i = 0; i < range; i++) ctx.sum(addM(from, i))];
    final e = ctx.est;
    final head = sans(11.5, color: MC.muted, weight: FontWeight.w600);
    Widget seg(int v) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: InkWell(
            onTap: () => onRange(v),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: range == v ? MC.gold : const Color(0x33000000),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: range == v ? MC.gold : const Color(0x33FFFFFF)),
              ),
              child: Text(s.pick('$v ay', '$v mo'), style: sans(12, weight: FontWeight.w600, color: range == v ? MC.ink : MC.text)),
            ),
          ),
        );
    return GlassPanel(
      delay: const Duration(milliseconds: 300),
      radius: 30,
      cut: 30,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PanelHead(
          s.pick('Önümüzdeki aylar', 'Coming months'),
          subtitle: s.pick('Satıra dokun: o ayın planı açılır', 'Tap a row to open that month'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [seg(12), seg(24)]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            Expanded(flex: 5, child: Text(s.pick('Ay', 'Month'), style: head)),
            Expanded(flex: 4, child: Text(s.pick('Gelir', 'Income'), textAlign: TextAlign.right, style: head)),
            Expanded(flex: 4, child: Text(s.pick('Ödemeler', 'Payments'), textAlign: TextAlign.right, style: head)),
            Expanded(flex: 4, child: Text(s.pick('Harcama', 'Spending'), textAlign: TextAlign.right, style: head)),
            Expanded(flex: 4, child: Text(s.pick('Serbest', 'Free'), textAlign: TextAlign.right, style: head)),
          ]),
        ),
        for (final x in sums)
          InkWell(
            onTap: () => onPick(x.month),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(color: x.month == selected ? const Color(0x24E3BF7C) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Expanded(
                  flex: 5,
                  child: Row(children: [
                    Flexible(child: Text(monthLabel(x.month, s.lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(13, weight: FontWeight.w600))),
                    if (x.close != null) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock_outline, size: 13, color: MC.mint)),
                  ]),
                ),
                Expanded(flex: 4, child: Text(money(x.income + x.carryIn), textAlign: TextAlign.right, style: sans(13))),
                Expanded(flex: 4, child: Text(money(x.total) + (x.estK > 0 ? '~' : ''), textAlign: TextAlign.right, style: sans(13))),
                Expanded(
                  flex: 4,
                  child: Text(x.estSpend > 0 ? '≈ ${money(x.estSpend)}' : money(x.spent), textAlign: TextAlign.right, style: sans(13, color: x.estSpend > 0 ? MC.muted : MC.text)),
                ),
                Expanded(
                  flex: 4,
                  child: Builder(builder: (_) {
                    final hi = x.income > 0 || x.carryIn != 0;
                    return Text(hi ? money(x.free) : '—',
                        textAlign: TextAlign.right, style: sans(13, weight: FontWeight.w700, color: hi ? (x.free < 0 ? MC.rose : MC.gold) : MC.muted));
                  }),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(color: const Color(0x26000000), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
              child: Text(
                s.pick('Gelecek aylar için günlük harcama tahmini ', 'Everyday spending estimate for coming months ') +
                    '${money(e.k)} / ${s.pick('ay', 'mo')}' +
                    (e.manual
                        ? s.pick(' · senin girdiğin', ' · entered by you')
                        : e.basisMonths.isNotEmpty
                            ? s.pick(' · ${e.basisMonths.map((x) => monthShortLabel(x, s.lang)).join(', ')} ortalaması', ' · average of ${e.basisMonths.map((x) => monthShortLabel(x, s.lang)).join(', ')}')
                            : s.pick(' · henüz veri yok', ' · no data yet')),
                style: sans(12.5),
              ),
            ),
            SmallButton(label: s.pick('Değiştir', 'Change'), icon: Icons.edit_outlined, onTap: () => openSpendEstimateSheet(context)),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          s.pick(
            "≈ işaretli harcamalar tahmindir: hesaptan ve nakit yapılan harcamaların aylık ortalaması (kira hariç; karttan yapılanlar kart ödemesine girer). ~ işaretli aylarda kart ödemesi, ekstre girilmediği için borcun %${(kMinPayRate * 100).round()}'si kadar tahmini asgaridir.",
            '≈ marks an estimate: the monthly average of spending from accounts and cash (rent excluded; card spending goes into the card payment). ~ means the card payment is an estimated minimum of ${(kMinPayRate * 100).round()}% of the debt, as no statement was entered.',
          ),
          style: sans(11.5, color: MC.dim, height: 1.4),
        ),
      ]),
    );
  }
}

void openSpendEstimateSheet(BuildContext context) => showEditSheet<void>(context, builder: (_) => const SpendEstimateSheet());

// ---------------------------------------------------------------- Grafikler

class _FlowChart extends StatelessWidget {
  const _FlowChart({required this.ctx, required this.months, required this.selected, required this.onPick});

  final Ctx ctx;
  final List<String> months;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sums = [for (final m in months) ctx.sum(m)];
    final keys = [...kGroupOrder, 'harcama', 'birikim'];
    bool used(String k) => sums.any((x) => (k == 'harcama' ? x.spent + x.estSpend : k == 'birikim' ? x.savings : x.groupTotal(k)) > 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 200,
        child: LayoutBuilder(builder: (context, c) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) {
              final i = (e.localPosition.dx / (c.maxWidth / sums.length)).floor();
              if (i >= 0 && i < sums.length) onPick(sums[i].month);
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => CustomPaint(
                size: Size(c.maxWidth, 200),
                painter: _FlowPainter(sums, selected, t, s.lang),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (final k in keys.where(used))
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: kGroups[k]!.color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(k == 'harcama' && sums.any((x) => x.estSpend > 0) ? s.pick('Harcamalar (soluk: tahmini)', 'Spending (faint: estimate)') : kGroups[k]!.label.of(s.lang),
                style: sans(11.5, color: MC.muted)),
          ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 2, color: MC.text),
          const SizedBox(width: 6),
          Text(s.pick('Gelir', 'Income'), style: sans(11.5, color: MC.muted)),
        ]),
      ]),
    ]);
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.sums, this.selected, this.t, this.lang);

  final List<MonthSummary> sums;
  final String selected;
  final double t;
  final String lang;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 10.0, bottom = 22.0;
    final ch = size.height - top - bottom;
    final n = sums.length;
    if (n == 0) return;
    int pos(int v) => v > 0 ? v : 0;
    int outOf(MonthSummary x) => x.total + pos(x.savings) + x.spent + x.estSpend;
    var max = 1;
    for (final x in sums) {
      max = math.max(max, math.max(outOf(x), x.income + pos(x.carryIn)));
    }
    final slot = size.width / n;
    final bw = math.min(26.0, slot * 0.55);
    final base = top + ch;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = const Color(0x1FFFFFFF));
    for (var i = 0; i < n; i++) {
      final x = sums[i];
      final cx = (i + 0.5) * slot;
      if (x.month == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(cx - slot / 2 + 2, 0, slot - 4, size.height), const Radius.circular(8)),
          Paint()..color = const Color(0x1FE3BF7C),
        );
      }
      var y = base;
      final parts = <(String, int, bool)>[
        for (final k in kGroupOrder) (k, x.groupTotal(k), false),
        ('harcama', x.spent, false),
        ('harcama', x.estSpend, true),
        ('birikim', pos(x.savings), false),
      ];
      for (final (k, v, est) in parts) {
        if (v <= 0) continue;
        final h = v / max * ch * t;
        y -= h;
        final color = kGroups[k]!.color;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(cx - bw / 2, y, bw, math.max(0.5, h)), const Radius.circular(2));
        canvas.drawRRect(r, Paint()..color = est ? color.withValues(alpha: 0.4) : color);
      }
      final inc = x.income + pos(x.carryIn);
      if (inc > 0) {
        final iy = base - inc / max * ch * t;
        final p = Paint()
          ..color = MC.text
          ..strokeWidth = 2;
        for (var dx = cx - bw / 2 - 5; dx < cx + bw / 2 + 5; dx += 7) {
          canvas.drawLine(Offset(dx, iy), Offset(math.min(dx + 4, cx + bw / 2 + 5), iy), p);
        }
      }
      final tp = TextPainter(
        text: TextSpan(text: monthShortLabel(x.month, lang).split(' ').first, style: sans(10.5, color: x.month == selected ? MC.gold : MC.muted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => old.t != t || old.selected != selected || old.sums != sums;
}

class _NetWorth extends StatelessWidget {
  const _NetWorth({required this.ctx});

  final Ctx ctx;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final mm = ctx.model;
    final now = mm.netWorth;
    final pts = <(String, int, bool)>[];
    for (final c in ctx.data.monthCloses) {
      final snap = c.j['snapshot'];
      if (snap is Map) {
        pts.add((c.month, toK(snap['liquid']) - toK(snap['cardDebt']) - toK(snap['loanDebt']), false));
      }
    }
    pts.sort((a, b) => a.$1.compareTo(b.$1));
    pts.add((ctx.cur, now, true));
    Widget stat(String label, int k, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: sans(11.5, color: MC.muted)),
            const SizedBox(height: 2),
            MoneyText(k, style: serif(24, color: color ?? MC.text)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        stat(s.pick('Bugün', 'Today'), now, color: now < 0 ? MC.rose : MC.gold),
        stat(s.pick('Hesaplar', 'Accounts'), mm.liquid),
        stat(s.pick('Borçlar', 'Debts'), mm.totalRemaining),
      ]),
      const SizedBox(height: 10),
      if (pts.length < 2)
        Text(s.pick('Her ayı kapattığında o ayın sonundaki net değer kaydedilir; aylar biriktikçe burada çizgi olarak görünür.',
            'Each time you close a month its closing net worth is saved; as months add up they show here as a line.'),
            style: sans(12.5, color: MC.muted, height: 1.4))
      else
        SizedBox(
          height: 150,
          child: CustomPaint(size: const Size(double.infinity, 150), painter: _LinePainter(pts, s.lang, st.hidden)),
        ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.lang, this.hidden);

  final List<(String, int, bool)> pts;
  final String lang;
  final bool hidden;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 14.0, bot = 24.0;
    final ch = size.height - top - bot;
    final ks = pts.map((p) => p.$2).toList();
    final lo = ks.reduce(math.min), hi = ks.reduce(math.max);
    final span = math.max(1, hi - lo);
    double xOf(int i) => (i + 0.5) * (size.width / pts.length);
    double yOf(int k) => top + ch - (k - lo) / span * ch;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(xOf(i), yOf(pts[i].$2));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = MC.gold);
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      canvas.drawCircle(Offset(xOf(i), yOf(p.$2)), p.$3 ? 4.5 : 3.5, Paint()..color = p.$3 ? MC.gold : MC.text);
      final tp = TextPainter(
        text: TextSpan(text: p.$3 ? (lang == 'tr' ? 'Şimdi' : 'Now') : monthShortLabel(p.$1, lang), style: sans(10.5, color: MC.muted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.pts != pts || old.hidden != hidden;
}

// ---------------------------------------------------------------- Tanımlar

class _Definitions extends StatelessWidget {
  const _Definitions({required this.ctx, required this.month, required this.open, required this.onToggle});

  final Ctx ctx;
  final String month;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = ctx.data;
    final m = month;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final recs = d.recurringExpenses.toList()..sort((a, b) => toK(b.amount) - toK(a.amount));
    final ones = d.oneOffIncomes.toList()..sort((a, b) => b.date.compareTo(a.date));
    return GlassPanel(
      delay: const Duration(milliseconds: 380),
      radius: 26,
      cut: 26,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.tune, color: MC.gold, size: 20),
              const SizedBox(width: 10),
              Text(s.pick('Tüm tanımlar', 'All definitions'), style: sans(15, weight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.pick('Gelirler ve sabit giderler; başlamamış ya da bitmiş olanlar dahil', 'Incomes and fixed costs, including ones not started or ended'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12.5, color: MC.muted)),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: MC.muted),
            ]),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 10),
          TwoColumns(
            leftFlex: 1,
            rightFlex: 1,
            left: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PanelHead(s.pick('Gelirler', 'Incomes'), trailing: SmallButton(label: s.pick('Gelir', 'Income'), onTap: () => openIncomeSheet(context))),
              for (final inc in d.incomes)
                RowItem(
                  leading: Text('₺', style: serif(24, color: kIncomeColor)),
                  title: inc.name.isEmpty ? s.pick('Gelir', 'Income') : inc.name,
                  subtitle: (inc.payDay != null ? s.pick('Her ayın ${dayPoss(inc.payDay!)}', 'Every month ${dayOfMonthText(inc.payDay!, 'en')}') : s.pick('Ödeme günü belirtilmemiş', 'No pay day set')) +
                      (inc.schedule.length > 1 ? s.pick(' · ${inc.schedule.length} dönem', ' · ${inc.schedule.length} periods') : ''),
                  trailing: Text(money(schedK(inc.schedule, m)), style: sans(14, weight: FontWeight.w700, color: MC.mint)),
                  onTap: () => openIncomeSheet(context, income: inc),
                ),
              for (final o in ones.take(8))
                RowItem(
                  leading: Text('+', style: serif(24, color: kIncomeColor)),
                  title: o.name.isEmpty ? s.pick('Gelir', 'Income') : o.name,
                  subtitle: s.pick('Tek seferlik · ', 'One-off · ') + fmtDate(o.date, s.lang),
                  trailing: Text('+${money(toK(o.amount))}', style: sans(14, weight: FontWeight.w700, color: MC.mint)),
                  onTap: () => openOneOffIncomeSheet(context, o),
                ),
              if (d.incomes.isEmpty && ones.isEmpty) Text(s.pick('Gelir tanımı yok.', 'No incomes defined.'), style: sans(13, color: MC.muted)),
            ]),
            right: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PanelHead(s.pick('Sabit giderler', 'Fixed costs'), trailing: SmallButton(label: s.pick('Gider', 'Cost'), onTap: () => openExpenseSheet(context))),
              for (final r in recs)
                Builder(builder: (_) {
                  final act = isMonth(r.startMonth) && r.activeIn(m);
                  final status = act ? '' : (r.startMonth.compareTo(m) > 0 ? s.pick(' · ${monthLabel(r.startMonth, s.lang)} başlar', ' · starts ${monthLabel(r.startMonth, s.lang)}') : s.pick(' · sona erdi', ' · ended'));
                  return RowItem(
                    dim: !act,
                    leading: Monogram(name: r.name, size: 36),
                    title: r.name,
                    subtitle: catLabel(r.category, s.lang) + (r.day != null ? ' · ${dayOfMonthText(r.day!, s.lang)}' : '') + status,
                    trailing: Text('${money(toK(r.amount))} / ${s.pick('ay', 'mo')}', style: sans(14, weight: FontWeight.w700)),
                    onTap: () => openExpenseSheet(context, expense: r),
                  );
                }),
              if (recs.isEmpty) Text(s.pick('Sabit gider yok.', 'No fixed costs.'), style: sans(13, color: MC.muted)),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- Yaklaşan ödemeler

/// Önümüzdeki 7 günün ödenmemiş kalemleri (üst menüdeki zil).
class UpcomingSheet extends StatelessWidget {
  const UpcomingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final list = ctx.upcoming(7);
    final tot = sumK(list, (Upcoming u) => u.item.planned);
    return SheetFrame(
      title: s.pick('Yaklaşan ödemeler', 'Coming payments'),
      subtitle: list.isEmpty
          ? s.pick('Önümüzdeki 7 günde ödenecek kalem yok.', 'Nothing to pay in the next 7 days.')
          : s.pick('7 gün içinde ${list.length} ödeme · toplam ${fmtMoney(tot, lang: s.lang, hidden: st.hidden)}', '${list.length} payments in 7 days · total ${fmtMoney(tot, lang: s.lang, hidden: st.hidden)}'),
      leftActions: [
        GlassButton(
          label: s.pick('Plan', 'Plan'),
          icon: Icons.calendar_month_outlined,
          onTap: () {
            Navigator.of(context).pop();
            st.setTab(AppTab.plan);
          },
        ),
      ],
      actions: [GoldButton(label: s.pick('Kapat', 'Close'), onTap: () => Navigator.of(context).pop())],
      children: [
        for (final u in list) PayRow(ctx: ctx, item: u.item, month: u.month),
      ],
    );
  }
}
