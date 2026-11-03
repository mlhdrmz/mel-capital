import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/sample.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/src/format.dart';
import 'package:mel_capital/src/pages/common.dart';
import 'package:mel_capital/src/sheet.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/store_memory.dart';

void main() {
  test('tutar biçimi', () {
    expect(money(52400), '52.400 TL');
    expect(money(52400, lang: 'en'), '52,400 TL');
    expect(money(1234.5, decimals: 2), '1.234,50 TL');
    expect(money(-950), '−950 TL');
    expect(money(0), '0 TL');
    expect(money(999), '999 TL');
    expect(money(1000000), '1.000.000 TL');
    expect(money(12, hidden: true), '•••• TL');
  });

  void bigWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(2400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Örnek verili profille açar.
  Future<AppState> openSample(WidgetTester tester, String lang) async {
    bigWindow(tester);
    final state = AppState(store: MemoryStore(), initialLocale: Locale(lang));
    await state.createProfile('Deniz', data: await loadSampleJson());
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> tapTab(WidgetTester tester, AppTab tab) async {
    final button = find.byKey(ValueKey<String>('tab-${tab.name}'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('örnek profil açılır ve bütün sekmeler hatasız çizilir', (tester) async {
    final state = await openSample(tester, 'tr');
    expect(state.status, AppStatus.ready);
    expect(find.text('Mel Capital'), findsOneWidget);
    expect(find.text('HARCANABİLİR'), findsOneWidget);
    for (final tab in AppTab.values) {
      await tapTab(tester, tab);
      expect(state.tab, tab);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Bankalar: banka sayfası açılır', (tester) async {
    final state = await openSample(tester, 'tr');
    await tapTab(tester, AppTab.bankalar);
    expect(find.text('Bankalarım'), findsOneWidget);
    await tester.tap(find.text('Akbank').first);
    await tester.pumpAndSettle();
    expect(find.text('Tüm bankalar'), findsOneWidget);
    expect(find.text('Kartlar'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(state.tab, AppTab.bankalar);
  });

  testWidgets('ilk açılış: sıfırdan başlanır', (tester) async {
    bigWindow(tester);
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'));
    await state.init();
    expect(state.status, AppStatus.welcome);
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Nasıl başlamak istersin?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Melih');
    await tester.tap(find.text('Sıfırdan başla'));
    await tester.pumpAndSettle();
    expect(state.status, AppStatus.ready);
    expect(state.profile?.name, 'Melih');
    expect(state.index.profiles.length, 1);
    expect(state.data.accounts.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dil değişir, tutarlar gizlenir', (tester) async {
    final state = await openSample(tester, 'tr');
    await tapTab(tester, AppTab.ayarlar);
    await tester.tap(find.byKey(const ValueKey<String>('lang-en')));
    await tester.pumpAndSettle();
    expect(state.locale.value.languageCode, 'en');
    expect(find.text('Overview'), findsOneWidget);
    expect(state.index.lang, 'en');

    await tapTab(tester, AppTab.bankalar);
    expect(find.textContaining('•••'), findsNothing);
    state.toggleHidden();
    await tester.pumpAndSettle();
    expect(find.textContaining('•••'), findsWidgets);
  });

  testWidgets('ikinci profil açılır, ilkine dönülür', (tester) async {
    final state = await openSample(tester, 'tr');
    final first = state.profile!.id;
    await state.createProfile('İkinci');
    await tester.pumpAndSettle();
    expect(state.index.profiles.length, 2);
    expect(state.profile?.name, 'İkinci');
    expect(state.data.debts, isEmpty);
    await state.openProfile(first);
    await tester.pumpAndSettle();
    expect(state.profile?.id, first);
    expect(state.data.debts, isNotEmpty);
    expect(state.index.last, first);
  });

  testWidgets('değişiklik kaydedilir ve yeniden açılınca okunur', (tester) async {
    bigWindow(tester);
    final store = MemoryStore();
    final state = AppState(store: store, initialLocale: const Locale('tr'));
    await state.createProfile('Deniz', data: await loadSampleJson());
    state.update((d) => d.accounts.first.balance = 1234.5);
    await state.flush();
    final again = AppState(store: store, initialLocale: const Locale('tr'));
    await again.init();
    expect(again.status, AppStatus.ready);
    expect(again.profile?.name, 'Deniz');
    expect(again.data.accounts.first.balance, 1234.5);
  });

  testWidgets('harcama paneli: eklenir, geri alınır', (tester) async {
    final state = await openSample(tester, 'tr');
    await tapTab(tester, AppTab.harcamalar);
    final n0 = state.data.spends.length;
    await tester.tap(find.text('Harcama').first);
    await tester.pumpAndSettle();
    expect(find.text('Harcama ekle'), findsOneWidget);
    final fields = find.descendant(of: find.byType(SheetFrame), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Kahve');
    await tester.enterText(fields.at(1), '85');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(state.data.spends.length, n0 + 1);
    expect(state.data.spends.last.name, 'Kahve');
    expect(find.byType(SheetFrame), findsNothing);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(state.data.spends.length, n0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan: ödendi işareti konur', (tester) async {
    final state = await openSample(tester, 'tr');
    await tapTab(tester, AppTab.plan);
    final p0 = state.data.payments.length;
    final tick = find.byTooltip('Ödendi olarak işaretle');
    expect(tick, findsWidgets);
    await tester.ensureVisible(tick.first);
    await tester.tap(tick.first);
    await tester.pumpAndSettle();
    expect(state.data.payments.length, greaterThan(p0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bütün düzenleme panelleri açılır', (tester) async {
    final state = await openSample(tester, 'tr');
    Future<void> openAndClose(Future<void> Function() open) async {
      await open();
      await tester.pumpAndSettle();
      expect(find.byType(SheetFrame), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(SheetFrame))).pop();
      await tester.pumpAndSettle();
    }

    final ctx = tester.element(find.byType(Scaffold).first);
    final d = state.data;
    await openAndClose(() async => openSpendSheet(ctx, spend: d.spends.first));
    await openAndClose(() async => openQuickSpendSheet(ctx));
    await openAndClose(() async => openTransferSheet(ctx));
    await openAndClose(() async => openCardPaySheet(ctx));
    await openAndClose(() async => openAccountSheet(ctx, account: d.accounts.first));
    await openAndClose(() async => openCardSheet(ctx, card: d.cards.first));
    await openAndClose(() async => openDebtSheet(ctx, debt: d.debts.first));
    await openAndClose(() async => openDebtSheet(ctx, debt: d.debts.last));
    await openAndClose(() async => openStatementSheet(ctx, d.debts.first));
    await openAndClose(() async => openCardBalanceSheet(ctx, d.debts.first));
    await openAndClose(() async => openSubSheet(ctx, sub: d.subscriptions.first));
    await openAndClose(() async => openExpenseSheet(ctx, expense: d.recurringExpenses.first));
    await openAndClose(() async => openIncomeSheet(ctx, income: d.incomes.first));
    await openAndClose(() async => openIncomeSheet(ctx));
    await openAndClose(() async => openGoalSheet(ctx, goal: d.goals.first));
    await openAndClose(() async => openGoalSaveSheet(ctx, d.goals.first));
    await openAndClose(() async => openFindeksSheet(ctx, entry: d.findeks.first));
  });
}
