import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/normalize.dart';
import '../../core/sample.dart';
import '../../core/util.dart';
import '../../core/version.dart';
import '../../storage/store.dart';
import '../dialogs.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

/// Ayarlar: profiller, dil ve görünüm, yedekler, veri.
class AyarlarPage extends StatelessWidget {
  const AyarlarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    return PageFrame(
      eyebrow: s.pick('AYARLAR', 'SETTINGS'),
      title: st.profile?.name ?? s.pick('Ayarlar', 'Settings'),
      children: [
        TwoColumns(
          leftFlex: 1,
          rightFlex: 1,
          left: const Column(children: [_ProfilesPanel(), SizedBox(height: 14), _BackupsPanel()]),
          // Yeni sürüm varsa "Mel Capital" bölümü en üstte durur.
          right: st.newVersion != null
              ? const Column(children: [_AboutPanel(), SizedBox(height: 14), _ViewPanel(), SizedBox(height: 14), _DataPanel()])
              : const Column(children: [_ViewPanel(), SizedBox(height: 14), _DataPanel(), SizedBox(height: 14), _AboutPanel()]),
        ),
      ],
    );
  }
}

/// Ayar satırı: solda başlık ve açıklama, sağda düğme.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.help, this.trailing});

  final String title;
  final String? help;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sans(14.5, weight: FontWeight.w600)),
                if (help != null) ...[
                  const SizedBox(height: 3),
                  Text(help!, style: sans(12.5, color: MC.muted, height: 1.4)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 14), trailing!],
        ],
      ),
    );
  }
}

class GoldSwitch extends StatelessWidget {
  const GoldSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: MC.ink,
        activeTrackColor: MC.gold,
        inactiveThumbColor: MC.muted,
        inactiveTrackColor: const Color(0x33000000),
      );
}

// ---------------------------------------------------------------- Profiller

class _ProfilesPanel extends StatelessWidget {
  const _ProfilesPanel();

  Future<void> _rename(BuildContext context, ProfileInfo p) async {
    final st = AppScope.of(context);
    final s = S.of(context);
    final name = await promptText(context, title: s.pick('Profilin adı', 'Profile name'), initial: p.name);
    if (name != null && name.isNotEmpty) await st.renameProfile(p.id, name);
  }

  Future<void> _delete(BuildContext context, ProfileInfo p) async {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ok = await confirmDialog(
      context,
      title: s.pick('"${p.name}" silinsin mi?', 'Delete "${p.name}"?'),
      text: s.pick(
        'Profilin bütün kayıtları uygulamadan kalkar. Dosyaları "Silinen profiller" klasörüne taşınır; istersen oradan geri alabilirsin.',
        'All records of this profile leave the app. Its files are moved to the "Silinen profiller" (deleted profiles) folder, where you can recover them.',
      ),
      ok: s.pick('Profili sil', 'Delete profile'),
      danger: true,
    );
    if (ok) await st.deleteProfile(p.id);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final current = st.profile;
    final others = st.index.profiles.where((p) => p.id != current?.id).toList();
    return GlassPanel(
      delay: const Duration(milliseconds: 60),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(
            s.pick('Profiller', 'Profiles'),
            subtitle: s.pick('Uygulama her açılışta son kullandığın profille açılır.', 'The app opens with the profile you used last.'),
            trailing: SmallButton(label: s.pick('Yeni profil', 'New profile'), onTap: () => st.setAddingProfile(true)),
          ),
          if (current != null)
            RowItem(
              leading: _ProfileMark(name: current.name, active: true),
              title: current.name,
              subtitle: s.pick('Açık profil', 'Open profile'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: s.pick('Adını değiştir', 'Rename'),
                    onPressed: () => _rename(context, current),
                    icon: const Icon(Icons.edit_outlined, size: 19, color: MC.muted),
                  ),
                  IconButton(
                    tooltip: s.pick('Profili sil', 'Delete profile'),
                    onPressed: () => _delete(context, current),
                    icon: const Icon(Icons.delete_outline, size: 19, color: MC.rose),
                  ),
                ],
              ),
            ),
          for (final p in others) ...[
            const Hairline(),
            RowItem(
              leading: _ProfileMark(name: p.name),
              title: p.name,
              subtitle: p.lastOpenedAt != null && p.lastOpenedAt!.length >= 10
                  ? s.pick('Son açılış ', 'Last opened ') + fmtDayShort(p.lastOpenedAt!.substring(0, 10), s.lang)
                  : null,
              trailing: const Icon(Icons.chevron_right, color: MC.muted),
              onTap: () => st.openProfile(p.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileMark extends StatelessWidget {
  const _ProfileMark({required this.name, this.active = false});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : trUpper(name.trim().characters.first);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: active ? MC.gold : const Color(0x33000000),
        shape: SignatureBorder(cut: 10, radius: 12, side: BorderSide(color: active ? MC.gold : const Color(0x40FFFFFF))),
      ),
      child: Text(letter, style: serif(22, color: active ? MC.ink : MC.text, weight: FontWeight.w700)),
    );
  }
}

// ---------------------------------------------------------------- Görünüm

class _ViewPanel extends StatelessWidget {
  const _ViewPanel();

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    Widget pill(String code, String label) {
      final on = s.lang == code;
      return TextButton(
        key: ValueKey<String>('lang-$code'),
        onPressed: () => st.setLanguage(code),
        style: TextButton.styleFrom(
          foregroundColor: on ? MC.ink : MC.text,
          backgroundColor: on ? MC.gold : const Color(0x33000000),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontFamily: MC.sans, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );
    }

    return GlassPanel(
      delay: const Duration(milliseconds: 100),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Dil ve görünüm', 'Language and display')),
          SettingRow(
            title: s.t('settings.language'),
            help: s.t('settings.languageHelp'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [pill('tr', 'Türkçe'), const SizedBox(width: 6), pill('en', 'English')]),
          ),
          const Hairline(),
          SettingRow(
            title: s.t('settings.hidden'),
            help: s.t('settings.hiddenHelp'),
            trailing: GoldSwitch(value: st.hidden, onChanged: (_) => st.toggleHidden()),
          ),
          const Hairline(),
          SettingRow(
            title: s.pick('Sayfa ipuçları', 'Page tips'),
            help: s.pick('Her sayfaya ilk girişte bir kez kısa bir ipucu gösterilir.', 'A short tip is shown once, the first time you open each page.'),
            trailing: SmallButton(
              key: const ValueKey<String>('tips-reset'),
              label: s.pick('Yeniden göster', 'Show again'),
              icon: Icons.lightbulb_outline,
              onTap: () {
                st.resetTips();
                toast(context, s.pick('İpuçları her sayfada bir kez yeniden gösterilecek.', 'Tips will show once more on each page.'));
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Yedekler

class _BackupsPanel extends StatefulWidget {
  const _BackupsPanel();

  @override
  State<_BackupsPanel> createState() => _BackupsPanelState();
}

class _BackupsPanelState extends State<_BackupsPanel> {
  Future<List<BackupInfo>>? _future;
  String? _for;

  void _load(AppState st) {
    final id = st.profile?.id;
    _for = id;
    _future = id == null ? Future.value(const <BackupInfo>[]) : st.store.listBackups(id);
  }

  Future<void> _backupNow() async {
    final st = AppScope.of(context);
    final s = S.of(context);
    final id = st.profile?.id;
    if (id == null) return;
    try {
      await st.flush();
      final name = await st.store.backupNow(id);
      if (!mounted) return;
      toast(context, s.pick('Yedek alındı: $name', 'Backup saved: $name'));
      setState(() => _load(st));
    } catch (e) {
      if (mounted) toast(context, s.pick('Yedek alınamadı: $e', 'Backup failed: $e'));
    }
  }

  Future<void> _restore(BackupInfo b) async {
    final st = AppScope.of(context);
    final s = S.of(context);
    final id = st.profile?.id;
    if (id == null) return;
    final ok = await confirmDialog(
      context,
      title: s.pick('Bu yedeğe dönülsün mü?', 'Go back to this backup?'),
      text: s.pick(
        '${b.name} yüklenir. Şimdiki verilerin önce ayrı bir yedeğe kopyalanır; istersen yeniden dönebilirsin.',
        '${b.name} will be loaded. Your current data is first copied to a separate backup, so you can come back.',
      ),
      ok: s.pick('Yedeğe dön', 'Restore'),
    );
    if (!ok) return;
    try {
      final raw = await st.store.readBackup(id, b.name);
      if (raw is! Map) throw const FormatException('');
      await st.replaceData(raw.cast<String, dynamic>());
      if (mounted) toast(context, s.pick('Yedek yüklendi.', 'Backup restored.'));
    } catch (_) {
      if (mounted) toast(context, s.pick('Bu yedek okunamadı.', 'This backup could not be read.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    if (_future == null || _for != st.profile?.id) _load(st);
    return GlassPanel(
      delay: const Duration(milliseconds: 140),
      radius: 30,
      cut: 30,
      child: FutureBuilder<List<BackupInfo>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data ?? const <BackupInfo>[];
          final autos = list.where((b) => b.auto).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelHead(
                s.pick('Yedekler', 'Backups'),
                subtitle: s.pick('$autos otomatik · ${list.length - autos} elle', '$autos automatic · ${list.length - autos} manual'),
              ),
              Text(
                s.pick('Her gün ilk değişiklikte otomatik yedek alınır; son 30 gün saklanır.',
                    'An automatic backup is taken with the first change each day; the last 30 days are kept.'),
                style: sans(12.5, color: MC.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GoldButton(label: s.pick('Şimdi yedek al', 'Back up now'), icon: Icons.save_alt, onTap: _backupNow),
                  GlassButton(
                    label: s.pick('Klasörü aç', 'Open folder'),
                    icon: Icons.folder_open_outlined,
                    onTap: () async {
                      final ok = await st.openFolder(backups: true);
                      if (!ok && context.mounted) toast(context, s.pick('Bu sürümde klasör açılamıyor.', 'Folders cannot be opened in this version.'));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (snap.connectionState != ConnectionState.done)
                Text(s.pick('Yedekler yükleniyor…', 'Loading backups…'), style: sans(13, color: MC.muted))
              else if (list.isEmpty)
                Text(s.pick('Henüz yedek yok.', 'No backups yet.'), style: sans(13, color: MC.muted))
              else
                for (final b in list.take(8))
                  RowItem(
                    leading: Icon(b.auto ? Icons.history : Icons.save_outlined, color: MC.gold, size: 22),
                    title: b.name,
                    subtitle: '${fmtDayShort(isoDay(b.time), s.lang)} · ${(b.size / 1024).toStringAsFixed(0)} KB',
                    trailing: Text(s.pick('Dön', 'Restore'), style: sans(13, color: MC.gold, weight: FontWeight.w600)),
                    onTap: () => _restore(b),
                  ),
              if (list.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.pick('${list.length - 8} yedek daha klasörde.', '${list.length - 8} more in the folder.'), style: sans(12, color: MC.dim)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Yerel tarih → YYYY-MM-DD.
String isoDay(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

// ---------------------------------------------------------------- Veri

class _DataPanel extends StatefulWidget {
  const _DataPanel();

  @override
  State<_DataPanel> createState() => _DataPanelState();
}

class _DataPanelState extends State<_DataPanel> {
  Json? _legacy;
  bool _checked = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    AppScope.of(context).store.readLegacyData().then((raw) {
      if (!mounted || raw == null) return;
      final n = normalizeData(raw);
      if (n.ok) setState(() => _legacy = n.data!.j);
    }).catchError((Object _) {});
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final legacy = _legacy == null ? null : Data(_legacy!);
    return GlassPanel(
      delay: const Duration(milliseconds: 180),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Veri', 'Data'), subtitle: s.pick('Veriler yalnızca bu bilgisayarda durur.', 'Your data stays on this computer.')),
          SettingRow(
            title: s.pick('Kurulum sihirbazı', 'Setup wizard'),
            help: s.pick('Hesaplarını, kartlarını, kredilerini, gelirini ve düzenli ödemelerini adım adım ekle.',
                'Add your accounts, cards, loans, income and regular payments step by step.'),
            trailing: SmallButton(
              key: const ValueKey<String>('setup-open'),
              label: s.pick('Aç', 'Open'),
              icon: Icons.auto_awesome_outlined,
              onTap: st.startSetup,
            ),
          ),
          const Hairline(),
          SettingRow(
            title: s.pick('Veri klasörü', 'Data folder'),
            help: s.pick('Belgeler › Mel Capital › Profiller', 'Documents › Mel Capital › Profiller'),
            trailing: SmallButton(
              label: s.pick('Aç', 'Open'),
              icon: Icons.folder_open_outlined,
              onTap: () async {
                final ok = await st.openFolder();
                if (!ok && context.mounted) toast(context, s.pick('Bu sürümde klasör açılamıyor.', 'Folders cannot be opened in this version.'));
              },
            ),
          ),
          if (legacy != null) ...[
            const Hairline(),
            SettingRow(
              title: s.pick('Eski Mel Capital verileri', 'Old Mel Capital data'),
              help: s.pick(
                '${legacy.accounts.length} hesap, ${legacy.debts.length} borç, ${legacy.spends.length} harcama. Yeni bir profil olarak açılır; eski dosyaya dokunulmaz.',
                '${legacy.accounts.length} accounts, ${legacy.debts.length} debts, ${legacy.spends.length} spends. Opens as a new profile; the old file is left untouched.',
              ),
              trailing: SmallButton(
                label: s.pick('Getir', 'Bring'),
                icon: Icons.drive_file_move_outline,
                onTap: _busy ? null : () => _run(() => st.createProfile(s.pick('Eski verilerim', 'My old data'), data: _legacy)),
              ),
            ),
          ],
          const Hairline(),
          SettingRow(
            title: s.pick('Örnek profil', 'Sample profile'),
            help: s.pick('Uydurma verilerle ayrı bir profil açılır; istediğinde silersin.', 'Opens a separate profile with made-up data; delete it whenever you like.'),
            trailing: SmallButton(
              label: s.pick('Aç', 'Open'),
              icon: Icons.visibility_outlined,
              onTap: _busy ? null : () => _run(() async => st.createProfile(s.pick('Örnek', 'Sample'), data: await loadSampleJson())),
            ),
          ),
          const Hairline(),
          SettingRow(
            title: s.pick('Bu profilin verilerini sil', 'Erase this profile\'s data'),
            help: s.pick('Silmeden önce yedek alınır. Profil boş olarak kalır.', 'A backup is taken first. The profile stays, empty.'),
            trailing: GlassButton(
              label: s.pick('Sil', 'Erase'),
              danger: true,
              onTap: () async {
                final ok = await confirmDialog(
                  context,
                  title: s.pick('Bütün kayıtlar silinsin mi?', 'Erase all records?'),
                  text: s.pick('Hesaplar, borçlar, harcamalar ve planlar silinir. Önce bir yedek alınır; Yedekler panelinden geri dönebilirsin.',
                      'Accounts, debts, spends and plans are erased. A backup is taken first; you can restore it from the Backups panel.'),
                  danger: true,
                );
                if (ok) await st.replaceData(emptyData().j);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Hakkında ve güncellemeler

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _install(AppState st) async {
    final info = st.newVersion;
    if (info == null) return;
    if (_android) {
      // Telefon: yeni APK tarayıcıda iner; açınca Android "Güncelle" der, veriler kalır.
      await launchUrl(Uri.parse(info.apk?.url ?? info.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    final done = await st.installUpdate();
    if (!done) {
      // Kurulum programıyla kurulmamış kopya: yeni sürüm sayfası açılır.
      await launchUrl(Uri.parse(info.pageUrl), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final info = st.newVersion;
    final version = kBuildLabel.isEmpty
        ? s.pick('Geliştirme derlemesi', 'Development build')
        : s.pick('Sürüm ${buildLabelText(kBuildLabel, 'tr')}', 'Version ${buildLabelText(kBuildLabel, 'en')}');
    final installed = st.updater?.installed ?? false;
    final progress = st.updateProgress;

    Widget? status;
    if (info != null) {
      final when = info.label.isEmpty ? '' : buildLabelText(info.label, s.lang);
      status = Container(
        key: const ValueKey<String>('update-card'),
        margin: const EdgeInsets.only(top: 4, bottom: 6),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: ShapeDecoration(
          color: MC.gold.withValues(alpha: 0.12),
          shape: SignatureBorder(cut: 14, radius: 14, side: BorderSide(color: MC.gold.withValues(alpha: 0.55))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.new_releases_outlined, color: MC.gold, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    when.isEmpty ? s.pick('Yeni sürüm hazır', 'A new version is ready') : s.pick('Yeni sürüm hazır · $when', 'New version ready · $when'),
                    style: sans(14.5, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(info.notes, maxLines: 6, overflow: TextOverflow.ellipsis, style: sans(12.5, color: MC.muted, height: 1.45)),
            ],
            const SizedBox(height: 12),
            if (progress != null && progress < 1) ...[
              ProgressLine(progress),
              const SizedBox(height: 6),
              Text(s.pick('İndiriliyor · %${(progress * 100).round()}', 'Downloading · ${(progress * 100).round()}%'), style: sans(12.5, color: MC.muted)),
            ] else if (progress == 1)
              Text(
                s.pick('Güncelleme başladı. Windows izin isterse "Evet"e bas; Mel Capital birazdan yeni sürümle açılır.',
                    'The update has started. If Windows asks for permission, click "Yes"; Mel Capital reopens with the new version.'),
                style: sans(12.5, color: MC.text, height: 1.45),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GoldButton(
                    key: const ValueKey<String>('update-install'),
                    label: _android
                        ? s.pick('Yeni sürümü indir', 'Download the new version')
                        : installed
                            ? s.pick('Güncellemeyi kur', 'Install the update')
                            : s.pick('Kurulum dosyasını indir', 'Download the installer'),
                    icon: installed ? Icons.system_update_alt : Icons.download_outlined,
                    onTap: () => _install(st),
                  ),
                ],
              ),
            if (!installed && progress == null) ...[
              const SizedBox(height: 8),
              Text(
                _android
                    ? s.pick('İndirilen dosyayı açıp "Güncelle"ye bas; verilerin telefonda kalır.',
                        'Open the downloaded file and tap "Update"; your data stays on the phone.')
                    : s.pick('Bu kopya kurulum programıyla kurulmamış; yeni sürümü indirdiğin kurulum dosyasıyla kurabilirsin.',
                        'This copy was not set up with the installer; install the new version with the downloaded setup file.'),
                style: sans(12, color: MC.dim, height: 1.4),
              ),
            ],
            if (st.updateError != null) ...[
              const SizedBox(height: 8),
              Text(s.pick('Güncelleme indirilemedi: ${st.updateError}', 'The update could not be downloaded: ${st.updateError}'),
                  style: sans(12.5, color: MC.rose, height: 1.4)),
            ],
          ],
        ),
      );
    } else if (st.updateChecking) {
      status = Text(s.pick('Yeni sürüm denetleniyor…', 'Checking for a new version…'), style: sans(12.5, color: MC.muted));
    } else if (st.updateChecked == true) {
      status = Text(s.pick('En güncel sürümü kullanıyorsun.', 'You\'re on the latest version.'), style: sans(12.5, color: MC.mint));
    } else if (st.updateChecked == false) {
      status = Text(s.pick('Yeni sürüm denetlenemedi; internet bağlantını kontrol et.', 'Could not check for a new version; check your internet connection.'),
          style: sans(12.5, color: MC.muted));
    }

    return GlassPanel(
      delay: const Duration(milliseconds: 220),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead('Mel Capital', subtitle: version),
          if (status != null) status,
          if (st.canCheckUpdates)
            SettingRow(
              title: s.pick('Yeni sürümü kendiliğinden denetle', 'Check for new versions automatically'),
              help: s.pick('Açılışta yalnızca sürüm numarasına bakılır; verilerin hiçbir yere gönderilmez.',
                  'Only the version number is checked at startup; your data is never sent anywhere.'),
              trailing: GoldSwitch(value: st.index.autoUpdate, onChanged: st.setAutoUpdate),
            ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (st.canCheckUpdates)
                SmallButton(
                  key: const ValueKey<String>('update-check'),
                  label: s.pick('Şimdi denetle', 'Check now'),
                  icon: Icons.refresh,
                  onTap: st.updateChecking || progress != null ? null : () => st.checkForUpdate(manual: true),
                ),
              SmallButton(
                key: const ValueKey<String>('intro-open'),
                label: s.pick('Tanıtımı izle', 'Watch the intro'),
                icon: Icons.slideshow_outlined,
                onTap: st.openIntro,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
