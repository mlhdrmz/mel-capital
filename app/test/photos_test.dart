// Arka plan fotoğrafları eski Mel Capital'deki gibi seçilmeli: hangi sekmede hangi fotoğraf, akşam teması,
// favoriler, gizlenenler, fotoğraflar yetmeyince kapaklar. Beklenen seçimler eski uygulamanın kendi kodu
// (app4.js photoPool/bgPhoto) çalıştırılarak üretildi (test/fixtures/foto.json; parlaklıklar uydurmadır).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/photos.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/photos.dart';
import 'package:mel_capital/storage/store.dart';
import 'package:mel_capital/storage/store_memory.dart';

class FakePhotoStore implements PhotoStore {
  FakePhotoStore(Iterable<String> ids, {this.legacy}) : _ids = ids.toList();

  final List<String> _ids;
  final Json? legacy;
  final Map<String, PhotoSrc> _avail = {};

  @override
  void Function()? onChange;

  @override
  Map<String, PhotoSrc> get available => _avail;

  @override
  int get missing => 0;

  @override
  bool get busy => false;

  @override
  Future<void> start(PhotoSize size) async {
    for (final id in _ids) {
      _avail[id] = PhotoSrc(path: '/yok/$id.jpg', lum: 0.5);
    }
    onChange?.call();
  }

  @override
  Future<Json?> readLegacyPrefs() async => legacy;

  @override
  void dispose() {}
}

FakePhotoStore fakeStore(Iterable<String> ids, {Json? legacy}) => FakePhotoStore(ids, legacy: legacy);

void main() {
  final all = [for (final p in kPhotos) p.id];

  group('seçim eski uygulamayla aynı', () {
    final fx = jsonDecode(File('test/fixtures/foto.json').readAsStringSync()) as Map;
    final lumAll = (fx['lum'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    final scenarios = {for (final s in (fx['scenarios'] as List).cast<Map<dynamic, dynamic>>()) s['name'] as String: s};
    for (final c in (fx['cases'] as List).cast<Map<dynamic, dynamic>>()) {
      final sc = scenarios[c['scenario']]!;
      test('${c['scenario']} · ${c['at']}', () {
        final now = DateTime.parse(c['at'] as String);
        expect(isEveningIst(now), c['evening']);
        final avail = sc['avail'] == 'hepsi' ? all.toSet() : (sc['avail'] as List).cast<String>().toSet();
        final pool = photoPool(
          avail: avail,
          lum: sc['lum'] == 'yok' ? const {} : lumAll,
          hide: (sc['photoHide'] as List).cast<String>().toSet(),
          fav: (sc['photoFav'] as List).cast<String>().toSet(),
          night: sc['photoNight'] == true,
          now: now,
        );
        final picks = [for (var i = 0; i < kPhotoPages; i++) bgPick(pool, i, now)];
        expect([for (final p in picks) p.photo?.id ?? p.cover], c['picks']);
      });
    }
  });

  test('fotoğraf listesi', () {
    expect(kPhotos.length, 75);
    expect(all.toSet().length, all.length, reason: 'kimlikler tekrarlanmaz');
    for (final id in all) {
      expect(kPhotoIdRe.hasMatch(id), isTrue, reason: id);
    }
    expect(photoCredits().length, lessThan(kPhotos.length));
    expect(photoById(all.first)?.by, 'Rosemary Media');
  });

  test('indirme boyutu eski uygulamadaki gibi', () {
    // Bilgisayar: ekranın büyük kenarı (fiziksel piksel) → 1920, 2560 ya da 3840
    expect(PhotoSize.forScreen(width: 1920, height: 1080, dpr: 1, phone: false).width, 1920);
    expect(PhotoSize.forScreen(width: 1366, height: 768, dpr: 1, phone: false).width, 1920);
    expect(PhotoSize.forScreen(width: 1280, height: 720, dpr: 1.5, phone: false).width, 1920);
    expect(PhotoSize.forScreen(width: 1707, height: 960, dpr: 1.5, phone: false).width, 2560);
    expect(PhotoSize.forScreen(width: 2560, height: 1440, dpr: 1, phone: false).width, 2560);
    expect(PhotoSize.forScreen(width: 1920, height: 1080, dpr: 2, phone: false).width, 3840);
    final d = const PhotoSize.desktop(2560).url('1559310589-2673bfe16970');
    expect(d, 'https://images.unsplash.com/photo-1559310589-2673bfe16970?ixlib=rb-4.1.0&w=2560&fit=max&q=82&fm=jpg');
    // Telefon: ekran (en çok 2× yoğunluk), 80'in katı, dikey
    final p = PhotoSize.forScreen(width: 412, height: 915, dpr: 2.625, phone: true);
    expect([p.width, p.height, p.phone], [800, 1840, true]);
    final l = PhotoSize.forScreen(width: 915, height: 412, dpr: 2.625, phone: true);
    expect([l.width, l.height], [800, 1840], reason: 'yatay tutulsa da dikey indirilir');
    final big = PhotoSize.forScreen(width: 1600, height: 2560, dpr: 2, phone: true);
    expect([big.width, big.height], [2400, 2400]);
    expect(p.url('x'), contains('w=800&h=1840&fit=crop'));
  });

  test('tercihler profil dizininde saklanır', () {
    final idx = ProfileIndex.fromJson({
      'photoHide': ['a', 3, 'b'],
      'photoFav': ['c'],
      'photoNight': false,
      'photoLegacy': true,
    });
    expect(idx.photoHide, ['a', 'b']);
    expect(idx.photoFav, ['c']);
    expect(idx.photoNight, isFalse);
    expect(idx.photoLegacy, isTrue);
    final back = ProfileIndex.fromJson(jsonDecode(jsonEncode(idx.toJson())) as Json);
    expect([back.photoHide, back.photoFav, back.photoNight, back.photoLegacy], [idx.photoHide, idx.photoFav, false, true]);
    // Eski dizinler: varsayılanlar
    final old = ProfileIndex.fromJson({'profiles': []});
    expect([old.photoHide, old.photoFav, old.photoNight, old.photoLegacy], [<String>[], <String>[], true, false]);
  });

  test('eski uygulamanın gizlenen ve favori fotoğrafları bir kez aktarılır', () async {
    final store = MemoryStore();
    final legacy = {
      'photoHide': [all[3], all[10], 'gecersiz'],
      'photoFav': [all[0], all[10]],
      'photoNight': false,
    };
    final st = AppState(store: store, photoStore: fakeStore(all, legacy: legacy));
    await st.init();
    await st.startPhotos(const PhotoSize.desktop(1920));
    expect(st.index.photoHide, [all[3], all[10]]);
    expect(st.index.photoFav, [all[0]], reason: 'gizlenen fotoğraf favori olmaz');
    expect(st.index.photoNight, isFalse);
    expect(st.photosAvailable, 75);
    final saved = await store.loadIndex();
    expect(saved.photoLegacy, isTrue);
    expect(saved.photoHide, [all[3], all[10]]);

    // Yeniden açılışta eski tercihler bir daha aktarılmaz (sonradan geri getirilenler gizlenmez)
    st.unhideAllPhotos();
    await Future<void>.delayed(Duration.zero);
    final again = AppState(store: store, photoStore: fakeStore(all, legacy: legacy));
    await again.init();
    await again.startPhotos(const PhotoSize.desktop(1920));
    expect(again.index.photoHide, isEmpty);
    st.dispose();
    again.dispose();
  });

  test('gizle, favori, akşam teması ve kapaklara dönüş', () async {
    final st = AppState(store: MemoryStore(), photoStore: fakeStore(all));
    await st.init();
    await st.startPhotos(const PhotoSize.desktop(1920));
    final now = DateTime.utc(2026, 11, 4, 9);
    final first = st.bgPickFor(0, now).photo!;
    expect(st.togglePhotoFav(first.id), isTrue);
    expect(st.isPhotoFav(first.id), isTrue);
    st.hidePhoto(first.id);
    expect(st.isPhotoFav(first.id), isFalse, reason: 'gizlenen favoriden çıkar');
    for (var i = 0; i < kPhotoPages; i++) {
      expect(st.bgPickFor(i, now).photo?.id, isNot(first.id));
    }
    st.unhidePhoto(first.id);
    expect(st.index.photoHide, isEmpty);
    st.setPhotoNight(false);
    expect(st.index.photoNight, isFalse);
    // Neredeyse hepsi gizlenirse gömülü kapaklar döner
    for (final id in all.skip(3)) {
      st.hidePhoto(id);
    }
    final pick = st.bgPickFor(2, now);
    expect(pick.photo, isNull);
    expect(kCovers, contains(pick.cover));
    st.dispose();
  });

  test('fotoğraf yeri yoksa kapaklar', () async {
    final st = AppState(store: MemoryStore());
    await st.init();
    await st.startPhotos(const PhotoSize.desktop(1920));
    expect(st.photosAvailable, 0);
    expect(st.bgPickFor(0, DateTime.utc(2026, 11, 4)).cover, isNotNull);
    st.dispose();
  });
}
