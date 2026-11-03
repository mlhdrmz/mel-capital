// Yedek dosyası: Mel Capital'in (eski ya da yeni) .json yedeğinden profil açmak için.

import 'dart:convert';

import 'model.dart';
import 'normalize.dart';

/// Yedek dosyasının içeriğini okur ve denetler: (veri, hata).
/// Eski uygulamanın yedekleri, yeni uygulamanın yedekleri ve veri dosyası aynı biçimdedir.
(Json?, String?) readBackupText(String text, String lang) {
  String pick(String tr, String en) => lang == 'tr' ? tr : en;
  Object? raw;
  try {
    raw = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
  } catch (_) {
    return (null, pick('Dosya okunamadı: JSON biçiminde değil.', 'The file could not be read: it is not JSON.'));
  }
  // Bazı dışa aktarımlar veriyi {"data": {...}} içinde tutar.
  if (raw is Map && raw['data'] is Map && raw['debts'] == null && raw['accounts'] == null) raw = raw['data'];
  if (raw is! Map || (raw['debts'] == null && raw['accounts'] == null && raw['spends'] == null)) {
    return (null, pick('Bu dosyada Mel Capital verisi yok.', 'This file holds no Mel Capital data.'));
  }
  final n = normalizeData(raw);
  if (!n.ok) return (null, n.errors.take(3).join(' · '));
  return (n.data!.j, null);
}
