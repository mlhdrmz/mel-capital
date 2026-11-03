// Sürüm bilgisi derleme sırasında verilir:
//   flutter build windows --dart-define=MC_SURUM=03.11.2026-22.39 --dart-define=MC_DERLEME=145
// Geliştirme derlemelerinde ve testlerde ikisi de boştur (sürüm kontrolü yapılmaz).

import 'constants.dart';

/// Derlemenin tarih-saat etiketi (İstanbul saatiyle "GG.AA.YYYY-SS.DD").
const String kBuildLabel = String.fromEnvironment('MC_SURUM');

/// Derleme numarası: her derlemede artar; sürümler bununla karşılaştırılır.
const int kBuildNumber = int.fromEnvironment('MC_DERLEME');

final RegExp _labelRe = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})-(\d{2})\.(\d{2})');

/// Bir metindeki ilk sürüm etiketini bulur ("Mel Capital 05.11.2026-14.20" → "05.11.2026-14.20").
String? findBuildLabel(String? text) => text == null ? null : _labelRe.firstMatch(text)?.group(0);

/// "03.11.2026-22.39" → "3 Kasım 2026, 22.39" / "3 November 2026, 22:39".
/// Etiket tanınmazsa olduğu gibi döner.
String buildLabelText(String label, String lang) {
  final m = _labelRe.firstMatch(label);
  if (m == null) return label;
  final day = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return label;
  final months = lang == 'tr' ? kMonthsTr : kMonthsEn;
  final time = lang == 'tr' ? '${m.group(4)}.${m.group(5)}' : '${m.group(4)}:${m.group(5)}';
  return '$day ${months[month - 1]} ${m.group(3)}, $time';
}
