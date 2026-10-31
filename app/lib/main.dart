import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/shell.dart';
import 'src/state.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MelCapitalApp(state: _initialState()));
}

/// Web önizlemesinde `?sekme=plan&dil=en` ile istenen ekran açılır (tasarım kontrolü için).
AppState _initialState() {
  if (!kIsWeb) return AppState();
  final query = Uri.base.queryParameters;
  final lang = query['dil'];
  final state = AppState(
    initialLocale: lang == null ? null : Locale(lang == 'tr' ? 'tr' : 'en'),
  );
  for (final tab in AppTab.values) {
    if (tab.name == query['sekme']) state.setTab(tab);
  }
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
