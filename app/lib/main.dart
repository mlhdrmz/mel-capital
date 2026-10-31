import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/sample.dart';
import 'src/shell.dart';
import 'src/state.dart';
import 'src/theme.dart';
import 'storage/store.dart';
import 'storage/store_memory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    runApp(MelCapitalApp(state: await previewState(Uri.base.queryParameters)));
    return;
  }
  final state = AppState(store: createStore());
  runApp(MelCapitalApp(state: state));
  await state.init();
}

/// Web önizlemesi (tasarım kontrolü): örnek verili bir profil bellekte açılır.
///
/// `?sekme=plan` istenen sekmeyi, `?dil=en` dili, `?ekran=hosgeldin` ilk açılış ekranını,
/// `?banka=akbank` Bankalar'da o bankanın sayfasını açar.
Future<AppState> previewState(Map<String, String> query) async {
  final lang = query['dil'];
  final state = AppState(
    store: MemoryStore(),
    initialLocale: lang == null ? null : Locale(lang == 'en' ? 'en' : 'tr'),
  );
  if (query['ekran'] == 'hosgeldin') {
    await state.init();
    return state;
  }
  await state.createProfile(state.lang == 'tr' ? 'Deniz' : 'Alex', data: await loadSampleJson());
  for (final tab in AppTab.values) {
    if (tab.name == query['sekme']) state.setTab(tab);
  }
  final bank = query['banka'];
  if (bank != null) state.preview['banka'] = bank;
  return state;
}

class MelCapitalApp extends StatelessWidget {
  const MelCapitalApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ValueListenableBuilder<Locale>(
        valueListenable: state.locale,
        builder: (context, locale, _) => MaterialApp(
          title: 'Mel Capital',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          scrollBehavior: const _NoScrollbars(),
          locale: locale,
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Shell(),
        ),
      ),
    );
  }
}

/// Kaydırma çubukları gösterilmez (fare tekerleği ve dokunmatik kaydırma çalışır).
class _NoScrollbars extends MaterialScrollBehavior {
  const _NoScrollbars();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}
