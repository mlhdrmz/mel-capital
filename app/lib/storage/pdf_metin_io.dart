import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../motor/ekstre.dart' show PdfHarf, satirlariKur;
import 'pdf_metin.dart';

Future<List<List<String>>> pdfSatirlari(Uint8List bytes, {PdfSifreSor? sifreSor}) async {
  await pdfrxFlutterInitialize();
  PdfDocument doc;
  try {
    doc = await PdfDocument.openData(
      bytes,
      sourceName: 'ekstre-${DateTime.now().microsecondsSinceEpoch}',
      passwordProvider: sifreSor,
    );
  } on PdfPasswordException {
    throw const PdfOkunamadi('PDF şifreli; şifre girilmedi ya da yanlış.', sifre: true);
  } catch (e) {
    throw PdfOkunamadi('PDF açılamadı: $e');
  }
  try {
    final out = <List<String>>[];
    for (final page in doc.pages) {
      final t = await page.loadText();
      if (t == null) {
        out.add(const []);
        continue;
      }
      final harfler = <PdfHarf>[];
      final runes = t.fullText.runes.toList();
      final n = runes.length < t.charRects.length ? runes.length : t.charRects.length;
      for (var i = 0; i < n; i++) {
        final r = t.charRects[i];
        harfler.add(PdfHarf(String.fromCharCode(runes[i]), r.left, r.top, r.right, r.bottom));
      }
      out.add(satirlariKur(harfler));
    }
    return out;
  } finally {
    await doc.dispose();
  }
}
