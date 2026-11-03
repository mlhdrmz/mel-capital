import 'package:flutter/material.dart';

import '../core/util.dart';
import 'i18n.dart';
import 'pages/ayarlar.dart';
import 'pages/bankalar.dart';
import 'pages/borclar.dart';
import 'pages/ozet.dart';
import 'state.dart';
import 'ui.dart';

/// Sekmeye göre sayfa.
Widget pageFor(AppTab tab) => switch (tab) {
      AppTab.ozet => const OzetPage(),
      AppTab.borclar => const BorclarPage(),
      AppTab.bankalar => const BankalarPage(),
      AppTab.ayarlar => const AyarlarPage(),
      _ => _SoonPage(tab: tab),
    };

/// Henüz taşınmamış sayfa.
class _SoonPage extends StatelessWidget {
  const _SoonPage({required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PageFrame(
      eyebrow: s.isTr ? trUpper(s.t('tab.${tab.name}')) : s.t('tab.${tab.name}').toUpperCase(),
      title: s.t('tab.${tab.name}'),
      children: [
        EmptyCard(
          icon: Icons.construction_outlined,
          title: s.pick('Bu sayfa taşınıyor', 'This page is on its way'),
          text: s.pick('Bu ekran yeni sürüme aktarılıyor; bir sonraki önizlemede burada olacak.',
              'This screen is being moved to the new version; it will be here in the next preview.'),
        ),
      ],
    );
  }
}
