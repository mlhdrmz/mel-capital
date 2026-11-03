// Sayfa ipuçları: her sayfaya ilk girişte bir kez, sağ altta kısa bir ipucu kartı.
// Ayarlar › Dil ve görünüm › Sayfa ipuçları ile yeniden gösterilir.

import 'package:flutter/material.dart';

import '../core/constants.dart';
import 'glass.dart';
import 'i18n.dart';
import 'state.dart';
import 'theme.dart';

const Map<AppTab, Lbl> kTips = {
  AppTab.ozet: Lbl(
    'Burada bugün harcayabileceğin para var: hesaplarındaki para ve kartlarındaki boş limit. Rakamlara dokununca ilgili sayfa açılır; 1–7 tuşlarıyla sayfalar arasında geçebilirsin.',
    'This is what you can spend today: the money in your accounts plus available card limit. Tap a figure to open its page; keys 1–7 switch between pages.',
  ),
  AppTab.harcamalar: Lbl(
    'Harcama eklemek için + Harcama\'ya ya da N tuşuna bas. Hızlı girişle (H) tek seferde birçok satır yazabilirsin: "kahve 85", "market 420".',
    'Press + Spend or the N key to log spending. Quick entry (H) takes many lines at once: "coffee 85", "groceries 420".',
  ),
  AppTab.borclar: Lbl(
    'Kartların ve kredilerin burada. Kartın yanındaki Öde ile kart borcunu öde; ekstre gelince kâğıt simgesinden ekle. Findeks notunu da buradan takip edersin.',
    'Your cards and loans live here. Use Pay next to a card to pay it off; add the statement with the paper icon when it arrives. Your credit score is tracked here too.',
  ),
  AppTab.bankalar: Lbl(
    'Bir bankaya dokununca o bankadaki hesapların, kartların ve borçların tek sayfada açılır.',
    'Tap a bank to see its accounts, cards and debts on one page.',
  ),
  AppTab.plan: Lbl(
    'Ayın ödemeleri takvimde. Bir ödemeyi yaptığında satırdaki yuvarlağa dokun; ödendi olarak işaretlenir. Ay bitince Ayı kapat ile kapatırsın.',
    'This month\'s payments are on the calendar. When you pay something, tap the circle on its row to mark it paid. Close the month when it ends.',
  ),
  AppTab.alisveris: Lbl(
    'Almak istediğin ürünün linkini ve fiyatını yaz; nakit, kart, taksit ve biriktirme seçeneklerini hesaplar. Beğendiklerini istek listesine ekle.',
    'Type a product\'s link and price; it works out cash, card, instalment and saving options. Put the ones you like on your wish list.',
  ),
  AppTab.ayarlar: Lbl(
    'Profiller, yedekler ve dil burada. Kurulum sihirbazını ve bu ipuçlarını da buradan yeniden açabilirsin.',
    'Profiles, backups and language are here. You can reopen the setup wizard and these tips from here too.',
  ),
};

/// Sağ altta beliren ipucu kartı.
class TipCard extends StatelessWidget {
  const TipCard({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final text = kTips[tab]?.of(s.lang) ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: GlassPanel(
        tint: MC.gold,
        delay: const Duration(milliseconds: 450),
        darkness: 0.5,
        radius: 22,
        cut: 22,
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.lightbulb_outline, color: MC.gold, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.pick('İPUCU', 'TIP'), style: sans(11, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      Text(text, style: sans(13.5, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey<String>('tip-ok'),
                onPressed: st.dismissTip,
                style: TextButton.styleFrom(
                  foregroundColor: MC.gold,
                  textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                child: Text(s.pick('Anladım', 'Got it')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
