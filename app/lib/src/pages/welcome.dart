import 'package:flutter/material.dart';

import '../../core/model.dart';
import '../../core/normalize.dart';
import '../../core/sample.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

/// İlk açılış: profil adı ve nasıl başlanacağı.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, this.addingProfile = false, this.onCancel});

  /// Ayarlar'dan yeni profil eklenirken.
  final bool addingProfile;
  final VoidCallback? onCancel;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _name = TextEditingController();
  Json? _legacy;
  bool _checked = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final st = AppScope.of(context);
    st.store.readLegacyData().then((raw) {
      if (!mounted || raw == null) return;
      final n = normalizeData(raw);
      if (n.ok) setState(() => _legacy = n.data!.j);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start(Future<Json?> Function() data) async {
    if (_busy) return;
    setState(() => _busy = true);
    final st = AppScope.of(context);
    try {
      await st.createProfile(_name.text, data: await data());
      if (widget.addingProfile) widget.onCancel?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final legacy = _legacy == null ? null : Data(_legacy!);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Reveal(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.addingProfile ? s.pick('YENİ PROFİL', 'NEW PROFILE') : s.pick('HOŞ GELDİN', 'WELCOME'),
                            style: sans(11.5, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.6, shadows: kPhotoTextShadow),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.addingProfile ? s.pick('Yeni bir profil aç', 'Open a new profile') : 'Mel Capital',
                            style: serif(52, shadows: kPhotoTextShadow),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.pick(
                              'Hesaplarındaki para, kartların, borçların ve harcamaların tek yerde. Verilerin yalnızca bu bilgisayarda durur.',
                              'Your accounts, cards, debts and spending in one place. Your data stays on this computer.',
                            ),
                            style: sans(15, color: MC.muted, shadows: kPhotoTextShadow),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.addingProfile) ...[
                      const SizedBox(width: 16),
                      _LangToggle(lang: s.lang, onChanged: st.setLanguage),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 26),
              GlassPanel(
                radius: 26,
                cut: 26,
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.pick('Adın', 'Your name'), style: sans(13, weight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _name,
                      style: sans(16),
                      decoration: InputDecoration(
                        hintText: s.pick('Profilin adı (ör. Melih)', 'Profile name (e.g. Alex)'),
                        hintStyle: sans(15, color: MC.dim),
                        filled: true,
                        fillColor: const Color(0x33000000),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x33FFFFFF))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x33FFFFFF))),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.pick('Aynı bilgisayarda birden fazla profil açabilirsin; uygulama her açılışta son kullandığın profille açılır.',
                          'You can keep several profiles on one computer; the app opens with the one you used last.'),
                      style: sans(12, color: MC.dim),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(s.pick('Nasıl başlamak istersin?', 'How would you like to start?'), style: serif(28, shadows: kPhotoTextShadow)),
              const SizedBox(height: 12),
              if (legacy != null) ...[
                _Choice(
                  icon: Icons.drive_file_move_outline,
                  title: s.pick('Eski Mel Capital verilerimi getir', 'Bring my old Mel Capital data'),
                  text: s.pick(
                    'Bu bilgisayardaki eski Mel Capital verisi bulundu: ${legacy.accounts.length} hesap, ${legacy.debts.length} borç, ${legacy.spends.length} harcama. Kopyası alınır; eski dosyaya dokunulmaz.',
                    'Your old Mel Capital data was found: ${legacy.accounts.length} accounts, ${legacy.debts.length} debts, ${legacy.spends.length} spends. A copy is taken; the old file is left untouched.',
                  ),
                  highlight: true,
                  onTap: _busy ? null : () => _start(() async => _legacy),
                ),
                const SizedBox(height: 10),
              ],
              _Choice(
                icon: Icons.add_circle_outline,
                title: s.pick('Sıfırdan başla', 'Start from scratch'),
                text: s.pick('Boş bir profil açılır; hesaplarını, kartlarını ve borçlarını sonra eklersin.',
                    'An empty profile opens; you add your accounts, cards and debts afterwards.'),
                highlight: legacy == null,
                onTap: _busy ? null : () => _start(() async => null),
              ),
              const SizedBox(height: 10),
              _Choice(
                icon: Icons.visibility_outlined,
                title: s.pick('Örnek verilerle göz at', 'Look around with sample data'),
                text: s.pick('Uydurma bir profil açılır; her sayfanın nasıl göründüğünü görürsün. İstediğinde silersin.',
                    'A made-up profile opens so you can see every page. Delete it whenever you like.'),
                onTap: _busy ? null : () => _start(loadSampleJson),
              ),
              if (widget.addingProfile) ...[
                const SizedBox(height: 18),
                GlassButton(label: s.pick('Vazgeç', 'Cancel'), icon: Icons.arrow_back, onTap: widget.onCancel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.text, required this.onTap, this.highlight = false});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: GlassPanel(
          tint: highlight ? MC.gold : null,
          radius: 22,
          cut: 22,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              Icon(icon, size: 28, color: MC.gold),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: sans(16, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(text, style: sans(13, color: MC.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: MC.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.lang, required this.onChanged});

  final String lang;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String code, String label) => TextButton(
          onPressed: () => onChanged(code),
          style: TextButton.styleFrom(
            foregroundColor: lang == code ? MC.ink : MC.text,
            backgroundColor: lang == code ? MC.gold : const Color(0x33000000),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(label),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [pill('tr', 'Türkçe'), const SizedBox(width: 6), pill('en', 'English')]);
  }
}
