import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/widgets.dart';

import '../core/calc.dart';
import '../core/model.dart';
import '../core/normalize.dart';
import '../core/sync/api.dart';
import '../core/sync/engine.dart';
import '../core/sync/stamp.dart';
import '../core/update.dart';
import '../core/util.dart';
import '../core/version.dart';
import '../storage/store.dart';
import '../storage/updater.dart';

/// Üst menüdeki sekmeler, soldan sağa.
enum AppTab { ozet, harcamalar, borclar, bankalar, plan, alisveris, ayarlar }

enum AppStatus { loading, welcome, ready, corrupt }

/// Kurulum sihirbazının adımları, sırayla.
const List<String> kSetupSteps = ['ekstre', 'hesaplar', 'kartlar', 'krediler', 'gelir', 'giderler', 'bitti'];
const String kFirstSetupStep = 'ekstre';

/// Uygulamanın durumu: profiller, açık profilin verisi, sekme, dil, ayarlar.
class AppState extends ChangeNotifier {
  AppState({
    required this.store,
    Locale? initialLocale,
    this.updater,
    this.syncApi,
    bool? phone,
    this.buildNumber = kBuildNumber,
  })  : phone = phone ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        locale = ValueNotifier<Locale>(initialLocale ?? systemLocale());

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
    await _closeSync();
    profile = p;
    _data = null;
    _ctx = null;
    _savedIdx = null;
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
    _savedIdx = indexData(n.data!.j);
    p.lastOpenedAt = nowISO();
    index.last = id;
    await _saveIndex();
    _tab = AppTab.ozet;
    _tip = null;
    status = AppStatus.ready;
    notifyListeners();
    await _openSync(id);
  }

  /// Yeni profil oluşturur (veri verilmezse boş başlar) ve açar.
  /// [setup] verilirse profil kurulum sihirbazıyla açılır.
  Future<void> createProfile(String name, {Json? data, bool setup = false, Json? syncState}) async {
    final clean = name.trim().isEmpty ? (lang == 'tr' ? 'Profilim' : 'My profile') : name.trim();
    final id = newProfileId(clean, index.profiles.map((p) => p.id));
    final info = ProfileInfo(id: id, name: clean, createdAt: nowISO());
    final n = normalizeData(data ?? emptyData().j);
    final json = n.data?.j ?? emptyData().j;
    await store.saveData(id, json);
    // Telefonda bilgisayarla eşleşerek açılan profil: eşitleme durumu veriyle birlikte yazılır.
    if (syncState != null) await store.saveSyncState(id, syncState);
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
    if (profile?.id == id) await _closeSync();
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

  /// Profil dizinini yazar (bütün yazmalarla aynı sırada; bkz. [_enqueue]).
  Future<void> _saveIndex() => _enqueue(() async {
        try {
          await store.saveIndex(index);
        } catch (_) {
          // dizin yazılamadıysa bir sonraki kayıtta yeniden denenir
        }
      });

  // ---------------------------------------------------------------- Değişiklikler

  Future<void> _saving = Future<void>.value();

  /// Dosya yazmaları sırayla yapılır; [flush] hepsinin bitmesini bekler
  /// (ör. pencere kapanırken son değişiklik yarım kalmasın).
  Future<void> _enqueue(Future<void> Function() job) {
    final next = _saving.then((_) => job());
    _saving = next.catchError((Object _) {});
    return _saving;
  }

  /// [_enqueue] gibi, ama işin hatası geri döner (eşitleme kaydedemediğini bilmeli).
  Future<void> _enqueueChecked(Future<void> Function() job) {
    final next = _saving.then((_) => job());
    _saving = next.catchError((Object _) {});
    return next;
  }

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
    // Değişen ve yeni kayıtlara değişiklik zamanı yazılır (eşitlemede son değişiklik kazanır).
    _savedIdx = stampChanges(d.j, _savedIdx, nowISO());
    final snapshot = deepCopy(d.j) as Json;
    unawaited(_enqueue(() async {
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
    }));
    _engine?.onSave();
  }

  /// Geri alma: verinin önceki bir kopyasını geri koyar ve kaydeder.
  void restore(Json snapshot) {
    if (_data == null) return;
    _undoUntil = null;
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

  // ---------------------------------------------------------------- Güncellemeler

  /// Yeni sürüm denetimi ve indirme (web önizlemesinde ve testlerde null).
  final Updater? updater;

  /// Bu derlemenin numarası (0: geliştirme derlemesi, denetim yapılmaz).
  final int buildNumber;

  /// Kullanılandan daha yeni bir sürüm varsa bilgisi.
  UpdateInfo? newVersion;

  /// Denetim sürüyor mu.
  bool updateChecking = false;

  /// Son denetimin sonucu: null (hiç denetlenmedi), true (güncel ya da yeni sürüm bulundu), false (denetlenemedi).
  bool? updateChecked;

  /// Güncelleme indiriliyorsa ilerleme (0–1); başlatıldıysa 1.
  double? updateProgress;
  String? updateError;

  bool get canCheckUpdates => updater != null && buildNumber > 0;

  /// Son sürüme bakar. [manual] değilse yalnızca otomatik denetim açıksa çalışır.
  Future<void> checkForUpdate({bool manual = false}) async {
    final u = updater;
    if (u == null || buildNumber <= 0 || updateChecking) return;
    if (!manual && !index.autoUpdate) return;
    updateChecking = true;
    updateError = null;
    notifyListeners();
    try {
      final raw = await u.fetchLatest();
      newVersion = parseRelease(raw, current: buildNumber);
      updateChecked = true;
    } catch (_) {
      updateChecked = false;
    } finally {
      updateChecking = false;
      notifyListeners();
    }
  }

  void setAutoUpdate(bool value) {
    if (index.autoUpdate == value) return;
    index.autoUpdate = value;
    unawaited(_saveIndex());
    notifyListeners();
    if (value) unawaited(checkForUpdate());
  }

  /// "Yeni sürüm var" haberi bu sürüm için verildi mi (her sürüm için bir kez gösterilir).
  bool get updateNeedsNotice => newVersion != null && index.updateNotified < newVersion!.build;

  void markUpdateNoticed() {
    final u = newVersion;
    if (u == null || index.updateNotified >= u.build) return;
    index.updateNotified = u.build;
    unawaited(_saveIndex());
  }

  /// Güncelleme dosyasını indirir ve başlatır; o da bu pencereyi kapatıp yeni sürümü kurar.
  /// Uygulama kurulum programıyla kurulmamışsa false döner (sürüm sayfası açılmalı).
  Future<bool> installUpdate() async {
    final u = updater;
    final info = newVersion;
    if (u == null || info == null || updateProgress != null) return true;
    if (!u.installed || info.updater == null) return false;
    updateProgress = 0;
    updateError = null;
    notifyListeners();
    try {
      final path = await u.download(info, (p) {
        updateProgress = p;
        notifyListeners();
      });
      await flush();
      await u.launch(path);
      updateProgress = 1;
    } catch (e) {
      updateProgress = null;
      updateError = e.toString();
    }
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- Telefon eşitlemesi

  /// Eşitlemenin şifreleme ve ağ işleri (web önizlemesinde ve testlerde null).
  final SyncApi? syncApi;

  /// Bu cihaz telefon mu (eşitleme süreleri ve metinler buna göre).
  final bool phone;

  SyncEngine? _engine;

  /// Açık profilin eşitlemesi (eşitleme olmayan platformda null). Eşleştirme yoksa
  /// `sync.paired` false'tur.
  SyncEngine? get sync => _engine;

  /// Kaydedilmiş kayıtların özeti: hangi kaydın değiştiği buradan anlaşılır.
  SyncIndex? _savedIdx;

  int _sheets = 0;
  DateTime? _undoUntil;
  final StreamController<SyncEvent> _syncEvents = StreamController<SyncEvent>.broadcast();

  /// Eşitlemenin kullanıcıya haberleri (kabuk bunları bildirim olarak gösterir).
  Stream<SyncEvent> get syncEvents => _syncEvents.stream;

  /// Bu bilgisayardaki eski Mel Capital'in telefon eşleştirmesi (yoksa null).
  Json? legacySync;
  bool _legacySyncRead = false;

  Future<void> _openSync(String id) async {
    final api = syncApi;
    if (api == null) return;
    final engine = SyncEngine(api: api, host: _SyncHost(this, id), phone: phone);
    _engine = engine;
    Object? raw;
    try {
      raw = await store.loadSyncState(id);
    } catch (_) {
      raw = null;
    }
    final ok = await engine.load(raw);
    if (_engine != engine) return;
    if (ok) engine.start();
    if (!phone && !_legacySyncRead && !index.legacySyncUsed) {
      _legacySyncRead = true;
      try {
        final legacy = await store.readLegacySync();
        if (syncStateValid(legacy)) legacySync = deepCopy(legacy) as Json;
      } catch (_) {
        legacySync = null;
      }
    }
    notifyListeners();
  }

  Future<void> _closeSync() async {
    final e = _engine;
    _engine = null;
    if (e != null) await e.close();
  }

  /// Bir düzenleme paneli açıldı / kapandı (açıkken gelen değişiklikler bekletilir).
  void sheetOpened() => _sheets++;
  void sheetClosed() {
    if (_sheets > 0) _sheets--;
    _engine?.uiFree();
  }

  /// "Geri al" düğmeli bildirim gösterildi: süresi bitene kadar gelen değişiklikler bekletilir.
  void noteUndo(Duration d) {
    final until = clock().add(d);
    final u = _undoUntil;
    if (u == null || until.isAfter(u)) _undoUntil = until;
  }

  /// Kullanıcı ekrana dokundu (yoklama sıklığı için).
  void touch() {
    final e = _engine;
    if (e != null) e.lastActive = clock().millisecondsSinceEpoch;
  }

  /// Uygulama arka plana geçti / öne geldi.
  void setVisible(bool visible) {
    final e = _engine;
    if (e == null) return;
    e.visible = visible;
    if (visible) {
      e.onVisible();
    } else {
      e.onHidden();
    }
  }

  /// Elle eşitleme ("Şimdi eşitle").
  Future<void> syncNow() async => _engine?.run('elle');

  /// Pencere kapanırken: gönderilmemiş değişiklik varsa son bir kez eşitlenir.
  Future<void> syncBeforeExit() async {
    final e = _engine;
    if (e == null || !e.paired || !e.dirty) return;
    try {
      await e.run('kapanis').timeout(const Duration(seconds: 6));
    } catch (_) {
      // eşitlenemediyse bir sonraki açılışta gönderilir
    }
  }

  /// Bilgisayar: eski Mel Capital'in telefon eşleştirmesi açık profille sürdürülebilir mi.
  bool get canAdoptLegacySync => legacySync != null && !index.legacySyncUsed && (sync?.paired == false) && hasData;

  /// Bilgisayar: eski Mel Capital'in telefon eşleştirmesini açık profille sürdürür. Eşleştirme
  /// yalnızca bir profile aktarılır.
  Future<void> adoptLegacySync() async {
    final e = _engine;
    final legacy = legacySync;
    if (e == null || legacy == null || !hasData || index.legacySyncUsed) return;
    final union = !syncSameOrigin(legacy['base'], data.j);
    await e.adopt(legacy, union: union);
    legacySync = null;
    index.legacySyncUsed = true;
    await _saveIndex();
    e.start();
    notifyListeners();
  }

  /// Eski Mel Capital'in verisiyle yeni profil açılır; o bilgisayarda telefon eşleştirmesi varsa
  /// bu profille sürer (eski uygulama nerede bıraktıysa oradan).
  Future<void> createLegacyProfile(String name, Json data) async {
    await createProfile(name, data: data);
    if (canAdoptLegacySync) {
      try {
        await adoptLegacySync();
      } catch (_) {
        // eşleştirme sürdürülemezse Ayarlar → Telefon'dan yeniden denenebilir
      }
    }
  }

  /// Telefon: bilgisayardaki koddan (bağlantı) eşleşir; bilgisayardaki verilerle yeni bir profil
  /// açılır. Hata olursa SyncError fırlatır.
  Future<void> pairFromLink(String key, String bilet, {String? name}) async {
    final api = syncApi;
    if (api == null) throw SyncError('ag');
    // Geçici eşitleme: yalnızca indirir; açık profilin eşitlemesine dokunmaz.
    final engine = SyncEngine(api: api, host: _SyncHost(this, ''), phone: phone);
    final remote = await engine.pair(key, bilet, newSyncDevice(phone: phone));
    final n = normalizeData(remote);
    if (!n.ok) throw SyncError('bicim', n.errors.take(3).toList());
    final st = engine.st!;
    await createProfile(name ?? '', data: n.data!.j, syncState: st);
  }

  /// Eşleştirmeyi kaldırır. Bilgisayarda sunucudaki şifreli kopya da silinir; telefonda yalnızca
  /// bu cihaz ayrılır (veriler profil olarak kalır).
  Future<void> unpairSync() async {
    final e = _engine;
    if (e == null) return;
    await e.unpair(deleteRemote: !phone);
    notifyListeners();
  }

  Future<void> _syncAdopt(String id, Json merged, Json state) async {
    if (profile?.id != id || _data == null) throw StateError('Profil değişti');
    _data = Data(merged);
    _ctx = null;
    _savedIdx = indexData(merged);
    notifyListeners();
    final dataCopy = deepCopy(merged) as Json;
    final stateCopy = deepCopy(state) as Json;
    await _enqueueChecked(() async {
      await store.saveData(id, dataCopy);
      await store.saveSyncState(id, stateCopy);
    });
  }

  void _syncChanged() => notifyListeners();

  Future<void> _syncPersist(String id, Json? state) {
    final copy = state == null ? null : deepCopy(state) as Json;
    return _enqueueChecked(() => store.saveSyncState(id, copy));
  }

  void setSetting(String key, Object? value) {
    settings[key] = value;
    final id = profile?.id;
    if (id != null) {
      final copy = deepCopy(settings) as Json;
      unawaited(_enqueue(() => store.saveSettings(id, copy).catchError((Object _) {})));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _engine?.stop();
    unawaited(_syncEvents.close());
    locale.dispose();
    super.dispose();
  }
}

/// Eşitlemenin kullanıcıya haberi.
class SyncEvent {
  const SyncEvent(this.notice, [this.detail]);
  final SyncNotice notice;
  final String? detail;
}

/// Eşitlemenin uygulamayla bağı: yalnızca kendi profiline yazar.
class _SyncHost implements SyncHost {
  _SyncHost(this.state, this.profileId);

  final AppState state;
  final String profileId;

  bool get _mine => state.profile?.id == profileId && state.status == AppStatus.ready;

  @override
  Json? get syncData => _mine && state.hasData ? state.data.j : null;

  @override
  bool get syncUiBusy {
    final u = state._undoUntil;
    return state._sheets > 0 || (u != null && u.isAfter(clock()));
  }

  @override
  DateTime? get syncUndoUntil => state._undoUntil;

  @override
  Future<void> syncAdopt(Json merged, Json st) => state._syncAdopt(profileId, merged, st);

  @override
  Future<void> syncPersist(Json? st) {
    if (profileId.isEmpty) return Future<void>.value();
    return state._syncPersist(profileId, st);
  }

  @override
  void syncChanged() {
    if (_mine) state._syncChanged();
  }

  @override
  void syncNotify(SyncNotice notice, {String? detail}) {
    if (_mine && !state._syncEvents.isClosed) state._syncEvents.add(SyncEvent(notice, detail));
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
