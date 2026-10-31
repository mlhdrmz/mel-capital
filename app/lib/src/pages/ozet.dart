import 'package:flutter/material.dart';

import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/util.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

/// Özet: yalnızca elde ne var — hesaplardaki para, kartlardaki boş limit ve toplamı.
class OzetPage extends StatelessWidget {
  const OzetPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    final m = ctx.model;
    final today = todayISO();
    final hour = clock().hour;
    final greet = hour < 6
        ? s.pick('İyi geceler', 'Good night')
        : hour < 12
            ? s.pick('Günaydın', 'Good morning')
            : hour < 18
                ? s.pick('İyi günler', 'Good afternoon')
                : s.pick('İyi akşamlar', 'Good evening');
    final withMoney = d.accounts.where((a) => toK(a.balance) != 0).toList();
    final accNote = withMoney.length == 1
        ? accLabel(withMoney.first, s.lang)
        : withMoney.isNotEmpty
            ? s.pick('${withMoney.length} hesapta', 'in ${withMoney.length} accounts')
            : s.pick('Hesaplarda para yok', 'No money in accounts');
    final cards = d.debts.where((x) => x.isCard).length;
    final cardNote = cards > 0
        ? s.pick('$cards kredi kartı · limit ${fmtMoney(m.cardLimit, lang: s.lang, hidden: st.hidden)}',
            '$cards credit cards · limit ${fmtMoney(m.cardLimit, lang: s.lang, hidden: st.hidden)}')
        : s.pick('Kredi kartı yok', 'No credit cards');
    final total = m.liquid + m.cardAvail;
    final name = st.profile?.name;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 56),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 900;
          final items = [
            _HomeItem(
              label: s.pick('Hesaplarda', 'In accounts'),
              k: m.liquid,
              note: accNote,
              onTap: () => st.setTab(AppTab.bankalar),
            ),
            _HomeItem(
              label: s.pick('Kartlarda boş limit', 'Available card limit'),
              k: m.cardLimit > 0 ? m.cardAvail : null,
              note: cardNote,
              onTap: () => st.setTab(AppTab.borclar),
            ),
          ];
          final big = _HomeItem(
            label: s.pick('Harcanabilir', 'Spendable'),
            k: total,
            note: s.pick('Hesaplar + kartlardaki boş limit', 'Accounts + available card limit'),
            big: true,
          );
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Reveal(
                  child: Text(
                    '${greet.toUpperCase()}${name == null ? '' : ', ${trUpper(name)}'} · ${fmtDate(today, s.lang).toUpperCase()}, ${trUpper(weekdayName(today, s.lang))}',
                    style: sans(12, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.2, shadows: kPhotoTextShadow),
                  ),
                ),
                SizedBox(height: narrow ? 40 : 120),
                Reveal(
                  delay: const Duration(milliseconds: 140),
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [big, const SizedBox(height: 34), items[0], const SizedBox(height: 26), items[1]],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: items[0]),
                            const SizedBox(width: 48),
                            Expanded(child: items[1]),
                            const SizedBox(width: 48),
                            Expanded(flex: 5, child: Align(alignment: Alignment.bottomRight, child: big)),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeItem extends StatelessWidget {
  const _HomeItem({required this.label, required this.k, required this.note, this.big = false, this.onTap});

  final String label;
  final int? k;
  final String note;
  final bool big;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = k;
    final style = serif(big ? 108.0 : 60.0, shadows: kBigTextShadow, color: value != null && value < 0 ? MC.rose : MC.text);
    final body = Column(
      crossAxisAlignment: big ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(trUpper(label), style: sans(12, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.2, shadows: kPhotoTextShadow)),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: value == null ? Text('—', style: style) : MoneyText(value, count: true, style: style),
        ),
        const SizedBox(height: 6),
        Text(note, textAlign: big ? TextAlign.right : TextAlign.left, style: sans(13, color: MC.muted, shadows: kPhotoTextShadow)),
      ],
    );
    if (onTap == null) return body;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: body));
  }
}
