// Eşitlemenin akışı (eski Mel Capital'deki runSync ile aynı): iki cihaz aynı sunucu kopyasını
// paylaşır. Sunucu bellekte çalışır (MemorySyncServer); ETag, 409 ve 404 kuralları gerçeğiyle aynı.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/sync/api.dart';
import 'package:mel_capital/core/sync/engine.dart';
import 'package:mel_capital/core/sync/merge.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/store_memory.dart';
import 'package:mel_capital/storage/sync_memory.dart';

import 'sync_helpers.dart';

void main() {
  setUp(() => clock = () => DateTime.utc(2026, 10, 25, 12));
  tearDown(() => clock = DateTime.now);

  test('telefon eşleşir ve bilgisayarın verisini alır', () async {
    final p = await paired();
    expect(canon(p.telHost.data), canon(sample()));
    expect(p.tel.st!['seq'], 1);
    expect(p.tel.st!['dev']['id'], startsWith('tel-'));
    expect(p.tel.status, SyncStatus.ok);
    expect(p.tel.link, pairLink(kKey, kBilet));
  });

  test('değişiklik yokken yazılmaz', () async {
    final p = await paired();
    final puts = p.server.puts;
    await p.pc.run('elle');
    await p.tel.run('elle');
    expect(p.server.puts, puts);
    expect(p.pc.status, SyncStatus.ok);
    expect(p.pcHost.notices, contains(SyncNotice.synced));
  });

  test('telefonda eklenen harcama bilgisayara geçer', () async {
    final p = await paired();
    p.telHost.edit((d) => addSpend(d, 'tel1', 120, 'akbank-vadesiz'));
    await p.tel.run('kayit');
    expect(p.tel.status, SyncStatus.ok);
    expect(p.tel.st!['seq'], 2);
    await p.pc.run('yoklama');
    final d = p.pcHost.data!;
    expect((d['spends'] as List).any((s) => (s as Map)['id'] == 'tel1'), isTrue);
    expect(toK(acc(d, 'akbank-vadesiz')['balance']), toK(18400) - toK(120));
    expect(p.pcHost.notices, contains(SyncNotice.peerChanges));
    expect(p.pc.peerAt, isNotNull);
  });

  test('iki tarafta aynı anda değişiklik: ikisi de kalır, bakiye iki kez düşer', () async {
    final p = await paired();
    p.pcHost.edit((d) => addSpend(d, 'pc1', 85, 'akbank-vadesiz'));
    p.telHost.edit((d) => addSpend(d, 'tel1', 300, 'akbank-vadesiz'));
    await p.tel.run('kayit');
    await p.pc.run('kayit');
    await p.tel.run('yoklama');
    for (final d in [p.pcHost.data!, p.telHost.data!]) {
      final ids = [for (final s in d['spends'] as List) (s as Map)['id']];
      expect(ids, containsAll(<String>['pc1', 'tel1']));
      expect(toK(acc(d, 'akbank-vadesiz')['balance']), toK(18400) - toK(85) - toK(300));
    }
    expect(canon(p.pcHost.data), canon(p.telHost.data));
  });

  test('arada başka cihaz yazdıysa (409) yeniden birleştirir', () async {
    final p = await paired();
    p.pcHost.edit((d) => addSpend(d, 'pc1', 50, 'papara'));
    p.telHost.edit((d) => addSpend(d, 'tel1', 70, 'papara'));
    // Bilgisayar okuduktan sonra, yazmadan hemen önce telefon yazar.
    p.pcApi.beforePut = () async {
      p.pcApi.beforePut = null;
      await p.tel.run('kayit');
    };
    await p.pc.run('kayit');
    expect(p.pc.status, SyncStatus.ok);
    await p.tel.run('yoklama');
    for (final d in [p.pcHost.data!, p.telHost.data!]) {
      expect(toK(acc(d, 'papara')['balance']), toK(820) - toK(50) - toK(70));
    }
    expect(canon(p.pcHost.data), canon(p.telHost.data));
  });

  test('yanıtı kaybolan gönderim iki kez sayılmaz', () async {
    final p = await paired();
    p.pcHost.edit((d) => addSpend(d, 'pc1', 100, 'elde-nakit'));
    p.pcApi.dropNextPutResponse = true;
    await p.pc.run('kayit');
    expect(p.pc.status, SyncStatus.offline);
    expect(p.pc.st!['pending'], isNotNull);
    await p.pc.run('tekrar');
    expect(p.pc.status, SyncStatus.ok);
    expect(p.pc.st!['pending'], isNull);
    expect(toK(acc(p.pcHost.data!, 'elde-nakit')['balance']), toK(1250) - toK(100));
    await p.tel.run('yoklama');
    expect(toK(acc(p.telHost.data!, 'elde-nakit')['balance']), toK(1250) - toK(100));
  });

  test('silme her iki tarafta da geçerli olur', () async {
    final p = await paired();
    p.telHost.edit((d) => (d['subscriptions'] as List).removeWhere((s) => (s as Map)['id'] == 'netflix'));
    await p.tel.run('kayit');
    await p.pc.run('yoklama');
    expect((p.pcHost.data!['subscriptions'] as List).any((s) => (s as Map)['id'] == 'netflix'), isFalse);
  });

  test('internet yoksa çevrimdışı; gelince eşitlenir', () async {
    final p = await paired();
    p.telHost.edit((d) => addSpend(d, 'tel1', 10, 'papara'));
    p.telApi.offline = true;
    await p.tel.run('kayit');
    expect(p.tel.status, SyncStatus.offline);
    p.telApi.offline = false;
    await p.tel.run('tekrar');
    expect(p.tel.status, SyncStatus.ok);
    expect(p.tel.st!['seq'], 2);
  });

  test('açık panel varken gelen değişiklik bekletilir', () async {
    final p = await paired();
    p.telHost.edit((d) => addSpend(d, 'tel1', 10, 'papara'));
    await p.tel.run('kayit');
    p.pcHost.uiBusy = true;
    final before = canon(p.pcHost.data);
    await p.pc.run('yoklama');
    expect(p.pc.status, SyncStatus.wait);
    expect(canon(p.pcHost.data), before);
    p.pcHost.uiBusy = false;
    await p.pc.run('pencere');
    expect(p.pc.status, SyncStatus.ok);
    expect((p.pcHost.data!['spends'] as List).any((s) => (s as Map)['id'] == 'tel1'), isTrue);
  });

  test('sunucudaki kopya silinirse bağlantı kaldırılmış sayılır', () async {
    final p = await paired();
    await p.pc.unpair();
    expect(p.pc.paired, isFalse);
    expect(p.pcHost.persisted, isNull);
    await p.tel.run('yoklama');
    expect(p.tel.status, SyncStatus.lost);
    expect(p.tel.lost, isTrue);
    expect(p.telHost.notices, contains(SyncNotice.lost));
    expect(p.telHost.persisted!['lost'], isTrue);
  });

  test('telefon ayrılınca sunucudaki kopya kalır', () async {
    final p = await paired();
    await p.tel.unpair(deleteRemote: false);
    expect(p.tel.paired, isFalse);
    await p.pc.run('yoklama');
    expect(p.pc.status, SyncStatus.ok);
  });

  test('eski bağlantı başka bir profille sürdürülürse hiçbir kayıt silinmez', () async {
    final server = MemorySyncServer();
    final api = MemorySyncApi(server);
    final legacy = await seed(api, sample());
    final host = FakeHost(emptyData().j);
    host.edit((d) => addSpend(d, 'yeni1', 5, 'elde-nakit'));
    final e = SyncEngine(api: api, host: host, phone: false);
    final union = !syncSameOrigin(legacy['base'], host.data!);
    expect(union, isTrue);
    await e.adopt(legacy, union: union);
    expect(e.st!['base'], isNull);
    await e.run('elle');
    expect(e.status, SyncStatus.ok);
    final d = host.data!;
    expect((d['spends'] as List).length, (sample()['spends'] as List).length + 1);
    expect((d['debts'] as List).length, (sample()['debts'] as List).length);
  });

  test('eski bağlantı aynı veriyle sürdürülünce kaldığı yerden devam eder', () async {
    final server = MemorySyncServer();
    final api = MemorySyncApi(server);
    final legacy = await seed(api, sample());
    final host = FakeHost(sample());
    host.edit((d) => addSpend(d, 'pc1', 40, 'papara'));
    final e = SyncEngine(api: api, host: host, phone: false);
    expect(syncSameOrigin(legacy['base'], host.data!), isTrue);
    await e.adopt(legacy, union: false);
    expect(e.st!['base'], isNotNull);
    await e.run('elle');
    expect(e.status, SyncStatus.ok);
    expect(e.st!['seq'], 2);
    expect(host.persisted!['adopted'], isNotNull);
  });

  group('uygulama ile', () {
    test('bilgisayar eski eşleştirmeyi sürdürür, telefon bağlanır, değişiklikler iki yöne geçer', () async {
      final server = MemorySyncServer();
      final pcApi = MemorySyncApi(server);
      final telApi = MemorySyncApi(server);
      final legacy = await seed(pcApi, sample());

      final pcStore = MemoryStore()..legacySync = legacy;
      final pc = AppState(store: pcStore, initialLocale: const Locale('tr'), syncApi: pcApi, phone: false);
      await pc.init();
      await pc.createLegacyProfile('Melih', sample());
      expect(pc.sync!.paired, isTrue);
      expect(pc.index.legacySyncUsed, isTrue);
      expect(pc.canAdoptLegacySync, isFalse);
      await pc.syncNow();
      expect(pc.sync!.status, SyncStatus.ok);

      final tel = AppState(store: MemoryStore(), initialLocale: const Locale('tr'), syncApi: telApi, phone: true);
      await tel.init();
      await tel.pairFromLink(kKey, kBilet);
      expect(tel.status, AppStatus.ready);
      expect(tel.sync!.paired, isTrue);
      expect(tel.data.spends.length, pc.data.spends.length);

      // Telefonda harcama: bilgisayara geçer.
      tel.update((d) => addSpend(d.j, 'tel1', 99, 'akbank-vadesiz'));
      await tel.syncNow();
      expect(tel.sync!.status, SyncStatus.ok);
      await pc.syncNow();
      expect(pc.data.spends.any((s) => s.id == 'tel1'), isTrue);
      expect(toK(pc.data.account('akbank-vadesiz')!.balance), toK(18400) - toK(99));
      // Kaydedilen veri de güncel.
      final saved = await pcStore.loadData(pc.profile!.id) as Map;
      expect((saved['spends'] as List).any((s) => (s as Map)['id'] == 'tel1'), isTrue);

      // Bilgisayarda silme: telefona geçer.
      pc.update((d) => d.j['subscriptions'] = [for (final s in d.j['subscriptions'] as List) if ((s as Map)['id'] != 'spotify') s]);
      await pc.syncNow();
      await tel.syncNow();
      expect(tel.data.subscriptions.any((s) => s.id == 'spotify'), isFalse);
      expect(canon(tel.data.j), canon(pc.data.j));

      pc.dispose();
      tel.dispose();
    });
  });
}
