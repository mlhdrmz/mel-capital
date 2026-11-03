import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/calc.dart';
import '../core/model.dart';
import '../core/normalize.dart';
import '../core/util.dart';
import '../storage/store.dart';

/// Üst menüdeki sekmeler, soldan sağa.
enum AppTab { ozet, harcamalar, borclar, bankalar, plan, alisveris, ayarlar }

enum AppStatus { loading, welcome, ready, corrupt }

/// Kurulum sihirbazının adımları, sırayla.
const List<String> kSetupSteps = ['ekstre', 'hesaplar', 'kartlar', 'krediler', 'gelir', 'giderler', 'bitti'];
const String kFirstSetupStep = 'ekstre';

/// Uygulamanın durumu: profiller, açık profilin verisi, sekme, dil, ayarlar.
class AppState extends ChangeNotifier {
  AppState({required this.store, Locale? initialLocale})
      : locale = ValueNotifier<Locale>(initialLocale ?? systemLocale());

  /// Windows'un dili Türkçe ise Türkçe, değilse İngilizce.
  static Locale systemLocale() {
    final code = ui.PlatformDispatcher.instance.locale.languageCode;
    return Locale(code == 'tr' ? 'tr' : 'en');
  }

  final Store store;
  final ValueNotifier<Locale> locale;
  String get lang => locale.value.languageCode;

  AppStatus status = AppStatus.loading;
  ProfileIndex index = ProfileIndex();
  ProfileInfo? profile;
  Data? _data;
  Ctx? _ctx;
  Json settings = {};
  List<String> corruptErrors = const [];
  Object? corruptRaw;
  String? saveError;

  /// Web önizlemesi için açılış ayrıntıları (ör. 'banka': 'akbank').
  final Map<String, String> preview = {};

  AppTab _tab = AppTab.ozet;
  AppTab get tab => _tab;

  /// Ayarlar'dan yeni profil açılırken ilk açılış ekranı gösterilir.
  bool _adding = false;
  bool get addingProfile => _adding;
  void setAddingProfile(bool value) {
    if (_adding == value) return;
    _adding = value;
    notifyListeners();
  }
  bool get hidden => settings['hidden'] == true;

  Data get data => _data!;
  bool get hasData => _data != null;

  /// Hesaplar: veri değişince ya da ay dönünce yeniden kurulur.
  Ctx get ctx {
    final c = _ctx;
    if (c != null && c.cur == currentMonth()) return c;
    return _ctx = Ctx(data);
  }

  // ---------------------------------------------------------------- Açılış ve profiller

  Future<void> init() async {
    try {
      index = await store.loadIndex();
    } catch (_) {
      index = ProfileIndex();
    }
    final savedLang = index.lang;
    if (savedLang != null) locale.value = Locale(savedLang);
    final last = index.byId(index.last) ?? (index.profiles.isEmpty ? null : index.profiles.first);
    if (last == null) {
      status = AppStatus.welcome;
      notifyListeners();
      return;
    }
    await openProfile(last.id);
  }

  Future<void> openProfile(String id) async {
    final p = index.byId(id);
    if (p == null) return;
    profile = p;
    _data = null;
    _ctx = null;
    Object? raw;
    try {
      raw = await store.loadData(id);
      settings = await store.loadSettings(id);
    } catch (e) {
      corruptErrors = ['Veri dosyası okunamadı: $e'];
      corruptRaw = null;
      status = AppStatus.corrupt;
      notifyListeners();
      return;
    }
    final n = normalizeData(raw ?? emptyData().j);
    if (!n.ok) {
      corruptErrors = n.errors;
      corruptRaw = raw;
      status = AppStatus.corrupt;
      notifyListeners();
      return;
    }
    _data = n.data;
    p.lastOpenedAt = nowISO();
    index.last = id;
    await _saveIndex();
    _tab = AppTab.ozet;
    _tip = null;
    status = AppStatus.ready;
    notifyListeners();
  }

  /// Yeni profil oluşturur (veri verilmezse boş başlar) ve açar.
  /// [setup] verilirse profil kurulum sihirbazıyla açılır.
  Future<void> createProfile(String name, {Json? data, bool setup = false}) async {
    final clean = name.trim().isEmpty ? (lang == 'tr' ? 'Profilim' : 'My profile') : name.trim();
    final id = newProfileId(clean, index.profiles.map((p) => p.id));
    final info = ProfileInfo(id: id, name: clean, createdAt: nowISO());
    final n = normalizeData(data ?? emptyData().j);
    final json = n.data?.j ?? emptyData().j;
    await store.saveData(id, json);
    if (setup) {
      try {
        await store.saveSettings(id, <String, dynamic>{'setupStep': kFirstSetupStep});
      } catch (_) {
        // ayarlar yazılamazsa sihirbaz yine açılır (bellekteki ayarla)
      }
    }
    _adding = false;
    _introOpen = false;
    index.intro = true;
    index.profiles.add(info);
    index.last = id;
    await _saveIndex();
    await openProfile(id);
    if (setup && setupStep == null) {
      settings['setupStep'] = kFirstSetupStep;
      notifyListeners();
    }
  }

  Future<void> renameProfile(String id, String name) async {
    final p = index.byId(id);
    if (p == null || name.trim().isEmpty) return;
    p.name = name.trim();
    await _saveIndex();
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    await store.deleteProfile(id);
    index.profiles.removeWhere((p) => p.id == id);
    if (index.last == id) index.last = index.profiles.isEmpty ? null : index.profiles.first.id;
    await _saveIndex();
    if (profile?.id == id) {
      profile = null;
      _data = null;
      _ctx = null;
      if (index.last != null) {
        await openProfile(index.last!);
        return;
      }
      status = AppStatus.welcome;
    }
    notifyListeners();
  }

  /// Bozuk veri yerine yedekten dönmek ya da boş başlamak için.
  Future<void> replaceData(Json raw) async {
    final id = profile?.id;
    if (id == null) return;
    final n = normalizeData(raw);
    if (!n.ok) throw FormatException(n.errors.take(3).join('\n'));
    await store.backupNow(id, prefix: 'degistirmeden-once').catchError((_) => '');
    await store.saveData(id, n.data!.j);
    await openProfile(id);
  }

  /// Profilin klasörünü (ya da yedek klasörünü) dosya gezgininde açar.
  Future<bool> openFolder({bool backups = false}) async {
    try {
      return await store.openFolder(profile?.id, backups: backups);
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveIndex() async {
    try {
      await store.saveIndex(index);
    } catch (_) {
      // dizin yazılamadıysa bir sonraki kayıtta yeniden denenir
    }
  }

  // ---------------------------------------------------------------- Değişiklikler

  Future<void> _saving = Future<void>.value();

  /// Veriyi değiştirir, hesapları yeniler ve dosyaya yazar.
  void update(void Function(Data d) change) {
    change(data);
    _ctx = null;
    _queueSave();
    notifyListeners();
  }

  void _queueSave() {
    final id = profile?.id;
    final d = _data;
    if (id == null || d == null) return;
    final snapshot = deepCopy(d.j) as Json;
    _saving = _saving.then((_) async {
      try {
        await store.saveData(id, snapshot);
        if (saveError != null) {
          saveError = null;
          notifyListeners();
        }
      } catch (e) {
        saveError = e.toString();
        notifyListeners();
      }
    });
  }

  /// Geri alma: verinin önceki bir kopyasını geri koyar ve kaydeder.
  void restore(Json snapshot) {
    if (_data == null) return;
    _data = Data(snapshot);
    _ctx = null;
    _queueSave();
    notifyListeners();
  }

  /// Değişiklikten önceki verinin kopyası (geri almak için).
  Json snapshot() => deepCopy(data.j) as Json;

  /// Bekleyen kayıtların bitmesini bekler.
  Future<void> flush() => _saving;

  // ---------------------------------------------------------------- Tanıtım

  bool _introOpen = false;

  /// Tanıtımda kaçıncı ekran (0–2).
  int introSlide = 0;

  /// Tanıtım gösterilsin mi: uygulama ilk açıldığında ya da Ayarlar'dan istenince.
  bool get showIntro => _introOpen || (status == AppStatus.welcome && !index.intro);

  void openIntro() {
    _introOpen = true;
    introSlide = 0;
    notifyListeners();
  }

  void setIntroSlide(int value) {
    if (introSlide == value) return;
    introSlide = value;
    notifyListeners();
  }

  void finishIntro() {
    _introOpen = false;
    introSlide = 0;
    if (!index.intro) {
      index.intro = true;
      unawaited(_saveIndex());
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- Kurulum sihirbazı

  /// Sihirbazın açık olduğu adım (null: sihirbaz kapalı). Profilin ayarlarında saklanır;
  /// uygulama yarıda kapanırsa kaldığı yerden açılır.
  String? get setupStep {
    final v = settings['setupStep'];
    return v is String && kSetupSteps.contains(v) ? v : null;
  }

  void setSetupStep(String? step) => setSetting('setupStep', step);

  /// Sihirbazı baştan açar (Ayarlar'dan).
  void startSetup() => setSetupStep(kFirstSetupStep);

  // ---------------------------------------------------------------- Sayfa ipuçları

  /// İpuçları gösterilsin mi (testlerde ve web önizlemesinde kapatılabilir).
  bool showTips = true;
  String? _tip;

  /// Bu sekmenin ipucu gösterilecekse sekmenin adı. İpucu ilk gösterildiği anda "görüldü"
  /// sayılır; kapatılana ya da sekme değişene kadar ekranda kalır.
  String? tipFor(AppTab tab) {
    if (_tip == tab.name) return _tip;
    if (!showTips || status != AppStatus.ready || !hasData || setupStep != null || _introOpen || _adding) return null;
    if (index.tips.contains(tab.name)) return null;
    _tip = tab.name;
    index.tips.add(tab.name);
    unawaited(_saveIndex());
    return _tip;
  }

  void dismissTip() {
    if (_tip == null) return;
    _tip = null;
    notifyListeners();
  }

  /// İpuçları her sayfada bir kez yeniden gösterilir.
  void resetTips() {
    index.tips.clear();
    _tip = null;
    unawaited(_saveIndex());
    notifyListeners();
  }

  // ---------------------------------------------------------------- Görünüm

  void setTab(AppTab value) {
    if (value == _tab) return;
    _tab = value;
    _tip = null;
    notifyListeners();
  }

  void setLanguage(String code) {
    final next = Locale(code == 'tr' ? 'tr' : 'en');
    if (locale.value == next) return;
    locale.value = next;
    index.lang = next.languageCode;
    unawaited(_saveIndex());
    notifyListeners();
  }

  void toggleHidden() => setSetting('hidden', !hidden);

  void setSetting(String key, Object? value) {
    settings[key] = value;
    final id = profile?.id;
    if (id != null) unawaited(store.saveSettings(id, settings).catchError((_) {}));
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
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope bulunamadı');
    return scope!.notifier!;
  }
}
