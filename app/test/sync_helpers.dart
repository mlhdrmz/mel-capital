// Eşitleme testlerinin ortak parçaları: örnek veri, sahte uygulama, eski bilgisayarın ilk kopyası.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/sync/engine.dart';
import 'package:mel_capital/core/sync/stamp.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/storage/sync_memory.dart';

/// Eski uygulamanın normalize ettiği örnek veri.
Json sample() {
  final f = jsonDecode(File('test/fixtures/sync/normalize.json').readAsStringSync()) as Map;
  return deepCopy(((f['cases'] as List).first as Map)['output']) as Json;
}

final String kKey = 'k${'Q' * 41}0';
final String kBilet = 'b${'Z' * 84}9';

class FakeHost implements SyncHost {
  FakeHost(this.data);

  Json? data;
  Json? persisted;
  bool uiBusy = false;
  DateTime? undo;
  int adopts = 0;
  final List<SyncNotice> notices = [];
  SyncIndex? idx;

  @override
  Json? get syncData => data;

  @override
  bool get syncUiBusy => uiBusy;

  @override
  DateTime? get syncUndoUntil => undo;

  @override
  Future<void> syncAdopt(Json merged, Json state) async {
    data = merged;
    idx = indexData(merged);
    adopts++;
    persisted = deepCopy(state) as Json;
  }

  @override
  Future<void> syncPersist(Json? state) async => persisted = state == null ? null : deepCopy(state) as Json;

  @override
  void syncChanged() {}

  @override
  void syncNotify(SyncNotice notice, {String? detail}) => notices.add(notice);

  /// Uygulamadaki gibi değişiklik: değişen kayıtlara zaman yazılır.
  void edit(void Function(Json d) change) {
    idx ??= indexData(data!);
    change(data!);
    idx = stampChanges(data!, idx, nowISO());
  }
}

Map<String, dynamic> acc(Json d, String id) => (d['accounts'] as List).cast<Map<String, dynamic>>().firstWhere((a) => a['id'] == id);

Json spend(String id, num amount, String source) => {
      'id': id,
      'date': '2026-10-25',
      'name': 'Harcama $id',
      'place': '',
      'category': 'diger',
      'amount': amount,
      'source': source,
      'installments': 1,
      'firstMonth': null,
      'note': '',
      'url': '',
      'goalId': null,
      'createdAt': nowISO(),
      'batch': null,
    };

void addSpend(Json d, String id, num amount, String accId) {
  (d['spends'] as List).add(spend(id, amount, 'acc:$accId'));
  final a = acc(d, accId);
  a['balance'] = fromK(toK(a['balance']) - toK(amount));
}

/// Eski bilgisayar uygulamasının yaptığı gibi: sunucuya ilk kopyayı yazar ve bilgisayarın
/// eşitleme durumunu döner.
Future<Json> seed(MemorySyncApi api, Json data) async {
  final keys = await api.derive(kKey);
  final dev = {'id': 'pc-eski', 'ad': 'Bilgisayar'};
  final hist = [
    {'s': 1, 'd': 'pc-eski'},
  ];
  final body = await api.seal(keys, {'v': 1, 'seq': 1, 'at': nowISO(), 'by': dev, 'hist': hist, 'data': data});
  final put = await api.request('PUT', keys, kBilet, create: true, body: body);
  expect(put.status, 200);
  return {
    'v': 1,
    'key': kKey,
    'bilet': kBilet,
    'dev': dev,
    'etag': (put.json as Map)['etag'],
    'seq': 1,
    'base': deepCopy(data),
    'hist': hist,
    'paired': nowISO(),
    'at': nowISO(),
    'peer': null,
  };
}

class Pair {
  Pair(this.server, this.pc, this.tel, this.pcApi, this.telApi, this.pcHost, this.telHost);
  final MemorySyncServer server;
  final SyncEngine pc;
  final SyncEngine tel;
  final MemorySyncApi pcApi;
  final MemorySyncApi telApi;
  final FakeHost pcHost;
  final FakeHost telHost;
}

/// Bilgisayar (eski eşleştirmeyle) ve ona bağlanmış telefon.
Future<Pair> paired() async {
  final server = MemorySyncServer();
  final pcApi = MemorySyncApi(server);
  final telApi = MemorySyncApi(server);
  final pcHost = FakeHost(sample());
  final pc = SyncEngine(api: pcApi, host: pcHost, phone: false);
  expect(await pc.load(await seed(pcApi, sample())), isTrue);
  final telHost = FakeHost(null);
  final tel = SyncEngine(api: telApi, host: telHost, phone: true);
  final remote = await tel.pair(kKey, kBilet, newSyncDevice(phone: true));
  telHost.data = normalizeData(remote).data!.j;
  return Pair(server, pc, tel, pcApi, telApi, pcHost, telHost);
}

