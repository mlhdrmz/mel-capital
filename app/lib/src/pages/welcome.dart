// Başlangıç: elinde veri var mı? Eski Mel Capital verisini getir, yedek dosyasından yükle,
// yeni profil kur (kurulum sihirbazı) ya da örnek verilerle göz at.

import 'package:flutter/material.dart';

import '../../core/backup_file.dart';
import '../../core/model.dart';
import '../../core/normalize.dart';
import '../../core/sample.dart';
import '../../storage/pick_file.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

class StartPage extends StatefulWidget {
  const StartPage({super.key, this.addingProfile = false, this.onCancel});

  /// Ayarlar'dan yeni profil eklenirken.
  final bool addingProfile;
  final VoidCallback? onCancel;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _name = TextEditingController();
  Json? _legacy;
  String? _legacyError;
  String? _fileError;
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
      setState(() {
        if (n.ok) {
          _legacy = n.data!.j;
        } else {
          _legacyError = n.errors.take(3).join(' · ');
        }
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _legacyError = e.toString());
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start(Future<Json?> Function() data, {bool setup = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final st = AppScope.of(context);
    try {
      await st.createProfile(_name.text, data: await data(), setup: setup);
      if (widget.addingProfile) widget.onCancel?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromFile() async {
    final s = S.of(context);
    setState(() => _fileError = null);
    PickedText? picked;
    try {
      picked = await pickTextFile(label: s.pick('Mel Capital yedeği', 'Mel Capital backup'), extensions: const ['json']);
    } catch (e) {
      if (mounted) setState(() => _fileError = s.pick('Dosya açılamadı: $e', 'The file could not be opened: $e'));
      return;
    }
    if (picked == null || !mounted) return;
    final file = picked;
    final (data, error) = readBackupText(file.text, s.lang);
    if (data == null) {
      setState(() => _fileError = '${file.name}: ${error ?? ''}');
      return;
    }
    await _start(() async => data);
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
                            widget.addingProfile ? s.pick('YENİ PROFİL', 'NEW PROFILE') : s.pick('BAŞLANGIÇ', 'GETTING STARTED'),
                            style: sans(11.5, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.6, shadows: kPhotoTextShadow),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.addingProfile ? s.pick('Yeni bir profil aç', 'Open a new profile') : s.pick('Nasıl başlayalım?', 'How shall we start?'),
                            style: serif(52, shadows: kPhotoTextShadow),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.pick('Önce adını yaz, sonra elinde Mel Capital verisi olup olmadığını seç.',
                                'Type your name, then tell us whether you already have Mel Capital data.'),
                            style: sans(15, color: MC.muted, shadows: kPhotoTextShadow),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.addingProfile) ...[
                      const SizedBox(width: 16),
                      LangToggle(lang: s.lang, onChanged: st.setLanguage),
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
                      key: const ValueKey<String>('start-name'),
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
              const SizedBox(height: 22),
              Text(s.pick('Elinde Mel Capital verisi var mı?', 'Do you already have Mel Capital data?'), style: serif(30, shadows: kPhotoTextShadow)),
              const SizedBox(height: 12),
              if (legacy != null) ...[
                _Choice(
                  key: const ValueKey<String>('start-legacy'),
                  icon: Icons.drive_file_move_outline,
                  title: s.pick('Evet, eski Mel Capital verilerimi getir', 'Yes, bring my old Mel Capital data'),
                  text: s.pick(
                    'Bu bilgisayardaki eski Mel Capital verisi bulundu: ${legacy.accounts.length} hesap, ${legacy.debts.length} borç, ${legacy.spends.length} harcama. Kopyası alınır; eski dosyaya dokunulmaz.',
                    'Your old Mel Capital data was found: ${legacy.accounts.length} accounts, ${legacy.debts.length} debts, ${legacy.spends.length} spends. A copy is taken; the old file is left untouched.',
                  ),
                  highlight: true,
                  onTap: _busy ? null : () => _start(() async => _legacy),
                ),
                const SizedBox(height: 10),
              ],
              if (legacy == null && _legacyError != null) ...[
                _Problem(
                  text: s.pick('Eski Mel Capital verisi bulundu ama okunamadı: $_legacyError. Eski dosyaya dokunulmadı.',
                      'Old Mel Capital data was found but could not be read: $_legacyError. The old file was not touched.'),
                ),
                const SizedBox(height: 10),
              ],
              _Choice(
                key: const ValueKey<String>('start-file'),
                icon: Icons.upload_file_outlined,
                title: s.pick('Evet, bir yedek dosyam var', 'Yes, I have a backup file'),
                text: s.pick(
                  'Mel Capital\'in .json yedek dosyasını seç (eski uygulamanınki de olur). Kopyası yeni profile alınır; dosyaya dokunulmaz.',
                  'Pick a Mel Capital .json backup (the old app\'s works too). A copy goes into the new profile; the file is left untouched.',
                ),
                onTap: _busy ? null : _fromFile,
              ),
              if (_fileError != null) ...[
                const SizedBox(height: 10),
                _Problem(text: s.pick('Bu dosyadan profil açılamadı. $_fileError', 'No profile could be opened from this file. $_fileError')),
              ],
              const SizedBox(height: 10),
              _Choice(
                key: const ValueKey<String>('start-new'),
                icon: Icons.auto_awesome_outlined,
                title: s.pick('Hayır, yeni profil kuralım', 'No, let\'s set up a new profile'),
                text: s.pick(
                  'Ekstrelerin, hesapların, kartların, kredilerin, gelirin ve düzenli ödemelerin için adım adım ilerleriz. Her adım atlanabilir.',
                  'We go step by step through your statements, accounts, cards, loans, income and regular payments. Every step can be skipped.',
                ),
                highlight: legacy == null,
                onTap: _busy ? null : () => _start(() async => null, setup: true),
              ),
              const SizedBox(height: 10),
              _Choice(
                key: const ValueKey<String>('start-sample'),
                icon: Icons.visibility_outlined,
                title: s.pick('Önce örnek verilerle göz atayım', 'Let me look around with sample data first'),
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

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tint: MC.rose,
      radius: 22,
      cut: 22,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: MC.rose, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: sans(13, height: 1.4))),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.icon, required this.title, required this.text, required this.onTap, this.highlight = false});

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
