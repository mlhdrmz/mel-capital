import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Üst menüdeki sekmeler, soldan sağa.
enum AppTab { ozet, harcamalar, borclar, bankalar, plan, alisveris, ayarlar }

/// Uygulamanın o anki durumu: açık sekme, dil, tutarların gizli olup olmadığı.
class AppState extends ChangeNotifier {
  AppState({Locale? initialLocale})
      : locale = ValueNotifier<Locale>(initialLocale ?? systemLocale());

  /// Windows'un dili Türkçe ise Türkçe, değilse İngilizce.
  static Locale systemLocale() {
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    return Locale(code == 'tr' ? 'tr' : 'en');
  }

  final ValueNotifier<Locale> locale;
  AppTab _tab = AppTab.ozet;
  bool _hidden = false;

  AppTab get tab => _tab;
  bool get hidden => _hidden;

  void setTab(AppTab value) {
    if (value == _tab) return;
    _tab = value;
    notifyListeners();
  }

  void setLanguage(String code) {
    final next = Locale(code == 'tr' ? 'tr' : 'en');
    if (locale.value == next) return;
    locale.value = next;
    notifyListeners();
  }

  void toggleHidden() {
    _hidden = !_hidden;
    notifyListeners();
  }

  @override
  void dispose() {
    locale.dispose();
    super.dispose();
  }
}

/// Durumu ağacın her yerine ulaştırır: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope bulunamadı');
    return scope!.notifier!;
  }
}
