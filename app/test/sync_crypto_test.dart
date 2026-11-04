// Eşitleme paketinin şifrelemesi eski Mel Capital'le (tarayıcıdaki Web Crypto) aynı olmalı: aynı
// anahtardan aynı kimlik türer, eski uygulamanın paketi açılır, bu uygulamanın paketi de aynı
// biçimdedir.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/sync/api.dart';
import 'package:mel_capital/core/sync/merge.dart' show canon;
import 'package:mel_capital/storage/sync_io.dart';

Map<String, dynamic> kripto() => jsonDecode(File('test/fixtures/sync/kripto.json').readAsStringSync()) as Map<String, dynamic>;

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('HKDF-SHA256: RFC 5869 örneği', () {
    final okm = hkdfSha256(List<int>.filled(22, 0x0b), List<int>.generate(13, (i) => i), List<int>.generate(10, (i) => 0xf0 + i), 42);
    expect(hex(okm), '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
  });

  test('base64url: dolgusuz yazılır, dolgulu ya da dolgusuz okunur', () {
    expect(b64u([251, 255, 0]), '-_8A');
    expect(unb64u('-_8A'), [251, 255, 0]);
    expect(unb64u('AQ'), [1]);
    expect(unb64u('AQ=='), [1]);
  });

  test('eski uygulamanın anahtarından aynı kimlik türer', () async {
    final f = kripto();
    final keys = await IoSyncApi().derive(f['key'] as String);
    expect(keys.token, f['token']);
    expect(keys.secret.length, 32);
  });

  test('eski uygulamanın paketi açılır (gzip)', () async {
    final f = kripto();
    final api = IoSyncApi();
    final keys = await api.derive(f['key'] as String);
    final p = await api.open(keys, f['sealed'] as String);
    expect(canon(p), canon(f['payload']));
  });

  test('eski uygulamanın sıkıştırılmamış paketi de açılır', () async {
    final f = kripto();
    final api = IoSyncApi();
    final keys = await api.derive(f['key'] as String);
    final p = await api.open(keys, f['plain'] as String);
    expect(canon(p), canon(f['plainPayload']));
  });

  test('kendi paketini açar; paket sunucunun beklediği biçimde', () async {
    final f = kripto();
    final api = IoSyncApi();
    final keys = await api.derive(f['key'] as String);
    final text = await api.seal(keys, f['payload'] as Map<String, dynamic>);
    final env = jsonDecode(text) as Map;
    expect(env['mc'], 'senkron');
    expect(env['v'], 1);
    expect(env['z'], 1);
    expect(RegExp(r'^[A-Za-z0-9_-]{16}$').hasMatch(env['iv'] as String), isTrue);
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(env['ct'] as String), isTrue);
    final back = await api.open(keys, text);
    expect(canon(back), canon(f['payload']));
    // Her pakette yeni iv
    final again = jsonDecode(await api.seal(keys, f['payload'] as Map<String, dynamic>)) as Map;
    expect(again['iv'] == env['iv'], isFalse);
  });

  test('başka anahtarla açılmaz', () async {
    final f = kripto();
    final api = IoSyncApi();
    final other = await api.derive(b64u(List<int>.generate(32, (i) => i)));
    await expectLater(api.open(other, f['sealed'] as String), throwsA(isA<SyncError>().having((e) => e.code, 'code', 'sifre')));
  });

  test('bozuk paket ve geçersiz anahtar', () async {
    final api = IoSyncApi();
    final keys = await api.derive(kripto()['key'] as String);
    await expectLater(api.open(keys, '{}'), throwsA(isA<SyncError>().having((e) => e.code, 'code', 'bicim')));
    await expectLater(api.open(keys, 'yok'), throwsA(isA<SyncError>().having((e) => e.code, 'code', 'bicim')));
    await expectLater(api.derive('kisa'), throwsA(isA<SyncError>().having((e) => e.code, 'code', 'anahtar')));
    await expectLater(api.derive(b64u(List<int>.filled(16, 1))), throwsA(isA<SyncError>().having((e) => e.code, 'code', 'anahtar')));
  });

  test('eşleştirme bağlantısı', () {
    final key = 'A' * 43;
    final bilet = 'b_-' * 28 + 'xy';
    expect(bilet.length, 86);
    final link = pairLink(key, bilet);
    expect(link, 'https://mel-capital.vercel.app/#e=$key.$bilet');
    expect(parsePairLink(link), (key, bilet));
    expect(parsePairLink('  $key.$bilet\n'), (key, bilet));
    expect(parsePairLink('https://mel-capital.vercel.app/'), isNull);
    expect(parsePairLink('$key.${bilet.substring(1)}'), isNull);
  });

  test('eşitleme durumunun biçimi', () {
    final ok = {'v': 1, 'key': 'A' * 43, 'bilet': 'B' * 86, 'dev': {'id': 'pc-x', 'ad': 'Bilgisayar'}};
    expect(syncStateValid(ok), isTrue);
    expect(syncStateValid({...ok, 'v': 2}), isFalse);
    expect(syncStateValid({...ok, 'key': 'kisa'}), isFalse);
    expect(syncStateValid({...ok}..remove('dev')), isFalse);
    expect(syncStateValid(null), isFalse);
  });
}
