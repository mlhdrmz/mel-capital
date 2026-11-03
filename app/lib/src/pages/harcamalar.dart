import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/actions.dart';
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

/// Harcama listesindeki bir satır: harcama ya da o ayki abonelik/fatura.
class SpendLine {
  const SpendLine({
    required this.id,
    required this.name,
    required this.date,
    required this.k,
    required this.category,
    this.source,
    this.place = '',
    this.createdAt = '',
    this.installments = 1,
    this.note = '',
    this.isSub = false,
  });

  factory SpendLine.of(Spend x) => SpendLine(
        id: x.id,
        name: x.name,
        date: x.date,
        k: toK(x.amount),
        category: x.category,
        source: x.source,
        place: x.place,
        createdAt: x.createdAt ?? '',
        installments: x.installments,
        note: x.note,
      );

  final String id;
  final String name;
  final String date;
  final int k;
  final String category;
  final String? source;
  final String place;
  final String createdAt;
  final int installments;
  final String note;
  final bool isSub;
}

int _byDateDesc(SpendLine a, SpendLine b) {
  final c = b.date.compareTo(a.date);
  return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
}

/// Aktif abonelik ve faturalar ödeme gününde gider olarak görünür (ödendiyse ödenen tutar ve tarih).
List<SpendLine> subSpendsIn(Ctx ctx, String m) {
  final d = ctx.data;
  final cur = ctx.cur;
  final today = todayISO();
  final out = <SpendLine>[];
  if (m.compareTo(cur) > 0) return out;
  final nD = daysInMonth(m);
  for (final s in d.subscriptions) {
    final pay = ctx.model.pay('sub', s.id, m);
    final dayISO = '$m-${two(math.min(s.day ?? 1, nD))}';
    int k;
    String date;
    var src = s.source;
    if (pay != null) {
      k = pay.k;
      final pd = pay.paidDate;
      date = pd != null && isDate(pd) && monthOf(pd) == m ? pd : dayISO;
      for (final p in pay.list) {
        if (p.fromAccount != null) {
          src = p.fromAccount;
          break;
        }
      }
    } else {
      if (!s.active) continue;
      k = subAmountK(s, m);
      if (k <= 0) continue;
      date = dayISO;
      if (m == cur && date.compareTo(today) > 0) continue;
    }
    out.add(SpendLine(id: s.id, name: s.name, date: date, k: k, source: src, category: s.isBill ? 'fatura' : 'abonelik', isSub: true));
  }
  return out;
}

/// Listede en çok geçen kaynak (yarısından fazlası) satırlarda ayrıca yazılmaz.
String? usualSource(List<SpendLine> list) {
  final cnt = <String, int>{};
  for (final x in list) {
    final s = x.source;
    if (s != null) cnt[s] = (cnt[s] ?? 0) + 1;
  }
  String? best;
  var n = 0;
  cnt.forEach((k, v) {
    if (v > n) {
      best = k;
      n = v;
    }
  });
  return best != null && list.length >= 3 && n / list.length >= 0.5 ? best : null;
}

/// Arama: ad, yer, not, kategori, kaynak; tutar yazılırsa o tutardaki harcamalar. Tüm aylarda.
List<SpendLine> spendSearch(Data d, String q, String lang) {
  final nq = normTxt(q);
  if (nq.isEmpty) return const [];
  final k = RegExp(r'^[\d.,\s]+(tl)?$', caseSensitive: false).hasMatch(q.trim()) ? parseAmount(q) : null;
  final words = nq.split(' ');
  final out = <SpendLine>[];
  for (final x in d.spends) {
    if (k != null && toK(x.amount) == k) {
      out.add(SpendLine.of(x));
      continue;
    }
    final hay = normTxt([x.name, x.place, x.note, catLabel(x.category, lang), sourceName(d, x.source, lang)].join(' '));
    if (words.every(hay.contains)) out.add(SpendLine.of(x));
  }
  out.sort(_byDateDesc);
  return out.take(300).toList();
}

/// Harcamalar: aylık liste, kategoriler, kaynaklar; ikinci sekmede abonelikler ve faturalar.
class HarcamalarPage extends StatefulWidget {
  const HarcamalarPage({super.key});

  @override
  State<HarcamalarPage> createState() => _HarcamalarPageState();
}

class _HarcamalarPageState extends State<HarcamalarPage> {
  bool _subs = false;
  String? _month;
  String _src = '';
  String _cat = '';
  final _query = TextEditingController();
  final Set<String> _open = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(SpendLine x, {bool ignoreCat = false}) {
    final f = _src;
    if (f == 'hesap' && srcCard(x.source) != null) return false;
    if (f == 'kart' && srcCard(x.source) == null) return false;
    if (f.isNotEmpty && f != 'hesap' && f != 'kart' && x.source != f) return false;
    if (!ignoreCat && _cat.isNotEmpty && x.category != _cat) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final ctx = st.ctx;
    final activeSubs = ctx.data.subscriptions.where((x) => x.active).length;
    final tabs = _SegTabs(
      subs: _subs,
      count: activeSubs,
      onChanged: (v) => setState(() => _subs = v),
    );
    return _subs ? _subsView(context, ctx, tabs) : _spendsView(context, ctx, tabs);
  }

  // ---------------------------------------------------------------- Harcamalar

  Widget _spendsView(BuildContext context, Ctx ctx, Widget tabs) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = ctx.data;
    final cur = ctx.cur;
    final m = _month ?? cur;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final all = [for (final x in spendsIn(d, m)) SpendLine.of(x), ...subSpendsIn(ctx, m)];
    final tot = sumK(all, (SpendLine x) => x.k);
    final onCard = sumK(all.where((x) => srcCard(x.source) != null), (SpendLine x) => x.k);
    final nDays = m == cur ? dayOf(todayISO()) : daysInMonth(m);
    final avg = nDays > 0 ? (tot / nDays).round() : 0;

    final cats = <String, int>{};
    for (final x in all.where((x) => _matches(x, ignoreCat: true))) {
      cats[x.category] = (cats[x.category] ?? 0) + x.k;
    }
    final catRows = cats.entries.toList()..sort((a, b) => b.value - a.value);
    final srcs = <String, int>{};
    for (final x in all) {
      final k = x.source ?? '';
      srcs[k] = (srcs[k] ?? 0) + x.k;
    }
    final srcRows = srcs.entries.toList()..sort((a, b) => b.value - a.value);

    final search = SizedBox(
      width: 230,
      child: TextField(
        controller: _query,
        style: sans(14),
        onChanged: (_) => setState(() {}),
        decoration: fieldDecoration(hint: s.pick('Ara: ad, yer, tutar', 'Search: name, place, amount')).copyWith(
          prefixIcon: const Icon(Icons.search, size: 18, color: MC.muted),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
      ),
    );
    final nav = Row(mainAxisSize: MainAxisSize.min, children: [
      _NavButton(icon: Icons.chevron_left, tip: s.pick('Önceki ay', 'Previous month'), onTap: () => setState(() => _month = addM(m, -1))),
      const SizedBox(width: 6),
      _NavButton(icon: Icons.chevron_right, tip: s.pick('Sonraki ay', 'Next month'), onTap: () => setState(() => _month = addM(m, 1))),
      if (m != cur) ...[
        const SizedBox(width: 6),
        GlassButton(label: s.pick('Bu ay', 'This month'), onTap: () => setState(() => _month = null)),
      ],
    ]);

    final q = _query.text.trim();
    return PageFrame(
      eyebrow: s.pick('HARCAMALAR', 'SPENDING'),
      title: monthLabel(m, s.lang),
      actions: [
        search,
        nav,
        GoldButton(label: s.pick('Harcama', 'Spend'), icon: Icons.add, onTap: () => openSpendSheet(context)),
        GlassButton(label: s.pick('Hızlı giriş', 'Quick entry'), icon: Icons.bolt, onTap: () => openQuickSpendSheet(context)),
      ],
      children: [
        tabs,
        const SizedBox(height: 14),
        KpiRow(children: [
          Kpi(label: s.pick('Toplam', 'Total'), k: tot, sub: s.pick('${all.length} kayıt', '${all.length} records'), color: MC.violet, delay: const Duration(milliseconds: 40)),
          Kpi(
            label: s.pick('Hesaptan ve nakit', 'From accounts and cash'),
            k: tot - onCard,
            sub: s.pick('Abonelik ve faturalar dahil', 'Including subscriptions and bills'),
            color: MC.gold,
            delay: const Duration(milliseconds: 90),
            onTap: () => setState(() => _src = _src == 'hesap' ? '' : 'hesap'),
          ),
          Kpi(
            label: s.pick('Kartla', 'By card'),
            k: onCard,
            sub: s.pick('Kartın ekstresiyle ödenir', 'Paid with the card statement'),
            color: MC.rose,
            delay: const Duration(milliseconds: 140),
            onTap: () => setState(() => _src = _src == 'kart' ? '' : 'kart'),
          ),
          Kpi(
            label: s.pick('Günlük ortalama', 'Daily average'),
            k: avg,
            sub: m == cur ? s.pick('Ayın ilk $nDays günü', 'First $nDays days of the month') : s.pick('$nDays gün', '$nDays days'),
            color: MC.sky,
            delay: const Duration(milliseconds: 190),
          ),
        ]),
        if (all.isNotEmpty && q.isEmpty) ...[
          const SizedBox(height: 14),
          _filters(context, d, catRows, srcs.keys.where((k) => k.isNotEmpty).toList()),
        ],
        const SizedBox(height: 14),
        TwoColumns(
          left: _list(context, ctx, m, all),
          right: all.isEmpty
              ? GlassPanel(
                  delay: const Duration(milliseconds: 240),
                  radius: 30,
                  cut: 30,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PanelHead(s.pick('İpucu', 'Tip')),
                    Text(
                      s.pick('Hızlı girişte her satıra "kahve 85" gibi ad ve tutar yaz; virgülle de ayırabilirsin: "kahve 85, market 340". Kategori, daha önce aynı adla girdiğin harcamadan öğrenilir.',
                          'In quick entry, write a name and an amount on each line, like "coffee 85"; commas work too: "coffee 85, groceries 340". The category is learned from earlier spends with the same name.'),
                      style: sans(13, color: MC.muted, height: 1.45),
                    ),
                  ]),
                )
              : Column(children: [
                  _CategoriesPanel(rows: catRows, selected: _cat, filtered: _src.isNotEmpty, onTap: (c) => setState(() => _cat = _cat == c ? '' : c)),
                  const SizedBox(height: 14),
                  GlassPanel(
                    delay: const Duration(milliseconds: 300),
                    radius: 30,
                    cut: 30,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      PanelHead(s.pick('Nereden ödendi', 'Paid from'), subtitle: s.pick('Kart harcamaları ekstreyle ödenir', 'Card spends are paid with the statement')),
                      _Bars(
                        rows: [
                          for (final e in srcRows)
                            _BarRow(
                              key: e.key,
                              label: SourceChip(source: e.key.isEmpty ? null : e.key),
                              k: e.value,
                              color: srcCard(e.key) != null ? const Color(0xFFE58F84) : const Color(0xFF8FC3E0),
                              on: _src == e.key && e.key.isNotEmpty,
                            ),
                        ],
                        money: money,
                        onTap: (k) => setState(() => _src = _src == k ? '' : k),
                      ),
                    ]),
                  ),
                ]),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context, Data d, List<MapEntry<String, int>> catRows, List<String> sources) {
    final st = AppScope.of(context);
    final s = S.of(context);
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    Widget chip({required String label, required bool on, required VoidCallback onTap, Color? dot, String? amount}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: on ? MC.gold : const Color(0x38000000),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: on ? MC.gold : const Color(0x33FFFFFF)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (dot != null) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 7)],
                Text(label, style: sans(13, weight: FontWeight.w600, color: on ? MC.ink : MC.text, shadows: on ? null : kPhotoTextShadow)),
                if (amount != null) ...[const SizedBox(width: 7), Text(amount, style: sans(12.5, color: on ? MC.ink : MC.muted, shadows: on ? null : kPhotoTextShadow))],
              ]),
            ),
          ),
        );
    final srcItems = <(String, String)>[
      ('', s.pick('Tüm kaynaklar', 'All sources')),
      ('hesap', s.pick('Hesaplar ve nakit', 'Accounts and cash')),
      ('kart', s.pick('Kredi kartları', 'Credit cards')),
      for (final k in sources) (k, sourceName(d, k, s.lang)),
    ];
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip(label: s.pick('Tümü', 'All'), on: _cat.isEmpty, onTap: () => setState(() => _cat = '')),
              for (final r in catRows)
                chip(
                  label: catLabel(r.key, s.lang),
                  on: _cat == r.key,
                  dot: catColor(r.key),
                  amount: money(r.value),
                  onTap: () => setState(() => _cat = _cat == r.key ? '' : r.key),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        GlassSelect<String>(value: _src, items: srcItems, width: 210, onChanged: (v) => setState(() => _src = v ?? '')),
        if (_src.isNotEmpty || _cat.isNotEmpty) ...[
          const SizedBox(width: 6),
          SmallButton(label: s.pick('Temizle', 'Clear'), icon: Icons.close, onTap: () => setState(() {
                _src = '';
                _cat = '';
              })),
        ],
      ],
    );
  }

  Widget _list(BuildContext context, Ctx ctx, String m, List<SpendLine> all) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = ctx.data;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final q = _query.text.trim();
    if (q.isNotEmpty) {
      final res = spendSearch(d, q, s.lang);
      if (res.isEmpty) {
        return GlassPanel(
          delay: const Duration(milliseconds: 200),
          radius: 30,
          cut: 30,
          child: Text(
            s.pick('“$q” için harcama bulunamadı. Ad, yer, not, kategori ya da tutar yazabilirsin.', 'No spends found for “$q”. Try a name, place, note, category or amount.'),
            style: sans(13.5, color: MC.muted),
          ),
        );
      }
      final hide = usualSource(res);
      return GlassPanel(
        delay: const Duration(milliseconds: 200),
        radius: 30,
        cut: 30,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(s.pick('${res.length} sonuç', '${res.length} results'), style: sans(14, weight: FontWeight.w700)),
            Text(s.pick('tüm aylarda · toplam ${money(sumK(res, (SpendLine x) => x.k))}', 'all months · total ${money(sumK(res, (SpendLine x) => x.k))}'),
                style: sans(12.5, color: MC.muted)),
            if (hide != null) ...[
              Text(s.pick('kaynağı yazmayanlar', 'rows without a source:'), style: sans(12.5, color: MC.muted)),
              SourceChip(source: hide, compact: true),
            ],
          ]),
          const SizedBox(height: 8),
          ..._dayGroups(context, res, hide, anyYear: true),
        ]),
      );
    }
    final list = all.where((x) => _matches(x)).toList()..sort(_byDateDesc);
    if (list.isEmpty) {
      return EmptyCard(
        icon: Icons.receipt_long_outlined,
        title: all.isNotEmpty ? s.pick('Filtreye uyan harcama yok', 'Nothing matches the filter') : s.pick('${monthLabel(m, s.lang)} için harcama yok', 'No spends in ${monthLabel(m, s.lang)}'),
        text: all.isNotEmpty
            ? s.pick('Filtreyi değiştir ya da temizle.', 'Change or clear the filter.')
            : s.pick('Tek tek ekleyebilir ya da "Hızlı giriş" ile birçok küçük harcamayı tek seferde girebilirsin.', 'Add them one by one, or enter many small spends at once with "Quick entry".'),
        actions: all.isNotEmpty
            ? const []
            : [
                GoldButton(label: s.pick('Harcama ekle', 'Add a spend'), icon: Icons.add, onTap: () => openSpendSheet(context)),
                GlassButton(label: s.pick('Hızlı giriş', 'Quick entry'), icon: Icons.bolt, onTap: () => openQuickSpendSheet(context)),
              ],
      );
    }
    final hide = usualSource(list);
    return GlassPanel(
      delay: const Duration(milliseconds: 200),
      radius: 30,
      cut: 30,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hide != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Text(s.pick('Kaynağı yazmayan satırlar ', 'Rows without a source: '), style: sans(12.5, color: MC.muted)),
              SourceChip(source: hide, compact: true),
            ]),
          ),
        ..._dayGroups(context, list, hide, anyYear: false),
      ]),
    );
  }

  List<Widget> _dayGroups(BuildContext context, List<SpendLine> list, String? hide, {required bool anyYear}) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final today = todayISO();
    final days = <String, List<SpendLine>>{};
    for (final x in list) {
      days.putIfAbsent(x.date, () => []).add(x);
    }
    final out = <Widget>[];
    days.forEach((day, arr) {
      final label = anyYear && day.length >= 4 && day.substring(0, 4) != today.substring(0, 4) ? fmtDate(day, s.lang) : fmtDayShort(day, s.lang);
      out.add(Padding(
        padding: EdgeInsets.only(top: out.isEmpty ? 2 : 14, bottom: 4),
        child: Row(children: [
          Text(label, style: sans(13.5, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(weekdayName(day, s.lang) + (day == today ? s.pick(' · bugün', ' · today') : ''), style: sans(12, color: MC.muted)),
          const SizedBox(width: 10),
          const Expanded(child: Hairline()),
          const SizedBox(width: 10),
          Text(fmtMoney(sumK(arr, (SpendLine x) => x.k), lang: s.lang, hidden: st.hidden), style: sans(12.5, color: MC.muted, weight: FontWeight.w600)),
        ]),
      ));
      out.addAll(_rows(context, arr, hide));
    });
    return out;
  }

  List<Widget> _rows(BuildContext context, List<SpendLine> arr, String? hide) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final groups = <String, List<SpendLine>>{};
    final order = <Object>[];
    for (final x in arr) {
      if (x.isSub) {
        order.add(x);
        continue;
      }
      final key = [x.date, normTxt(x.name), x.k, x.source ?? '', x.category].join('|');
      final g = groups[key];
      if (g != null) {
        g.add(x);
      } else {
        groups[key] = [x];
        order.add(key);
      }
    }
    String sub(SpendLine x) {
      final bits = <String>[];
      final nm = normTxt(x.name);
      final cl = catLabel(x.category, s.lang);
      if (x.place.isNotEmpty && normTxt(x.place) != nm) bits.add(x.place);
      if (normTxt(cl) != nm) bits.add(cl);
      return bits.join(' · ');
    }

    final out = <Widget>[];
    for (final o in order) {
      if (o is SpendLine) {
        out.add(_SpendRow(
          lead: CategoryMark(o.category, size: 38),
          name: o.name,
          sub: o.category == 'fatura' ? s.pick('Fatura', 'Bill') : s.pick('Abonelik', 'Subscription'),
          k: o.k,
          source: o.source == hide ? null : o.source,
          onTap: () => openSubSheet(context, sub: d.subscription(o.id)),
        ));
        continue;
      }
      final its = groups[o as String]!;
      final x = its.first;
      final inst = srcCard(x.source) != null && x.installments > 1 ? x.installments : 0;
      final name = x.name.isEmpty ? catLabel(x.category, s.lang) : x.name;
      final subText = sub(x) + (inst > 0 ? s.pick(' · $inst taksit', ' · $inst instalments') : '');
      if (its.length == 1) {
        out.add(_SpendRow(
          lead: CategoryMark(x.category, size: 38),
          name: name,
          sub: subText,
          k: x.k,
          source: x.source == hide ? null : x.source,
          onTap: () => _editSpend(context, x.id),
        ));
        continue;
      }
      final open = _open.contains(o);
      out.add(_SpendRow(
        lead: CategoryMark(x.category, size: 38),
        name: '$name  ${its.length}×',
        sub: '${its.length} × ${fmtMoney(x.k, lang: s.lang, hidden: st.hidden)}${subText.isEmpty ? '' : ' · $subText'}',
        k: sumK(its, (SpendLine y) => y.k),
        source: x.source == hide ? null : x.source,
        trailingIcon: open ? Icons.expand_less : Icons.expand_more,
        onTap: () => setState(() => open ? _open.remove(o) : _open.add(o)),
      ));
      if (open) {
        for (var i = 0; i < its.length; i++) {
          final y = its[i];
          out.add(Padding(
            padding: const EdgeInsets.only(left: 30),
            child: _SpendRow(
              lead: const SizedBox(width: 38),
              name: s.pick('${i + 1}. kayıt', 'Record ${i + 1}'),
              sub: y.note.isNotEmpty ? y.note : s.pick('Düzenlemek için dokun', 'Tap to edit'),
              k: y.k,
              onTap: () => _editSpend(context, y.id),
            ),
          ));
        }
      }
    }
    return out;
  }

  void _editSpend(BuildContext context, String id) {
    final d = AppScope.of(context).data;
    for (final x in d.spends) {
      if (x.id == id) {
        openSpendSheet(context, spend: x);
        return;
      }
    }
  }

  // ---------------------------------------------------------------- Abonelikler

  Widget _subsView(BuildContext context, Ctx ctx, Widget tabs) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = ctx.data;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final subs = d.subscriptions;
    bool priced(Subscription x) => (x.amount ?? 0) > 0;
    final pricedList = subs.where((x) => x.active && priced(x)).toList()..sort((a, b) => subMonthlyK(b) - subMonthlyK(a));
    final unpriced = subs.where((x) => x.active && !priced(x)).toList();
    final paused = subs.where((x) => !x.active).toList();
    final bills = subs.where((x) => x.isBill && x.active).toList();
    final viaCard = sumK(pricedList.where((x) => srcCard(x.source) != null), subMonthlyK);
    final have = {for (final x in subs) slugify(x.name)};
    final sugg = kSubCatalog.where((e) => !have.contains(slugify(e.$1))).toList();
    final bySrc = <String, int>{};
    for (final x in pricedList) {
      final k = x.source ?? '';
      bySrc[k] = (bySrc[k] ?? 0) + subMonthlyK(x);
    }
    final srcRows = bySrc.entries.toList()..sort((a, b) => b.value - a.value);

    Widget section(String title, String sub, List<Subscription> arr) {
      if (arr.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
            Text(title, style: serif(22)),
            Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(sub, style: sans(12, color: MC.muted))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: [for (final x in arr) SubTile(sub: x)]),
        ]),
      );
    }

    return PageFrame(
      eyebrow: s.pick('HARCAMALAR', 'SPENDING'),
      title: s.pick('Abonelikler ve faturalar', 'Subscriptions and bills'),
      actions: [GoldButton(label: s.pick('Abonelik', 'Subscription'), icon: Icons.add, onTap: () => openSubSheet(context))],
      children: [
        tabs,
        const SizedBox(height: 14),
        KpiRow(children: [
          Kpi(
            label: s.pick('Aylık toplam', 'Monthly total'),
            k: ctx.model.subsMonthly,
            sub: s.pick('${pricedList.length} abonelik hesaba katılıyor', '${pricedList.length} subscriptions counted'),
            color: MC.teal,
            delay: const Duration(milliseconds: 40),
          ),
          Kpi(label: s.pick('Yıllık', 'Yearly'), k: ctx.model.subsMonthly * 12, sub: s.pick('Bugünkü fiyatlarla', 'At today\'s prices'), color: MC.violet, delay: const Duration(milliseconds: 90)),
          Kpi(label: s.pick('Kartlardan', 'From cards'), k: viaCard, sub: s.pick('Kart ekstresine eklenir', 'Added to the card statement'), color: MC.rose, delay: const Duration(milliseconds: 140)),
          Kpi(
            label: s.pick('Bekleyen', 'Pending'),
            k: 0,
            text: '${unpriced.length + paused.length}',
            sub: s.pick('${unpriced.length} fiyatsız · ${paused.length} dondurulmuş', '${unpriced.length} without price · ${paused.length} paused'),
            color: MC.gold,
            delay: const Duration(milliseconds: 190),
          ),
        ]),
        const SizedBox(height: 14),
        TwoColumns(
          left: subs.isEmpty
              ? EmptyCard(
                  icon: Icons.autorenew,
                  title: s.pick('Abonelik yok', 'No subscriptions'),
                  text: s.pick('Sağdaki önerilerden seç ya da kendin ekle. Fiyatını girdiğin abonelikler aylık plana ve bilançoya eklenir.',
                      'Pick from the suggestions or add your own. Subscriptions with a price are added to the monthly plan and balance.'),
                  actions: [GoldButton(label: s.pick('Abonelik ekle', 'Add a subscription'), icon: Icons.add, onTap: () => openSubSheet(context))],
                )
              : GlassPanel(
                  delay: const Duration(milliseconds: 200),
                  radius: 30,
                  cut: 30,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    section(s.pick('Ev faturaları', 'Home bills'), s.pick('her ay gelen tutarı gir; girilmezse her zamanki tutar sayılır', 'enter each month\'s amount; otherwise the usual amount counts'), bills),
                    section(s.pick('Hesaba katılanlar', 'Counted'), '${money(sumK(pricedList.where((x) => !x.isBill), subMonthlyK))} / ${s.pick('ay', 'mo')}', pricedList.where((x) => !x.isBill).toList()),
                    section(s.pick('Fiyatı girilmemiş', 'No price yet'), s.pick('fiyatını girince hesaba katılır', 'counted once you enter a price'), unpriced.where((x) => !x.isBill).toList()),
                    section(s.pick('Dondurulmuş', 'Paused'), s.pick('hesaba katılmaz', 'not counted'), paused),
                  ]),
                ),
          right: Column(children: [
            GlassPanel(
              delay: const Duration(milliseconds: 240),
              radius: 30,
              cut: 30,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PanelHead(s.pick('Öneriler', 'Suggestions'), subtitle: s.pick('Tıkla, fiyatını sen gir', 'Tap one and enter its price')),
                if (sugg.isEmpty)
                  Text(s.pick('Hepsi listende.', 'All of them are on your list.'), style: sans(13, color: MC.muted))
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in sugg)
                      InkWell(
                        onTap: () => openSubSheet(context, prefill: {'name': e.$1, 'group': e.$2}),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(4, 4, 11, 4),
                          decoration: BoxDecoration(
                            color: const Color(0x2E000000),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x2EFFFFFF)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Monogram(name: e.$1, group: e.$2, size: 22),
                            const SizedBox(width: 7),
                            Text(e.$1, style: sans(12.5)),
                          ]),
                        ),
                      ),
                  ]),
              ]),
            ),
            const SizedBox(height: 14),
            GlassPanel(
              delay: const Duration(milliseconds: 280),
              radius: 30,
              cut: 30,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PanelHead(s.pick('Nereden ödeniyor', 'Paid from'), subtitle: s.pick('Karttan ödenenler ekstreye eklenir', 'Card ones are added to the statement')),
                if (srcRows.isEmpty) Text(s.pick('Fiyatı girilmiş abonelik yok.', 'No subscription with a price.'), style: sans(13, color: MC.muted)),
                for (final e in srcRows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Flexible(child: SourceChip(source: e.key.isEmpty ? null : e.key)),
                      const Spacer(),
                      Text('${money(e.value)} / ${s.pick('ay', 'mo')}', style: sans(13.5, weight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Text(
              s.pick('Yıllık ödenenler aylık payıyla sayılır. Dondurduğun abonelik kayıtta kalır ama hesaba katılmaz.',
                  'Yearly ones count with their monthly share. A paused subscription stays on record but is not counted.'),
              style: sans(12, color: MC.muted, shadows: kPhotoTextShadow),
            ),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Parçalar

class _SegTabs extends StatelessWidget {
  const _SegTabs({required this.subs, required this.count, required this.onChanged});

  final bool subs;
  final int count;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget tab(bool value, IconData icon, String label, {int? badge}) {
      final on = subs == value;
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: ShapeDecoration(
            color: on ? MC.gold : const Color(0x38000000),
            shape: SignatureBorder(cut: 10, radius: 12, side: BorderSide(color: on ? MC.gold : const Color(0x33FFFFFF))),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: on ? MC.ink : MC.text),
            const SizedBox(width: 8),
            Text(label, style: sans(14, weight: FontWeight.w600, color: on ? MC.ink : MC.text)),
            if (badge != null && badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: on ? const Color(0x33000000) : const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: sans(11.5, weight: FontWeight.w700, color: on ? MC.ink : MC.text)),
              ),
            ],
          ]),
        ),
      );
    }

    return Row(children: [
      tab(false, Icons.receipt_long_outlined, s.pick('Harcamalar', 'Spends')),
      const SizedBox(width: 8),
      tab(true, Icons.autorenew, s.pick('Abonelikler', 'Subscriptions'), badge: count),
    ]);
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          foregroundColor: MC.text,
          backgroundColor: const Color(0x38000000),
          side: const BorderSide(color: Color(0x40FFFFFF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          fixedSize: const Size(46, 46),
        ),
      );
}

class _SpendRow extends StatelessWidget {
  const _SpendRow({required this.lead, required this.name, required this.sub, required this.k, this.source, this.onTap, this.trailingIcon});

  final Widget lead;
  final String name;
  final String sub;
  final int k;
  final String? source;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return RowItem(
      leading: lead,
      title: name,
      subtitle: sub,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (source != null) ...[SourceChip(source: source, compact: true), const SizedBox(width: 12)],
        MoneyText(-k, style: sans(14.5, weight: FontWeight.w700)),
        if (trailingIcon != null) ...[const SizedBox(width: 6), Icon(trailingIcon, size: 18, color: MC.muted)],
      ]),
    );
  }
}

/// Abonelik kutusu: monogram, ad, grup ve gün; altta tutar, ödeme yeri ve dondur düğmesi.
class SubTile extends StatelessWidget {
  const SubTile({super.key, required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final x = sub;
    final priced = (x.amount ?? 0) > 0;
    final bits = <String>[(kSubGroups[x.group] ?? const Lbl('Diğer', 'Other')).of(s.lang)];
    if (x.day != null) bits.add(dayOfMonthText(x.day!, s.lang));
    final src = x.source != null ? sourceName(d, x.source, s.lang) : '';
    final cm = currentMonth();
    Widget amount;
    if (x.isBill) {
      final v = x.monthAmounts[cm];
      amount = InkWell(
        onTap: () => openBillAmountSheet(context, x, cm),
        child: Text(
        v != null
            ? '${monthName(cm, s.lang)}: ${fmtMoney(toK(v), lang: s.lang, hidden: st.hidden)}'
            : priced
                ? '≈ ${fmtMoney(toK(x.amount), lang: s.lang, hidden: st.hidden)}'
                : s.pick('Bu ayın tutarı', 'This month\'s amount'),
        style: sans(13.5, weight: FontWeight.w700, color: v != null ? MC.text : MC.gold),
        ),
      );
    } else if (priced) {
      amount = Text.rich(TextSpan(children: [
        TextSpan(text: fmtMoney(toK(x.amount), lang: s.lang, hidden: st.hidden), style: sans(15, weight: FontWeight.w700)),
        TextSpan(text: x.period == 'yil' ? s.pick(' / yıl', ' / yr') : s.pick(' / ay', ' / mo'), style: sans(11.5, color: MC.muted)),
      ]));
    } else {
      amount = InkWell(onTap: () => openSubSheet(context, sub: x), child: Text(s.pick('Fiyat gir', 'Enter price'), style: sans(13.5, weight: FontWeight.w700, color: MC.gold)));
    }
    return Opacity(
      opacity: x.active ? 1 : 0.6,
      child: Container(
        width: 238,
        padding: const EdgeInsets.fromLTRB(14, 13, 10, 10),
        decoration: ShapeDecoration(
          color: const Color(0x30000000),
          shape: SignatureBorder(cut: 16, radius: 16, side: BorderSide(color: priced || x.isBill ? const Color(0x33FFFFFF) : MC.gold.withValues(alpha: 0.45))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => openSubSheet(context, sub: x),
            borderRadius: BorderRadius.circular(10),
            child: Row(children: [
              Monogram(name: x.name, group: x.group, size: 40),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(14, weight: FontWeight.w600)),
                  Text(bits.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11.5, color: MC.muted)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                amount,
                Text(src.isEmpty ? s.pick('ödeme yeri yok', 'no payment source') : src,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11, color: src.isEmpty ? MC.dim : MC.muted)),
              ]),
            ),
            Tooltip(
              message: x.active ? s.pick('Dondur (hesaba katılmaz)', 'Pause (not counted)') : s.pick('Devam ettir', 'Resume'),
              child: Transform.scale(
                scale: 0.82,
                child: Switch(
                  value: x.active,
                  activeThumbColor: MC.ink,
                  activeTrackColor: MC.gold,
                  inactiveThumbColor: MC.muted,
                  inactiveTrackColor: const Color(0x33000000),
                  onChanged: (_) => _toggle(context, x),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  void _toggle(BuildContext context, Subscription x) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final id = x.id;
    final name = x.name;
    final snap = st.snapshot();
    var next = false;
    st.update((d) => next = toggleSubscription(d, id));
    toast(context, undo: () => st.restore(snap), next ? s.pick('"$name" yeniden hesaba katılıyor.', '"$name" is counted again.') : s.pick('"$name" donduruldu; hesaba katılmaz.', '"$name" is paused; it is not counted.'));
  }
}

const Map<String, Color> _groupColors = {
  'fatura': Color(0xFF7FC3B4),
  'video': Color(0xFFE07A8B),
  'muzik': Color(0xFF9FD7A5),
  'yz': Color(0xFFD9AE68),
  'guvenlik': Color(0xFF8FB3C9),
  'is': Color(0xFF9AA4B5),
  'yemek': Color(0xFFE0A36B),
  'yayin': Color(0xFFA99BD6),
  'iletisim': Color(0xFF8FC3E6),
  'oyun': Color(0xFFB7A2F2),
  'bulut': Color(0xFF8FC3E6),
  'spor': Color(0xFFE0A3B8),
};

/// Ad baş harfli kare (abonelikler; marka logosu kullanılmaz).
class Monogram extends StatelessWidget {
  const Monogram({super.key, required this.name, this.group, this.size = 36});

  final String name;
  final String? group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = _groupColors[group] ?? catColor(name);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final text = words.isEmpty
        ? '?'
        : words.length == 1
            ? trUpper(words.first.characters.first)
            : trUpper(words[0].characters.first + words[1].characters.first);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: 0.9), Color.lerp(c, Colors.black, 0.45)!]),
        shape: SignatureBorder(cut: size * 0.26, radius: size * 0.28),
      ),
      child: Text(text, style: sans(size * (text.length > 1 ? 0.34 : 0.42), weight: FontWeight.w700, color: Colors.white)),
    );
  }
}

class _CategoriesPanel extends StatelessWidget {
  const _CategoriesPanel({required this.rows, required this.selected, required this.filtered, required this.onTap});

  final List<MapEntry<String, int>> rows;
  final String selected;
  final bool filtered;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final total = sumK(rows, (MapEntry<String, int> r) => r.value);
    return GlassPanel(
      delay: const Duration(milliseconds: 240),
      radius: 30,
      cut: 30,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PanelHead(s.pick('Kategoriler', 'Categories'), subtitle: filtered ? s.pick('Seçili kaynağa göre', 'For the selected source') : s.pick('Dokununca liste süzülür', 'Tap to filter the list')),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  size: const Size(150, 150),
                  painter: DonutPainter([for (final r in rows) (r.value.toDouble(), catColor(r.key))], progress: t, highlight: rows.indexWhere((r) => r.key == selected)),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                MoneyText(total, count: true, style: serif(21)),
                Text(s.pick('${rows.length} kategori', '${rows.length} categories'), style: sans(11, color: MC.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(children: [
              for (final r in rows.take(7))
                InkWell(
                  onTap: () => onTap(r.key),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                    decoration: BoxDecoration(color: selected == r.key ? const Color(0x1FFFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: catColor(r.key), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(catLabel(r.key, s.lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12.5))),
                      Text(st.hidden ? '•••' : '%${(r.value / math.max(1, total) * 100).round()}', style: sans(12, color: MC.muted, weight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// Halka grafik.
class DonutPainter extends CustomPainter {
  DonutPainter(this.parts, {this.progress = 1, this.highlight = -1, this.stroke = 17});

  final List<(double, Color)> parts;
  final double progress;
  final int highlight;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - stroke / 2 - 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0x14FFFFFF));
    final total = parts.fold<double>(0, (a, p) => a + p.$1);
    if (total <= 0) return;
    var start = -math.pi / 2;
    final sweepAll = math.pi * 2 * progress;
    for (var i = 0; i < parts.length; i++) {
      final sweep = parts[i].$1 / total * sweepAll;
      final gap = sweep > 0.08 ? 0.025 : 0.0;
      final on = highlight == i;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? stroke + 5 : stroke
          ..color = highlight >= 0 && !on ? parts[i].$2.withValues(alpha: 0.45) : parts[i].$2,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter old) => old.progress != progress || old.highlight != highlight || old.parts.length != parts.length;
}

class _BarRow {
  const _BarRow({required this.key, required this.label, required this.k, required this.color, this.on = false});
  final String key;
  final Widget label;
  final int k;
  final Color color;
  final bool on;
}

class _Bars extends StatelessWidget {
  const _Bars({required this.rows, required this.money, required this.onTap});

  final List<_BarRow> rows;
  final String Function(int) money;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(1, (a, r) => math.max(a, r.k));
    return Column(children: [
      for (final r in rows)
        InkWell(
          onTap: () => onTap(r.key),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            decoration: BoxDecoration(color: r.on ? const Color(0x1FFFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Align(alignment: Alignment.centerLeft, child: r.label)),
                const SizedBox(width: 10),
                Text(money(r.k), style: sans(13, weight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              ProgressLine(math.max(0.02, r.k / max), color: r.color, height: 5),
            ]),
          ),
        ),
    ]);
  }
}
