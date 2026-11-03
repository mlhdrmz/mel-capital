// Mel Capital — sabit listeler: kategoriler, bankalar, türler, abonelik grupları.
// Her etiket iki dillidir: Lbl('Türkçe', 'English').

import 'package:flutter/painting.dart' show Color;

import 'util.dart';

/// İki dilli etiket.
class Lbl {
  const Lbl(this.tr, this.en);
  final String tr;
  final String en;
  String of(String lang) => lang == 'tr' ? tr : en;
}

class CategoryInfo {
  const CategoryInfo(this.label, this.color);
  final Lbl label;
  final Color color;
}

const Map<String, CategoryInfo> kCategories = {
  'market': CategoryInfo(Lbl('Market', 'Groceries'), Color(0xFF9FD7A5)),
  'yemek': CategoryInfo(Lbl('Yeme-içme', 'Dining'), Color(0xFFE0A36B)),
  'kafe': CategoryInfo(Lbl('Kafe', 'Café'), Color(0xFFC9A27A)),
  'ulasim': CategoryInfo(Lbl('Ulaşım', 'Transport'), Color(0xFF8FB3C9)),
  'alisveris': CategoryInfo(Lbl('Alışveriş', 'Shopping'), Color(0xFFD98A7A)),
  'fatura': CategoryInfo(Lbl('Fatura', 'Bills'), Color(0xFF7FC3B4)),
  'abonelik': CategoryInfo(Lbl('Abonelik', 'Subscriptions'), Color(0xFFE0A3B8)),
  'transfer': CategoryInfo(Lbl('Banka transferi', 'Bank transfer'), Color(0xFF8FB3C9)),
  'nakit': CategoryInfo(Lbl('Nakit çekim', 'Cash withdrawal'), Color(0xFF9FD7A5)),
  'kira': CategoryInfo(Lbl('Kira', 'Rent'), Color(0xFFB9A37A)),
  'eglence': CategoryInfo(Lbl('Eğlence', 'Entertainment'), Color(0xFFA99BD6)),
  'saglik': CategoryInfo(Lbl('Sağlık', 'Health'), Color(0xFFE07A8B)),
  'giyim': CategoryInfo(Lbl('Giyim', 'Clothing'), Color(0xFFE0A3B8)),
  'teknoloji': CategoryInfo(Lbl('Teknoloji', 'Technology'), Color(0xFF9AA4B5)),
  'kisisel': CategoryInfo(Lbl('Kişisel bakım', 'Personal care'), Color(0xFFD6B8E0)),
  'egitim': CategoryInfo(Lbl('Eğitim', 'Education'), Color(0xFFC9B27A)),
  'banka': CategoryInfo(Lbl('Banka ücreti', 'Bank fees'), Color(0xFF8A8178)),
  'kart_asgari': CategoryInfo(Lbl('Kart ödemesi', 'Card payment'), Color(0xFFD98A7A)),
  'diger': CategoryInfo(Lbl('Diğer', 'Other'), Color(0xFF766E64)),
};

String catLabel(String? c, String lang) {
  final info = kCategories[c];
  if (info != null) return info.label.of(lang);
  return (c == null || c.isEmpty) ? kCategories['diger']!.label.of(lang) : c;
}

Color catColor(String? c) {
  final info = kCategories[c];
  if (info != null) return info.color;
  var h = 0;
  for (final ch in (c ?? '').codeUnits) {
    h = (h * 31 + ch) & 0xFFFFFFFF;
  }
  const palette = [Color(0xFFC9B27A), Color(0xFF7FC3B4), Color(0xFFB9A37A), Color(0xFF9AA4B5), Color(0xFFE0A3B8)];
  return palette[h % 5];
}

/// Hızlı girişte kategori tahmini (sıra önemli).
final List<(String, RegExp)> _catWords = [
  ('kafe', RegExp(r'kahve|cafe|kafe|starbucks|espresso|latte|cappucc|çay\b|nescafe')),
  ('yemek', RegExp(r'yemek|döner|burger|pizza|lahmacun|restoran|lokanta|kebap|köfte|tost|simit|börek|dürüm|tatlı|pasta|yemeksepeti')),
  ('market', RegExp(r'market|migros|a101|bim\b|şok\b|carrefour|manav|bakkal|fırın|ekmek|kasap|süt|meyve')),
  ('ulasim', RegExp(r'taksi|uber|otobüs|metro|marmaray|akbil|istanbulkart|benzin|yakıt|mazot|otopark|dolmuş|bilet|köprü|hgs|ogs|vapur|tren')),
  ('saglik', RegExp(r'eczane|ilaç|doktor|hastane|diş|muayene|vitamin')),
  ('giyim', RegExp(r'giyim|tişört|gömlek|ayakkabı|mont|pantolon|kazak|çorap|zara|lcw|h&m|defacto')),
  ('eglence', RegExp(r'sinema|konser|oyun|steam|maç|bar\b|bira|tiyatro|bowling')),
  ('fatura', RegExp(r'fatura|elektrik|doğalgaz|su faturası|internet|aidat')),
  ('kisisel', RegExp(r'berber|kuaför|kozmetik|şampuan|parfüm|deodorant|tıraş')),
  ('teknoloji', RegExp(r'kulaklık|kılıf|şarj|kablo|bilgisayar|telefon|mouse|klavye|ssd')),
  ('egitim', RegExp(r'kitap|kurs|eğitim|kırtasiye|defter|kalem')),
  ('banka', RegExp(r'havale|eft|komisyon|kart aidat|masraf')),
];

String guessCategory(String? text) {
  final raw = text ?? '';
  final t = trLower(raw);
  final t2 = raw.replaceAll('İ', 'i').toLowerCase().replaceAll('̇', '');
  for (final (id, re) in _catWords) {
    if (re.hasMatch(t) || re.hasMatch(t2)) return id;
  }
  return 'diger';
}

class BankInfo {
  const BankInfo(this.name, this.c1, this.c2, {this.mono, this.wallet = false, this.notBank = false});
  final String name;
  final Color c1;
  final Color c2;
  final String? mono;
  final bool wallet;
  final bool notBank;
}

const Map<String, BankInfo> kBanks = {
  'akbank': BankInfo('Akbank', Color(0xFFE2322F), Color(0xFF7A0F12)),
  'denizbank': BankInfo('DenizBank', Color(0xFF0D5AA7), Color(0xFF06264A)),
  'enpara': BankInfo('Enpara', Color(0xFFA24D9E), Color(0xFF2C1235)),
  'fibabanka': BankInfo('Fibabanka', Color(0xFF1B6FD1), Color(0xFF0A2B55)),
  'garanti': BankInfo('Garanti BBVA', Color(0xFF1D8A52), Color(0xFF07301D)),
  'halkbank': BankInfo('Halkbank', Color(0xFF0A5BA8), Color(0xFF062A50)),
  'isbank': BankInfo('İş Bankası', Color(0xFF0A4EA2), Color(0xFF06224A)),
  'odeabank': BankInfo('Odeabank', Color(0xFF3A3A3A), Color(0xFF0A0A0A)),
  'qnb': BankInfo('QNB', Color(0xFF16406F), Color(0xFF06111F)),
  'teb': BankInfo('TEB', Color(0xFF13A06A), Color(0xFF063524)),
  'vakifbank': BankInfo('VakıfBank', Color(0xFFE9A91F), Color(0xFF5A3D05)),
  'yapikredi': BankInfo('Yapı Kredi', Color(0xFF24479A), Color(0xFF0B1738)),
  'ziraat': BankInfo('Ziraat Bankası', Color(0xFFD42A2A), Color(0xFF4A0808)),
  'papara': BankInfo('Papara', Color(0xFF222222), Color(0xFF0B0B0B), wallet: true),
  'kyk': BankInfo('KYK', Color(0xFF1F5D7A), Color(0xFF08202B), mono: 'KYK', notBank: true),
};

/// Ad içinden banka tahmini ("Axess" → akbank).
String? detectBank(String? name) {
  final s = slugify(name);
  if (s.isEmpty) return null;
  bool m(String p) => RegExp(p).hasMatch(s);
  if (m(r'qnb|finansbank|cardfinans')) return 'qnb';
  if (m(r'garanti')) return 'garanti';
  if (m(r'enpara')) return 'enpara';
  if (m(r'akbank|axess')) return 'akbank';
  if (m(r'yapi-?kredi')) return 'yapikredi';
  if (m(r'(^|-)teb($|-)|cepteteb')) return 'teb';
  if (m(r'odea')) return 'odeabank';
  if (m(r'ziraat|bankkart')) return 'ziraat';
  if (m(r'vakif')) return 'vakifbank';
  if (m(r'deniz')) return 'denizbank';
  if (m(r'fiba')) return 'fibabanka';
  if (m(r'halk|paraf')) return 'halkbank';
  if (m(r'(^|-)is-?banka|isbank|maximum|maxipara')) return 'isbank';
  if (m(r'papara')) return 'papara';
  if (m(r'(^|-)kyk($|-)|kredi-yurtlar')) return 'kyk';
  return null;
}

String bankName(String? key, String lang) {
  if (key != null && kBanks.containsKey(key)) return kBanks[key]!.name;
  if (key == null || key.isEmpty) return lang == 'tr' ? 'Diğer' : 'Other';
  return key;
}

const Map<String, Lbl> kDebtTypes = {
  'yapilandirma': Lbl('Yapılandırma', 'Restructured debt'),
  'kyk': Lbl('KYK kredisi', 'Student loan (KYK)'),
  'kredi_karti': Lbl('Kredi kartı', 'Credit card'),
  'kredi': Lbl('Kredi', 'Loan'),
  'diger': Lbl('Diğer', 'Other'),
};

const Map<String, Lbl> kAccountTypes = {
  'vadesiz': Lbl('Vadesiz hesap', 'Current account'),
  'nakit': Lbl('Elde nakit', 'Cash'),
  'on_odemeli': Lbl('Ön ödemeli kart hesabı', 'Prepaid card account'),
  'cuzdan': Lbl('Dijital cüzdan', 'Digital wallet'),
  'birikim': Lbl('Birikim hesabı', 'Savings account'),
  'diger': Lbl('Diğer', 'Other'),
};

const Map<String, Lbl> kCardKinds = {
  'banka': Lbl('Banka kartı', 'Debit card'),
  'kredi': Lbl('Kredi kartı', 'Credit card'),
  'on_odemeli': Lbl('Ön ödemeli kart', 'Prepaid card'),
};

const List<String> kPatterns = ['none', 'lines', 'waves', 'dots', 'rings', 'geo', 'glow', 'confetti'];
const List<String> kInks = ['light', 'dark', 'gold'];
const List<String> kNetworks = ['Mastercard', 'Visa', 'Troy', 'American Express'];

const Map<String, Lbl> kPriorities = {
  'yuksek': Lbl('Yüksek', 'High'),
  'orta': Lbl('Orta', 'Medium'),
  'dusuk': Lbl('Düşük', 'Low'),
};
const Map<String, int> kPriorityOrder = {'yuksek': 0, 'orta': 1, 'dusuk': 2};

const List<int> kInstallmentOptions = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 18, 24, 36];

class GroupInfo {
  const GroupInfo(this.label, this.color);
  final Lbl label;
  final Color color;
}

/// Plan sayfasındaki gruplar.
const Map<String, GroupInfo> kGroups = {
  'taksit': GroupInfo(Lbl('Borç taksitleri', 'Debt instalments'), Color(0xFFD9AE68)),
  'sabit': GroupInfo(Lbl('Faturalar ve sabit giderler', 'Bills and fixed costs'), Color(0xFF8FB3C9)),
  'abonelik': GroupInfo(Lbl('Abonelikler', 'Subscriptions'), Color(0xFFE0A3B8)),
  'kart': GroupInfo(Lbl('Kart ödemeleri', 'Card payments'), Color(0xFFD98A7A)),
  'harcama': GroupInfo(Lbl('Harcamalar', 'Spending'), Color(0xFFA99BD6)),
  'birikim': GroupInfo(Lbl('Birikim', 'Savings'), Color(0xFF9FD7A5)),
  'serbest': GroupInfo(Lbl('Serbest', 'Free'), Color(0x38ECE6DC)),
};
const List<String> kGroupOrder = ['taksit', 'sabit', 'abonelik', 'kart'];

const Map<String, Lbl> kSubGroups = {
  'fatura': Lbl('Ev faturaları', 'Home bills'),
  'video': Lbl('Dizi ve film', 'Series and film'),
  'muzik': Lbl('Müzik ve sesli kitap', 'Music and audiobooks'),
  'yz': Lbl('Yapay zekâ', 'AI'),
  'guvenlik': Lbl('VPN ve güvenlik', 'VPN and security'),
  'is': Lbl('İş ve verimlilik', 'Work and productivity'),
  'yemek': Lbl('Yemek ve market', 'Food and groceries'),
  'yayin': Lbl('Yayıncı ve topluluk', 'Creators and community'),
  'iletisim': Lbl('Telefon ve internet', 'Phone and internet'),
  'oyun': Lbl('Oyun', 'Gaming'),
  'bulut': Lbl('Bulut depolama', 'Cloud storage'),
  'spor': Lbl('Spor', 'Sports'),
  'diger': Lbl('Diğer', 'Other'),
};

/// Abonelik önerileri (genel katalog).
const List<(String, String)> kSubCatalog = [
  ('Mullvad VPN', 'guvenlik'), ('Proton VPN', 'guvenlik'), ('NordVPN', 'guvenlik'),
  ('Spotify Premium', 'muzik'), ('Apple Music', 'muzik'), ('Storytel', 'muzik'),
  ('YouTube Premium', 'video'), ('Netflix', 'video'), ('Amazon Prime', 'video'), ('Disney+', 'video'),
  ('HBO Max', 'video'), ('Exxen', 'video'), ('Apple TV+', 'video'), ('TOD', 'video'),
  ('YouTube kanal üyeliği (Katıl)', 'yayin'), ('Twitch abonelik', 'yayin'), ('Kick abonelik', 'yayin'),
  ('Discord Nitro', 'yayin'), ('Patreon', 'yayin'),
  ('Claude Pro', 'yz'), ('ChatGPT Plus', 'yz'), ('Gemini Pro', 'yz'),
  ('LinkedIn Premium', 'is'), ('Microsoft 365', 'is'), ('GitHub Copilot', 'is'), ('Duolingo Super', 'is'),
  ('iCloud+', 'bulut'), ('Google One', 'bulut'),
  ('Xbox Game Pass', 'oyun'), ('PlayStation Plus', 'oyun'),
  ('Yemeksepeti Pro', 'yemek'),
  ('Doğalgaz', 'fatura'), ('Elektrik', 'fatura'), ('Su', 'fatura'), ('İnternet', 'fatura'),
  ('Telefon', 'fatura'), ('Aidat', 'fatura'),
  ('Spor salonu', 'spor'),
];

/// Findeks notu bandı: (etiket, ton) — ton: ok | gold | warn | danger.
(Lbl, String) findeksBand(num? score) {
  if (score == null) return (const Lbl('belirtilmemiş', 'not set'), '');
  if (score >= 1700) return (const Lbl('Çok İyi', 'Very good'), 'ok');
  if (score >= 1500) return (const Lbl('İyi', 'Good'), 'ok');
  if (score >= 1100) return (const Lbl('Az Riskli', 'Low risk'), 'gold');
  if (score >= 700) return (const Lbl('Orta Riskli', 'Medium risk'), 'warn');
  if (score >= 1) return (const Lbl('En Riskli', 'Highest risk'), 'danger');
  return (const Lbl('belirtilmemiş', 'not set'), '');
}

/// Ekstresi girilmemiş aylarda kart asgari ödemesi tahmini (borcun %20'si).
const double kMinPayRate = 0.20;

class ShopInfo {
  const ShopInfo(this.id, this.name, this.url, this.hosts);
  final String id;
  final String name;
  final String url;
  final List<String> hosts;
}

const List<ShopInfo> kShops = [
  ShopInfo('trendyol', 'Trendyol', 'https://www.trendyol.com/', ['trendyol.com', 'ty.gl']),
  ShopInfo('hepsiburada', 'Hepsiburada', 'https://www.hepsiburada.com/', ['hepsiburada.com', 'hb.gl']),
  ShopInfo('amazon', 'Amazon', 'https://www.amazon.com.tr/', ['amazon.com.tr', 'amazon.com', 'amzn.eu', 'amzn.to']),
  ShopInfo('n11', 'n11', 'https://www.n11.com/', ['n11.com']),
  ShopInfo('pttavm', 'PttAVM', 'https://www.pttavm.com/', ['pttavm.com']),
  ShopInfo('idefix', 'idefix', 'https://www.idefix.com/', ['idefix.com']),
];

const List<String> kMonthsTr = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const List<String> kMonthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> kMonthsShortTr = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
const List<String> kMonthsShortEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> kMonthsLocTr = [
  "Ocak'ta", "Şubat'ta", "Mart'ta", "Nisan'da", "Mayıs'ta", "Haziran'da",
  "Temmuz'da", "Ağustos'ta", "Eylül'de", "Ekim'de", "Kasım'da", "Aralık'ta",
];
const List<String> kWeekdaysTr = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'];
const List<String> kWeekdaysEn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

String monthLabel(String? m, String lang) {
  if (!isMonth(m)) return lang == 'tr' ? 'belirtilmemiş' : 'not set';
  final mo = int.parse(m!.substring(5, 7));
  return '${(lang == 'tr' ? kMonthsTr : kMonthsEn)[mo - 1]} ${m.substring(0, 4)}';
}

String monthName(String? m, String lang) {
  if (!isMonth(m)) return '';
  return (lang == 'tr' ? kMonthsTr : kMonthsEn)[int.parse(m!.substring(5, 7)) - 1];
}

String monthShortLabel(String m, String lang) {
  final mo = int.parse(m.substring(5, 7));
  return '${(lang == 'tr' ? kMonthsShortTr : kMonthsShortEn)[mo - 1]} ${m.substring(2, 4)}';
}

String fmtDate(String? d, String lang) {
  if (!isDate(d)) return lang == 'tr' ? 'belirtilmemiş' : 'not set';
  final mo = int.parse(d!.substring(5, 7));
  final day = int.parse(d.substring(8, 10));
  return lang == 'tr'
      ? '$day ${kMonthsTr[mo - 1]} ${d.substring(0, 4)}'
      : '${kMonthsEn[mo - 1]} $day, ${d.substring(0, 4)}';
}

String fmtDayShort(String? d, String lang) {
  if (!isDate(d)) return '';
  final mo = int.parse(d!.substring(5, 7));
  final day = int.parse(d.substring(8, 10));
  return lang == 'tr' ? '$day ${kMonthsShortTr[mo - 1]}' : '${kMonthsShortEn[mo - 1]} $day';
}

String weekdayName(String? d, String lang) =>
    isDate(d) ? (lang == 'tr' ? kWeekdaysTr : kWeekdaysEn)[weekdayIndex(d!)] : '';

/// "ayın 13'ü" / "on the 13th".
String dayOfMonthText(int day, String lang) {
  if (lang == 'tr') return 'ayın ${dayPoss(day)}';
  final suffix = (day % 100 >= 11 && day % 100 <= 13)
      ? 'th'
      : const {1: 'st', 2: 'nd', 3: 'rd'}[day % 10] ?? 'th';
  return 'on the $day$suffix';
}

/// "5 Kasım" / "November 5" (gün ve ay; ay yoksa "belirtilmemiş").
String dayMonth(int? day, String? m, String lang) {
  if (day == null || !isMonth(m)) return lang == 'tr' ? 'belirtilmemiş' : 'not set';
  final name = monthName(m, lang);
  return lang == 'tr' ? '$day $name' : '$name $day';
}
