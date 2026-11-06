// İlk açılış tanıtımı: üç kısa ekran (Mel Capital nedir, neler yapar, verilerin sende).
// Uygulama ilk kez açıldığında gösterilir; Ayarlar'dan yeniden izlenebilir.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

/// Tanıtım ekranlarının arka plan fotoğrafları.
const List<String> kIntroCovers = ['lobby', 'highrise', 'villa'];

/// Geçerli tanıtım ekranı sırası (0–2).
int introIndex(int i) => i < 0 ? 0 : (i >= kIntroCovers.length ? kIntroCovers.length - 1 : i);

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  static const int count = 3;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final i = introIndex(st.introSlide);
    final last = i == count - 1;
    void next() => last ? st.finishIntro() : st.setIntroSlide(i + 1);
    void back() {
      if (i > 0) st.setIntroSlide(i - 1);
    }

    final slide = switch (i) {
      0 => const _WhatSlide(),
      1 => const _FeaturesSlide(),
      _ => const _PrivacySlide(),
    };
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowRight): next,
        const SingleActivator(LogicalKeyboardKey.enter): next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): back,
        const SingleActivator(LogicalKeyboardKey.escape): st.finishIntro,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 760;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(narrow ? 20 : 40, 10, narrow ? 20 : 40, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 38),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.pick('TANITIM · ${i + 1} / $count', 'INTRODUCTION · ${i + 1} / $count'),
                              style: sans(11.5, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.6, shadows: kPhotoTextShadow),
                            ),
                          ),
                          if (i == 0 && st.status != AppStatus.ready) ...[
                            LangToggle(lang: s.lang, onChanged: st.setLanguage),
                            const SizedBox(width: 12),
                          ],
                          if (!last)
                            TextButton(
                              key: const ValueKey<String>('intro-skip'),
                              onPressed: st.finishIntro,
                              style: TextButton.styleFrom(
                                foregroundColor: MC.text,
                                textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              child: Text(s.pick('Geç', 'Skip'), style: const TextStyle(shadows: kPhotoTextShadow)),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: narrow ? 28 : 48),
                    KeyedSubtree(key: ValueKey<int>(i), child: slide),
                    SizedBox(height: narrow ? 28 : 40),
                    Row(
                      children: [
                        _Dots(index: i, count: count, onTap: st.setIntroSlide),
                        const Spacer(),
                        if (i > 0) ...[
                          GlassButton(label: s.pick('Geri', 'Back'), icon: Icons.arrow_back, onTap: back),
                          const SizedBox(width: 10),
                        ],
                        GoldButton(
                          key: const ValueKey<String>('intro-next'),
                          label: last
                              ? (st.status == AppStatus.ready ? s.pick('Tamam', 'Done') : s.pick('Başlayalım', 'Let\'s start'))
                              : s.pick('İleri', 'Next'),
                          icon: last ? Icons.check : Icons.arrow_forward,
                          onTap: next,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Başlık bloğu: küçük üst yazı, büyük başlık, açıklama.
class _Head extends StatelessWidget {
  const _Head({required this.eyebrow, required this.title, required this.text});

  final String eyebrow;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Reveal(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eyebrow, style: sans(12, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.4, shadows: kPhotoTextShadow)),
            const SizedBox(height: 10),
            Text(title, style: serif(wide ? 74 : 52, shadows: kBigTextShadow, height: 1.0)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Text(text, style: sans(16.5, color: MC.muted, height: 1.5, shadows: kPhotoTextShadow)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 1. Mel Capital nedir

class _WhatSlide extends StatelessWidget {
  const _WhatSlide();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final questions = [
      s.pick('Bugün ne kadar param var?', 'How much money do I have today?'),
      s.pick('Bu ay neyi, ne zaman ödeyeceğim?', 'What do I pay this month, and when?'),
      s.pick('Borcum ne zaman biter?', 'When will my debt be paid off?'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Head(
          eyebrow: s.pick('MEL CAPITAL NEDİR?', 'WHAT IS MEL CAPITAL?'),
          title: s.pick('Paranın tamamı,\ntek bakışta.', 'All your money,\nat a glance.'),
          text: s.pick(
            'Banka hesaplarındaki parayı, kredi kartlarını, kredilerini ve harcamalarını bir arada tutan kişisel finans uygulaman. Rakamları sen girersin, hesabı Mel Capital yapar.',
            'Your personal finance app that keeps your bank accounts, credit cards, loans and spending together. You enter the figures; Mel Capital does the maths.',
          ),
        ),
        const SizedBox(height: 40),
        Reveal(
          delay: const Duration(milliseconds: 160),
          child: Wrap(
            spacing: 44,
            runSpacing: 22,
            children: [
              for (var n = 0; n < questions.length; n++)
                SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('0${n + 1}', style: serif(40, color: MC.gold, shadows: kPhotoTextShadow)),
                      const SizedBox(height: 4),
                      Container(width: 36, height: 1.5, color: MC.gold.withValues(alpha: 0.7)),
                      const SizedBox(height: 10),
                      Text(questions[n], style: sans(16, weight: FontWeight.w600, height: 1.4, shadows: kPhotoTextShadow)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          delay: const Duration(milliseconds: 260),
          child: Text(
            s.pick('Mel Capital bu üç sorunun cevabını her gün güncel tutar.', 'Mel Capital keeps the answers to these three questions up to date, every day.'),
            style: sans(13.5, color: MC.dim, shadows: kPhotoTextShadow),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 2. Neler yapar

class _Feature {
  const _Feature(this.icon, this.color, this.title, this.text);
  final IconData icon;
  final Color color;
  final String title;
  final String text;
}

class _FeaturesSlide extends StatelessWidget {
  const _FeaturesSlide();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      _Feature(Icons.home_outlined, MC.gold, s.pick('Özet', 'Overview'),
          s.pick('Bugün harcayabileceğin para: hesaplar ve kartlardaki boş limit.', 'What you can spend today: accounts plus available card limit.')),
      _Feature(Icons.receipt_long_outlined, MC.rose, s.pick('Harcamalar', 'Spending'),
          s.pick('Harcamalarını saniyeler içinde gir; abonelikler ayrı listede.', 'Log spending in seconds; subscriptions get their own list.')),
      _Feature(Icons.balance_outlined, MC.sky, s.pick('Borçlar', 'Debts'),
          s.pick('Kartlar, krediler, ekstreler ve Findeks notun bir arada.', 'Cards, loans, statements and your credit score together.')),
      _Feature(Icons.account_balance_outlined, MC.teal, s.pick('Bankalar', 'Banks'),
          s.pick('Her bankanın hesabı, kartı ve borcu kendi sayfasında.', 'Each bank\'s accounts, cards and debts on its own page.')),
      _Feature(Icons.calendar_month_outlined, MC.violet, 'Plan',
          s.pick('Ayın ödeme takvimi; ödediğini işaretle, ay sonunu gör.', 'This month\'s payment calendar; tick what you paid, see the month\'s end.')),
      _Feature(Icons.shopping_cart_outlined, MC.mint, s.pick('Alışveriş', 'Shopping'),
          s.pick('Alabilir miyim? Nakit, kart, taksit ve birikimle hesaplar.', 'Can I afford it? Works it out for cash, card, instalments and saving.')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Head(
          eyebrow: s.pick('NELER YAPAR?', 'WHAT DOES IT DO?'),
          title: s.pick('Her sayfa tek bir işi\niyi yapar.', 'Every page does\none job well.'),
          text: s.pick('Üstteki menüde yedi sayfa var; hangisinde ne olduğunu bir bakışta bilirsin.',
              'The top menu has seven pages; you always know what lives where.'),
        ),
        const SizedBox(height: 30),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1050 ? 3 : (c.maxWidth >= 620 ? 2 : 1);
            final w = (c.maxWidth - (cols - 1) * 14) / cols;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var n = 0; n < items.length; n++)
                  SizedBox(
                    width: w,
                    child: GlassPanel(
                      tint: items[n].color,
                      delay: Duration(milliseconds: 80 + n * 60),
                      radius: 20,
                      cut: 20,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(items[n].icon, color: items[n].color, size: 26),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(items[n].title, style: serif(24)),
                                const SizedBox(height: 4),
                                Text(items[n].text, style: sans(13, color: MC.muted, height: 1.4)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        Reveal(
          delay: const Duration(milliseconds: 500),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: MC.gold, borderRadius: BorderRadius.circular(20)),
                child: Text(s.pick('YAKINDA', 'COMING SOON'), style: sans(10.5, color: MC.ink, weight: FontWeight.w700, letterSpacing: 1.4, shadows: const [])),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.pick('Ekstre okuma: kart ve hesap ekstrelerini ver, harcamaların ve bakiyelerin kendiliğinden eklensin.',
                      'Statement reading: hand over your card and bank statements and your spending and balances fill in by themselves.'),
                  style: sans(14, weight: FontWeight.w600, shadows: kPhotoTextShadow),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 3. Verilerin sende

class _PrivacySlide extends StatelessWidget {
  const _PrivacySlide();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final phone = AppScope.of(context).phone;
    final points = [
      (
        Icons.lock_outline,
        s.pick('Hesap açman, şifre girmen gerekmez. Telefonla bilgisayar arasında eşitlerken veriler yolda şifrelenir; aradaki sunucu içeriği okuyamaz.',
            'No sign-up and no password. When your phone and computer sync, data is encrypted on the way; the server in between cannot read it.'),
      ),
      phone
          ? (Icons.smartphone_outlined, s.pick('Her şey bu telefonda durur; internet yokken de çalışır.', 'Everything lives on this phone and works offline too.'))
          : (Icons.folder_outlined, s.pick('Her şey Belgeler › Mel Capital klasöründe durur.', 'Everything lives in Documents › Mel Capital.')),
      (Icons.history, s.pick('Her gün otomatik yedek alınır; istediğin an elle de yedekleyebilirsin.', 'An automatic backup is taken every day, and you can back up by hand any time.')),
      (
        Icons.people_outline,
        phone
            ? s.pick('Aynı telefonda birden fazla profil açabilirsin; uygulama son kullandığınla açılır.', 'Keep several profiles on one phone; the app opens with the one you used last.')
            : s.pick('Aynı bilgisayarda birden fazla profil açabilirsin; uygulama son kullandığınla açılır.', 'Keep several profiles on one computer; the app opens with the one you used last.'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Head(
          eyebrow: s.pick('VERİLERİN SENDE', 'YOUR DATA STAYS WITH YOU'),
          title: phone ? s.pick('Verilerin yalnızca\nsende.', 'Your data stays\nwith you.') : s.pick('Verilerin yalnızca\nbu bilgisayarda.', 'Your data stays\non this computer.'),
          text: s.pick('Mel Capital internete bağlanmadan çalışır. Kimse senin rakamlarını görmez.',
              'Mel Capital works without going online. Nobody else sees your figures.'),
        ),
        const SizedBox(height: 30),
        for (var n = 0; n < points.length; n++)
          Reveal(
            delay: Duration(milliseconds: 120 + n * 70),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(points[n].$1, color: MC.gold, size: 24, shadows: kPhotoTextShadow),
                    const SizedBox(width: 16),
                    Expanded(child: Text(points[n].$2, style: sans(16, weight: FontWeight.w600, height: 1.45, shadows: kPhotoTextShadow))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ekran sırası noktaları.
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count, required this.onTap});

  final int index;
  final int count;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 0; n < count; n++)
          GestureDetector(
            onTap: () => onTap(n),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(right: 8),
                width: n == index ? 30 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: n == index ? MC.gold : const Color(0x66FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
