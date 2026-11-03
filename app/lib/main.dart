import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/model.dart';
import 'core/normalize.dart';
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
/// `?sekme=plan` istenen sekmeyi, `?dil=en` dili, `?banka=akbank` Bankalar'da o bankanın sayfasını,
/// `?panel=harcama` harcama panelini açar. `?ekran=tanitim&slayt=2` ilk açılış tanıtımını,
/// `?ekran=baslangic` başlangıç ekranını, `?ekran=kurulum&adim=kartlar` kurulum sihirbazını,
/// `?ipucu=1` sayfa ipucunu gösterir.
Future<AppState> previewState(Map<String, String> query) async {
  final lang = query['dil'];
  final screen = query['ekran'];
  final state = AppState(
    store: MemoryStore(index: ProfileIndex(intro: screen != 'tanitim')),
    initialLocale: lang == null ? null : Locale(lang == 'en' ? 'en' : 'tr'),
  );
  state.showTips = query['ipucu'] != null;
  if (screen == 'tanitim' || screen == 'baslangic' || screen == 'hosgeldin') {
    await state.init();
    final slide = int.tryParse(query['slayt'] ?? '');
    if (slide != null) state.introSlide = slide < 1 ? 0 : (slide > 3 ? 2 : slide - 1);
    return state;
  }
  final name = state.lang == 'tr' ? 'Deniz' : 'Alex';
  final sample = await loadSampleJson();
  if (screen == 'kurulum') {
    final asked = query['adim'];
    final step = asked != null && kSetupSteps.contains(asked) ? asked : kFirstSetupStep;
    await state.createProfile(name, data: setupPreviewData(sample, step), setup: true);
    state.setSetupStep(step);
    return state;
  }
  await state.createProfile(name, data: sample);
  for (final tab in AppTab.values) {
    if (tab.name == query['sekme']) state.setTab(tab);
  }
  final bank = query['banka'];
  if (bank != null) state.preview['banka'] = bank;
  final panel = query['panel'];
  if (panel != null) state.preview['panel'] = panel;
  return state;
}

/// Kurulum ekranlarının önizlemesi: o adıma kadar eklenmiş gibi örnek veri.
Json setupPreviewData(Json sample, String step) {
  final i = kSetupSteps.indexOf(step);
  bool past(String x) => i >= kSetupSteps.indexOf(x);
  final debts = [for (final x in sample['debts'] as List) (x as Map).cast<String, dynamic>()];
  return <String, dynamic>{
    ...emptyData().j,
    if (past('hesaplar')) 'accounts': sample['accounts'],
    'debts': [
      if (past('kartlar')) ...debts.where((x) => x['type'] == 'kredi_karti'),
      if (past('krediler')) ...debts.where((x) => x['type'] != 'kredi_karti'),
    ],
    if (past('gelir')) 'incomes': sample['incomes'],
    if (past('giderler')) ...<String, dynamic>{
      'subscriptions': sample['subscriptions'],
      'recurringExpenses': sample['recurringExpenses'],
    },
  };
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
