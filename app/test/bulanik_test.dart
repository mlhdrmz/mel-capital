// Bulanık kopya gerçekten hazırlanıyor mu? s71'de hazırlık kendini bekleyip hiç bitmiyordu
// (whenComplete işlevi haritadan çıkardığı Future'ı, yani kendisini döndürüyordu); kopya ancak
// sekmeye ikinci gelişte görünüyor, yazıların arkası bulanıklaşmıyordu. Bu test, hazırlık belirli
// bir sürede bitmezse kalır.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/src/bulanik.dart';

Future<Uint8List> _png(int w, int h, Color renk) async {
  final kayit = ui.PictureRecorder();
  Canvas(kayit).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = renk);
  final resim = await kayit.endRecording().toImage(w, h);
  final veri = await resim.toByteData(format: ui.ImageByteFormat.png);
  return veri!.buffer.asUint8List();
}

void main() {
  testWidgets('bulanık kopya ilk istekte hazırlanır ve gösterilir; başka fotoğrafa geçilir, ilkine dönülür', (tester) async {
    await tester.runAsync(() async {
      const sure = Duration(seconds: 30);
      final a = MemoryImage(await _png(64, 40, const Color(0xFF336699)));
      final b = MemoryImage(await _png(80, 30, const Color(0xFF996633)));
      await bulanikKopyaHazirla('deneme-a', a, ImageConfiguration.empty).timeout(sure);
      expect(kBulanikArka.value?.anahtar, 'deneme-a', reason: 'kopya ilk istekte hazır olmalı');
      expect(kBulanikArka.value!.kaynak, const Size(64, 40));
      expect(kBulanikArka.value!.resim.width, 320);
      await bulanikKopyaHazirla('deneme-b', b, ImageConfiguration.empty).timeout(sure);
      expect(kBulanikArka.value?.anahtar, 'deneme-b');
      await bulanikKopyaHazirla('deneme-a', a, ImageConfiguration.empty).timeout(sure);
      expect(kBulanikArka.value?.anahtar, 'deneme-a', reason: 'saklanan kopya yeniden gösterilir');
      // Önceden hazırlama (sekmelerin fotoğrafları) da biter ve gösterileni değiştirmez
      final c = MemoryImage(await _png(50, 50, const Color(0xFF225522)));
      await bulanikKopyaOnceden('deneme-c', c, ImageConfiguration.empty).timeout(sure);
      expect(kBulanikArka.value?.anahtar, 'deneme-a');
    });
  });
}
