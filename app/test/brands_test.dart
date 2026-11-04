// Abonelik, fatura ve harcama logoları eski Mel Capital'deki gibi seçilmeli. Örnek adların beklenen
// sonuçları eski uygulamanın kendi kodu (app1.js brandOf/brandHTML) çalıştırılarak üretildi
// (test/fixtures/marka.json, yalnızca uydurma adlar).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/brands.dart';
import 'package:mel_capital/src/logos.dart';

String hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  final cases = ((jsonDecode(File('test/fixtures/marka.json').readAsStringSync()) as Map)['cases'] as List).cast<Map<String, dynamic>>();

  group('logo seçimi eski uygulamayla aynı', () {
    for (final c in cases) {
      final name = c['name'] as String;
      test('"$name"', () {
        expect(brandOf(name) != null, c['brand'], reason: 'bilinen marka mı');
        final look = brandLook(name);
        switch (c['kind']) {
          case 'svg':
            expect(look, isA<BrandSvg>());
            final l = look as BrandSvg;
            expect(l.key, c['key']);
            expect(hex(l.bg), (c['bg'] as String).toLowerCase());
            expect(hex(l.fg), (c['fg'] as String).toLowerCase());
          case 'txt':
            expect(look, isA<BrandText>());
            final l = look as BrandText;
            expect(l.text, c['t']);
            expect(hex(l.bg), (c['bg'] as String).toLowerCase());
            expect(hex(l.ink), (c['ink'] as String) == '#fff' ? '#ffffff' : c['ink']);
          case 'gen':
            expect(look, isA<BrandGeneric>());
            final l = look as BrandGeneric;
            expect(l.icon, c['icon']);
            expect(hex(l.color), (c['color'] as String).isEmpty ? '#e3bf7c' : c['color']);
          default:
            expect(look, isA<BrandInitials>());
            final l = look as BrandInitials;
            expect(l.text, c['t']);
            expect(hex(l.bg), c['bg']);
        }
      });
    }
  });

  test('kurallardaki her simge tanımlı', () {
    for (final r in kBrandRules) {
      if (r.icon != null) expect(kBrandIcons.containsKey(r.icon), isTrue, reason: r.icon);
      if (r.icon == null) expect(r.text, isNotEmpty, reason: r.pattern);
    }
    for (final r in kGenericRules) {
      expect(kLineIcons.containsKey(r.icon), isTrue, reason: r.icon);
    }
  });

  test('bütün simge yolları çözülür ve 24×24 alana sığar', () {
    void check(String name, String data) {
      // Sınırlar eğrilerin denetim noktalarını da içerir: biraz pay bırakılır.
      final b = svgPath(data).getBounds();
      expect(b.left, greaterThan(-1), reason: name);
      expect(b.top, greaterThan(-1), reason: name);
      expect(b.right, lessThan(25), reason: name);
      expect(b.bottom, lessThan(25), reason: name);
      expect(math.max(b.width, b.height), greaterThan(10), reason: name);
    }

    for (final e in kBrandIcons.entries) {
      check(e.key, e.value.$2);
    }
    for (final e in kLineIcons.entries) {
      check(e.key, e.value);
    }
  });

  test('logosu olmayan alacaklının kısaltması eski uygulamadaki gibi', () {
    expect(bankMono('kyk', 'Kredi Yurtlar'), 'KYK');
    expect(bankMono(null, 'Ahmet abi'), 'AHM');
    expect(bankMono(null, 'iş yeri'), 'İŞY');
    expect(bankMono(null, '…'), '?');
    expect(bankMono(null, null), '?');
  });

  testWidgets('logolar çizilir', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (final c in cases) BrandMark(c['name'] as String, size: 30),
            const BrandMark('Spotify', size: 22, round: true),
            for (final k in kBankLogoAspect.keys) BankPlate(bankKey: k, size: 28),
            const BankPlate(bankKey: 'kyk', size: 28),
            const BankPlate(name: 'Ahmet', size: 22),
            const BankPlate(icon: Icons.payments_outlined, size: 34),
            for (final id in kShopLogoAspect.keys) shopLogo(id, maxWidth: 140, maxHeight: 40)!,
          ]),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(BrandMark), findsNWidgets(cases.length + 1));
    expect(find.text('KYK'), findsOneWidget);
    expect(find.text('AHM'), findsOneWidget);
    // Bankası bilinen plakalarda kısaltma yok, logo var
    expect(find.text('GAR'), findsNothing);
    expect(find.byType(Image), findsNWidgets(kBankLogoAspect.length + kShopLogoAspect.length));
  });
}
