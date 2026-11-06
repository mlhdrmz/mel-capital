import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../motor/motorlar.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../card_art.dart';
import '../dialogs.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';
import 'common.dart';

/// Borçlar: kredi kartları, krediler ve yapılandırmalar, Findeks notu, "Fazla ödersem?".
class BorclarPage extends StatelessWidget {
  const BorclarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    final m = ctx.model;
    int cur(Debt x) => m.debts[x.id]?.current ?? 0;
    final cards = d.debts.where((x) => x.isCard).toList();
    final loans = d.debts.where((x) => !x.isCard).toList()..sort((a, b) => cur(b) - cur(a));
    final openLoans = loans.where((x) => cur(x) > 0).length;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final usedAll = m.cardLimit > 0 ? m.cardDebt / m.cardLimit : 0.0;

    return PageFrame(
      eyebrow: s.pick('BORÇLAR', 'DEBTS'),
      title: s.pick('Kartlar ve krediler', 'Cards and loans'),
      actions: [
        if (cards.isNotEmpty)
          GoldButton(label: s.pick('Kart borcu öde', 'Pay a card'), icon: Icons.payments_outlined, onTap: () => openCardPaySheet(context)),
        GlassButton(label: s.pick('Borç / kart', 'Debt / card'), icon: Icons.add, onTap: () => openDebtSheet(context)),
      ],
      children: [
        KpiRow(children: [
          Kpi(
            label: s.pick('Toplam borç', 'Total debt'),
            k: m.totalRemaining,
            sub: s.pick('${cards.length} kart · $openLoans kredi', '${cards.length} cards · $openLoans loans'),
            color: MC.rose,
            delay: const Duration(milliseconds: 40),
          ),
          Kpi(
            label: s.pick('Kart borcu', 'Card debt'),
            k: m.cardDebt,
            sub: m.cardLimit > 0
                ? s.pick('Boş limit ${money(m.cardAvail)} / ${money(m.cardLimit)}', 'Available ${money(m.cardAvail)} / ${money(m.cardLimit)}')
                : s.pick('Limit girilmedi', 'No limit entered'),
            color: MC.sky,
            delay: const Duration(milliseconds: 100),
            footer: m.cardLimit > 0 ? ProgressLine(usedAll, color: usedAll > 0.9 ? MC.rose : MC.sky, height: 4) : null,
          ),
          Kpi(
            label: s.pick('Krediler ve yapılandırmalar', 'Loans and restructured debt'),
            k: m.loanDebt,
            sub: openLoans > 0 ? s.pick('$openLoans açık kayıt', '$openLoans open') : s.pick('Açık kredi yok', 'No open loans'),
            color: MC.gold,
            delay: const Duration(milliseconds: 160),
          ),
        ]),
        const SizedBox(height: 14),
        TwoColumns(
          left: Column(children: [
            GlassPanel(
              delay: const Duration(milliseconds: 200),
              radius: 30,
              cut: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PanelHead(
                    s.pick('Kredi kartları', 'Credit cards'),
                    subtitle: cards.isEmpty
                        ? s.pick('Kredi kartı yok', 'No credit cards')
                        : s.pick('Kart rengine dokun: kart kaydı · ${money(m.cardDebt)} borç', 'Tap the swatch to open the card · ${money(m.cardDebt)} debt'),
                    trailing: SmallButton(label: s.pick('Kart', 'Card'), onTap: () => openDebtSheet(context, type: 'kredi_karti')),
                  ),
                  if (cards.isEmpty)
                    Text(s.pick('Kredi kartı eklenince limit, ekstre ve borç burada görünür.', 'Once you add a credit card, its limit, statements and debt show here.'),
                        style: sans(13, color: MC.muted)),
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const Hairline(),
                    CardRow(debt: cards[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassPanel(
              delay: const Duration(milliseconds: 240),
              radius: 30,
              cut: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PanelHead(
                    s.pick('Krediler ve yapılandırmalar', 'Loans and restructured debt'),
                    subtitle: loans.isEmpty
                        ? s.pick('Kayıt yok', 'Nothing yet')
                        : s.pick('Kalan ${money(m.loanDebt)} · dokununca düzenlenir', '${money(m.loanDebt)} left · tap to edit'),
                    trailing: SmallButton(label: s.pick('Borç', 'Debt'), onTap: () => openDebtSheet(context)),
                  ),
                  if (loans.isEmpty)
                    Text(s.pick('Taksitli bir borcun varsa ödeme planıyla ekle.', 'If you have a debt paid in instalments, add it with its plan.'),
                        style: sans(13, color: MC.muted)),
                  for (var i = 0; i < loans.length; i++) ...[
                    if (i > 0) const Hairline(),
                    LoanRow(debt: loans[i]),
                  ],
                ],
              ),
            ),
          ]),
          right: Column(children: [
            const FindeksPanel(),
            if (d.debts.any((x) => cur(x) > 0)) ...[
              const SizedBox(height: 14),
              const _DebtCalcPanel(),
            ],
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Kredi kartı satırı

/// Kartın ekstre durumu: renkli kısa metin parçaları.
List<InlineSpan> cardStatusSpans(BuildContext context, Ctx ctx, Debt debt) {
  final s = S.of(context);
  final st = AppScope.of(context);
  String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
  final cur = ctx.cur;
  final sts = debt.statements.where((x) => isMonth(x.month) && x.month.compareTo(addM(cur, 1)) <= 0).toList()
    ..sort((a, b) => a.month.compareTo(b.month));
  final spans = <InlineSpan>[];
  if (sts.isNotEmpty) {
    final last = sts.last;
    final pay = ctx.model.pay('debt', debt.id, last.month);
    final planK = statementPlanK(debt, last);
    final mn = monthName(last.month, s.lang);
    if (pay != null && pay.k >= planK) {
      spans.add(TextSpan(text: s.pick('$mn ekstresi ödendi', '$mn statement paid'), style: const TextStyle(color: MC.mint)));
    } else if (pay != null) {
      spans.add(TextSpan(text: s.pick('$mn ekstresi: ${money(pay.k)} ödendi, plan ${money(planK)}', '$mn statement: ${money(pay.k)} paid of ${money(planK)}')));
    } else {
      final due = debt.dueDay;
      final late = last.month.compareTo(cur) < 0 || (last.month == cur && due != null && due < dayOf(todayISO()));
      final dueTxt = due != null ? s.pick(' · son gün ${dayMonth(due, last.month, s.lang)}', ' · due ${dayMonth(due, last.month, s.lang)}') : '';
      spans.add(TextSpan(
        text: s.pick('$mn ekstresi: ${money(planK)} ödenecek', '$mn statement: ${money(planK)} to pay') + dueTxt,
        style: TextStyle(color: late ? MC.rose : MC.gold),
      ));
    }
  }
  final nc = nextCycle(debt);
  if (nc != null) {
    if (spans.isNotEmpty) spans.add(const TextSpan(text: ' · '));
    spans.add(TextSpan(text: s.pick('kesim ', 'cut-off ') + dayMonth(nc.cutDay, nc.cutM, s.lang)));
  }
  if (spans.isEmpty) spans.add(TextSpan(text: s.pick('Ekstre girilmedi', 'No statement yet')));
  return spans;
}

/// Kredi kartı satırı: kart rengi, ekstre durumu, limit çubuğu, borç ve düğmeler.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.debt, this.full = true});

  final Debt debt;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final info = ctx.model.debts[debt.id];
    if (info == null) return const SizedBox.shrink();
    final phys = physicalCardOf(ctx.data, debt.id);
    final bank = phys?.bank.isNotEmpty == true ? phys!.bank : bankKeyOf(debt);
    final look = CardLook.of(phys?.style, bank);
    final limit = info.limit;
    final used = limit != null && limit > 0 ? (info.current / limit).clamp(0.0, 1.0).toDouble() : 0.0;
    final spans = cardStatusSpans(context, ctx, debt);
    if (info.subsK > 0) {
      spans.add(TextSpan(
          text: s.pick(' · abonelikler ${fmtMoney(info.subsK, lang: s.lang, hidden: st.hidden)}/ay',
              ' · subscriptions ${fmtMoney(info.subsK, lang: s.lang, hidden: st.hidden)}/mo')));
    }
    final swatch = Tooltip(
      message: s.pick('Kart kaydını aç', 'Open the card'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openDebtSheet(context, debt: debt),
          // Eski uygulamadaki küçük kart örneği: kartın renkleri ve banka logosu
          child: Container(
            width: 62,
            height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0x24FFFFFF))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                painter: CardArtPainter(c1: look.c1, c2: look.c2, pattern: look.pattern, darkInk: look.ink == 'dark', patternOn: false),
                child: Center(child: BankPlate(bankKey: bank, name: debt.creditor, size: 18, shadow: false, maxLogoWidth: 44)),
              ),
            ),
          ),
        ),
      ),
    );
    final amounts = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: limit != null
          ? [
              Text(s.pick('Boş limit', 'Available'), style: sans(11, color: MC.muted)),
              MoneyText(info.available ?? 0, style: serif(23, color: (info.available ?? 0) < 0 ? MC.rose : MC.text)),
              Text(s.pick('Borç ', 'Debt ') + fmtMoney(info.current, lang: s.lang, hidden: st.hidden), style: sans(11, color: MC.muted)),
            ]
          : [
              Text(s.pick('Borç', 'Debt'), style: sans(11, color: MC.muted)),
              MoneyText(info.current, style: serif(23)),
            ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SmallButton(label: s.pick('Öde', 'Pay'), icon: Icons.payments_outlined, onTap: () => openCardPaySheet(context, debt: debt)),
        _IconAct(icon: Icons.add, tip: s.pick('Bu kartla harcama ekle', 'Add a spend on this card'), onTap: () => openSpendSheetFor(context, source: 'card:${debt.id}')),
        if (full) ...[
          _IconAct(icon: Icons.receipt_long_outlined, tip: s.pick('Ekstre gir', 'Enter statement'), onTap: () => openStatementSheet(context, debt)),
          _IconAct(icon: Icons.edit_outlined, tip: s.pick('Bakiye ve limiti güncelle', 'Update balance and limit'), onTap: () => openCardBalanceSheet(context, debt)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 620;
        final middle = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(phys?.name ?? debt.creditor, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(15, weight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text.rich(TextSpan(children: spans), maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(12, color: MC.muted)),
            if (limit != null) ...[
              const SizedBox(height: 8),
              ProgressLine(used, color: used > 0.9 ? MC.rose : MC.sky, height: 4),
            ],
          ],
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [swatch, const SizedBox(width: 14), Expanded(child: middle)]),
              const SizedBox(height: 8),
              Row(children: [
                actions,
                const SizedBox(width: 8),
                // Dar ekranda tutarlar sığmazsa küçülür
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: amounts),
                  ),
                ),
              ]),
            ],
          );
        }
        return Row(
          children: [
            swatch,
            const SizedBox(width: 16),
            Expanded(child: middle),
            const SizedBox(width: 16),
            amounts,
            const SizedBox(width: 10),
            actions,
          ],
        );
      }),
    );
  }
}

class _IconAct extends StatelessWidget {
  const _IconAct({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: MC.text,
          backgroundColor: const Color(0x26000000),
          side: const BorderSide(color: Color(0x30FFFFFF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
        ),
      );
}

// ---------------------------------------------------------------- Findeks

const Map<String, Color> kBandColors = {
  'danger': Color(0xFFEF8F7F),
  'warn': Color(0xFFE8C06A),
  'gold': Color(0xFFD9AE68),
  'ok': Color(0xFF9FD7A5),
};

/// Raporda yazan etiket varsa o, yoksa puandan bulunan bant: (etiket, ton).
(String, String) bandInfo(String? text, num? score, String lang) {
  final t = trLower(text ?? '');
  final fb = findeksBand(score);
  var tone = fb.$2;
  if (RegExp('kritik|en riskli').hasMatch(t)) {
    tone = 'danger';
  } else if (t.contains('orta')) {
    tone = 'warn';
  } else if (t.contains('az riskli')) {
    tone = 'gold';
  } else if (t.contains('iyi')) {
    tone = 'ok';
  }
  return (text != null && text.isNotEmpty ? text : fb.$1.of(lang), tone);
}

num? _num(Object? v) => v is num ? v : null;

class FindeksPanel extends StatelessWidget {
  const FindeksPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final report = d.findeksReport;
    final list = findeksSorted(d);
    final last = list.isEmpty ? null : list.last;
    final num? score = last?.score ?? _num(report?['score']);
    final band = bandInfo(last?.band ?? (report?['band'] is String ? report!['band'] as String : null), score, s.lang);
    final color = kBandColors[band.$2] ?? const Color(0xFF9B9286);
    final when = last != null
        ? monthLabel(last.date, s.lang)
        : (report != null && isDate(report['date']) ? fmtDate(report['date'] as String, s.lang) : '');
    final num? late = last?.lateCount ?? _num(report?['lateAccounts']);
    final hide = st.hidden;
    final ratio = _num(report?['ratio']);
    Widget pill(Color c, String text) => Container(
          margin: const EdgeInsets.only(right: 6, top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0x2E000000), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x30FFFFFF))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(text, style: sans(12)),
          ]),
        );
    return GlassPanel(
      tint: MC.violet,
      delay: const Duration(milliseconds: 220),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Findeks notu', 'Credit score (Findeks)'),
              subtitle: when.isEmpty ? s.pick('Kayıt yok', 'No record') : when,
              trailing: LogoPlate(asset: 'assets/logos/findeks.webp', aspect: kBankLogoAspect['findeks']!, label: 'Findeks')),
          if (score == null)
            Text(s.pick('Findeks raporundaki puanı ekle.', 'Add the score from your Findeks report.'), style: sans(13, color: MC.muted))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(hide ? '•••' : score.round().toString(), style: numStyle(serif(54))),
                const SizedBox(width: 8),
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('/ 1900', style: sans(13, color: MC.muted))),
              ],
            ),
            Wrap(children: [
              pill(color, band.$1),
              if (late != null) pill(late > 0 ? const Color(0xFFEF8F7F) : const Color(0xFF9FD7A5), s.pick('Gecikmedeki hesap: $late', 'Accounts in arrears: $late')),
            ]),
            if (!hide) ...[
              const SizedBox(height: 12),
              ProgressLine(math.max(0, math.min(1, score / 1900)).toDouble(), color: color, height: 6),
              const SizedBox(height: 3),
              Row(children: [Text('1', style: sans(10.5, color: MC.dim)), const Spacer(), Text('1900', style: sans(10.5, color: MC.dim))]),
            ],
          ],
          if (ratio != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(child: Text(s.pick('Limit kullanımı (rapor)', 'Limit use (report)'), style: sans(13, color: MC.muted))),
                Text('%${(ratio * 100).round()}', style: sans(13.5, weight: FontWeight.w700, color: ratio > 0.5 ? MC.rose : MC.text)),
              ]),
            ),
          if (list.length > 1) ...[
            const SizedBox(height: 8),
            for (final f in list.reversed.take(4))
              InkWell(
                onTap: () => openFindeksSheet(context, entry: f),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Row(children: [
                    Expanded(child: Text(monthLabel(f.date, s.lang), style: sans(13, color: MC.muted))),
                    Text(hide ? '•••' : f.score.round().toString(), style: sans(13.5, weight: FontWeight.w700)),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            SmallButton(label: s.pick('Puan', 'Score'), onTap: () => openFindeksSheet(context)),
            if (last != null) SmallButton(label: s.pick('Son kayıt', 'Last entry'), icon: Icons.edit_outlined, onTap: () => openFindeksSheet(context, entry: last)),
            if (report != null)
              SmallButton(label: s.pick('Rapor', 'Report'), icon: Icons.description_outlined, onTap: () => showFindeksReport(context, report)),
          ]),
        ],
      ),
    );
  }
}

/// Findeks raporunun ayrıntısı (girildiği gibi).
Future<void> showFindeksReport(BuildContext context, Json r) {
  final st = AppScope.of(context);
  final s = S.of(context);
  final hide = st.hidden;
  String show(Object? v) => v == null || v == '' ? '—' : v.toString();
  final ratio = _num(r['ratio']);
  List<String> strings(Object? v) => v is List ? [for (final x in v) maskTxt(x?.toString(), hide)] : const [];
  Widget h4(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t, style: serif(21)));
  Widget ul(List<String> items) => items.isEmpty
      ? Text(s.pick('belirtilmemiş', 'not set'), style: sans(12.5, color: MC.muted))
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final x in items) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $x', style: sans(13, height: 1.4)))],
        );
  Widget kv(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: sans(11.5, color: MC.muted)),
          const SizedBox(height: 2),
          Text(v, style: sans(15, weight: FontWeight.w700)),
        ]),
      );
  String moneyOf(Object? v) => v is num ? fmtMoney(toK(v), lang: s.lang, hidden: hide) : '—';
  final comps = r['components'] is List ? (r['components'] as List).whereType<Map<dynamic, dynamic>>().toList() : const <Map<dynamic, dynamic>>[];
  final worst = r['worst'] is Map ? r['worst'] as Map : null;
  final months = r['historyMonths'] is List ? (r['historyMonths'] as List).map((e) => e.toString()).toList() : const <String>[];
  final history = r['history'] is List ? (r['history'] as List).whereType<Map<dynamic, dynamic>>().toList() : const <Map<dynamic, dynamic>>[];
  final closed = r['closed'] is List ? (r['closed'] as List).whereType<Map<dynamic, dynamic>>().toList() : const <Map<dynamic, dynamic>>[];
  const cellColors = {'ok': Color(0xFF9FD7A5), '1': Color(0xFFE8C06A), '2': Color(0xFFEFA06F), '3': Color(0xFFEF8F7F)};
  const cellText = {'ok': '✓', '1': '1', '2': '2', '3': '3', '-': '–'};
  return showGlassDialog<void>(
    context,
    maxWidth: 860,
    builder: (context) => GlassPanel(
      animate: false,
      blur: 24,
      darkness: 0.66,
      radius: 28,
      cut: 28,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(s.pick('Findeks raporu', 'Findeks report'), style: serif(32))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: MC.muted)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                kv(s.pick('Limit kullanımı', 'Limit use'), ratio == null ? '—' : '%${(ratio * 100).round()}'),
                kv(s.pick('Toplam limit', 'Total limit'), moneyOf(r['limitTotal'])),
                kv(s.pick('Toplam borç', 'Total debt'), moneyOf(r['debtTotal'])),
                kv(s.pick('Gecikmedeki hesap', 'In arrears'), show(r['lateAccounts'])),
              ]),
              const SizedBox(height: 8),
              Text(
                s.pick(
                  'Rapor tarihi ${isDate(r['date']) ? fmtDate(r['date'] as String, s.lang) : 'belirtilmemiş'} · ${show(r['institutions'])} kurum · ${show(r['products'])} ürün',
                  'Report date ${isDate(r['date']) ? fmtDate(r['date'] as String, s.lang) : 'not set'} · ${show(r['institutions'])} institutions · ${show(r['products'])} products',
                ),
                style: sans(12, color: MC.muted),
              ),
              if (comps.isNotEmpty) ...[
                h4(s.pick('Notu oluşturan etkenler', 'What makes up the score')),
                for (final c in comps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(show(c['name']), style: sans(13))),
                        Text('%${show(c['pct'])}', style: sans(13, weight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 4),
                      ProgressLine(((_num(c['pct']) ?? 0) / 100).toDouble(), color: MC.violet, height: 4),
                    ]),
                  ),
              ],
              if (worst != null) ...[
                h4(s.pick('En olumsuz durum', 'Most negative item')),
                Text(show(worst['title']), style: sans(14, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(maskTxt(worst['detail']?.toString(), hide), style: sans(13, color: MC.muted, height: 1.4)),
              ],
              if (months.isNotEmpty && history.isNotEmpty) ...[
                h4(s.pick('Ödeme geçmişi · son 12 ay', 'Payment history · last 12 months')),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(40),
                    columnWidths: const {0: FixedColumnWidth(170)},
                    children: [
                      TableRow(children: [
                        const SizedBox(),
                        for (final m in months)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(isMonth(m) ? monthShortLabel(m, s.lang) : m, textAlign: TextAlign.center, style: sans(10, color: MC.muted)),
                          ),
                      ]),
                      for (final row in history)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
                            child: Text(show(row['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12)),
                          ),
                          for (var i = 0; i < months.length; i++)
                            Builder(builder: (_) {
                              final cells = row['cells'] is List ? row['cells'] as List : const [];
                              final v = i < cells.length ? (cells[i] ?? '-').toString() : '-';
                              final c = cellColors[v];
                              return Container(
                                margin: const EdgeInsets.all(2),
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c?.withValues(alpha: 0.28) ?? const Color(0x1AFFFFFF),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(cellText[v] ?? v, style: sans(11, weight: FontWeight.w700, color: c ?? MC.dim)),
                              );
                            }),
                        ]),
                    ],
                  ),
                ),
              ],
              h4(s.pick('Lehine olanlar', 'In your favour')),
              ul(strings(r['positives'])),
              h4(s.pick('Notu aşağı çekenler', 'Pulling the score down')),
              ul(strings(r['negatives'])),
              if (closed.isNotEmpty) ...[
                h4(s.pick('Kapanmış hesaplar', 'Closed accounts')),
                for (final c in closed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Expanded(child: Text(show(c['name']) + (c['note'] != null && c['note'] != '' ? ' · ${c['note']}' : ''), style: sans(13))),
                      Text(isDate(c['date']) ? fmtDate(c['date'] as String, s.lang) : show(c['date']), style: sans(12.5, color: MC.muted)),
                    ]),
                  ),
              ],
              if (r['notes'] is List && (r['notes'] as List).isNotEmpty) ...[
                h4(s.pick('Notlar', 'Notes')),
                ul(strings(r['notes'])),
              ],
              const SizedBox(height: 12),
              Text(
                s.pick(
                  'Raporda yazan risk etiketi girildiği gibi gösterilir. Etiket yoksa puandan hesaplanır: 1–699 En Riskli, 700–1099 Orta Riskli, 1100–1499 Az Riskli, 1500–1699 İyi, 1700–1900 Çok İyi.',
                  'The risk label in the report is shown as entered. Without one it follows the score: 1–699 highest risk, 700–1099 medium, 1100–1499 low, 1500–1699 good, 1700–1900 very good.',
                ),
                style: sans(11.5, color: MC.dim, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- Fazla ödersem?

class _DebtCalcPanel extends StatefulWidget {
  const _DebtCalcPanel();

  @override
  State<_DebtCalcPanel> createState() => _DebtCalcPanelState();
}

class _DebtCalcPanelState extends State<_DebtCalcPanel> {
  String? _id;
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    final open = d.debts.where((x) => (ctx.model.debts[x.id]?.current ?? 0) > 0).toList();
    if (open.isEmpty) return const SizedBox.shrink();
    final sel = open.any((x) => x.id == _id) ? _id! : open.first.id;
    return GlassPanel(
      delay: const Duration(milliseconds: 260),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Fazla ödersem?', 'What if I pay extra?'),
              subtitle: s.pick('Bir borca fazladan ödeme yaparsan ne değişir', 'What changes if you pay extra on a debt')),
          GlassSelect<String>(
            value: sel,
            items: [
              for (final x in open)
                (x.id, '${x.creditor} · ${fmtMoney(ctx.model.debts[x.id]!.current, lang: s.lang, hidden: st.hidden)}'),
            ],
            onChanged: (v) => setState(() => _id = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: sans(15),
            onChanged: (_) => setState(() {}),
            decoration: fieldDecoration(hint: s.pick('Fazladan ödeme, ör. 2.000', 'Extra payment, e.g. 2,000'), suffix: 'TL'),
          ),
          const SizedBox(height: 12),
          ..._out(context, ctx, sel, parseAmount(_amount.text)),
        ],
      ),
    );
  }

  List<Widget> _out(BuildContext context, Ctx ctx, String id, int? k) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final debt = ctx.data.debt(id);
    final info = ctx.model.debts[id];
    if (debt == null || info == null) return const [];
    if (k == null || k <= 0) {
      return [
        Text(s.pick('Tutarı yazınca kalan borç ve ödeme planındaki değişiklik burada görünür.', 'Type an amount to see how the debt and its plan change.'),
            style: sans(12.5, color: MC.muted)),
      ];
    }
    String money(int v) => fmtMoney(v, lang: s.lang, hidden: st.hidden);
    final pay = math.min(k, info.current);
    final lines = <(String, String)>[];
    lines.add((s.pick('Kalan borç', 'Remaining debt'), '${money(info.current)} → ${money(info.current - pay)}'));
    if (debt.isCard) {
      if (info.limit != null) lines.add((s.pick('Kullanılabilir limit', 'Available limit'), '${money(info.available!)} → ${money(info.available! + pay)}'));
      int minOf(int x) => (x * kMinPayRate / 100).round() * 100;
      lines.add((s.pick('Tahmini asgari ödeme', 'Estimated minimum'), '${money(minOf(info.current))} → ${money(minOf(info.current - pay))}'));
      if (info.limit != null && info.limit! > 0) {
        lines.add((
          s.pick('Limit doluluğu', 'Limit used'),
          '%${(info.current / info.limit! * 100).round()} → %${((info.current - pay) / info.limit! * 100).round()}',
        ));
      }
    } else {
      // Fazla ödeme son taksitlerden düşülür: plan sondan kısalır.
      final fut = <(String, int)>[];
      info.months.forEach((m, v) {
        if (m.compareTo(ctx.cur) >= 0 && v.planned > 0 && v.direct == null && v.st == null) fut.add((m, v.planned));
      });
      var left = pay, n = 0;
      for (var i = fut.length - 1; i >= 0 && left >= fut[i].$2; i--) {
        left -= fut[i].$2;
        n++;
      }
      if (fut.isNotEmpty) {
        lines.add((
          s.pick('Kalan taksit', 'Instalments left'),
          '${fut.length} → ${fut.length - n}${n > 0 ? s.pick(' · $n taksit erken biter', ' · $n end early') : ''}',
        ));
        if (n > 0) {
          lines.add((
            s.pick('Son taksit', 'Last instalment'),
            '${monthLabel(fut.last.$1, s.lang)} → ${fut.length - n > 0 ? monthLabel(fut[fut.length - n - 1].$1, s.lang) : s.pick('kalmaz', 'none')}',
          ));
        }
        if (left > 0 && fut.length - n > 0) {
          final lastK = fut[fut.length - n - 1].$2;
          lines.add((s.pick('Son taksit tutarı', 'Last instalment amount'), '${money(lastK)} → ${money(math.max(0, lastK - left))}'));
        }
      }
    }
    if (k > info.current) lines.add((s.pick('Not', 'Note'), s.pick('Borç ${money(info.current)}; fazlası hesaba katılmadı', 'The debt is ${money(info.current)}; the rest is ignored')));
    return [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(l.$1, style: sans(13, color: MC.muted))),
            const SizedBox(width: 10),
            Flexible(child: Text(l.$2, textAlign: TextAlign.right, style: sans(13.5, weight: FontWeight.w700))),
          ]),
        ),
      const SizedBox(height: 6),
      Text(s.pick('Faiz ve erken ödeme indirimi hesaba katılmadı; bankanın göstereceği tutar farklı olabilir.', 'Interest and early-payment discounts are not included; your bank may show a different figure.'),
          style: sans(11.5, color: MC.dim, height: 1.4)),
      if (debt.isCard) ...[
        const SizedBox(height: 10),
        SmallButton(label: s.pick('Kart borcu öde', 'Pay the card'), icon: Icons.payments_outlined, onTap: () => openCardPaySheet(context, debt: debt)),
      ],
    ];
  }
}
