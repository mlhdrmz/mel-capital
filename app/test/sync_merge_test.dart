// Eşitlemenin birleştirme kuralları ve veri biçimi eski Mel Capital'le (JS) birebir aynı olmalı:
// telefondaki eski uygulama ile bu uygulama aynı sunucu kopyasını paylaşır. Örnek dosyalar eski
// uygulamanın kendi kodu çalıştırılarak üretildi (test/fixtures/sync, yalnızca uydurma veri).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/sync/engine.dart';
import 'package:mel_capital/core/sync/merge.dart';
import 'package:mel_capital/core/sync/stamp.dart';
import 'package:mel_capital/core/util.dart';

Object? fixture(String name) {
  final f = File('test/fixtures/sync/$name');
  final bytes = f.readAsBytesSync();
  return jsonDecode(utf8.decode(name.endsWith('.gz') ? gzip.decode(bytes) : bytes));
}

/// İki verinin nerede ayrıldığını kısaca söyler (test raporunda neyin farklı olduğu görünsün).
String diffHint(Object? a, Object? b) {
  if (a is! Map || b is! Map) return 'dart: ${canon(a)}\njs:   ${canon(b)}';
  final out = <String>[];
  for (final k in {...a.keys, ...b.keys}) {
    final x = a.containsKey(k) ? a[k] : absent;
    final y = b.containsKey(k) ? b[k] : absent;
    if (canon(x) == canon(y)) continue;
    if (x is List && y is List && kSyncColls.containsKey(k)) {
      final key = kSyncColls[k]!;
      final xm = {for (final r in x) if (r is Map) '${r[key]}': r};
      final ym = {for (final r in y) if (r is Map) '${r[key]}': r};
      for (final id in {...xm.keys, ...ym.keys}) {
        if (canon(xm[id]) != canon(ym[id])) out.add('$k[$id]\n  dart: ${canon(xm[id])}\n  js:   ${canon(ym[id])}');
        if (out.length > 6) break;
      }
      if (canon(xm.keys.toList()) != canon(ym.keys.toList())) out.add('$k sırası: dart ${xm.keys.toList()} · js ${ym.keys.toList()}');
    } else {
      out.add('$k\n  dart: ${canon(x)}\n  js:   ${canon(y)}');
    }
    if (out.length > 8) break;
  }
  return out.join('\n');
}

void main() {
  setUp(() => clock = () => DateTime.utc(2026, 10, 25, 12));
  tearDown(() => clock = DateTime.now);

  group('normalize eski uygulamayla aynı', () {
    final cases = (fixture('normalize.json') as Map)['cases'] as List;
    for (final c in cases.cast<Map>()) {
      test('${c['name']}', () {
        final n = normalizeData(deepCopy(c['input']));
        expect(n.ok, isTrue, reason: n.errors.join('\n'));
        final dart = n.data!.j;
        expect(canon(dart), canon(c['output']), reason: diffHint(dart, c['output']));
      });
      test('${c['name']}: eski uygulamanın çıktısı değişmeden kalır', () {
        final n = normalizeData(deepCopy(c['output']));
        expect(n.ok, isTrue, reason: n.errors.join('\n'));
        expect(canon(n.data!.j), canon(c['output']), reason: diffHint(n.data!.j, c['output']));
      });
    }
  });

  group('birleştirme eski uygulamayla aynı', () {
    final f = fixture('birlestirme.json.gz') as Map;
    for (final c in (f['cases'] as List).cast<Map>()) {
      test('${c['name']}', () {
        final base = c['base'] == 'N' ? deepCopy(f['base']) : deepCopy(c['base']);
        final l = deepCopy(c['local']) as Map;
        final r = deepCopy(c['remote']) as Map;
        if (c['error'] != null) {
          expect(() => syncMerge(base, l, r), throwsA(isA<MergeError>()));
          return;
        }
        final m = syncMerge(base, l, r).j;
        expect(canon(m), canon(c['merged']), reason: diffHint(m, c['merged']));
        // Girdiler değiştirilmez.
        expect(canon(l), canon(c['local']));
        expect(canon(r), canon(c['remote']));
      });
    }
  });

  group('karşılaştırma metni (canon)', () {
    test('anahtar sırası ve tam sayılar', () {
      expect(canon({'b': 1, 'a': [1, 2.0, 'x', null]}), '{"a":[1,2,"x",null],"b":1}');
      expect(canon({'a': 1.5, 'b': true}), canon({'b': true, 'a': 1.5}));
      expect(canon({'a': 'çğ"\\\n'}), '{"a":"çğ\\"\\\\\\n"}');
      expect(canon(absent), '~');
    });
    test('kaydın özeti değişiklik zamanını saymaz', () {
      expect(rsig({'id': 'a', 'x': 1, 'updatedAt': '2026-01-01'}), rsig({'x': 1, 'id': 'a'}));
      expect(rsig({'id': 'a', 'x': 1}) == rsig({'id': 'a', 'x': 2}), isFalse);
    });
  });

  group('değişiklik zamanı', () {
    Json sample() => deepCopy((fixture('normalize.json') as Map)['cases'][0]['output']) as Json;

    test('yalnızca değişen ve yeni kayıtlara yazılır', () {
      final d = sample();
      final idx = indexData(d);
      final spends = d['spends'] as List;
      (spends.first as Map)['note'] = 'değişti';
      spends.add({'id': 'yeni', 'date': '2026-10-25', 'amount': 10, 'source': 'acc:elde-nakit'});
      const t = '2026-10-25T12:00:00.000Z';
      final next = stampChanges(d, idx, t);
      expect((spends.first as Map)['updatedAt'], t);
      expect((spends.last as Map)['updatedAt'], t);
      final others = [for (final s in spends.skip(1).take(spends.length - 2)) (s as Map)['updatedAt']];
      expect(others.contains(t), isFalse);
      // Yeni özet artık değişikliği içerir: aynı veri yeniden damgalanmaz.
      final again = stampChanges(d, next, '2026-10-26T00:00:00.000Z');
      expect((spends.first as Map)['updatedAt'], t);
      expect(canon(again), canon(next));
    });

    test('ilk kayıtta yalnızca özet çıkarılır', () {
      final d = sample();
      final before = canon(d);
      stampChanges(d, null, '2026-10-25T12:00:00.000Z');
      expect(canon(d), before);
    });
  });

  group('eski bağlantının kaynağı', () {
    Json sample() => deepCopy((fixture('normalize.json') as Map)['cases'][0]['output']) as Json;

    test('eski verinin kopyası: aynı kaynak', () {
      final base = sample();
      final local = sample();
      (local['spends'] as List).removeLast();
      (local['spends'] as List).add({'id': 'x1'});
      expect(syncSameOrigin(base, local), isTrue);
    });

    test('başka profil: aynı kaynak değil (ortak hâl kullanılmaz)', () {
      expect(syncSameOrigin(sample(), emptyData().j), isFalse);
      expect(syncSameOrigin(null, sample()), isFalse);
    });
  });
}
