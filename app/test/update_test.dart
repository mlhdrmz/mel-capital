import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/sample.dart';
import 'package:mel_capital/core/update.dart';
import 'package:mel_capital/core/version.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/store_memory.dart';
import 'package:mel_capital/storage/updater.dart';

Map<String, dynamic> release({String tag = 's150', bool pre = false, String? digest}) => {
      'tag_name': tag,
      'name': 'Mel Capital 05.11.2026-14.20',
      'html_url': 'https://github.com/mlhdrmz/mel-capital/releases/tag/$tag',
      'prerelease': pre,
      'draft': false,
      'body': 'Yenilikler\r\n- kurulum dosyası',
      'assets': [
        {
          'name': 'MelCapital-Kurulum.exe',
          'browser_download_url': 'https://github.com/mlhdrmz/mel-capital/releases/download/$tag/MelCapital-Kurulum.exe',
          'size': 1000,
        },
        {
          'name': 'MelCapital-Guncelleme-05.11.2026-14.20.exe',
          'browser_download_url': 'https://github.com/mlhdrmz/mel-capital/releases/download/$tag/MelCapital-Guncelleme-05.11.2026-14.20.exe',
          'size': 2000,
          'digest': digest,
        },
        {'name': 'MelCapital-Windows.zip', 'browser_download_url': 'https://example.com/z.zip', 'size': 5},
      ],
    };

class FakeUpdater implements Updater {
  FakeUpdater({this.latest, this.installed = true});

  Object? latest;
  @override
  bool installed;
  bool fail = false;
  int fetches = 0;
  final List<String> launched = [];

  @override
  Future<Object?> fetchLatest() async {
    fetches++;
    if (fail) throw Exception('çevrimdışı');
    return latest;
  }

  @override
  Future<String> download(UpdateInfo info, void Function(double progress) onProgress) async {
    onProgress(0.5);
    onProgress(1);
    return 'C:/Temp/Mel Capital Güncelleme ${info.label}.exe';
  }

  @override
  Future<void> launch(String path) async => launched.add(path);
}

void main() {
  test('sürüm etiketi okunur', () {
    expect(buildFromTag('s145'), 145);
    expect(buildFromTag('v1.0'), isNull);
    expect(buildFromTag(null), isNull);
    expect(findBuildLabel('Mel Capital 05.11.2026-14.20'), '05.11.2026-14.20');
    expect(buildLabelText('03.11.2026-22.39', 'tr'), '3 Kasım 2026, 22.39');
    expect(buildLabelText('03.11.2026-22.39', 'en'), '3 November 2026, 22:39');
    expect(buildLabelText('geliştirme', 'tr'), 'geliştirme');
  });

  test('yalnızca daha yeni resmi sürüm haber verilir', () {
    final sha = 'a' * 64;
    final info = parseRelease(release(digest: 'sha256:$sha'), current: 140);
    expect(info, isNotNull);
    expect(info!.build, 150);
    expect(info.label, '05.11.2026-14.20');
    expect(info.updater?.name, 'MelCapital-Guncelleme-05.11.2026-14.20.exe');
    expect(info.updater?.size, 2000);
    expect(info.updater?.sha256, sha);
    expect(info.setup?.name, 'MelCapital-Kurulum.exe');
    expect(info.notes, contains('kurulum dosyası'));
    expect(info.notes, isNot(contains('\r')));

    expect(parseRelease(release(), current: 150), isNull, reason: 'aynı sürüm');
    expect(parseRelease(release(), current: 160), isNull, reason: 'daha eski sürüm');
    expect(parseRelease(release(pre: true), current: 140), isNull, reason: 'önizleme sürümü');
    expect(parseRelease(release(), current: 0), isNull, reason: 'geliştirme derlemesi');
    expect(parseRelease(release(tag: 'onizleme'), current: 140), isNull);
    expect(parseRelease('bozuk', current: 140), isNull);
    expect(parseRelease(release(digest: 'md5:xx'), current: 140)?.updater?.sha256, isNull);
  });

  test('denetim ve tek tıkla güncelleme', () async {
    final fake = FakeUpdater(latest: release());
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), updater: fake, buildNumber: 140);
    await state.init();
    await state.checkForUpdate();
    expect(state.newVersion?.build, 150);
    expect(state.updateChecked, isTrue);
    expect(state.updateNeedsNotice, isTrue);
    state.markUpdateNoticed();
    expect(state.updateNeedsNotice, isFalse);
    expect(state.index.updateNotified, 150);

    expect(await state.installUpdate(), isTrue);
    expect(fake.launched.single, contains('05.11.2026-14.20'));
    expect(state.updateProgress, 1);

    // Kurulum programıyla kurulmamış kopya: sürüm sayfası açılmalı
    final portable = FakeUpdater(latest: release(), installed: false);
    final other = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), updater: portable, buildNumber: 140);
    await other.init();
    await other.checkForUpdate();
    expect(await other.installUpdate(), isFalse);
    expect(portable.launched, isEmpty);
  });

  test('otomatik denetim kapatılabilir; internet yoksa sessizce geçer', () async {
    final fake = FakeUpdater(latest: release());
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), updater: fake, buildNumber: 140);
    await state.init();
    state.setAutoUpdate(false);
    await state.checkForUpdate();
    expect(fake.fetches, 0);
    await state.checkForUpdate(manual: true);
    expect(fake.fetches, 1);
    expect(state.newVersion, isNotNull);

    fake.fail = true;
    state.newVersion = null;
    await state.checkForUpdate(manual: true);
    expect(state.updateChecked, isFalse);
    expect(state.newVersion, isNull);

    // Geliştirme derlemesinde hiç denetlenmez
    final dev = FakeUpdater(latest: release());
    final devState = AppState(store: MemoryStore(), updater: dev, buildNumber: 0);
    await devState.init();
    await devState.checkForUpdate(manual: true);
    expect(dev.fetches, 0);
  });

  testWidgets('Ayarlar: yeni sürüm haberi ve kurulum düğmesi', (tester) async {
    tester.view.physicalSize = const Size(2400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakeUpdater(latest: release());
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), updater: fake, buildNumber: 140);
    state.showTips = false;
    await state.createProfile('Deniz', data: await loadSampleJson());
    await state.checkForUpdate();
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    // Sekmede nokta ve bir kez gösterilen haber
    expect(find.byKey(const ValueKey<String>('update-dot')), findsOneWidget);
    expect(find.textContaining('yeni sürümü hazır'), findsOneWidget);
    expect(state.index.updateNotified, 150);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('tab-ayarlar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('update-card')), findsOneWidget);
    expect(find.textContaining('5 Kasım 2026, 14.20'), findsOneWidget);
    final install = find.byKey(const ValueKey<String>('update-install'));
    await tester.ensureVisible(install);
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(fake.launched, hasLength(1));
    expect(find.textContaining('Güncelleme başladı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
