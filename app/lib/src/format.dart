/// Tutar biçimi: Türkçede "52.400 TL", İngilizcede "52,400 TL".
String money(num value, {String lang = 'tr', bool hidden = false, int decimals = 0}) {
  if (hidden) return '•••• TL';
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0];
  final group = lang == 'tr' ? '.' : ',';
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(group);
    buffer.write(whole[i]);
  }
  var out = buffer.toString();
  if (decimals > 0 && parts.length > 1) {
    out += (lang == 'tr' ? ',' : '.') + parts[1];
  }
  return '${negative ? '−' : ''}$out TL';
}
