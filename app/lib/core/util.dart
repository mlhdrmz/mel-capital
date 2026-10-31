// Mel Capital — temel yardımcılar: para (kuruş), tarih (ay/gün metinleri), kimlik ve metin işlemleri.
//
// Veri dosyasındaki tutarlar TL cinsinden ondalıklı sayıdır; hesaplar kuruş cinsinden tam sayıyla
// yapılır (toK / fromK). Aylar "YYYY-AA", günler "YYYY-AA-GG" metinleridir.

import 'dart:math' as math;

// ---------------------------------------------------------------- Para

/// TL → kuruş (tam sayı). Geçersiz değer 0 sayılır.
int toK(Object? tl) {
  double? n;
  if (tl is num) {
    n = tl.toDouble();
  } else if (tl is String) {
    n = double.tryParse(tl);
  }
  if (n == null || n.isNaN || n.isInfinite) return 0;
  return (n * 100).round();
}

/// Kuruş → TL.
double fromK(int k) => k / 100;

/// 1234567 kuruş → "12.345,67" (tr) / "12,345.67" (en). Küsuratsızsa kuruş yazılmaz.
String fmtNum(int k, {String lang = 'tr'}) {
  final negative = k < 0;
  final a = k.abs();
  final whole = a ~/ 100;
  final frac = a % 100;
  final group = lang == 'tr' ? '.' : ',';
  final dec = lang == 'tr' ? ',' : '.';
  final digits = whole.toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(group);
    b.write(digits[i]);
  }
  if (frac != 0) b.write('$dec${frac.toString().padLeft(2, '0')}');
  return '${negative ? '−' : ''}$b';
}

/// Kuruş → "12.345 TL". Gizliyse "•••".
String fmtMoney(int k, {String lang = 'tr', bool hidden = false}) =>
    hidden ? '•••' : '${fmtNum(k, lang: lang)} TL';

/// Yüzde: 0.684 → "%68,4" (tr) / "68.4%" (en).
String fmtPct(double x, {String lang = 'tr'}) {
  final v = (x * 1000).round() / 10;
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  return lang == 'tr' ? '%${s.replaceAll('.', ',')}' : '$s%';
}

final RegExp _amountChars = RegExp(r'^[\d.,]+$');
final RegExp _digits = RegExp(r'^\d*$');

/// "12.500,50", "12500.50", "12.500", "1.234.567,8", "2500" → kuruş. Geçersizse null.
int? parseAmount(String? input) {
  var s = (input ?? '').trim().replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp('tl|₺', caseSensitive: false), '');
  if (s.isEmpty || !_amountChars.hasMatch(s)) return null;
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  var intPart = s;
  var frac = '';
  if (lastDot >= 0 && lastComma >= 0) {
    final decIdx = math.max(lastDot, lastComma);
    final decChar = s[decIdx];
    final thouChar = decChar == ',' ? '.' : ',';
    intPart = s.substring(0, decIdx);
    frac = s.substring(decIdx + 1);
    if (intPart.contains(decChar)) return null;
    intPart = intPart.split(thouChar).join();
  } else if (lastComma >= 0) {
    final parts = s.split(',');
    if (parts.length > 2) {
      intPart = parts.join();
    } else {
      intPart = parts[0];
      frac = parts[1];
    }
  } else if (lastDot >= 0) {
    final parts = s.split('.');
    if (parts.length > 2) {
      intPart = parts.join();
    } else if (parts[1].length == 3 && parts[0].isNotEmpty) {
      intPart = parts.join();
    } else {
      intPart = parts[0];
      frac = parts[1];
    }
  }
  if (!_digits.hasMatch(intPart) || !_digits.hasMatch(frac)) return null;
  if (intPart.isEmpty && frac.isEmpty) return null;
  if (intPart.length > 13) return null;
  var k = int.parse(intPart.isEmpty ? '0' : intPart) * 100;
  if (frac.isNotEmpty) {
    final f = '${frac}000'.substring(0, 3);
    k += int.parse(f.substring(0, 2));
    if (int.parse(f[2]) >= 5) k += 1;
  }
  return k;
}

/// Eksi işaretli tutar: "-250" → −25000. Boşsa 0.
int? parseSigned(String? input) {
  var raw = (input ?? '').trim();
  var negative = false;
  if (raw.startsWith('-') || raw.startsWith('−')) {
    negative = true;
    raw = raw.substring(1).trim();
  }
  if (raw.isEmpty) return 0;
  final k = parseAmount(raw);
  return k == null ? null : (negative ? -k : k);
}

/// Bir listedeki değerlerin toplamı.
int sumK<T>(Iterable<T> items, int Function(T) f) {
  var total = 0;
  for (final x in items) {
    total += f(x);
  }
  return total;
}

// ---------------------------------------------------------------- Tarih

/// Testlerde "bugün"ü sabitlemek için.
DateTime Function() clock = DateTime.now;

String two(int n) => n.toString().padLeft(2, '0');

String currentMonth() {
  final d = clock();
  return '${d.year}-${two(d.month)}';
}

String todayISO() {
  final d = clock();
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Dosya adları için: "2026-10-31_2359".
String stamp() {
  final d = clock();
  return '${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}

String nowISO() => clock().toUtc().toIso8601String();

final RegExp _monthRe = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');
final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isMonth(Object? s) => s is String && _monthRe.hasMatch(s);

bool isDate(Object? s) {
  if (s is! String || !_dateRe.hasMatch(s)) return false;
  final y = int.parse(s.substring(0, 4));
  final m = int.parse(s.substring(5, 7));
  final d = int.parse(s.substring(8, 10));
  if (m < 1 || m > 12 || d < 1) return false;
  final dt = DateTime.utc(y, m, d);
  return dt.year == y && dt.month == m && dt.day == d;
}

bool isISO(Object? s) => s is String && DateTime.tryParse(s) != null;

int mIdx(String m) => int.parse(m.substring(0, 4)) * 12 + int.parse(m.substring(5, 7)) - 1;

String mFromIdx(int i) {
  final y = (i / 12).floor();
  final mo = i - y * 12 + 1;
  return '$y-${two(mo)}';
}

String addM(String m, int n) => mFromIdx(mIdx(m) + n);

/// a'dan b'ye kaç ay (b - a).
int mDiff(String a, String b) => mIdx(b) - mIdx(a);

String maxMonth(String a, String b) => a.compareTo(b) > 0 ? a : b;
String minMonth(String a, String b) => a.compareTo(b) < 0 ? a : b;

List<String> monthsBetween(String a, String b) => [
      for (var i = mIdx(a); i <= mIdx(b); i++) mFromIdx(i),
    ];

String monthOf(String date) => date.substring(0, 7);
int dayOf(String date) => int.parse(date.substring(8, 10));

String addDays(String date, int n) {
  final y = int.parse(date.substring(0, 4));
  final m = int.parse(date.substring(5, 7));
  final d = int.parse(date.substring(8, 10));
  final t = DateTime.utc(y, m, d + n);
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Ayın kaç gün çektiği.
int daysInMonth(String m) {
  final y = int.parse(m.substring(0, 4));
  final mo = int.parse(m.substring(5, 7));
  return DateTime.utc(y, mo + 1, 0).day;
}

/// 0 = Pazar … 6 = Cumartesi (JavaScript'teki gibi).
int weekdayIndex(String date) {
  final y = int.parse(date.substring(0, 4));
  final m = int.parse(date.substring(5, 7));
  final d = int.parse(date.substring(8, 10));
  return DateTime.utc(y, m, d).weekday % 7;
}

/// İki gün arasındaki fark (b - a), gün cinsinden.
int dayDiff(String a, String b) {
  DateTime p(String s) =>
      DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));
  return p(b).difference(p(a)).inDays;
}

// ---------------------------------------------------------------- Metin ve kimlik

final math.Random _random = math.Random.secure();

/// Rastgele kimlik: "od-lw3k9x2ab".
String rid([String prefix = 'k']) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final time = clock().millisecondsSinceEpoch.toRadixString(36);
  final tail = List.generate(5, (_) => chars[_random.nextInt(chars.length)]).join();
  return '$prefix-$time$tail';
}

/// Türkçe küçük harf: I → ı, İ → i.
String trLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Türkçe büyük harf: i → İ, ı → I.
String trUpper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

const Map<String, String> _plain = {
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u',
  'é': 'e', 'è': 'e', 'á': 'a', 'à': 'a', 'ó': 'o', 'ò': 'o', 'í': 'i', 'ì': 'i', 'ú': 'u', 'ù': 'u',
  'ä': 'a', 'ë': 'e', 'ï': 'i', 'ñ': 'n',
};

String _plainLetters(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (r == 0x0307) continue; // birleşik nokta (İ'nin küçük hali)
    b.write(_plain[ch] ?? ch);
  }
  return b.toString();
}

/// Kimlik için sade metin: "Doğalgaz Faturası" → "dogalgaz-faturasi".
String slugify(String? s) {
  final plain = _plainLetters(trLower(s ?? ''));
  final slug = plain.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.length > 40 ? slug.substring(0, 40) : slug;
}

/// Arama ve eşleştirme için: küçük harf, Türkçe harfler sade, tek boşluk.
String normTxt(String? s) =>
    _plainLetters(trLower(s ?? '')).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Okunur, benzersiz kimlik: "doğalgaz" → "dogalgaz", varsa "dogalgaz-2".
String uniqueId(String base, Iterable<String> existing) {
  final set = existing.toSet();
  final b = slugify(base).isEmpty ? 'kayit' : slugify(base);
  if (!set.contains(b)) return b;
  var i = 2;
  while (set.contains('$b-$i')) {
    i++;
  }
  return '$b-$i';
}

/// Marka eşleştirmesi için küçük harf ("LinkedIn" → "linkedin", ı yerine i).
String brandKey(String? name) => trLower(name ?? '').replaceAll('ı', 'i');

/// Kaynak alanı: "acc:<hesap>" | "card:<kredi kartı borcu>" | null.
String? srcAcc(Object? s) => s is String && s.startsWith('acc:') ? s.substring(4) : null;
String? srcCard(Object? s) => s is String && s.startsWith('card:') ? s.substring(5) : null;

/// Türkçe iyelik eki: "1'i", "13'ü", "16'sı", "20'si".
String dayPoss(int n) {
  final last = n % 10;
  final tens = n % 100;
  if (last == 0) {
    return n.toString() + (const {10: "'u", 20: "'si", 30: "'u"}[tens] ?? "'ı");
  }
  return n.toString() + const ['', "'i", "'si", "'ü", "'ü", "'i", "'sı", "'si", "'i", "'u"][last];
}

/// Güvenli bağlantı: yalnızca http/https.
String safeUrl(String? u) {
  final uri = Uri.tryParse((u ?? '').trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return '';
  return uri.toString();
}

/// Derin kopya (yalnızca JSON türleri).
dynamic deepCopy(dynamic v) {
  if (v is Map) return {for (final e in v.entries) e.key.toString(): deepCopy(e.value)};
  if (v is List) return [for (final x in v) deepCopy(x)];
  return v;
}
