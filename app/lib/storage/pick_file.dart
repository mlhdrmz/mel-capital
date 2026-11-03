// Dosya seçme penceresi (Windows'ta sistemin "Aç" penceresi, web'de tarayıcınınki).

import 'package:file_selector/file_selector.dart';

/// Seçilen dosyanın adı ve metin içeriği.
class PickedText {
  const PickedText(this.name, this.text);
  final String name;
  final String text;
}

/// Kullanıcıya bir dosya seçtirir; vazgeçerse null.
typedef TextFilePicker = Future<PickedText?> Function({required String label, required List<String> extensions});

Future<PickedText?> _pickWithDialog({required String label, required List<String> extensions}) async {
  final file = await openFile(acceptedTypeGroups: <XTypeGroup>[XTypeGroup(label: label, extensions: extensions)]);
  if (file == null) return null;
  return PickedText(file.name, await file.readAsString());
}

/// Testlerde değiştirilebilir.
TextFilePicker pickTextFile = _pickWithDialog;
