import 'package:flutter/widgets.dart';

/// Arayüz metinleri (Türkçe ve İngilizce).
///
/// `S.of(context).t('anahtar')` o anki dildeki metni verir. Bir metin İngilizcede
/// yoksa Türkçesi, o da yoksa anahtarın kendisi gösterilir.
class S {
  const S(this.lang);

  final String lang;

  static S of(BuildContext context) =>
      S(Localizations.localeOf(context).languageCode == 'tr' ? 'tr' : 'en');

  bool get isTr => lang == 'tr';

  String t(String key) =>
      _strings[lang]?[key] ?? _strings['tr']?[key] ?? key;

  /// İki dilli kısa metin: `s.pick('Gelir', 'Income')`.
  String pick(String tr, String en) => isTr ? tr : en;

  String monthYear(DateTime d) =>
      '${(isTr ? _monthsTr : _monthsEn)[d.month - 1]} ${d.year}';

  String monthShort(DateTime d) =>
      (isTr ? _monthsShortTr : _monthsShortEn)[d.month - 1];
}

const List<String> _monthsTr = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const List<String> _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _monthsShortTr = [
  'OCA', 'ŞUB', 'MAR', 'NİS', 'MAY', 'HAZ',
  'TEM', 'AĞU', 'EYL', 'EKİ', 'KAS', 'ARA',
];
const List<String> _monthsShortEn = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const Map<String, Map<String, String>> _strings = {
  'tr': {
    'tab.ozet': 'Özet',
    'tab.harcamalar': 'Harcamalar',
    'tab.borclar': 'Borçlar',
    'tab.bankalar': 'Bankalar',
    'tab.plan': 'Plan',
    'tab.alisveris': 'Alışveriş',
    'tab.ayarlar': 'Ayarlar',
    'win.minimize': 'Küçült',
    'win.close': 'Kapat',
    'top.hide': 'Tutarları gizle',
    'top.show': 'Tutarları göster',
    'preview':
        'Önizleme: tasarım hazır. Gerçek verilerin 2. aşamada bu ekranlara gelecek; şimdilik örnek rakamlar görüyorsun.',
    'eyebrow.ozet': 'ÖZET',
    'title.ozet': 'Bugün elinde olan',
    'eyebrow.harcamalar': 'HARCAMALAR',
    'eyebrow.borclar': 'BORÇLAR',
    'title.borclar': 'Kartlar ve krediler',
    'eyebrow.bankalar': 'BANKALAR VE HESAPLAR',
    'title.bankalar': 'Bankalarım',
    'eyebrow.plan': 'PLAN',
    'eyebrow.alisveris': 'ALIŞVERİŞ',
    'title.alisveris': 'Alabilir miyim?',
    'eyebrow.ayarlar': 'AYARLAR',
    'title.ayarlar': 'Ayarlar',
    'settings.language': 'Dil',
    'settings.languageHelp': 'Arayüzün dili. İlk açılışta Windows\'un diline göre seçilir.',
    'settings.languageHelpPhone': 'Arayüzün dili. İlk açılışta telefonun diline göre seçilir.',
    'settings.hidden': 'Tutarları gizle',
    'settings.hiddenHelp': 'Rakamlar •••• olarak görünür; üst menüdeki göz simgesiyle de açıp kapatabilirsin.',
    'settings.about': 'Sürüm',
    'settings.aboutValue': '0.1 · Önizleme (1. aşama)',
  },
  'en': {
    'tab.ozet': 'Overview',
    'tab.harcamalar': 'Spending',
    'tab.borclar': 'Debts',
    'tab.bankalar': 'Banks',
    'tab.plan': 'Plan',
    'tab.alisveris': 'Shopping',
    'tab.ayarlar': 'Settings',
    'win.minimize': 'Minimize',
    'win.close': 'Close',
    'top.hide': 'Hide amounts',
    'top.show': 'Show amounts',
    'preview':
        'Preview: the design is in place. Your real data comes to these screens in phase 2; for now you see sample figures.',
    'eyebrow.ozet': 'OVERVIEW',
    'title.ozet': 'What you have today',
    'eyebrow.harcamalar': 'SPENDING',
    'eyebrow.borclar': 'DEBTS',
    'title.borclar': 'Cards and loans',
    'eyebrow.bankalar': 'BANKS AND ACCOUNTS',
    'title.bankalar': 'My banks',
    'eyebrow.plan': 'PLAN',
    'eyebrow.alisveris': 'SHOPPING',
    'title.alisveris': 'Can I afford it?',
    'eyebrow.ayarlar': 'SETTINGS',
    'title.ayarlar': 'Settings',
    'settings.language': 'Language',
    'settings.languageHelp': 'The interface language. On first launch it follows your Windows language.',
    'settings.languageHelpPhone': 'The interface language. On first launch it follows your phone\'s language.',
    'settings.hidden': 'Hide amounts',
    'settings.hiddenHelp': 'Figures show as ••••; you can also toggle this with the eye icon in the top bar.',
    'settings.about': 'Version',
    'settings.aboutValue': '0.1 · Preview (phase 1)',
  },
};
