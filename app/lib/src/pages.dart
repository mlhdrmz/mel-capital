import 'package:flutter/material.dart';

import 'format.dart';
import 'glass.dart';
import 'i18n.dart';
import 'state.dart';
import 'theme.dart';

/// Sekmeye göre sayfa.
Widget pageFor(AppTab tab) => switch (tab) {
      AppTab.ozet => const OzetPage(),
      AppTab.ayarlar => const AyarlarPage(),
      _ => SamplePage(tab: tab),
    };

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ---------------------------------------------------------------- Özet

class OzetPage extends StatelessWidget {
  const OzetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _PageScroll(
      children: [
        PageHeader(eyebrow: s.t('eyebrow.ozet'), title: s.t('title.ozet')),
        const SizedBox(height: 16),
        const PreviewNote(),
        const SizedBox(height: 64),
        const Reveal(
          delay: Duration(milliseconds: 140),
          child: _HomeNumbers(),
        ),
      ],
    );
  }
}

class _HomeNumbers extends StatelessWidget {
  const _HomeNumbers();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      _HomeItem(label: s.pick('Hesaplarda', 'In accounts'), value: 23600),
      _HomeItem(label: s.pick('Kartlarda boş limit', 'Available card limit'), value: 16200),
    ];
    final total = _HomeItem(
      label: s.pick('Toplam', 'Total'),
      value: 39800,
      big: true,
      note: s.pick('hesaplar + kart limitleri', 'accounts + card limits'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [total, const SizedBox(height: 30), ...items.expand((w) => [w, const SizedBox(height: 24)])],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: items[0]),
            const SizedBox(width: 48),
            Expanded(child: items[1]),
            const SizedBox(width: 48),
            Expanded(flex: 5, child: Align(alignment: Alignment.bottomRight, child: total)),
          ],
        );
      },
    );
  }
}

class _HomeItem extends StatelessWidget {
  const _HomeItem({required this.label, required this.value, this.big = false, this.note});

  final String label;
  final double value;
  final bool big;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: big ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: sans(12, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.2, shadows: kPhotoTextShadow),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedMoney(
            value,
            duration: const Duration(milliseconds: 1200),
            style: serif(big ? 104.0 : 58.0, shadows: kBigTextShadow),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note!, style: sans(13, color: MC.muted, shadows: kPhotoTextShadow)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- Örnek sayfalar

class _Kpi {
  const _Kpi(this.tr, this.en, this.value, this.subTr, this.subEn, this.color, {this.valueColor});

  final String tr;
  final String en;
  final double value;
  final String subTr;
  final String subEn;
  final Color color;
  final Color? valueColor;
}

class _Item {
  const _Item(this.day, this.tr, this.en, this.subTr, this.subEn, this.amount);

  final int? day;
  final String tr;
  final String en;
  final String subTr;
  final String subEn;
  final double amount;
}

class _Sample {
  const _Sample({
    required this.kpis,
    required this.listTr,
    required this.listEn,
    required this.items,
    required this.sideTr,
    required this.sideEn,
    required this.sideSubTr,
    required this.sideSubEn,
    required this.sideValue,
    required this.progress,
    required this.captionTr,
    required this.captionEn,
  });

  final List<_Kpi> kpis;
  final String listTr;
  final String listEn;
  final List<_Item> items;
  final String sideTr;
  final String sideEn;
  final String sideSubTr;
  final String sideSubEn;
  final double sideValue;
  final double progress;
  final String captionTr;
  final String captionEn;
}

const Map<AppTab, _Sample> _samples = {
  AppTab.harcamalar: _Sample(
    kpis: [
      _Kpi('Toplam', 'Total', 18420, '42 kayıt', '42 entries', MC.gold),
      _Kpi('Hesaptan', 'From accounts', 12950, 'abonelikler dahil', 'subscriptions included', MC.sky),
      _Kpi('Kartla', 'By card', 5470, 'ekstreyle ödenir', 'paid with the statement', MC.violet),
    ],
    listTr: 'Son harcamalar',
    listEn: 'Recent spending',
    items: [
      _Item(3, 'Market', 'Groceries', 'Gıda · kart', 'Food · card', 1240),
      _Item(3, 'Akaryakıt', 'Fuel', 'Ulaşım · hesap', 'Transport · account', 1100),
      _Item(2, 'Restoran', 'Restaurant', 'Yeme-içme · kart', 'Dining · card', 640),
      _Item(1, 'Kitap', 'Books', 'Diğer · hesap', 'Other · account', 285),
    ],
    sideTr: 'Günlük ortalama',
    sideEn: 'Daily average',
    sideSubTr: 'Bu ayın şimdiye kadarki günleri',
    sideSubEn: 'Days of this month so far',
    sideValue: 614,
    progress: 0.62,
    captionTr: 'Geçen aya göre %8 daha az',
    captionEn: '8% less than last month',
  ),
  AppTab.borclar: _Sample(
    kpis: [
      _Kpi('Toplam borç', 'Total debt', 64300, '2 kart · 3 kredi', '2 cards · 3 loans', MC.rose),
      _Kpi('Kart borcu', 'Card debt', 8900, 'boş limit 11.100 TL', 'available limit 11,100 TL', MC.violet),
      _Kpi('Krediler', 'Loans', 55400, '3 açık kayıt', '3 open records', MC.sky),
    ],
    listTr: 'Bu ayın ödemeleri',
    listEn: 'This month\'s payments',
    items: [
      _Item(6, 'Kredi kartı A', 'Credit card A', 'Son ödeme günü', 'Payment due', 4900),
      _Item(13, 'İhtiyaç kredisi', 'Personal loan', '14 taksit kaldı', '14 instalments left', 2730),
      _Item(20, 'Taşıt kredisi', 'Car loan', '6 taksit kaldı', '6 instalments left', 2870),
      _Item(25, 'Kredi kartı B', 'Credit card B', 'Son ödeme günü', 'Payment due', 4000),
    ],
    sideTr: 'Bu ay ödenecek',
    sideEn: 'Due this month',
    sideSubTr: '4 ödeme',
    sideSubEn: '4 payments',
    sideValue: 14500,
    progress: 0.35,
    captionTr: '%35\'i ödendi',
    captionEn: '35% paid',
  ),
  AppTab.bankalar: _Sample(
    kpis: [
      _Kpi('Hesaplarda', 'In accounts', 23600, '4 hesap', '4 accounts', MC.mint),
      _Kpi('Kartlarda boş limit', 'Available card limit', 16200, '3 kart', '3 cards', MC.gold),
      _Kpi('Toplam', 'Total', 39800, 'elindeki para', 'money at hand', MC.sky),
    ],
    listTr: 'Bankalarım',
    listEn: 'My banks',
    items: [
      _Item(null, 'Banka A', 'Bank A', 'vadesiz · kredi kartı', 'current · credit card', 12300),
      _Item(null, 'Banka B', 'Bank B', 'vadesiz · banka kartı', 'current · debit card', 8900),
      _Item(null, 'Banka C', 'Bank C', 'kredi kartı', 'credit card', 2400),
      _Item(null, 'Banka D', 'Bank D', 'vadesiz', 'current', 0),
    ],
    sideTr: 'Bu ay giren',
    sideEn: 'In this month',
    sideSubTr: 'maaş ve diğer gelirler',
    sideSubEn: 'salary and other income',
    sideValue: 52400,
    progress: 1,
    captionTr: 'Maaş günü: ayın 15\'i',
    captionEn: 'Payday: the 15th',
  ),
  AppTab.plan: _Sample(
    kpis: [
      _Kpi('Gelir', 'Income', 52400, '3 kalem', '3 items', MC.mint),
      _Kpi('Ödemeler', 'Payments', 21860, '12 kalem · %68 ödendi', '12 items · 68% paid', MC.rose),
      _Kpi('Serbest kalan', 'Free to spend', 4120, 'ay sonuna kadar', 'until month end', MC.gold, valueColor: MC.gold),
    ],
    listTr: 'Ödeme takvimi',
    listEn: 'Payment calendar',
    items: [
      _Item(1, 'Kira', 'Rent', 'Hesaptan', 'From account', 12500),
      _Item(6, 'Kredi kartı ekstresi', 'Card statement', 'Son ödeme günü', 'Payment due', 3940),
      _Item(12, 'İnternet', 'Internet', 'Fatura', 'Bill', 450),
      _Item(20, 'Kredi taksiti', 'Loan instalment', '9 taksit kaldı', '9 instalments left', 1780),
    ],
    sideTr: 'Ay sonu',
    sideEn: 'Month end',
    sideSubTr: 'Ödemeler düşülünce elde kalan',
    sideSubEn: 'Left after payments',
    sideValue: 4120,
    progress: 0.68,
    captionTr: 'Ödemelerin %68\'i tamam',
    captionEn: '68% of payments done',
  ),
  AppTab.alisveris: _Sample(
    kpis: [
      _Kpi('Bu ay ayrılan', 'Set aside this month', 3000, '2 hedef', '2 goals', MC.gold),
      _Kpi('Biriken', 'Saved', 7450, 'hedeflere', 'towards goals', MC.mint),
      _Kpi('Harcayabileceğin', 'You can spend', 4120, 'ay sonuna kadar', 'until month end', MC.violet),
    ],
    listTr: 'İstek listesi',
    listEn: 'Wishlist',
    items: [
      _Item(null, 'Kahve makinesi', 'Coffee machine', '%35 birikti', '35% saved', 14000),
      _Item(null, 'Kulaklık', 'Headphones', '%60 birikti', '60% saved', 6500),
      _Item(null, 'Saat', 'Watch', '%10 birikti', '10% saved', 25000),
      _Item(null, 'Spor ayakkabı', 'Sneakers', 'alınabilir', 'affordable', 3200),
    ],
    sideTr: 'Alabilir miyim?',
    sideEn: 'Can I afford it?',
    sideSubTr: 'Spor ayakkabı · 3.200 TL',
    sideSubEn: 'Sneakers · 3,200 TL',
    sideValue: 920,
    progress: 0.78,
    captionTr: 'Evet; alırsan ay sonunda bu kadar kalır',
    captionEn: 'Yes; if you buy it, this much is left at month end',
  ),
};

class SamplePage extends StatelessWidget {
  const SamplePage({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sample = _samples[tab]!;
    final now = DateTime.now();
    final title = switch (tab) {
      AppTab.harcamalar || AppTab.plan => s.monthYear(now),
      _ => s.t('title.${tab.name}'),
    };
    return _PageScroll(
      children: [
        PageHeader(eyebrow: s.t('eyebrow.${tab.name}'), title: title),
        const SizedBox(height: 16),
        const PreviewNote(),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < sample.kpis.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(
                child: KpiTile(
                  label: s.pick(sample.kpis[i].tr, sample.kpis[i].en),
                  value: sample.kpis[i].value,
                  sub: s.pick(sample.kpis[i].subTr, sample.kpis[i].subEn),
                  color: sample.kpis[i].color,
                  valueColor: sample.kpis[i].valueColor,
                  delay: Duration(milliseconds: 60 + i * 70),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final list = _ListPanel(sample: sample, now: now);
            final side = _SidePanel(sample: sample);
            if (constraints.maxWidth < 860) {
              return Column(children: [list, const SizedBox(height: 14), side]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 17, child: list),
                const SizedBox(width: 14),
                Expanded(flex: 10, child: side),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ListPanel extends StatelessWidget {
  const _ListPanel({required this.sample, required this.now});

  final _Sample sample;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final hidden = AppScope.of(context).hidden;
    final rows = <Widget>[];
    for (final item in sample.items) {
      rows.add(Container(height: 1, color: const Color(0x1FFFFFFF)));
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              if (item.day != null)
                DateChip(day: item.day!, month: s.monthShort(now))
              else
                _Monogram(letter: s.pick(item.tr, item.en).characters.first),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.pick(item.tr, item.en), style: sans(14.5, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(s.pick(item.subTr, item.subEn), style: sans(12, color: MC.muted)),
                  ],
                ),
              ),
              Text(
                money(item.amount, lang: s.lang, hidden: hidden),
                style: sans(14.5, weight: FontWeight.w700).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GlassPanel(
      delay: const Duration(milliseconds: 260),
      radius: 30,
      cut: 30,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: Text(s.pick(sample.listTr, sample.listEn), style: serif(24))),
                Text(
                  s.pick('${sample.items.length} kalem', '${sample.items.length} items'),
                  style: sans(12, color: MC.muted),
                ),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.sample});

  final _Sample sample;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GlassPanel(
      delay: const Duration(milliseconds: 330),
      radius: 30,
      cut: 30,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.pick(sample.sideTr, sample.sideEn), style: serif(24)),
          const SizedBox(height: 4),
          Text(s.pick(sample.sideSubTr, sample.sideSubEn), style: sans(12, color: MC.muted)),
          const SizedBox(height: 14),
          AnimatedMoney(sample.sideValue, style: serif(44, color: MC.gold)),
          const SizedBox(height: 14),
          _ProgressBar(value: sample.progress),
          const SizedBox(height: 8),
          Text(s.pick(sample.captionTr, sample.captionEn), style: sans(12, color: MC.muted)),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x24FFFFFF)),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [MC.gold2, Color(0xFFECC987)]),
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

class _Monogram extends StatelessWidget {
  const _Monogram({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: const Color(0x1AFFFFFF),
        shape: SignatureBorder(
          cut: 10,
          radius: 10,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
      child: Text(letter, style: serif(20, weight: FontWeight.w700)),
    );
  }
}

// ---------------------------------------------------------------- Ayarlar

class AyarlarPage extends StatelessWidget {
  const AyarlarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    return _PageScroll(
      children: [
        PageHeader(eyebrow: s.t('eyebrow.ayarlar'), title: s.t('title.ayarlar')),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: GlassPanel(
            radius: 30,
            cut: 30,
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Column(
              children: [
                _SettingRow(
                  title: s.t('settings.language'),
                  help: s.t('settings.languageHelp'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Pill(
                        key: const ValueKey<String>('lang-tr'),
                        label: 'Türkçe',
                        selected: s.lang == 'tr',
                        onTap: () => st.setLanguage('tr'),
                      ),
                      const SizedBox(width: 6),
                      _Pill(
                        key: const ValueKey<String>('lang-en'),
                        label: 'English',
                        selected: s.lang == 'en',
                        onTap: () => st.setLanguage('en'),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: const Color(0x1FFFFFFF)),
                _SettingRow(
                  title: s.t('settings.hidden'),
                  help: s.t('settings.hiddenHelp'),
                  trailing: Switch(
                    value: st.hidden,
                    onChanged: (_) => st.toggleHidden(),
                  ),
                ),
                Container(height: 1, color: const Color(0x1FFFFFFF)),
                _SettingRow(
                  title: s.t('settings.about'),
                  help: s.t('settings.aboutValue'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.help, this.trailing});

  final String title;
  final String help;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sans(15, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(help, style: sans(12.5, color: MC.muted)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 18), trailing!],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? MC.ink : MC.text,
        backgroundColor: selected ? MC.gold : const Color(0x1AFFFFFF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
