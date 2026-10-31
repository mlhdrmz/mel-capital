import 'package:flutter/material.dart';

import '../../core/normalize.dart';
import '../../storage/store.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

/// Veri okunamadığında: hiçbir şey silinmez; yedekten dönülebilir.
class CorruptPage extends StatefulWidget {
  const CorruptPage({super.key});

  @override
  State<CorruptPage> createState() => _CorruptPageState();
}

class _CorruptPageState extends State<CorruptPage> {
  List<BackupInfo>? _backups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final st = AppScope.of(context);
    final id = st.profile?.id;
    if (_backups == null && id != null) {
      st.store.listBackups(id).then((b) {
        if (mounted) setState(() => _backups = b);
      }).catchError((Object _) {
        if (mounted) setState(() => _backups = const []);
      });
    }
  }

  Future<void> _restore(BackupInfo b) async {
    final st = AppScope.of(context);
    final s = S.of(context);
    final id = st.profile?.id;
    if (id == null) return;
    try {
      final raw = await st.store.readBackup(id, b.name);
      if (raw is! Map) throw const FormatException('');
      await st.replaceData(raw.cast<String, dynamic>());
    } catch (_) {
      if (mounted) toast(context, s.pick('Bu yedek de okunamadı; başka bir yedek seç.', 'This backup could not be read either; pick another.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    return PageFrame(
      eyebrow: s.pick('VERİ OKUNAMADI', 'DATA COULD NOT BE READ'),
      title: st.profile?.name ?? 'Mel Capital',
      children: [
        GlassPanel(
          tint: MC.rose,
          radius: 26,
          cut: 26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.pick('Kayıtlı veri beklenen yapıda değil. Hiçbir şey silinmedi; en son yedeğinden geri dönebilirsin.',
                    'The saved data is not in the expected shape. Nothing was deleted; you can go back to your latest backup.'),
                style: sans(14),
              ),
              const SizedBox(height: 10),
              for (final e in st.corruptErrors.take(8)) Text('• $e', style: sans(12, color: MC.muted)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassPanel(
          radius: 26,
          cut: 26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelHead(s.pick('Yedekler', 'Backups'), subtitle: s.pick('Birine dokununca o yedeğe dönülür', 'Tap one to go back to it')),
              if (_backups == null)
                Text(s.pick('Yedekler yükleniyor…', 'Loading backups…'), style: sans(13, color: MC.muted))
              else if (_backups!.isEmpty)
                Text(s.pick('Yedek bulunamadı.', 'No backups found.'), style: sans(13, color: MC.muted))
              else
                for (final b in _backups!.take(12))
                  RowItem(
                    leading: const Icon(Icons.restore, color: MC.gold),
                    title: b.name,
                    subtitle: '${b.time.toLocal()}'.substring(0, 16),
                    onTap: () => _restore(b),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GlassButton(
              label: s.pick('Sil ve boş başla', 'Delete and start empty'),
              icon: Icons.delete_outline,
              danger: true,
              onTap: () => st.replaceData(emptyData().j),
            ),
          ],
        ),
      ],
    );
  }
}
