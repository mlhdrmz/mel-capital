// Fotoğraf indirme (bilgisayar): eksikler bir kez indirilir; eski uygulamanın indirdikleri yeniden
// indirilmez ve o klasöre hiçbir şey yazılmaz. Sunucu yerine bilgisayardaki küçük bir sunucu kullanılır.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/photos.dart';
import 'package:mel_capital/storage/photos.dart';
import 'package:mel_capital/storage/photos_io.dart';

/// JPEG gibi başlayan, yeterince büyük uydurma dosya.
Uint8List fakeJpeg(int seed) => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.filled(30000, seed % 251)]);

Future<double> lum(Uint8List _) async => 0.42;

Future<void> waitIdle(PhotoStore s) async {
  for (var i = 0; i < 500 && s.busy; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory tmp;
  late HttpServer server;
  final requests = <String>[];
  var offline = false;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mc-foto');
    requests.clear();
    offline = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.uri.toString());
      if (offline) {
        req.response.statusCode = 503;
      } else {
        final id = req.uri.pathSegments.last.replaceFirst('photo-', '');
        req.response.headers.contentType = ContentType('image', 'jpeg');
        req.response.add(fakeJpeg(id.hashCode));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('eksikler iner, eski uygulamanın fotoğrafları yeniden inmez ve o klasör değişmez', () async {
    final own = Directory('${tmp.path}/yeni')..createSync();
    final legacyRoot = Directory('${tmp.path}/eski')..createSync();
    final legacyPhotos = Directory('${legacyRoot.path}/Fotograflar')..createSync();
    final ids = [for (final p in kPhotos) p.id];
    // Eski uygulama ikisini 2560 genişlikte, birini küçük indirmiş
    File('${legacyPhotos.path}/${ids[0]}.jpg').writeAsBytesSync(fakeJpeg(1));
    File('${legacyPhotos.path}/${ids[1]}.jpg').writeAsBytesSync(fakeJpeg(2));
    File('${legacyPhotos.path}/${ids[2]}.jpg').writeAsBytesSync(fakeJpeg(3));
    File('${legacyPhotos.path}/fotolar.json').writeAsStringSync(jsonEncode({
      ids[0]: {'w': 2560, 'lum': 0.3},
      ids[1]: {'w': 3840, 'lum': 0.6},
      ids[2]: {'w': 1920, 'lum': 0.5},
    }));
    File('${legacyRoot.path}/ayarlar.json').writeAsStringSync(jsonEncode({'photoHide': [ids[5]], 'photoFav': [ids[6]], 'photoNight': false}));
    final before = {for (final f in legacyRoot.listSync(recursive: true)) f.path: f.statSync().modified};

    final store = IoPhotoStore(dirOverride: own.path, legacyDirOverride: legacyRoot.path, base: 'http://127.0.0.1:${server.port}', lumOf: lum);
    var changes = 0;
    store.onChange = () => changes++;
    await store.start(const PhotoSize.desktop(2560));
    // Açılışta eski uygulamanın üç fotoğrafı hemen kullanılır
    expect(store.available.containsKey(ids[0]), isTrue);
    expect(store.available[ids[1]]!.lum, 0.6);
    await waitIdle(store);

    expect(store.available.length, kPhotos.length);
    expect(store.missing, 0);
    expect(changes, greaterThan(1));
    // İkisi yeterince büyük: inmedi. Küçük olan (1920) ve hiç olmayanlar indi.
    expect(requests.length, kPhotos.length - 2);
    expect(requests.any((u) => u.contains(ids[0])), isFalse);
    expect(requests.any((u) => u.contains(ids[2])), isTrue);
    expect(requests.first, contains('w=2560&fit=max&q=82&fm=jpg'));
    expect(store.available[ids[0]]!.path, startsWith(legacyPhotos.path));
    expect(store.available[ids[2]]!.path, startsWith(own.path));
    // Eski uygulamanın klasörüne dokunulmadı
    final after = {for (final f in legacyRoot.listSync(recursive: true)) f.path: f.statSync().modified};
    expect(after, before);
    // Tercihler yalnızca okunur
    final prefs = await store.readLegacyPrefs();
    expect(prefs?['photoHide'], [ids[5]]);
    final meta = jsonDecode(File('${own.path}/fotolar.json').readAsStringSync()) as Map;
    expect((meta[ids[2]] as Map)['w'], 2560);

    // Yeniden açılış: hepsi bu cihazda, hiçbir şey inmez
    requests.clear();
    final again = IoPhotoStore(dirOverride: own.path, legacyDirOverride: legacyRoot.path, base: 'http://127.0.0.1:${server.port}', lumOf: lum);
    await again.start(const PhotoSize.desktop(2560));
    await waitIdle(again);
    expect(again.available.length, kPhotos.length);
    expect(requests, isEmpty);
    store.dispose();
    again.dispose();
  });

  test('internet yoksa üç denemede bırakır, kapaklar kalır', () async {
    offline = true;
    final store = IoPhotoStore(dirOverride: '${tmp.path}/yeni', legacyDirOverride: '${tmp.path}/yok', base: 'http://127.0.0.1:${server.port}', lumOf: lum);
    await store.start(const PhotoSize.desktop(1920));
    await waitIdle(store);
    expect(store.available, isEmpty);
    expect(requests.length, 3);
    expect(store.missing, kPhotos.length);
    store.dispose();
  });

  test('telefonda ekran boyutunda kırpılmış iner; boyut değişince yeniden iner', () async {
    final dir = '${tmp.path}/telefon';
    final store = IoPhotoStore(dirOverride: dir, legacyDirOverride: '${tmp.path}/yok', base: 'http://127.0.0.1:${server.port}', lumOf: lum);
    await store.start(const PhotoSize.phone(800, 1840));
    await waitIdle(store);
    expect(store.available.length, kPhotos.length);
    expect(requests.first, contains('w=800&h=1840&fit=crop'));
    requests.clear();
    final other = IoPhotoStore(dirOverride: dir, legacyDirOverride: '${tmp.path}/yok', base: 'http://127.0.0.1:${server.port}', lumOf: lum);
    await other.start(const PhotoSize.phone(720, 1600));
    expect(other.available.length, kPhotos.length, reason: 'eskiler inene kadar kullanılır');
    await waitIdle(other);
    expect(requests.length, kPhotos.length);
    store.dispose();
    other.dispose();
  });
}
