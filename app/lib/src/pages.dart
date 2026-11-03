import 'package:flutter/widgets.dart';

import 'pages/alisveris.dart';
import 'pages/ayarlar.dart';
import 'pages/bankalar.dart';
import 'pages/borclar.dart';
import 'pages/harcamalar.dart';
import 'pages/ozet.dart';
import 'pages/plan.dart';
import 'state.dart';

/// Sekmeye göre sayfa.
Widget pageFor(AppTab tab) => switch (tab) {
      AppTab.ozet => const OzetPage(),
      AppTab.harcamalar => const HarcamalarPage(),
      AppTab.borclar => const BorclarPage(),
      AppTab.bankalar => const BankalarPage(),
      AppTab.plan => const PlanPage(),
      AppTab.alisveris => const AlisverisPage(),
      AppTab.ayarlar => const AyarlarPage(),
    };
