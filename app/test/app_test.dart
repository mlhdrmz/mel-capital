import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/motor/motorlar.dart';
import 'package:mel_capital/core/sample.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/src/format.dart';
import 'package:mel_capital/src/pages/common.dart';
import 'package:mel_capital/src/pages/intro.dart';
import 'package:mel_capital/src/pages/setup.dart';
import 'package:mel_capital/src/sheet.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/src/tips.dart';
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
    final state = AppState(store: MemoryStore(), initialLocale: Locale(lang))..showTips = false;
    await state.createProfile('Deniz', data: await loadSampleJson());
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  /// Düğmeyi ekranın ortasına kaydırır; önceki işlemin alttaki bildirimi kapatılır (düğmenin üstüne gelmesin).
  Future<void> reveal(WidgetTester tester, Finder f) async {
    for (final m in find.byType(ScaffoldMessenger).evaluate()) {
      final ms = (m as StatefulElement).state;
      if (ms is ScaffoldMessengerState) ms.clearSnackBars();
    }
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey<String>(key));
    await reveal(tester, f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> typeKey(WidgetTester tester, String key, String text) async {
    final f = find.byKey(ValueKey<String>(key));
    await reveal(tester, f);
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
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

  testWidgets('ilk açılış: tanıtım, başlangıç ve kurulum sihirbazı', (tester) async {
    bigWindow(tester);
    final store = MemoryStore();
    final state = AppState(store: store, initialLocale: const Locale('tr'))..showTips = false;
    await state.init();
    expect(state.status, AppStatus.welcome);
    expect(state.showIntro, isTrue);
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();

    // Tanıtım: üç ekran
    expect(find.byType(IntroPage), findsOneWidget);
    expect(find.text('MEL CAPITAL NEDİR?'), findsOneWidget);
    await tapKey(tester, 'intro-next');
    expect(state.introSlide, 1);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'intro-next');
    expect(state.introSlide, 2);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'intro-next');
    expect(state.index.intro, isTrue);

    // Başlangıç: yeni profil kur
    expect(find.text('Elinde Mel Capital verisi var mı?'), findsOneWidget);
    await typeKey(tester, 'start-name', 'Melih');
    await tapKey(tester, 'start-new');
    expect(state.status, AppStatus.ready);
    expect(state.profile?.name, 'Melih');
    expect(state.setupStep, 'ekstre');
    expect(find.byType(SetupPage), findsOneWidget);

    // Ekstreler: elle gireceğim
    await tapKey(tester, 'setup-manual');
    expect(state.setupStep, 'hesaplar');

    // Hesaplar
    await tapKey(tester, 'bank-akbank');
    await typeKey(tester, 'setup-acc-balance', '12.500');
    await tapKey(tester, 'setup-add');
    expect(state.data.accounts.length, 2);
    expect(state.data.accounts.any((a) => a.bank == 'akbank' && a.balance == 12500), isTrue);
    await tapKey(tester, 'setup-next');
    expect(state.setupStep, 'kartlar');

    // Kartlar: yarım kalan form "İleri"de eklenir
    await typeKey(tester, 'setup-card-name', 'Axess');
    await typeKey(tester, 'setup-card-limit', '20.000');
    await typeKey(tester, 'setup-card-debt', '3.500');
    await typeKey(tester, 'setup-card-due', '16');
    await tapKey(tester, 'setup-next');
    final cards = state.data.debts.where((x) => x.isCard).toList();
    expect(cards.length, 1);
    expect(cards.first.bank, 'akbank');
    expect(cards.first.remaining, 3500);
    expect(cards.first.limit, 20000);
    expect(state.setupStep, 'krediler');

    // Krediler
    await typeKey(tester, 'setup-loan-name', 'İhtiyaç kredisi');
    await typeKey(tester, 'setup-loan-monthly', '2.730');
    await typeKey(tester, 'setup-loan-count', '13');
    await tapKey(tester, 'setup-add');
    final loans = state.data.debts.where((x) => !x.isCard).toList();
    expect(loans.length, 1);
    expect(loans.first.remaining, 2730 * 13);
    expect(loans.first.schedule.single.amount, 2730);
    await tapKey(tester, 'setup-next');
    expect(state.setupStep, 'gelir');

    // Gelir
    await typeKey(tester, 'setup-income-amount', '45.000');
    await typeKey(tester, 'setup-income-day', '15');
    await tapKey(tester, 'setup-next');
    expect(state.data.incomes.length, 1);
    expect(state.setupStep, 'giderler');

    // Düzenli ödemeler
    await tapKey(tester, 'cost-netflix');
    await typeKey(tester, 'setup-cost-amount', '229,99');
    await tapKey(tester, 'setup-add');
    expect(state.data.subscriptions.single.name, 'Netflix');
    await tapKey(tester, 'cost-kira');
    await typeKey(tester, 'setup-cost-amount', '12.500');
    await tapKey(tester, 'setup-add');
    expect(state.data.recurringExpenses.single.name, 'Kira');
    await tapKey(tester, 'setup-next');
    expect(state.setupStep, 'bitti');
    expect(tester.takeException(), isNull);

    // Bitti
    await tapKey(tester, 'setup-finish');
    expect(state.setupStep, isNull);
    expect(find.byKey(const ValueKey<String>('tab-ozet')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Kaydedilen veri yeniden açılınca denetimden geçer
    await state.flush();
    final again = AppState(store: store, initialLocale: const Locale('tr'));
    await again.init();
    expect(again.status, AppStatus.ready);
    expect(again.setupStep, isNull);
    expect(again.data.debts.length, 2);
    expect(again.data.subscriptions.length, 1);
  });

  testWidgets('kurulum adımları örnek veriyle hatasız çizilir', (tester) async {
    final state = await openSample(tester, 'tr');
    state.startSetup();
    await tester.pumpAndSettle();
    for (final step in kSetupSteps) {
      state.setSetupStep(step);
      await tester.pumpAndSettle();
      expect(find.byType(SetupPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tapKey(tester, 'setup-finish');
    expect(state.setupStep, isNull);
  });

  testWidgets('Ayarlar: kurulum ve tanıtım yeniden açılır', (tester) async {
    final state = await openSample(tester, 'tr');
    await tapTab(tester, AppTab.ayarlar);
    await tapKey(tester, 'setup-open');
    expect(state.setupStep, 'ekstre');
    await tapKey(tester, 'setup-later');
    expect(state.setupStep, isNull);
    expect(state.tab, AppTab.ayarlar);
    await tapKey(tester, 'intro-open');
    expect(state.showIntro, isTrue);
    expect(find.byType(IntroPage), findsOneWidget);
    await tapKey(tester, 'intro-skip');
    expect(state.showIntro, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ipucu: her sayfada ilk girişte bir kez gösterilir', (tester) async {
    bigWindow(tester);
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'));
    await state.createProfile('Deniz', data: await loadSampleJson());
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    expect(find.byType(TipCard), findsOneWidget);
    expect(state.index.tips, contains('ozet'));
    await tester.tap(find.byKey(const ValueKey<String>('tip-ok')));
    await tester.pumpAndSettle();
    expect(find.byType(TipCard), findsNothing);
    await tapTab(tester, AppTab.plan);
    expect(find.byType(TipCard), findsOneWidget);
    await tapTab(tester, AppTab.ozet);
    expect(find.byType(TipCard), findsNothing);
    expect(state.index.tips, containsAll(<String>['ozet', 'plan']));
    state.resetTips();
    await tester.pumpAndSettle();
    expect(find.byType(TipCard), findsOneWidget);
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
    state.update((d) {
      final a = d.accounts.first;
      saveAccount(d, id: a.id, bank: a.bank, name: a.name, type: a.type, balanceK: 123450);
    });
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
    // Panel açan işlevler panel kapanana kadar bekleyen bir Future döndürür; beklenmez.
    Future<void> openAndClose(void Function() open) async {
      open();
      await tester.pumpAndSettle();
      expect(find.byType(SheetFrame), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(SheetFrame))).pop();
      await tester.pumpAndSettle();
    }

    final ctx = tester.element(find.byType(Scaffold).first);
    final d = state.data;
    await openAndClose(() => openSpendSheet(ctx, spend: d.spends.first));
    await openAndClose(() => openQuickSpendSheet(ctx));
    await openAndClose(() => openTransferSheet(ctx));
    await openAndClose(() => openCardPaySheet(ctx));
    await openAndClose(() => openAccountSheet(ctx, account: d.accounts.first));
    await openAndClose(() => openCardSheet(ctx, card: d.cards.first));
    await openAndClose(() => openDebtSheet(ctx, debt: d.debts.first));
    await openAndClose(() => openDebtSheet(ctx, debt: d.debts.last));
    await openAndClose(() => openStatementSheet(ctx, d.debts.first));
    await openAndClose(() => openCardBalanceSheet(ctx, d.debts.first));
    await openAndClose(() => openSubSheet(ctx, sub: d.subscriptions.first));
    await openAndClose(() => openExpenseSheet(ctx, expense: d.recurringExpenses.first));
    await openAndClose(() => openIncomeSheet(ctx, income: d.incomes.first));
    await openAndClose(() => openIncomeSheet(ctx));
    await openAndClose(() => openGoalSheet(ctx, goal: d.goals.first));
    await openAndClose(() => openGoalSaveSheet(ctx, d.goals.first));
    await openAndClose(() => openFindeksSheet(ctx, entry: d.findeks.first));
  });
}
