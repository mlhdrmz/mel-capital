// Örnek veri: "Örnek verilerle göz at" profili ve web önizlemesi için.
//
// assets/sample/ornek.json Ekim 2026'ya göre yazılmıştır; yüklenirken bütün tarihler bugünün
// ayına kaydırılır, böylece örnek her zaman "bu ay" gibi görünür.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'model.dart';
import 'util.dart';

const String kSampleBaseMonth = '2026-10';

final RegExp _monthRe = RegExp(r'^\d{4}-\d{2}$');
final RegExp _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _isoRe = RegExp(r'^(\d{4}-\d{2}-\d{2})(T.*)$');
final RegExp _refRe = RegExp(r'^(.*\|)(\d{4}-\d{2})$');

String _shiftDate(String d, int n) {
  final mo = addM(d.substring(0, 7), n);
  final day = math.min(int.parse(d.substring(8, 10)), daysInMonth(mo));
  return '$mo-${two(day)}';
}

String _shiftStr(String s, int n) {
  if (_monthRe.hasMatch(s) && isMonth(s)) return addM(s, n);
  if (_dateRe.hasMatch(s) && isDate(s)) return _shiftDate(s, n);
  final iso = _isoRe.firstMatch(s);
  if (iso != null && isDate(iso.group(1))) return _shiftDate(iso.group(1)!, n) + iso.group(2)!;
  final ref = _refRe.firstMatch(s);
  if (ref != null && isMonth(ref.group(2))) return ref.group(1)! + addM(ref.group(2)!, n);
  return s;
}

dynamic _walk(dynamic v, int n) {
  if (v is Map) return <String, dynamic>{for (final e in v.entries) _shiftStr(e.key.toString(), n): _walk(e.value, n)};
  if (v is List) return [for (final x in v) _walk(x, n)];
  if (v is String) return _shiftStr(v, n);
  return v;
}

/// Bütün ay ve gün metinlerini n ay kaydırır.
Json shiftDates(Json raw, int months) => months == 0 ? deepCopy(raw) as Json : _walk(raw, months) as Json;

/// Örnek veriyi bugünün ayına kaydırılmış olarak yükler.
Future<Json> loadSampleJson() async {
  // loadString büyük dosyaları ayrı bir iş parçacığında çözer; burada doğrudan çözülür.
  final bytes = await rootBundle.load('assets/sample/ornek.json');
  final text = utf8.decode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final raw = jsonDecode(text) as Json;
  return shiftDates(raw, mDiff(kSampleBaseMonth, currentMonth()));
}
