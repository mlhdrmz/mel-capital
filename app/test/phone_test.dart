// Telefon boyutunda (390 × 844) bütün ekranlar: gerçek yazı tipleriyle çizilir ki taşmalar
// gerçekteki gibi görünsün (diğer testlerdeki Ahem yazı tipi harfleri çok geniş çizer).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/sample.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/src/pages/common.dart';
import 'package:mel_capital/src/sheet.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/store_memory.dart';

Future<void> loadRealFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await family('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
  await family('Cormorant', ['CormorantGaramond-Medium.ttf', 'CormorantGaramond-SemiBold.ttf', 'CormorantGaramond-Bold.ttf']);
}

void main() {
  setUpAll(loadRealFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<AppState> openSample(WidgetTester tester) async {
    phone(tester);
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'));
    state.showTips = false;
    await state.createProfile('Deniz', data: await loadSampleJson());
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Finder pageScroll() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

  testWidgets('telefon: alt menü var, bütün sayfalar taşmadan çizilir', (tester) async {
    final state = await openSample(tester);
    expect(find.byKey(const ValueKey<String>('tab-diger')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('phone-add')), findsOneWidget);
    for (final tab in AppTab.values) {
      state.setTab(tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab.name);
      final scroll = pageScroll();
      if (scroll.evaluate().isNotEmpty) {
        await tester.drag(scroll.first, const Offset(0, -4000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${tab.name}, sayfanın altı');
      }
    }
  });

  testWidgets('telefon: "Diğer"den Ayarlar açılır, + düğmesi harcama paneli açar', (tester) async {
    final state = await openSample(tester);
    await tester.tap(find.byKey(const ValueKey<String>('tab-diger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tab-ayarlar')));
    await tester.pumpAndSettle();
    expect(state.tab, AppTab.ayarlar);
    expect(find.byKey(const ValueKey<String>('phone-add')), findsNothing);
    state.setTab(AppTab.harcamalar);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('phone-add')));
    await tester.pumpAndSettle();
    expect(find.byType(SheetFrame), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('telefon: düzenleme panelleri taşmadan açılır', (tester) async {
    final state = await openSample(tester);
    Future<void> openAndClose(String name, void Function() open) async {
      open();
      await tester.pumpAndSettle();
      expect(find.byType(SheetFrame), findsOneWidget, reason: name);
      expect(tester.takeException(), isNull, reason: name);
      Navigator.of(tester.element(find.byType(SheetFrame))).pop();
      await tester.pumpAndSettle();
    }

    final ctx = tester.element(find.byType(Scaffold).first);
    final d = state.data;
    await openAndClose('harcama', () => openSpendSheet(ctx, spend: d.spends.first));
    await openAndClose('hızlı giriş', () => openQuickSpendSheet(ctx));
    await openAndClose('aktarma', () => openTransferSheet(ctx));
    await openAndClose('kart ödemesi', () => openCardPaySheet(ctx));
    await openAndClose('hesap', () => openAccountSheet(ctx, account: d.accounts.first));
    await openAndClose('kart', () => openCardSheet(ctx, card: d.cards.first));
    await openAndClose('borç', () => openDebtSheet(ctx, debt: d.debts.last));
    await openAndClose('ekstre', () => openStatementSheet(ctx, d.debts.first));
    await openAndClose('abonelik', () => openSubSheet(ctx, sub: d.subscriptions.first));
    await openAndClose('gelir', () => openIncomeSheet(ctx, income: d.incomes.first));
    await openAndClose('hedef', () => openGoalSheet(ctx, goal: d.goals.first));
    await openAndClose('findeks', () => openFindeksSheet(ctx, entry: d.findeks.first));
  });

  testWidgets('telefon: tanıtım, başlangıç ve kurulum adımları sığar', (tester) async {
    phone(tester);
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'));
    await state.init();
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    expect(state.showIntro, isTrue);
    for (var i = 0; i < 3; i++) {
      state.setIntroSlide(i);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tanıtım ${i + 1}');
    }
    state.finishIntro();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'başlangıç');
    await state.createProfile('Deniz', data: await loadSampleJson(), setup: true);
    await tester.pumpAndSettle();
    for (final step in kSetupSteps) {
      state.setSetupStep(step);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'kurulum: $step');
    }
  });
}
