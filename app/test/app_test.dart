import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/src/format.dart';
import 'package:mel_capital/src/state.dart';

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

  Future<AppState> open(WidgetTester tester, String lang) async {
    tester.view.physicalSize = const Size(2400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = AppState(initialLocale: Locale(lang));
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('Türkçe açılır ve bütün sekmeler çizilir', (tester) async {
    final state = await open(tester, 'tr');
    expect(find.text('Mel Capital'), findsOneWidget);
    expect(find.text('Bugün elinde olan'), findsOneWidget);
    for (final tab in AppTab.values) {
      final button = find.byKey(ValueKey<String>('tab-${tab.name}'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(state.tab, tab);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Ayarlar'), findsWidgets);
  });

  testWidgets('dil değişir, tutarlar gizlenir', (tester) async {
    final state = await open(tester, 'tr');
    await tester.tap(find.byKey(const ValueKey<String>('tab-ayarlar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('lang-en')));
    await tester.pumpAndSettle();
    expect(state.locale.value.languageCode, 'en');
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('tab-plan')));
    await tester.pumpAndSettle();
    expect(find.text('Payment calendar'), findsOneWidget);
    expect(find.text('12,500 TL'), findsOneWidget);
    state.toggleHidden();
    await tester.pumpAndSettle();
    expect(find.text('12,500 TL'), findsNothing);
    expect(find.text('•••• TL'), findsWidgets);
  });
}
