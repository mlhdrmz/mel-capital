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
import 'theme.dart';
import 'tips.dart';

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
    final scaffold = Scaffold(
      backgroundColor: MC.bg,
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
          if (tip != null)
            Positioned(
              right: 24,
              bottom: 24,
              child: SafeArea(child: TipCard(key: ValueKey<String>('tip-$tip'), tab: st.tab)),
            ),
        ],
      ),
    );
    if (!tabs) return scaffold;
    // Web önizlemesi: ?panel=harcama
    final panel = st.preview.remove('panel');
    if (panel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (panel == 'harcama') openSpendSheet(context, prefill: {'name': 'Kahve', 'amount': 85, 'category': 'kafe'});
        if (panel == 'borc') openDebtSheet(context, debt: st.data.debts.isEmpty ? null : st.data.debts.last);
      });
    }
    return Focus(autofocus: true, onKeyEvent: (node, event) => _shortcut(context, st, event), child: scaffold);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 18, 6),
      child: Row(
        children: [
          const _Brand(),
          const SizedBox(width: 18),
          if (!tabs) const Spacer(),
          if (tabs) Expanded(
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
