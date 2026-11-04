// Telefon eşitlemesinin ekranları: Ayarlar'daki Telefon bölümü, eşleştirme kodu, telefonda
// bağlantıyı yapıştırarak bağlanma. Sunucu bellekte çalışır.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/sync/engine.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/store_memory.dart';
import 'package:mel_capital/storage/sync_memory.dart';

import 'phone_test.dart' show loadRealFonts, withErrors;
import 'sync_helpers.dart';

void main() {
  setUpAll(loadRealFonts);

  void size(WidgetTester tester, {required bool phone}) {
    tester.view.physicalSize = phone ? const Size(390 * 3, 844 * 3) : const Size(1440 * 2, 900 * 2);
    tester.view.devicePixelRatio = phone ? 3 : 2;
    addTearDown(tester.view.reset);
  }

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  testWidgets('bilgisayar: eski telefon bağlantısı bu profille sürdürülür, kod gösterilir', (tester) async => withErrors((log) async {
        size(tester, phone: false);
        final server = MemorySyncServer();
        final api = MemorySyncApi(server);
        final legacy = await seed(api, sample());
        final st = AppState(store: MemoryStore()..legacySync = legacy, initialLocale: const Locale('tr'), syncApi: api, phone: false);
        st.showTips = false;
        await st.createProfile('Melih', data: sample());
        expect(st.canAdoptLegacySync, isTrue);
        await tester.pumpWidget(MelCapitalApp(state: st));
        st.setTab(AppTab.ayarlar);
        await tester.pumpAndSettle();
        expect(key('sync-panel'), findsOneWidget);
        expect(key('sync-button'), findsNothing);
        log.check('Telefon bölümü (eski bağlantı bulundu)');

        await tester.tap(key('sync-adopt'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sürdür'));
        await tester.pumpAndSettle();
        expect(st.sync!.paired, isTrue);
        expect(st.index.legacySyncUsed, isTrue);
        expect(key('sync-now'), findsOneWidget);
        expect(key('sync-button'), findsOneWidget);
        log.check('Telefon bölümü (bağlı)');

        await tester.tap(key('sync-code'));
        await tester.pumpAndSettle();
        expect(key('pair-qr'), findsOneWidget);
        log.check('eşleştirme kodu');
        await tester.tap(find.text('Tamam'));
        await tester.pumpAndSettle();

        // Üst menüdeki düğme hemen eşitler.
        await tester.tap(key('sync-button'));
        await tester.pumpAndSettle();
        expect(st.sync!.status, SyncStatus.ok);
        st.sync!.stop();
      }));

  testWidgets('telefon: bağlantı yapıştırılarak bilgisayara bağlanılır', (tester) async => withErrors((log) async {
        size(tester, phone: true);
        final server = MemorySyncServer();
        final api = MemorySyncApi(server);
        await seed(api, sample());
        final st = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), syncApi: api, phone: true);
        st.showTips = false;
        await st.init();
        st.finishIntro();
        await tester.pumpWidget(MelCapitalApp(state: st));
        await tester.pumpAndSettle();
        expect(key('start-pair'), findsOneWidget);
        log.check('başlangıç (telefon)');

        await tester.tap(key('start-pair'));
        await tester.pumpAndSettle();
        expect(key('pair-scan'), findsOneWidget);
        log.check('bağlanma paneli');
        await tester.tap(key('pair-paste'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'yanlış');
        await tester.tap(key('pair-connect'));
        await tester.pumpAndSettle();
        expect(find.textContaining('eşleştirme bağlantısı değil'), findsOneWidget);
        log.check('yanlış bağlantı');

        await tester.enterText(find.byType(TextField).last, 'https://mel-capital.vercel.app/#e=$kKey.$kBilet');
        await tester.tap(key('pair-connect'));
        await tester.pumpAndSettle();
        expect(st.status, AppStatus.ready);
        expect(st.sync!.paired, isTrue);
        expect(st.data.spends.length, (sample()['spends'] as List).length);
        log.check('bağlandıktan sonra');

        st.setTab(AppTab.ayarlar);
        await tester.pumpAndSettle();
        expect(key('sync-panel'), findsOneWidget);
        expect(key('sync-code'), findsNothing);
        await tester.drag(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        log.check('Ayarlar (telefon, bağlı)');
        st.sync!.stop();
      }));

  testWidgets('telefon: bağlı değilken Ayarlar\'da bağlanma düğmesi', (tester) async => withErrors((log) async {
        size(tester, phone: true);
        final st = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), syncApi: MemorySyncApi(MemorySyncServer()), phone: true);
        st.showTips = false;
        await st.createProfile('Deniz', data: sample());
        await tester.pumpWidget(MelCapitalApp(state: st));
        st.setTab(AppTab.ayarlar);
        await tester.pumpAndSettle();
        expect(key('sync-pair'), findsOneWidget);
        log.check('Ayarlar (telefon, bağlı değil)');
      }));
}
