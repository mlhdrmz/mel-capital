import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'i18n.dart';
import 'native_window.dart';
import 'pages.dart';
import 'pages/common.dart';
import 'pages/corrupt.dart';
import 'pages/intro.dart';
import 'pages/plan.dart' show UpcomingSheet;
import 'pages/setup.dart';
import 'pages/welcome.dart';
import 'sheet.dart';
import 'state.dart';
import 'sync_ui.dart';
import 'theme.dart';
import 'tips.dart';
import 'ui.dart' show isPhoneLayout, showToast;

const Map<AppTab, String> _covers = {
  AppTab.ozet: 'lobby',
  AppTab.harcamalar: 'courtyard',
  AppTab.borclar: 'mountain',
  AppTab.bankalar: 'villa',
  AppTab.plan: 'highrise',
  AppTab.alisveris: 'palm',
  AppTab.ayarlar: 'santorini',
};

const Map<AppTab, IconData> _icons = {
  AppTab.ozet: Icons.home_outlined,
  AppTab.harcamalar: Icons.receipt_long_outlined,
  AppTab.borclar: Icons.balance_outlined,
  AppTab.bankalar: Icons.account_balance_outlined,
  AppTab.plan: Icons.calendar_month_outlined,
  AppTab.alisveris: Icons.shopping_cart_outlined,
  AppTab.ayarlar: Icons.settings_outlined,
};

/// Ana iskelet: duruma göre (açılıyor, hoş geldin, veri okunamadı, hazır) fotoğraf, üst menü ve sayfa.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    var tabs = false;
    var cover = 'lobby';
    Widget body = const _Loading();
    final introCover = kIntroCovers[introIndex(st.introSlide)];
    switch (st.status) {
      case AppStatus.loading:
        break;
      case AppStatus.welcome:
        if (st.showIntro) {
          cover = introCover;
          body = const IntroPage();
        } else {
          cover = 'lobby';
          body = const StartPage();
        }
      case AppStatus.corrupt:
        cover = 'lock';
        body = const CorruptPage();
      case AppStatus.ready:
        final step = st.setupStep;
        if (st.showIntro) {
          cover = introCover;
          body = const IntroPage();
        } else if (st.addingProfile) {
          cover = 'lobby';
          body = StartPage(addingProfile: true, onCancel: () => st.setAddingProfile(false));
        } else if (step != null) {
          cover = kSetupCovers[step] ?? 'lobby';
          body = const SetupPage();
        } else {
          tabs = true;
          cover = _covers[st.tab] ?? 'lobby';
          // Sekme değişince yeni sayfa sıfırdan kurulur; paneller kendileri
          // buğulanarak belirir (sayfanın üstüne saydamlık konmaz).
          body = KeyedSubtree(
            key: ValueKey<String>('${st.profile?.id}/${st.tab.name}'),
            child: pageFor(st.tab),
          );
        }
    }
    // Sayfanın ipucu (ilk girişte bir kez)
    final tip = tabs ? st.tipFor(st.tab) : null;
    // Telefonda sekmeler alttaki menüde; "+" düğmesi harcama ekler.
    final phone = isPhoneLayout(context);
    final s = S.of(context);
    final scaffold = Scaffold(
      backgroundColor: MC.bg,
      extendBody: true,
      bottomNavigationBar: phone && tabs ? const _PhoneNav() : null,
      floatingActionButton: phone && tabs && st.tab != AppTab.ayarlar
          ? FloatingActionButton(
              key: const ValueKey<String>('phone-add'),
              tooltip: s.pick('Harcama ekle', 'Add spending'),
              backgroundColor: MC.gold,
              foregroundColor: MC.ink,
              shape: const SignatureBorder(cut: 14, radius: 18),
              onPressed: () => openSpendSheet(context),
              child: const Icon(Icons.add, size: 28),
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Background(cover: cover),
          SafeArea(
            child: Column(
              children: [
                TopBar(tabs: tabs),
                if (st.saveError != null) _SaveError(message: st.saveError!),
                Expanded(child: body),
              ],
            ),
          ),
          // Özet'te büyük rakam sağ altta olduğu için ipucu sağ üstte durur; telefonda alt menünün üstünde.
          if (tip != null)
            phone
                ? Positioned(
                    left: 12,
                    right: 12,
                    bottom: 96,
                    child: SafeArea(top: false, child: TipCard(key: ValueKey<String>('tip-$tip'), tab: st.tab)),
                  )
                : Positioned(
                    right: 24,
                    top: st.tab == AppTab.ozet ? 84 : null,
                    bottom: st.tab == AppTab.ozet ? null : 24,
                    child: SafeArea(child: TipCard(key: ValueKey<String>('tip-$tip'), tab: st.tab)),
                  ),
        ],
      ),
    );
    if (!tabs) return SyncToasts(child: scaffold);
    // Yeni sürüm haberi: her sürüm için bir kez kısa bir not (ayrıntısı ve kurulumu Ayarlar'da).
    if (st.updateNeedsNotice) {
      st.markUpdateNoticed();
      final messenger = ScaffoldMessenger.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showToast(
          messenger,
          st.lang,
          st.lang == 'tr'
              ? 'Mel Capital\'in yeni sürümü hazır. Ayarlar\'dan tek tıkla kurabilirsin.'
              : 'A new version of Mel Capital is ready. Install it from Settings in one click.',
          seconds: 8,
          actionLabel: st.lang == 'tr' ? 'Ayarlar' : 'Settings',
          action: () => st.setTab(AppTab.ayarlar),
        );
      });
    }
    // Web önizlemesi: ?panel=harcama
    final panel = st.preview.remove('panel');
    if (panel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (panel == 'harcama') openSpendSheet(context, prefill: {'name': 'Kahve', 'amount': 85, 'category': 'kafe'});
        if (panel == 'borc') openDebtSheet(context, debt: st.data.debts.isEmpty ? null : st.data.debts.last);
        if (panel == 'kod') showPairCodeSheet(context);
        if (panel == 'esle') openPhonePairing(context);
      });
    }
    return Focus(autofocus: true, onKeyEvent: (node, event) => _shortcut(context, st, event), child: SyncToasts(child: scaffold));
  }

  /// Klavye kısayolları: 1–7 sekmeler, N harcama, H hızlı giriş, T para aktar.
  /// Bir metin kutusuna yazılırken devreye girmez.
  KeyEventResult _shortcut(BuildContext context, AppState st, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isAltPressed || kb.isMetaPressed) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null && (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return KeyEventResult.ignored;
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
    ];
    final key = event.logicalKey;
    final i = digits.indexOf(key);
    if (i >= 0 && i < AppTab.values.length) {
      st.setTab(AppTab.values[i]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      openSpendSheet(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH) {
      openQuickSpendSheet(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      openTransferSheet(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: MC.gold),
      ),
    );
  }
}

class _SaveError extends StatelessWidget {
  const _SaveError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 4),
      child: GlassPanel(
        tint: MC.rose,
        animate: false,
        radius: 16,
        cut: 16,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: MC.rose, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.pick('Son değişiklik dosyaya yazılamadı; bir sonraki değişiklikte yeniden denenecek. ($message)',
                    'The last change could not be written to disk; it will be retried with the next change. ($message)'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arka plan fotoğrafı; sekme değişince yumuşakça geçer.
class Background extends StatelessWidget {
  const Background({super.key, required this.cover});

  final String cover;

  @override
  Widget build(BuildContext context) {
    final name = cover;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: Image.asset(
        'assets/images/cover_$name.webp',
        key: ValueKey<String>(name),
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.16),
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}

/// Üst menü: marka, sekmeler, tutarları gizle, pencere düğmeleri.
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.tabs = true});

  /// false: yalnızca marka ve pencere düğmeleri (ilk açılış, veri okunamadı).
  final bool tabs;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final phone = isPhoneLayout(context);
    return Padding(
      padding: phone ? const EdgeInsets.fromLTRB(16, 10, 12, 2) : const EdgeInsets.fromLTRB(24, 14, 18, 6),
      child: Row(
        children: [
          const _Brand(),
          const SizedBox(width: 18),
          if (!tabs || phone) const Spacer(),
          if (tabs && !phone) Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tab in AppTab.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _TabButton(
                          key: ValueKey<String>('tab-${tab.name}'),
                          icon: _icons[tab] ?? Icons.circle_outlined,
                          label: s.t('tab.${tab.name}'),
                          selected: st.tab == tab,
                          // Yeni sürüm varsa Ayarlar'ın yanında küçük bir nokta
                          dot: tab == AppTab.ayarlar && st.newVersion != null,
                          onTap: () => st.setTab(tab),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (tabs) ...[
            const SizedBox(width: 12),
            // Telefon eşitlemesi varsa durumu (dokununca hemen eşitler)
            if (st.sync?.paired == true) ...[const SyncButton(), const SizedBox(width: 8)],
            _Bell(count: st.hasData ? st.ctx.upcoming(7).length : 0),
            const SizedBox(width: 8),
            _SquareButton(
              icon: st.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              tooltip: s.t(st.hidden ? 'top.show' : 'top.hide'),
              onTap: st.toggleHidden,
            ),
          ],
          if (NativeWindow.available) ...[
            if (tabs)
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: const Color(0x33FFFFFF),
              ),
            _SquareButton(
              icon: Icons.remove,
              tooltip: s.t('win.minimize'),
              onTap: NativeWindow.minimize,
            ),
            const SizedBox(width: 8),
            _SquareButton(
              icon: Icons.close,
              tooltip: s.t('win.close'),
              onTap: NativeWindow.close,
              danger: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: const Color(0xE61B1712),
            shape: SignatureBorder(
              cut: 9,
              radius: 9,
              side: BorderSide(color: MC.gold.withValues(alpha: 0.7)),
            ),
          ),
          child: Text('MC', style: serif(15, color: MC.gold, weight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Text('Mel Capital', style: serif(23, shadows: kPhotoTextShadow)),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final button = _button();
    if (!dot) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 6,
          top: 5,
          child: IgnorePointer(
            child: Container(
              key: const ValueKey<String>('update-dot'),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: selected ? MC.ink : MC.gold,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x99000000), width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _button() {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: selected ? MC.ink : MC.text,
        backgroundColor: selected ? MC.gold : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: const StadiumBorder(),
        textStyle: TextStyle(
          fontFamily: MC.sans,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          shadows: selected ? null : kPhotoTextShadow,
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: MC.text,
        backgroundColor: const Color(0x2E000000),
        hoverColor: danger ? MC.danger : const Color(0x22FFFFFF),
        side: const BorderSide(color: Color(0x38FFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        fixedSize: const Size(40, 40),
      ),
    );
  }
}

/// Zil: 7 gün içindeki ödenmemiş ödemelerin sayısı (uyarı değil, yalnızca liste).
class _Bell extends StatelessWidget {
  const _Bell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Stack(clipBehavior: Clip.none, children: [
      _SquareButton(
        icon: count > 0 ? Icons.notifications_outlined : Icons.notifications_none,
        tooltip: s.pick('7 gün içindeki ödemeler', 'Payments in the next 7 days'),
        onTap: () => showEditSheet<void>(context, builder: (_) => const UpcomingSheet()),
      ),
      if (count > 0)
        Positioned(
          right: -3,
          top: -3,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(color: MC.gold, borderRadius: BorderRadius.circular(9)),
              child: Text('$count', textAlign: TextAlign.center, style: sans(11, weight: FontWeight.w700, color: MC.ink)),
            ),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Telefon: alt menü

/// Telefonda alttaki menü: dört ana sayfa ve "Diğer" (Bankalar, Alışveriş, Ayarlar).
class _PhoneNav extends StatelessWidget {
  const _PhoneNav();

  static const List<AppTab> main = [AppTab.ozet, AppTab.harcamalar, AppTab.plan, AppTab.borclar];
  static const List<AppTab> more = [AppTab.bankalar, AppTab.alisveris, AppTab.ayarlar];

  void _openMore(BuildContext context, AppState st) {
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF2171513),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(2)),
              ),
              for (final t in more)
                ListTile(
                  key: ValueKey<String>('tab-${t.name}'),
                  leading: Icon(_icons[t], color: st.tab == t ? MC.gold : MC.text),
                  title: Text(s.t('tab.${t.name}'), style: sans(15.5, weight: FontWeight.w600, color: st.tab == t ? MC.gold : MC.text)),
                  trailing: t == AppTab.ayarlar && st.newVersion != null
                      ? Text(s.pick('Yeni sürüm', 'New version'), style: sans(12.5, color: MC.gold, weight: FontWeight.w600))
                      : null,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    st.setTab(t);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    Widget item({required String key, required IconData icon, required String label, required bool selected, required VoidCallback onTap, bool dot = false}) {
      final color = selected ? MC.gold : MC.text;
      return Expanded(
        child: InkResponse(
          key: ValueKey<String>(key),
          onTap: onTap,
          radius: 34,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 9, 2, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 23, color: color),
                    if (dot)
                      Positioned(
                        right: -4,
                        top: -2,
                        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: MC.gold, shape: BoxShape.circle)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11, weight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xB8100D0B),
            border: Border(top: BorderSide(color: Color(0x26FFFFFF))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                for (final t in main)
                  item(key: 'tab-${t.name}', icon: _icons[t] ?? Icons.circle_outlined, label: s.t('tab.${t.name}'), selected: st.tab == t, onTap: () => st.setTab(t)),
                item(
                  key: 'tab-diger',
                  icon: Icons.more_horiz,
                  label: s.pick('Diğer', 'More'),
                  selected: more.contains(st.tab),
                  dot: st.newVersion != null,
                  onTap: () => _openMore(context, st),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
