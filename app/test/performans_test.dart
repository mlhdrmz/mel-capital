// Performans Motoru'nun bütçe denetimi: büyük veriyle (3 yıl, ~5.000 harcama, her ay abonelik
// ödemeleri ve aktarmalar) motorların ve sekme geçişlerinin süresi ile her sekmedeki pahalı çizim
// sayısı. Bütçeler lib/motor/performans.dart'ta ([PerfButce]); aşılırsa derleme durur. Süreler CI
// çıktısında "PERF" satırlarıyla görünür. Testler hata ayıklama modunda koşar; gerçek uygulama
// birkaç kat hızlıdır.
//
// Yeni bir özellik eklenince:
//   - yeni sekme ya da sekmeye yeni bölüm: aşağıdaki sekme döngüsü kendiliğinden denetler;
//   - yeni motor işlevi: "motorlar büyük veriyle hızlı" testine bir [olc] satırı ve [PerfButce.motorMs]'e
//     bütçesi eklenir.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';
import 'package:mel_capital/main.dart';
import 'package:mel_capital/motor/motorlar.dart';
import 'package:mel_capital/src/state.dart';
import 'package:mel_capital/storage/store_memory.dart';

/// Örnek veri + 36 ay boyunca ayda 140 harcama, her ay abonelik ödemeleri ve 6 aktarma (uydurma).
Data buyukVeri() {
  final raw = jsonDecode(File('assets/sample/ornek.json').readAsStringSync());
  final d = normalizeData(raw).data!;
  const kaynaklar = ['acc:akbank-vadesiz', 'acc:enpara-vadesiz', 'card:akbank-axess', 'card:enpara-kk', 'acc:elde-nakit', null];
  const kategoriler = ['market', 'yemek', 'kafe', 'ulasim', 'alisveris', 'eglence', 'saglik', 'giyim', 'teknoloji'];
  final spends = d.j['spends'] as List;
  final payments = d.j['payments'] as List;
  final transfers = d.j['transfers'] as List;
  var n = 0;
  for (var ay = 0; ay < 36; ay++) {
    final m = addM('2026-11', -ay);
    for (var i = 0; i < 140; i++) {
      n++;
      final src = kaynaklar[n % kaynaklar.length];
      final kart = src != null && src.startsWith('card:');
      spends.add(<String, dynamic>{
        'id': 'perf-$n',
        'date': '$m-${two(1 + i % 28)}',
        'name': 'Harcama ${n % 300}',
        'place': '',
        'category': kategoriler[n % kategoriler.length],
        'amount': 10 + (n * 37) % 900,
        'source': src,
        'installments': kart && n % 9 == 0 ? 3 : 1,
        'firstMonth': kart ? addM(m, 1) : null,
        'note': '',
        'url': '',
        'createdAt': '$m-01T10:00:00.000Z',
      });
    }
    for (final s in d.subscriptions) {
      if (ay == 0) continue;
      payments.add(<String, dynamic>{
        'id': 'perf-od-$m-${s.id}',
        'kind': 'sub',
        'refId': s.id,
        'month': m,
        'paidAmount': s.amount ?? 100,
        'paidDate': '$m-10',
        if (s.source != null && s.source!.startsWith('acc:')) 'fromAccount': s.source,
        'createdAt': '$m-10T10:00:00.000Z',
      });
    }
    for (var i = 0; i < 6; i++) {
      transfers.add(<String, dynamic>{
        'id': 'perf-tr-$m-$i',
        'date': '$m-${two(2 + i * 4)}',
        'from': i.isEven ? 'acc:akbank-vadesiz' : 'acc:enpara-vadesiz',
        'to': i.isEven ? 'acc:enpara-vadesiz' : 'acc:akbank-vadesiz',
        'amount': 250 + i * 10,
        'note': '',
      });
    }
  }
  return d;
}

/// [f]'yi bir kez ısıtıp [tekrar] kez çalıştırır; en kısa süreyi (ms) yazar ve bütçesiyle
/// ([PerfButce.motorMs]) karşılaştırır.
double olc(String ad, void Function() f, {int tekrar = 5}) {
  f();
  var enKisa = double.infinity;
  for (var i = 0; i < tekrar; i++) {
    final sw = Stopwatch()..start();
    f();
    sw.stop();
    final ms = sw.elapsedMicroseconds / 1000;
    if (ms < enKisa) enKisa = ms;
  }
  final butce = PerfButce.motorMs[ad];
  debugPrint('PERF $ad: ${enKisa.toStringAsFixed(1)} ms (bütçe ${butce?.toStringAsFixed(0) ?? '?'} ms)');
  expect(butce, isNotNull, reason: '"$ad" için PerfButce.motorMs\'e bütçe ekle');
  expect(enKisa, lessThan(butce!), reason: '"$ad" bütçesini aştı');
  return enKisa;
}

bool _bulanik(List<Shadow>? golgeler) => golgeler != null && golgeler.any((g) => g.blurRadius > 0);

/// Ekrandaki pahalı çizimler: her biri her karede ekran kartına ayrı bir bulanıklık işi çıkarır.
({int bulanikGolgeliYazi, int canliBulaniklik, int yolGolgesi}) pahaliCizimler(WidgetTester tester) {
  var yazi = 0;
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    var var_ = false;
    p.text.visitChildren((span) {
      if (_bulanik(span.style?.shadows)) var_ = true;
      return !var_;
    });
    if (var_) yazi++;
  }
  var canli = 0, yol = 0;
  for (final w in tester.allWidgets) {
    if (w is BackdropFilter || w is ImageFiltered) canli++;
    if (w is DecoratedBox) {
      final d = w.decoration;
      if (d is ShapeDecoration && _bulanik(d.shadows) && d.shape is! RoundedRectangleBorder && d.shape is! StadiumBorder && d.shape is! CircleBorder) yol++;
    }
  }
  return (bulanikGolgeliYazi: yazi, canliBulaniklik: canli, yolGolgesi: yol);
}

void main() {
  setUpAll(() => clock = () => DateTime(2026, 11, 20, 12));
  tearDownAll(() => clock = DateTime.now);

  test('motorlar büyük veriyle hızlı', () {
    final d = buyukVeri();
    debugPrint('PERF veri: ${d.spends.length} harcama, ${d.payments.length} ödeme, ${d.transfers.length} aktarma');
    olc('Ctx kurulumu (bütün motorlar)', () => Ctx(d));
    final ctx = Ctx(d);
    olc('Plan: 13 ayın kalemleri ve özetleri', () {
      final c = Ctx(d);
      for (var i = -1; i < 12; i++) {
        c.sum(addM(c.cur, i));
      }
    });
    olc('Yaklaşan ödemeler', () => Ctx(d).upcoming(7));
    olc('Hareketler listesi', () => movements(d, 'tr'));
    olc('Harcama arama', () => spendSearch(d, 'harcama 1', 'tr'));
    olc('Kategori öğrenme dizini', () => learnIndex(d));
    olc('Veri kopyası (her değişiklikte kayıt için)', () => deepCopy(d.j));
    olc('Veri JSON (dosyaya yazılan)', () => jsonEncode(d.j));
    olc('Borç kapatma hesabı (üç yön)', () {
      final b = kapatmaBorclari(ctx);
      kapatmaHesapla(b);
      kapatmaHesapla(b, aylikK: 1500000);
      kapatmaHesapla(b, topluK: 2000000, sira: KapatmaSirasi.kucuk);
      kapatmaIcinAylik(b, 24);
    });
    expect(ctx.model.liquid, isNonZero);
  });

  testWidgets('sekme geçişleri büyük veriyle: süre ve çizim bütçesi', (tester) async {
    tester.view.physicalSize = const Size(2400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final state = AppState(store: MemoryStore(), initialLocale: const Locale('tr'))..showTips = false;
    await state.createProfile('Deniz', data: buyukVeri().j);
    await tester.pumpWidget(MelCapitalApp(state: state));
    await tester.pumpAndSettle();
    for (final tab in [...AppTab.values, AppTab.ozet]) {
      final button = find.byKey(ValueKey<String>('tab-${tab.name}'));
      final sw = Stopwatch()..start();
      await tester.tap(button);
      await tester.pump();
      final ilkKare = sw.elapsedMicroseconds / 1000;
      await tester.pumpAndSettle();
      sw.stop();
      final toplam = sw.elapsedMicroseconds / 1000;
      final c = pahaliCizimler(tester);
      debugPrint('PERF sekme ${tab.name}: ilk kare ${ilkKare.toStringAsFixed(1)} ms, toplam ${toplam.toStringAsFixed(1)} ms · '
          'bulanık gölgeli yazı ${c.bulanikGolgeliYazi}, canlı bulanıklık ${c.canliBulaniklik}, yol gölgesi ${c.yolGolgesi}');
      expect(state.tab, tab);
      expect(tester.takeException(), isNull);
      expect(ilkKare, lessThan(PerfButce.sekmeIlkKareMs), reason: '${tab.name}: ilk kare bütçesi');
      expect(toplam, lessThan(PerfButce.sekmeToplamMs), reason: '${tab.name}: toplam süre bütçesi');
      // Çizim bütçesi: bunların her biri her karede ayrı bir bulanıklık işidir
      expect(c.bulanikGolgeliYazi, lessThanOrEqualTo(PerfButce.bulanikGolgeliYazi),
          reason: '${tab.name}: yazıya bulanık gölge (blurRadius > 0) konmaz; yazının arkası için HaleZemini/Hale kullan');
      expect(c.canliBulaniklik, lessThanOrEqualTo(PerfButce.canliBulaniklik), reason: '${tab.name}: BackdropFilter/ImageFiltered yerine BulanikZemin kullan');
      expect(c.yolGolgesi, lessThanOrEqualTo(PerfButce.yolGolgesi), reason: '${tab.name}: özel biçime bulanık gölge konmaz; gölgeyi yuvarlak dikdörtgenden ver');
    }
    // Bir değişiklik (ör. harcama eklemek): motorlar yeniden kurulur, sayfa yenilenir
    final sw = Stopwatch()..start();
    state.update((d) => toggleSubscription(d, d.subscriptions.first.id));
    await tester.pump();
    final degisiklik = sw.elapsedMicroseconds / 1000;
    debugPrint('PERF değişiklik + yenileme: ${degisiklik.toStringAsFixed(1)} ms');
    expect(degisiklik, lessThan(PerfButce.degisiklikMs));
  });
}
