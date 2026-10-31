import 'package:flutter/material.dart';

import 'glass.dart';
import 'i18n.dart';
import 'native_window.dart';
import 'pages.dart';
import 'state.dart';
import 'theme.dart';

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

/// Ana iskelet: sekmeye göre değişen fotoğraf, üst menü ve sayfa.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Scaffold(
      backgroundColor: MC.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Background(tab: st.tab),
          SafeArea(
            child: Column(
              children: [
                const TopBar(),
                Expanded(
                  // Sekme değişince yeni sayfa sıfırdan kurulur; paneller kendileri
                  // buğulanarak belirir (sayfanın üstüne saydamlık konmaz).
                  child: KeyedSubtree(
                    key: ValueKey<AppTab>(st.tab),
                    child: pageFor(st.tab),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Arka plan fotoğrafı; sekme değişince yumuşakça geçer.
class Background extends StatelessWidget {
  const Background({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final name = _covers[tab] ?? 'lobby';
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
  const TopBar({super.key});

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
          Expanded(
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
          const SizedBox(width: 12),
          _SquareButton(
            icon: st.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            tooltip: s.t(st.hidden ? 'top.show' : 'top.hide'),
            onTap: st.toggleHidden,
          ),
          if (NativeWindow.available) ...[
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
