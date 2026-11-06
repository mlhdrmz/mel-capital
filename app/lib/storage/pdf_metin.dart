// PDF ekstrenin yazısını okur (cihazın içinde, internetsiz). Bilgisayarda ve telefonda PDFium
// (pdfrx) kullanılır; web önizlemesinde PDF okunmaz.

import 'dart:typed_data';

import 'pdf_metin_stub.dart' if (dart.library.io) 'pdf_metin_io.dart' as platform;

/// PDF şifreliyse sorulan şifre (vazgeçilirse null).
typedef PdfSifreSor = Future<String?> Function();

/// PDF'in sayfalarındaki satırlar. PDF açılamazsa [PdfOkunamadi] fırlatır.
typedef PdfSatirOkuyucu = Future<List<List<String>>> Function(Uint8List bytes, {PdfSifreSor? sifreSor});

class PdfOkunamadi implements Exception {
  const PdfOkunamadi(this.neden, {this.sifre = false});
  final String neden;

  /// Şifre gerekiyordu ama girilmedi ya da yanlıştı.
  final bool sifre;

  @override
  String toString() => neden;
}

/// Testlerde değiştirilebilir.
PdfSatirOkuyucu pdfSatirlariOku = platform.pdfSatirlari;
