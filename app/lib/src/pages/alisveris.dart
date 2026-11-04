import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../dialogs.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';
import 'common.dart';

// ---------------------------------------------------------------- Linkler

/// Linkin ait olduğu alışveriş sitesi (bilinmiyorsa alan adı).
ShopInfo? siteOf(String? url) {
  final u = safeUrl(url);
  if (u.isEmpty) return null;
  final host = (Uri.tryParse(u)?.host ?? '').replaceFirst(RegExp(r'^www\.'), '').toLowerCase();
  if (host.isEmpty) return null;
  for (final s in kShops) {
    if (s.hosts.any((x) => host == x || host.endsWith('.$x'))) return s;
  }
  return ShopInfo('', host, u, [host]);
}

/// Linkteki ürün adını tahmin eder (ör. trendyol.com/marka/urun-adi-p-123 → "Marka urun adi").
String nameFromUrl(String? url) {
  final u = safeUrl(url);
  if (u.isEmpty) return '';
  final x = Uri.tryParse(u);
  if (x == null) return '';
  final site = siteOf(u);
  final segs = x.pathSegments.where((s) => s.isNotEmpty).map((s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }).toList();
  var best = '';
  final dp = segs.indexOf('dp');
  if (dp > 0) {
    best = segs[dp - 1];
  } else {
    final dashed = segs.where((s) => s.contains('-')).toList()..sort((a, b) => b.length - a.length);
    best = dashed.isEmpty ? '' : dashed.first;
  }
  best = best
      .replaceFirst(RegExp(r'\.html?$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'-(p|pm)-[\w-]*$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'-\d{5,}$'), '')
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .trim();
  if (site != null && site.id == 'trendyol' && segs.length >= 2 && !segs[0].contains('-') && segs[0].length < 30) {
    best = '${segs[0].replaceAll(RegExp(r'[-_]+'), ' ')} $best';
  }
  if (best.length < 3) return '';
  if (best.length > 80) best = best.substring(0, 80);
  return best[0].toUpperCase() + best.substring(1);
}

Future<void> openLink(BuildContext context, String url) async {
  final u = safeUrl(url);
  final s = S.of(context);
  if (u.isEmpty) return;
  try {
    final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, s.pick('Link açılamadı.', 'The link could not be opened.'));
  } catch (_) {
    if (context.mounted) toast(context, s.pick('Link açılamadı.', 'The link could not be opened.'));
  }
}

// ---------------------------------------------------------------- Alabilir miyim?

enum OptState { ok, warn, no }

class AffordOption {
  const AffordOption(this.state, this.title, this.text, {this.action, this.table});
  final OptState state;
  final String title;
  final String text;
  final Widget? action;
  final List<InstallmentRow>? table;
}

class InstallmentRow {
  const InstallmentRow(this.n, this.monthlyK, this.first, this.last, this.worstFree, this.worstMonth);
  final int n;
  final int monthlyK;
  final String first;
  final String last;
  final int worstFree;
  final String worstMonth;
  bool get ok => worstFree >= 0;
}

/// Fiyatı verilen bir ürün için nakit, kart, taksit ve biriktirme seçenekleri (eldeki rakamlarla).
List<AffordOption> affordOptions(BuildContext context, Ctx ctx, int k, {required void Function(String? card, int n) onBuy, required void Function(int monthly) onWish}) {
  final st = AppScope.of(context);
  final s = S.of(context);
  String money(int v) => fmtMoney(v, lang: s.lang, hidden: st.hidden);
  final d = ctx.data;
  final mm = ctx.model;
  final cur = ctx.cur;
  final nm = addM(cur, 1);
  final curName = monthName(cur, s.lang), nmName = monthName(nm, s.lang);
  final sNow = ctx.sum(cur), sN = ctx.sum(nm);
  final opts = <AffordOption>[];
  Widget btn(String label, VoidCallback onTap) => SmallButton(label: label, icon: Icons.check, onTap: onTap);
  final cashBtn = btn(s.pick('Nakit aldım', 'Bought with cash'), () => onBuy(null, 1));
  final dueRest = sumK(sNow.items.where((it) => it.pay == null && it.planned > 0), (PlanItem it) => it.planned);
  final liquid = mm.liquid, spare = liquid - dueRest;
  final cashTitle = s.pick('Nakit · hemen', 'Cash · now');
  if (d.accounts.isEmpty) {
    opts.add(AffordOption(OptState.warn, cashTitle, s.pick('Hesap bakiyesi girilmedi; Bankalar sayfasından ekleyebilirsin.', 'No account balance entered; add one on the Banks page.')));
  } else if (spare >= k) {
    opts.add(AffordOption(
      OptState.ok,
      cashTitle,
      s.pick('Hesaplarında ${money(liquid)} var. $curName ayının kalan ödemelerinden (${money(dueRest)}) ve bu alışverişten sonra ${money(spare - k)} kalır.',
          'You have ${money(liquid)} in your accounts. After this month\'s remaining payments (${money(dueRest)}) and this purchase, ${money(spare - k)} is left.'),
      action: cashBtn,
    ));
  } else if (liquid >= k) {
    opts.add(AffordOption(
      OptState.warn,
      cashTitle,
      s.pick('Hesaplarında ${money(liquid)} var ama $curName ayının kalan ödemeleri (${money(dueRest)}) için ${money(k - spare)} eksik kalır.',
          'You have ${money(liquid)}, but you would be ${money(k - spare)} short for this month\'s remaining payments (${money(dueRest)}).'),
      action: cashBtn,
    ));
  } else {
    opts.add(AffordOption(
      OptState.no,
      cashTitle,
      s.pick('Hesaplarında ${money(liquid)} var; ${money(k - liquid)} eksik.${dueRest > 0 ? ' $curName ayının kalan ödemeleri de ${money(dueRest)}.' : ''}',
          'You have ${money(liquid)}; ${money(k - liquid)} short.${dueRest > 0 ? ' This month\'s remaining payments are ${money(dueRest)}.' : ''}'),
    ));
  }
  if (sN.income > 0) {
    final incs = [...sN.incomeItems]..sort((a, b) => (a.payDay ?? 32) - (b.payDay ?? 32));
    final inc = incs.isEmpty ? null : incs.first;
    final when = inc?.payDay != null ? dayMonth(inc!.payDay, nm, s.lang) : monthLabel(nm, s.lang);
    final after = sN.free - k;
    final pend = sN.items.where((it) => it.pending).map((it) => it.name).toList();
    final pendTxt = pend.isEmpty
        ? ''
        : s.pick(' ${pend.join(' ve ')} ekstresi henüz belli değil; ödemeleri bu tutardan düşecek.', ' The ${pend.join(' and ')} statement is not known yet; it will come out of this.');
    final title = s.pick('Nakit · $when maaşından sonra', 'Cash · after the $when pay');
    if (after >= 0) {
      opts.add(AffordOption(pend.isEmpty ? OptState.ok : OptState.warn, title,
          s.pick('$nmName ayının serbest parası ${money(sN.free)} → ${money(after)}.$pendTxt', '$nmName\'s free money ${money(sN.free)} → ${money(after)}.$pendTxt'),
          action: cashBtn));
    } else {
      opts.add(AffordOption(OptState.no, title,
          s.pick('$nmName ayının serbest parası (${money(sN.free)}) yetmiyor; ${money(-after)} eksik.$pendTxt', '$nmName\'s free money (${money(sN.free)}) is not enough; ${money(-after)} short.$pendTxt')));
    }
  }
  final cards = d.debts.where((x) => x.isCard && mm.debts[x.id]?.limit != null).toList();
  Debt? best;
  for (final c in cards) {
    final info = mm.debts[c.id]!;
    final avail = info.available ?? 0;
    final after = avail - k;
    if (after >= 0) {
      final u = (info.limit ?? 0) > 0 ? (info.current + k) / info.limit! : 1.0;
      if (best == null || avail > (mm.debts[best.id]?.available ?? 0)) best = c;
      final fm = nextStatementMonth(c, todayISO());
      opts.add(AffordOption(
        u > 0.9 ? OptState.warn : OptState.ok,
        s.pick('${c.creditor} · tek çekim', '${c.creditor} · single payment'),
        s.pick('Boş limit ${money(avail)} → ${money(after)} (doluluk %${(u * 100).round()}). ${monthLabel(fm, s.lang)} ekstresine eklenir.${u > 0.9 ? ' Limit doluluğunun yüksek kalması kredi notunu olumsuz etkiler.' : ''}',
            'Available ${money(avail)} → ${money(after)} (${(u * 100).round()}% used). Added to the ${monthLabel(fm, s.lang)} statement.${u > 0.9 ? ' Keeping the limit this full weighs on your credit score.' : ''}'),
        action: btn(s.pick('Kartla aldım', 'Bought by card'), () => onBuy(c.id, 1)),
      ));
    } else {
      opts.add(AffordOption(OptState.no, c.creditor,
          s.pick('Boş limit ${money(avail)}; ${money(-after)} yetmiyor. Taksitli alışverişte de tutarın tamamı limitten düşer.', 'Available ${money(avail)}; ${money(-after)} short. With instalments too, the full amount comes off the limit.')));
    }
  }
  if (cards.isEmpty) opts.add(AffordOption(OptState.warn, s.pick('Kredi kartı', 'Credit card'), s.pick('Limiti girilmiş kredi kartı yok.', 'No credit card with a limit entered.')));
  final b = best;
  if (b != null) {
    final fm = nextStatementMonth(b, todayISO());
    final rows = <InstallmentRow>[];
    for (final n in const [2, 3, 6, 9, 12]) {
      final total = k;
      final base = total ~/ n;
      final rem = total - base * n;
      final inst = [for (var i = 0; i < n; i++) (addM(fm, i), base + (i == n - 1 ? rem : 0))];
      // Taksit süresince her ay: o ayın serbest parası − taksit. En sıkışık ay gösterilir.
      var worst = (inst.first.$1, ctx.sum(inst.first.$1).free - inst.first.$2);
      for (final it in inst) {
        final f = ctx.sum(it.$1).free - it.$2;
        if (f < worst.$2) worst = (it.$1, f);
      }
      rows.add(InstallmentRow(n, inst.first.$2, inst.first.$1, inst.last.$1, worst.$2, worst.$1));
    }
    opts.add(AffordOption(
      OptState.ok,
      s.pick('${b.creditor} · taksitli', '${b.creditor} · instalments'),
      s.pick('Tutarın tamamı (${money(k)}) limitten düşer, taksit ödendikçe limit açılır. Vade farkı hesaba katılmadı; mağazanın taksit koşullarına bak. Son sütun: taksit süresince en sıkışık ayda, taksitten sonra kalan serbest para (tahmini günlük harcama düşülmüş).',
          'The full amount (${money(k)}) comes off the limit and frees up as instalments are paid. Interest is not included; check the shop\'s terms. Last column: the free money left after the instalment in the tightest month (estimated spending deducted).'),
      table: rows,
    ));
  } else if (cards.isNotEmpty) {
    opts.add(AffordOption(OptState.no, s.pick('Taksitli', 'Instalments'), s.pick('Hiçbir kartta bu tutar için yeterli boş limit yok.', 'No card has enough available limit for this amount.')));
  }
  final frees = [for (var i = 1; i <= 6; i++) ctx.sum(addM(cur, i)).free];
  final avg = (frees.fold<int>(0, (a, x) => a + x) / frees.length).round();
  if (avg > 0) {
    final monthly = math.min(k, math.max(50000, ((avg * 0.25) / 10000).ceil() * 10000));
    final n = (k / monthly).ceil();
    final pct = math.max(1, (monthly / avg * 100).round());
    final share = s.pick('önümüzdeki 6 ayın ortalama serbest parasının (${money(avg)}) yaklaşık %$pct kadarı', 'about $pct% of the average free money of the next 6 months (${money(avg)})');
    final txt = n == 1
        ? s.pick('$nmName ayında ${money(monthly)} ayırman yeterli; bu, $share.', 'Setting aside ${money(monthly)} in $nmName is enough; that is $share.')
        : s.pick('Ayda ${money(monthly)} ayırırsan $n ayda biriktirirsin (${monthLabel(addM(nm, n - 1), s.lang)}). Bu, $share.',
            'Setting aside ${money(monthly)} a month, you get there in $n months (${monthLabel(addM(nm, n - 1), s.lang)}). That is $share.');
    opts.add(AffordOption(OptState.ok, s.pick('Biriktirerek', 'By saving up'), txt, action: btn(s.pick('İstek listesine ekle', 'Add to wish list'), () => onWish(monthly))));
  } else {
    opts.add(AffordOption(OptState.no, s.pick('Biriktirerek', 'By saving up'), s.pick('Önümüzdeki aylarda serbest para görünmüyor.', 'No free money shows up in the coming months.')));
  }
  return opts;
}

// ---------------------------------------------------------------- Sayfa

class AlisverisPage extends StatefulWidget {
  const AlisverisPage({super.key});

  @override
  State<AlisverisPage> createState() => _AlisverisPageState();
}

class _AlisverisPageState extends State<AlisverisPage> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  bool _nameAuto = false;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _onUrl(String v) {
    final guess = nameFromUrl(v);
    if (guess.isNotEmpty && (_name.text.trim().isEmpty || _nameAuto)) {
      _name.text = guess;
      _nameAuto = true;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final mm = ctx.model;
    final nm = addM(ctx.cur, 1);
    final sN = ctx.sum(nm);
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final k = parseAmount(_price.text);
    final site = siteOf(_url.text);
    final nmLoc = s.isTr ? kMonthsLocTr[int.parse(nm.substring(5, 7)) - 1] : 'In ${monthName(nm, s.lang)}';

    final phone = isPhoneLayout(context);
    return SingleChildScrollView(
      padding: phone ? const EdgeInsets.fromLTRB(16, 6, 16, 96) : const EdgeInsets.fromLTRB(28, 14, 28, 56),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Açık renkli fotoğrafta okunması için rakamlar cam panelin içinde.
        GlassPanel(
          radius: 30,
          cut: 30,
          darkness: 0.46,
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 24,
            runSpacing: 12,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.pick('HARCAMA GÜCÜN', 'YOUR SPENDING POWER'), style: sans(11.5, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.6)),
                const SizedBox(height: 6),
                // Dar ekranda büyük rakam sığmazsa küçülür
                Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Flexible(
                    flex: 3,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: MoneyText(mm.cardAvail, count: true, style: serif(60))),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(s.pick('kartlarda boş limit', 'available on cards'), maxLines: 2, style: sans(15, color: MC.muted)),
                    ),
                  ),
                ]),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(s.pick('Hesaplarda', 'In accounts'), style: sans(12, color: MC.muted)),
                MoneyText(mm.liquid, style: serif(30)),
                const SizedBox(height: 4),
                Text(
                  s.pick('$nmLoc serbest kalacak ≈ ${money(sN.free)}', '$nmLoc you will have ≈ ${money(sN.free)} free'),
                  style: sans(13.5, weight: FontWeight.w600, color: sN.free < 0 ? MC.rose : MC.gold),
                ),
                if (sN.estSpend > 0)
                  Text(s.pick('tahmini ${money(sN.estSpend)} günlük harcama düşüldü', 'estimated ${money(sN.estSpend)} everyday spending deducted'), style: sans(11.5, color: MC.dim)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _Section(
          title: s.pick('Alışveriş siteleri', 'Shopping sites'),
          sub: s.pick('Siteler tarayıcıda açılır. Beğendiğin ürünün linkini kopyalayıp aşağıya yapıştır.', 'Sites open in your browser. Copy the link of a product you like and paste it below.'),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final shop in kShops) _ShopTile(shop: shop),
          ]),
        ),
        _Section(
          title: s.pick('Alabilir miyim?', 'Can I afford it?'),
          sub: s.pick('Linki ve fiyatı yaz; nakit, kart, taksit ve biriktirme seçenekleri hesaplanır.', 'Enter the link and price; cash, card, instalment and saving options are worked out.'),
          trailing: _url.text.isNotEmpty || _name.text.isNotEmpty || _price.text.isNotEmpty
              ? SmallButton(
                  label: s.pick('Temizle', 'Clear'),
                  icon: Icons.close,
                  onTap: () => setState(() {
                    _url.clear();
                    _name.clear();
                    _price.clear();
                    _nameAuto = false;
                  }),
                )
              : null,
          child: GlassPanel(
            radius: 30,
            cut: 30,
            padding: const EdgeInsets.all(20),
            child: TwoColumns(
              leftFlex: 9,
              rightFlex: 14,
              breakpoint: 760,
              left: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Field(
                  label: s.pick('Ürün linki', 'Product link'),
                  child: TextField(controller: _url, style: sans(14.5), onChanged: _onUrl, decoration: fieldDecoration(hint: 'https://www.trendyol.com/...')),
                ),
                if (_url.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: site == null
                        ? Text(s.pick('Geçerli bir link değil (https:// ile başlamalı).', 'Not a valid link (it should start with https://).'), style: sans(12, color: MC.rose))
                        : Row(children: [
                            if (shopPlate(site.id) case final logo?) ...[logo, const SizedBox(width: 8)],
                            Text(site.name, style: sans(12.5, weight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            SmallButton(label: s.pick('Ürünü aç', 'Open product'), icon: Icons.open_in_new, onTap: () => openLink(context, _url.text)),
                          ]),
                  ),
                const SizedBox(height: 12),
                _Field(
                  label: s.pick('Ürün adı', 'Product name'),
                  child: TextField(
                    controller: _name,
                    style: sans(14.5),
                    onChanged: (_) => setState(() => _nameAuto = false),
                    decoration: fieldDecoration(hint: s.pick('Linkten tahmin edilir; değiştirebilirsin', 'Guessed from the link; you can change it')),
                  ),
                ),
                const SizedBox(height: 12),
                _Field(
                  label: s.pick('Fiyat', 'Price'),
                  child: TextField(
                    controller: _price,
                    style: sans(14.5),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: fieldDecoration(hint: s.pick('ör. 2.499,90', 'e.g. 2,499.90'), suffix: 'TL'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(s.pick('Sitenin sayfası uygulamadan okunmadığı için fiyatı sen yazıyorsun. İstek listesine eklersen link de saklanır.',
                    'The shop page is not read by the app, so you type the price. If you add it to the wish list, the link is kept too.'),
                    style: sans(12, color: MC.dim, height: 1.4)),
              ]),
              right: k == null || k <= 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
                      child: Column(children: [
                        const Icon(Icons.balance_outlined, size: 40, color: MC.gold),
                        const SizedBox(height: 10),
                        Text(s.pick('Fiyatı yazınca nakit, kart, taksit ve biriktirme seçenekleri güncel durumuna göre hesaplanır.',
                            'Once you enter a price, cash, card, instalment and saving options are worked out from your current figures.'),
                            textAlign: TextAlign.center, style: sans(13.5, color: MC.muted, height: 1.45)),
                      ]),
                    )
                  : _AffordOut(
                      ctx: ctx,
                      k: k,
                      name: _name.text.trim(),
                      site: site?.name,
                      onBuy: (card, n) => openSpendSheet(context, prefill: {
                        'name': _name.text.trim().isEmpty ? s.pick('Alışveriş', 'Purchase') : _name.text.trim(),
                        'amount': fromK(k),
                        'category': 'alisveris',
                        'url': safeUrl(_url.text),
                        'place': site?.name ?? '',
                        if (card != null) 'source': 'card:$card',
                        'installments': n,
                      }),
                      onWish: (monthly) => openGoalSheet(context, prefill: {
                        'name': _name.text.trim(),
                        'target': fromK(k),
                        'url': safeUrl(_url.text),
                        'monthlyPlan': fromK(monthly),
                      }),
                    ),
            ),
          ),
        ),
        const _Wishlist(),
        const _Purchases(),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.sub, required this.child, this.trailing});

  final String title;
  final String sub;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: serif(32, shadows: kBigTextShadow)),
              const SizedBox(height: 3),
              Text(sub, style: sans(13.5, color: MC.text, weight: FontWeight.w500, shadows: kBigTextShadow)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: sans(12.5, weight: FontWeight.w600, color: MC.label)),
        const SizedBox(height: 6),
        child,
      ]);
}

class _ShopTile extends StatefulWidget {
  const _ShopTile({required this.shop});

  final ShopInfo shop;

  @override
  State<_ShopTile> createState() => _ShopTileState();
}

class _ShopTileState extends State<_ShopTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sh = widget.shop;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => openLink(context, sh.url),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 168,
          height: 92,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          decoration: ShapeDecoration(
            color: _hover ? const Color(0xF2FFFFFF) : const Color(0xE6FFFFFF),
            shape: const SignatureBorder(cut: 14, radius: 14),
            shadows: [BoxShadow(color: const Color(0x55000000), blurRadius: _hover ? 22 : 14, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Eski uygulamadaki gibi sitenin kendi logosu (yoksa adı).
            Expanded(
              child: Center(
                child: shopLogo(sh.id, maxWidth: 140, maxHeight: 40) ??
                    Text(sh.name, style: serif(25, color: const Color(0xFF1B1712), weight: FontWeight.w700)),
              ),
            ),
            Row(children: [
              Expanded(
                child: Text(Uri.parse(sh.url).host.replaceFirst('www.', ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11, color: const Color(0xFF5A534A))),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.open_in_new, size: 14, color: Color(0xFF5A534A)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _AffordOut extends StatelessWidget {
  const _AffordOut({required this.ctx, required this.k, required this.name, required this.site, required this.onBuy, required this.onWish});

  final Ctx ctx;
  final int k;
  final String name;
  final String? site;
  final void Function(String? card, int n) onBuy;
  final void Function(int monthly) onWish;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    String money(int v) => fmtMoney(v, lang: s.lang, hidden: st.hidden);
    final opts = affordOptions(context, ctx, k, onBuy: onBuy, onWish: onWish);
    Widget icon(OptState x) => switch (x) {
          OptState.ok => const Icon(Icons.check_circle, color: MC.mint, size: 22),
          OptState.warn => const Icon(Icons.error, color: Color(0xFFE8C06A), size: 22),
          OptState.no => const Icon(Icons.cancel, color: MC.rose, size: 22),
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: name.isEmpty ? s.pick('Ürün', 'Product') : name, style: sans(15, weight: FontWeight.w700)),
            if (site != null) TextSpan(text: ' · $site', style: sans(13, color: MC.muted)),
          ])),
        ),
        Text(money(k), style: serif(30, color: MC.gold)),
      ]),
      const SizedBox(height: 8),
      for (final o in opts)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: ShapeDecoration(
            color: const Color(0x2A000000),
            shape: SignatureBorder(
              cut: 12,
              radius: 12,
              side: BorderSide(
                color: switch (o.state) {
                  OptState.ok => MC.mint.withValues(alpha: 0.35),
                  OptState.warn => const Color(0x66E8C06A),
                  OptState.no => MC.rose.withValues(alpha: 0.35),
                },
              ),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              icon(o.state),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.title, style: sans(14, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(o.text, style: sans(12.5, color: MC.muted, height: 1.45)),
                ]),
              ),
              if (o.action != null) ...[const SizedBox(width: 8), o.action!],
            ]),
            if (o.table != null) ...[
              const SizedBox(height: 8),
              for (final r in o.table!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const SizedBox(width: 32),
                    Icon(r.ok ? Icons.check : Icons.error_outline, size: 16, color: r.ok ? MC.mint : const Color(0xFFE8C06A)),
                    const SizedBox(width: 8),
                    SizedBox(width: 74, child: Text(s.pick('${r.n} taksit', '${r.n} instalments'), style: sans(12.5, weight: FontWeight.w600))),
                    SizedBox(width: 108, child: Text('${money(r.monthlyK)} / ${s.pick('ay', 'mo')}', textAlign: TextAlign.right, style: sans(12.5))),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 108,
                      child: Text('${monthShortLabel(r.first, s.lang)} – ${monthShortLabel(r.last, s.lang)}', style: sans(12, color: MC.muted)),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: s.pick('En sıkışık ay: ${monthLabel(r.worstMonth, s.lang)}', 'Tightest month: ${monthLabel(r.worstMonth, s.lang)}'),
                        child: Text(
                          r.ok
                              ? s.pick('her ay ≥ ${money(r.worstFree)} kalır', '≥ ${money(r.worstFree)} left each month')
                              : s.pick('${money(-r.worstFree)} eksik (${monthShortLabel(r.worstMonth, s.lang)})', '${money(-r.worstFree)} short (${monthShortLabel(r.worstMonth, s.lang)})'),
                          textAlign: TextAlign.right,
                          style: sans(12.5, weight: FontWeight.w600, color: r.ok ? MC.mint : MC.rose),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(label: s.pick('Seç', 'Pick'), icon: Icons.check, onTap: () => onBuy(_bestCard(ctx, k), r.n)),
                  ]),
                ),
            ],
          ]),
        ),
      const SizedBox(height: 10),
      Text(
        s.pick('Hesap, uygulamadaki güncel verilerle yapılır. Kart ekstresi girilmemiş aylarda o kartın ödemesi bilinmez. Bu bir öneri değil, mevcut rakamların özetidir.',
            'This uses the current figures in the app. For months without a card statement, that card\'s payment is not known. It is not advice, just a summary of your numbers.'),
        style: sans(11.5, color: MC.dim, height: 1.4),
      ),
    ]);
  }
}

/// Taksit için en çok boş limiti olan kart.
String? _bestCard(Ctx ctx, int k) {
  String? best;
  var bestAvail = -1;
  for (final c in ctx.data.debts) {
    final info = ctx.model.debts[c.id];
    if (!c.isCard || info?.limit == null) continue;
    final a = info!.available ?? 0;
    if (a >= k && a > bestAvail) {
      best = c.id;
      bestAvail = a;
    }
  }
  return best;
}

// ---------------------------------------------------------------- İstek listesi

class _Wishlist extends StatelessWidget {
  const _Wishlist();

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final active = activeGoalsSorted(d);
    final bought = d.goals.where((g) => !g.isActive).toList();
    final totalSaved = sumK(active, (Goal g) => ctx.model.goals[g.id]?.saved ?? 0);
    final totalTarget = sumK(active, (Goal g) => ctx.model.goals[g.id]?.target ?? 0);
    return _Section(
      title: s.pick('İstek listesi', 'Wish list'),
      sub: d.goals.isEmpty
          ? s.pick('Almak istediklerin ve onlar için ayırdığın para', 'Things you want and the money you set aside for them')
          : s.pick('${active.length} aktif hedef · biriken ${money(totalSaved)} / ${money(totalTarget)} · bu ay ayrılan ${money(ctx.sum(ctx.cur).savingsActual)}',
              '${active.length} active · saved ${money(totalSaved)} / ${money(totalTarget)} · set aside this month ${money(ctx.sum(ctx.cur).savingsActual)}'),
      trailing: GoldButton(label: s.pick('Ekle', 'Add'), icon: Icons.add, onTap: () => openGoalSheet(context)),
      child: d.goals.isEmpty
          ? EmptyCard(
              icon: Icons.card_giftcard,
              title: s.pick('İstek listen boş', 'Your wish list is empty'),
              text: s.pick('Almak istediğin şeyleri ekle ya da yukarıdaki hesaplamadan "İstek listesine ekle" de; para ayırdıkça ne kadar yaklaştığını görürsün.',
                  'Add things you want, or use "Add to wish list" above; as you set money aside you see how close you are.'),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 14, runSpacing: 14, children: [for (final g in active) GoalCard(goal: g)]),
              if (bought.isNotEmpty) ...[
                const SizedBox(height: 14),
                GlassPanel(
                  radius: 26,
                  cut: 26,
                  child: Column(children: [
                    for (var i = 0; i < bought.length; i++) ...[
                      if (i > 0) const Hairline(),
                      RowItem(
                        leading: Text(bought[i].emoji, style: const TextStyle(fontSize: 24)),
                        title: bought[i].name,
                        subtitle: (srcCard(bought[i].boughtVia) != null || bought[i].boughtVia == 'kart' ? s.pick('Kartla alındı', 'Bought by card') : s.pick('Nakit alındı', 'Bought with cash')) +
                            (bought[i].boughtAt != null ? ' · ${fmtDate(bought[i].boughtAt, s.lang)}' : ''),
                        trailing: Text(money(toK(bought[i].boughtPrice ?? bought[i].target)), style: sans(14, weight: FontWeight.w700)),
                        onTap: () => openGoalSheet(context, goal: bought[i]),
                      ),
                    ],
                  ]),
                ),
              ],
            ]),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final g = goal;
    final info = st.ctx.model.goals[g.id];
    if (info == null) return const SizedBox.shrink();
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final reached = info.target > 0 && info.saved >= info.target;
    final link = safeUrl(g.url);
    final (projText, projColor) = reached
        ? (s.pick('Hedefe ulaşıldı', 'Goal reached'), MC.mint)
        : info.completion != null
            ? (s.pick('Tahmini: ${monthLabel(info.completion, s.lang)}', 'Expected: ${monthLabel(info.completion, s.lang)}'), MC.gold)
            : (s.pick('Aylık ayırma tutarı belirtilmemiş', 'No monthly amount set'), MC.muted);
    Widget chip(String text, Color color) => Container(
          margin: const EdgeInsets.only(right: 6, top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
          child: Text(text, style: sans(11.5, color: color == MC.muted ? MC.text : color, weight: FontWeight.w600)),
        );
    return SizedBox(
      width: 340,
      child: GlassPanel(
        tint: kGroups['birikim']!.color,
        radius: 26,
        cut: 26,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(alignment: Alignment.center, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: info.pct),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CustomPaint(size: const Size(72, 72), painter: _RingPainter(v, kGroups['birikim']!.color)),
                ),
                Text(g.emoji, style: const TextStyle(fontSize: 28)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(23)),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  TextSpan(text: money(info.saved), style: sans(14, weight: FontWeight.w700)),
                  TextSpan(text: ' / ${money(info.target)} · %${(info.pct * 100).round()}', style: sans(12.5, color: MC.muted)),
                ])),
              ]),
            ),
          ]),
          Wrap(children: [
            chip(s.pick('${(kPriorities[g.priority] ?? const Lbl('Orta', 'Medium')).of(s.lang)} öncelik', '${(kPriorities[g.priority] ?? const Lbl('Orta', 'Medium')).of(s.lang)} priority'), MC.muted),
            if (g.monthlyPlan != null) chip(s.pick('Ayda ${money(toK(g.monthlyPlan))}', '${money(toK(g.monthlyPlan))} a month'), MC.muted),
            chip(projText, projColor),
          ]),
          if (g.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(maskTxt(g.note, st.hidden), style: sans(12.5, color: MC.muted))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                GoldButton(label: s.pick('Para ayır', 'Set aside'), onTap: () => openGoalSaveSheet(context, g)),
                GlassButton(label: s.pick('Aldım', 'Bought it'), onTap: () => openGoalBuySheet(context, g)),
              ]),
            ),
            if (link.isNotEmpty) IconButton(tooltip: s.pick('Ürüne git', 'Open product'), onPressed: () => openLink(context, link), icon: const Icon(Icons.open_in_new, size: 18, color: MC.muted)),
            IconButton(tooltip: s.pick('Düzenle', 'Edit'), onPressed: () => openGoalSheet(context, goal: g), icon: const Icon(Icons.edit_outlined, size: 18, color: MC.muted)),
          ]),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.color);

  final double p;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final r = size.width / 2 - stroke / 2;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0x24FFFFFF));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * p.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p || old.color != color;
}

// ---------------------------------------------------------------- Taksitli alışverişler

class _Purchases extends StatelessWidget {
  const _Purchases();

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final list = d.spends.where((p) => srcCard(p.source) != null && p.installments > 1).toList()..sort((a, b) => b.date.compareTo(a.date));
    return _Section(
      title: s.pick('Taksitli kart alışverişleri', 'Card purchases in instalments'),
      sub: s.pick('Tutarın tamamı limitten düşer; taksitler ilgili ayın kart ödemesine eklenir.', 'The full amount comes off the limit; instalments are added to each month\'s card payment.'),
      trailing: GlassButton(label: s.pick('Taksitli alışveriş', 'Instalment purchase'), icon: Icons.add_shopping_cart, onTap: () => openSpendSheet(context, prefill: {'installments': 3})),
      child: list.isEmpty
          ? Text(s.pick('Taksitli kart alışverişi yok. Tek çekim harcamalar Harcamalar sayfasında.', 'No card purchases in instalments. Single payments are on the Spending page.'),
              style: sans(13, color: MC.muted, shadows: kPhotoTextShadow))
          : GlassPanel(
              radius: 26,
              cut: 26,
              child: Column(children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Hairline(),
                  Builder(builder: (_) {
                    final p = list[i];
                    final ps = ctx.purchaseState(p);
                    final card = d.debt(srcCard(p.source));
                    final sub = [
                      card?.creditor ?? s.pick('kart', 'card'),
                      s.pick('${ps.billedN}/${p.installments} taksit ekstreye yansıdı', '${ps.billedN}/${p.installments} instalments billed'),
                      s.pick('aylık ${money(ps.monthly)}', '${money(ps.monthly)} a month'),
                      s.pick('bitiş ${monthLabel(ps.end, s.lang)}', 'ends ${monthLabel(ps.end, s.lang)}'),
                      fmtDate(p.date, s.lang),
                    ];
                    return RowItem(
                      leading: BankPlate(bankKey: bankKeyOf(card), name: card?.creditor, size: 28),
                      title: p.name.isEmpty ? s.pick('Alışveriş', 'Purchase') : p.name,
                      subtitle: sub.join(' · '),
                      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        MoneyText(toK(p.amount), style: sans(14.5, weight: FontWeight.w700)),
                        if (ps.remainK > 0) Text(s.pick('kalan ${money(ps.remainK)}', '${money(ps.remainK)} left'), style: sans(11.5, color: MC.muted)),
                      ]),
                      onTap: () => openSpendSheet(context, spend: p),
                    );
                  }),
                ],
              ]),
            ),
    );
  }
}
