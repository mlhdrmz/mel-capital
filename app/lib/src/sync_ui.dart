// Telefon eşitlemesinin arayüzü: üst menüdeki durum düğmesi, Ayarlar'daki Telefon bölümü,
// eşleştirme kodu (QR), telefonda kod okutma ve eşitleme bildirimleri.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr/qr.dart';

import '../core/constants.dart';
import '../core/sync/api.dart';
import '../core/sync/engine.dart';
import '../core/util.dart';
import 'dialogs.dart';
import 'glass.dart';
import 'i18n.dart';
import 'sahne.dart' show kontrolZemini;
import 'sheet.dart';
import 'state.dart';
import 'theme.dart';
import 'ui.dart';

// ---------------------------------------------------------------- Metinler

/// Eşitleme hatasının kısa açıklaması.
String syncErrorText(String? code, S s, {required bool phone}) {
  switch (code) {
    case 'ag':
      return s.pick('internete ulaşılamıyor', 'no internet connection');
    case 'sifre':
      return s.pick('paket açılamadı (anahtar uyuşmuyor)', 'the package could not be opened (key mismatch)');
    case 'birlestirme':
      return s.pick('değişiklikler birleştirilemedi', 'changes could not be merged');
    case 'eski':
      return s.pick('sunucudaki kopya bu cihazdakinden eski', 'the server copy is older than this device\'s');
    case 'sunucu':
      return s.pick('sunucu hatası', 'server error');
    case 'yerel':
      return phone ? s.pick('telefona kaydedilemedi', 'could not save on the phone') : s.pick('bilgisayara kaydedilemedi', 'could not save on the computer');
    case 'kimlik':
      return s.pick('eşleştirme geçersiz', 'the pairing is not valid');
    case 'sik':
      return s.pick('çok sık eşitleme, 15 dakika ara', 'syncing too often, pausing 15 minutes');
  }
  return s.pick('beklenmeyen hata', 'unexpected error');
}

/// "az önce", "5 dk önce", "3 sa önce" ya da tarih ve saat.
String syncAgo(String? iso, S s) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return '';
  final sec = math.max(0, clock().difference(t).inSeconds);
  if (sec < 50) return s.pick('az önce', 'just now');
  if (sec < 3600) return s.pick('${(sec / 60).round()} dk önce', '${(sec / 60).round()} min ago');
  if (sec < 86400) return s.pick('${(sec / 3600).round()} sa önce', '${(sec / 3600).round()} h ago');
  return syncDateTime(iso, s);
}

/// Tarih ve saat (yerel saatle): "4 Kasım 2026, 15.48" / "November 4, 2026, 15:48".
String syncDateTime(String? iso, S s) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  final day = '${t.year}-${two(t.month)}-${two(t.day)}';
  return s.pick('${fmtDate(day, 'tr')}, ${two(t.hour)}.${two(t.minute)}', '${fmtDate(day, 'en')}, ${two(t.hour)}:${two(t.minute)}');
}

/// Durumun tek satırlık açıklaması (düğmenin ipucu ve Ayarlar'daki satır).
String syncStatusText(AppState st, S s) {
  final e = st.sync;
  if (e == null || !e.paired) return s.pick('Bağlı değil', 'Not connected');
  switch (e.status) {
    case SyncStatus.busy:
      return s.pick('Eşitleniyor…', 'Syncing…');
    case SyncStatus.offline:
      return s.pick('İnternet yok: bağlanınca eşitlenecek', 'Offline: it will sync once you are connected');
    case SyncStatus.err:
      return s.pick('Eşitlenemedi: ', 'Could not sync: ') + syncErrorText(e.errorCode, s, phone: st.phone);
    case SyncStatus.lost:
      return s.pick('Bağlantı kaldırılmış', 'The connection was removed');
    case SyncStatus.wait:
      return s.pick('Açık pencere kapanınca eşitlenecek', 'It will sync when the open panel closes');
    case SyncStatus.off:
    case SyncStatus.ok:
      final at = e.syncedAt;
      return at == null ? s.pick('Eşitlendi', 'Synced') : s.pick('Eşitlendi · ', 'Synced · ') + syncAgo(at, s);
  }
}

Color _statusColor(SyncStatus status) => switch (status) {
      SyncStatus.offline => MC.gold,
      SyncStatus.err || SyncStatus.lost => MC.rose,
      SyncStatus.wait => MC.dim,
      _ => MC.mint,
    };

// ---------------------------------------------------------------- Bildirimler

/// Eşitlemenin haberlerini alt köşede bildirim olarak gösterir.
class SyncToasts extends StatefulWidget {
  const SyncToasts({super.key, required this.child});

  final Widget child;

  @override
  State<SyncToasts> createState() => _SyncToastsState();
}

class _SyncToastsState extends State<SyncToasts> {
  StreamSubscription<SyncEvent>? _sub;
  AppState? _st;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final st = AppScope.of(context);
    if (identical(st, _st)) return;
    unawaited(_sub?.cancel());
    _st = st;
    _sub = st.syncEvents.listen(_show);
  }

  void _show(SyncEvent e) {
    if (!mounted) return;
    final st = _st!;
    final s = S.of(context);
    final text = switch (e.notice) {
      SyncNotice.synced => s.pick('Eşitlendi.', 'Synced.'),
      SyncNotice.peerChanges => st.phone
          ? s.pick('Bilgisayardan gelen değişiklikler eklendi.', 'Changes from your computer were added.')
          : s.pick('Telefondan gelen değişiklikler eklendi.', 'Changes from your phone were added.'),
      SyncNotice.offline => s.pick('İnternet yok; bağlanınca eşitlenecek.', 'No internet; it will sync once you are online.'),
      SyncNotice.failed => s.pick('Eşitlenemedi: ', 'Could not sync: ') + syncErrorText(e.detail, s, phone: st.phone) + '.',
      SyncNotice.lost => st.phone
          ? s.pick('Bilgisayardaki Mel Capital bu bağlantıyı kaldırmış.', 'Mel Capital on your computer removed this connection.')
          : s.pick('Telefon bağlantısı kaldırılmış; eşitleme durdu.', 'The phone connection was removed; syncing stopped.'),
      SyncNotice.paused => s.pick('Çok sık eşitleme oldu; 15 dakika ara verildi.', 'Synced too often; pausing for 15 minutes.'),
    };
    showToast(ScaffoldMessenger.of(context), st.lang, text, seconds: e.notice == SyncNotice.lost ? 7 : 4);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------- Üst menüdeki düğme

/// Eşleştirme varsa üst menüde durum düğmesi: dokununca hemen eşitler.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key});

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final e = st.sync;
    if (e == null || !e.paired) return const SizedBox.shrink();
    final status = e.status;
    final busy = status == SyncStatus.busy;
    // Dönme, çizimden sonra başlar ya da durur (çizim sırasında animasyon değiştirilmez).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (busy && !_spin.isAnimating) {
        _spin.repeat();
      } else if (!busy && _spin.isAnimating) {
        _spin
          ..stop()
          ..value = 0;
      }
    });
    final icon = switch (status) {
      SyncStatus.offline => Icons.cloud_off_outlined,
      SyncStatus.err || SyncStatus.lost => Icons.sync_problem,
      _ => Icons.sync,
    };
    return IconButton(
      key: const ValueKey<String>('sync-button'),
      tooltip: syncStatusText(st, s),
      onPressed: e.lost ? () => st.setTab(AppTab.ayarlar) : st.syncNow,
      icon: RotationTransition(turns: Tween<double>(begin: 1, end: 0).animate(_spin), child: Icon(icon, size: 18)),
      style: IconButton.styleFrom(
        foregroundColor: status == SyncStatus.ok || busy ? MC.text : _statusColor(status),
        backgroundColor: kontrolZemini(context, asil: const Color(0x2E000000)),
        hoverColor: const Color(0x22FFFFFF),
        side: const BorderSide(color: Color(0x38FFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        fixedSize: const Size(40, 40),
      ),
    );
  }
}

// ---------------------------------------------------------------- Ayarlar: Telefon bölümü

/// Ayarlar'da telefon eşitlemesi: bilgisayarda "Telefon", telefonda "Bilgisayarla eşitleme".
class SyncPanel extends StatefulWidget {
  const SyncPanel({super.key});

  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  bool _busy = false;

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
    final e = st.sync;
    if (e == null) return const SizedBox.shrink();
    final phone = st.phone;
    final title = phone ? s.pick('Bilgisayarla eşitleme', 'Sync with computer') : s.pick('Telefon', 'Phone');
    final children = <Widget>[];
    String subtitle;
    if (e.paired && e.lost) {
      subtitle = s.pick('Bağlantı kaldırılmış', 'Connection removed');
      children.addAll([
        Text(
          phone
              ? s.pick('Bilgisayardaki Mel Capital bu bağlantıyı kaldırmış. Buradaki veriler olduğu gibi duruyor.',
                  'Mel Capital on your computer removed this connection. The data here is untouched.')
              : s.pick('Sunucudaki şifreli kopya silinmiş; telefonla eşitleme durdu. Bu bilgisayardaki verilerin olduğu gibi duruyor.',
                  'The encrypted copy on the server was deleted; syncing with the phone stopped. Your data on this computer is untouched.'),
          style: sans(13, color: MC.muted, height: 1.45),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (phone)
            GoldButton(
              label: s.pick('Yeniden bağlan', 'Connect again'),
              icon: Icons.qr_code_scanner,
              onTap: _busy ? null : () => openPhonePairing(context),
            ),
          GlassButton(
            key: const ValueKey<String>('sync-forget'),
            label: phone ? s.pick('Bu telefonu ayır', 'Disconnect this phone') : s.pick('Eşitlemeyi kapat', 'Turn syncing off'),
            onTap: _busy ? null : () => _run(st.unpairSync),
          ),
        ]),
      ]);
    } else if (e.paired) {
      subtitle = s.pick('Bağlı', 'Connected');
      final peer = e.peerAt;
      children.addAll([
        _Row(
          title: s.pick('Durum', 'Status'),
          text: syncStatusText(st, s),
          trailing: _StatusChip(status: e.status),
        ),
        const Hairline(),
        _Row(
          title: phone ? s.pick('Bilgisayardan son değişiklik', 'Last change from the computer') : s.pick('Telefondan son değişiklik', 'Last change from the phone'),
          text: peer != null
              ? syncDateTime(peer, s)
              : s.pick('Henüz yok. Karşı tarafta bir değişiklik yapınca burada görünür.', 'None yet. It shows up here after a change on the other side.'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          GoldButton(
            key: const ValueKey<String>('sync-now'),
            label: s.pick('Şimdi eşitle', 'Sync now'),
            icon: Icons.sync,
            onTap: e.busy ? null : st.syncNow,
          ),
          if (!phone)
            GlassButton(
              key: const ValueKey<String>('sync-code'),
              label: s.pick('Kodu göster', 'Show code'),
              icon: Icons.qr_code_2,
              onTap: () => showPairCodeSheet(context),
            ),
          GlassButton(
            key: const ValueKey<String>('sync-unpair'),
            label: phone ? s.pick('Bu telefonu ayır', 'Disconnect this phone') : s.pick('Bağlantıyı kaldır', 'Remove connection'),
            danger: true,
            onTap: _busy ? null : () => _unpair(context, st),
          ),
        ]),
      ]);
    } else if (phone) {
      subtitle = s.pick('Bağlı değil', 'Not connected');
      children.addAll([
        Text(
          s.pick('Bilgisayardaki Mel Capital\'e bağlan: orada yaptığın her değişiklik burada, burada eklediğin harcamalar orada görünür. Veriler yolda şifreli gider; aradaki sunucu içeriği okuyamaz.',
              'Connect to Mel Capital on your computer: every change there shows up here, and what you add here shows up there. Data travels encrypted; the server in between cannot read it.'),
          style: sans(13, color: MC.muted, height: 1.45),
        ),
        const SizedBox(height: 12),
        GoldButton(
          key: const ValueKey<String>('sync-pair'),
          label: s.pick('Bilgisayarıma bağlan', 'Connect to my computer'),
          icon: Icons.qr_code_scanner,
          onTap: () => openPhonePairing(context),
        ),
      ]);
    } else if (st.canAdoptLegacySync) {
      subtitle = s.pick('Eski bağlantı bulundu', 'Old connection found');
      children.addAll([
        Text(
          s.pick('Eski Mel Capital\'de telefonunu bağlamıştın. Bu bağlantıyı bu profille sürdürebilirsin: telefonda eklediklerin buraya gelir, buradaki değişiklikler telefona gider.',
              'You had connected your phone in the old Mel Capital. You can keep that connection with this profile: what you add on the phone comes here, and changes here go to the phone.'),
          style: sans(13, color: MC.muted, height: 1.45),
        ),
        const SizedBox(height: 12),
        GoldButton(
          key: const ValueKey<String>('sync-adopt'),
          label: s.pick('Bu profille sürdür', 'Keep it with this profile'),
          icon: Icons.sync,
          onTap: _busy ? null : () => _adopt(context, st),
        ),
      ]);
    } else {
      subtitle = s.pick('Bağlı değil', 'Not connected');
      children.add(Text(
        st.index.legacySyncUsed
            ? s.pick('Telefon bağlantın başka bir profilde.', 'Your phone connection is on another profile.')
            : s.pick('Bu bilgisayarda telefon bağlantısı yok. Yeni bağlantı kurmak bu sürümde henüz yok; eski Mel Capital\'de bağladığın telefon burada otomatik bulunur.',
                'There is no phone connection on this computer. Making a new connection is not in this version yet; a phone you connected in the old Mel Capital is found here automatically.'),
        style: sans(13, color: MC.muted, height: 1.45),
      ));
    }
    return GlassPanel(
      key: const ValueKey<String>('sync-panel'),
      delay: const Duration(milliseconds: 120),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [PanelHead(title, subtitle: subtitle), ...children],
      ),
    );
  }

  Future<void> _adopt(BuildContext context, AppState st) async {
    final s = S.of(context);
    final ok = await confirmDialog(
      context,
      title: s.pick('Telefon bu profille eşitlensin mi?', 'Sync the phone with this profile?'),
      text: s.pick(
        'Eski Mel Capital\'de bağladığın telefon bundan sonra "${st.profile?.name ?? ''}" profiliyle eşitlenir. Telefonda eklediğin değişiklikler buraya gelir, buradakiler telefona gider. Önce bu profilin bir yedeği alınır.',
        'The phone you connected in the old Mel Capital will sync with the "${st.profile?.name ?? ''}" profile from now on. Changes on the phone come here and changes here go to the phone. A backup of this profile is taken first.',
      ),
      ok: s.pick('Sürdür', 'Keep it'),
    );
    if (!ok || !context.mounted) return;
    await _run(() async {
      final id = st.profile?.id;
      if (id != null) await st.store.backupNow(id, prefix: 'esitlemeden-once').catchError((Object _) => '');
      try {
        await st.adoptLegacySync();
        await st.syncNow();
      } catch (e) {
        if (context.mounted) toast(context, s.pick('Bağlantı sürdürülemedi: $e', 'The connection could not be kept: $e'));
      }
    });
  }

  Future<void> _unpair(BuildContext context, AppState st) async {
    final s = S.of(context);
    final e = st.sync!;
    final pending = e.dirty || e.status == SyncStatus.offline || e.status == SyncStatus.err;
    final ok = await confirmDialog(
      context,
      title: st.phone ? s.pick('Bu telefon ayrılsın mı?', 'Disconnect this phone?') : s.pick('Telefon bağlantısı kaldırılsın mı?', 'Remove the phone connection?'),
      text: st.phone
          ? s.pick(
              'Bu telefon bilgisayarla eşitlenmeyi bırakır; buradaki veriler ayrı bir profil olarak kalır. Yeniden bağlamak için bilgisayardaki kodu yeniden okutman yeterli.${pending ? '\nDİKKAT: Bu telefonda henüz bilgisayara gitmemiş değişiklikler olabilir.' : ''}',
              'This phone stops syncing with the computer; the data here stays as a separate profile. To connect again, scan the code on the computer again.${pending ? '\nNOTE: There may be changes on this phone that have not reached the computer yet.' : ''}')
          : s.pick(
              'Sunucudaki şifreli kopya silinir; telefon bir daha eşitlenmez. Bu bilgisayardaki verilerin olduğu gibi kalır.\nBu sürüm yeni bağlantı kuramadığı için telefon eşitlemesini sonradan yeniden açamazsın.',
              'The encrypted copy on the server is deleted; the phone stops syncing. Your data on this computer stays as it is.\nThis version cannot make new connections, so you will not be able to turn phone syncing back on later.'),
      ok: st.phone ? s.pick('Ayır', 'Disconnect') : s.pick('Bağlantıyı kaldır', 'Remove connection'),
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await _run(() async {
      try {
        await st.unpairSync();
        if (context.mounted) toast(context, st.phone ? s.pick('Bu telefon ayrıldı.', 'This phone was disconnected.') : s.pick('Telefon bağlantısı kaldırıldı.', 'The phone connection was removed.'));
      } on SyncError catch (err) {
        if (context.mounted) {
          toast(context, s.pick('Bağlantı kaldırılamadı: ', 'The connection could not be removed: ') + syncErrorText(err.code, s, phone: st.phone) + '.');
        }
      }
    });
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.text, this.trailing});

  final String title;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: sans(14.5, weight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(text, style: sans(12.5, color: MC.muted, height: 1.4)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = status == SyncStatus.busy ? MC.sky : _statusColor(status);
    final label = switch (status) {
      SyncStatus.busy => s.pick('Eşitleniyor', 'Syncing'),
      SyncStatus.offline => s.pick('İnternet yok', 'Offline'),
      SyncStatus.err => s.pick('Sorun var', 'Problem'),
      SyncStatus.lost => s.pick('Kaldırılmış', 'Removed'),
      SyncStatus.wait => s.pick('Bekliyor', 'Waiting'),
      _ => s.pick('Eşitlendi', 'Synced'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(label, style: sans(12, weight: FontWeight.w600, color: c)),
    );
  }
}

// ---------------------------------------------------------------- Bilgisayar: eşleştirme kodu

/// Telefonu bağlamak için kod (QR) ve adımlar.
Future<void> showPairCodeSheet(BuildContext context) {
  final st = AppScope.of(context);
  final link = st.sync?.link;
  if (link == null) return Future<void>.value();
  return showEditSheet<void>(context, width: 560, builder: (context) => _PairCodeSheet(link: link));
}

class _PairCodeSheet extends StatelessWidget {
  const _PairCodeSheet({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: MC.gold.withValues(alpha: 0.18), shape: BoxShape.circle, border: Border.all(color: MC.gold.withValues(alpha: 0.6))),
              child: Text('$n', style: sans(12, weight: FontWeight.w700, color: MC.gold)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: sans(13.5, height: 1.45))),
          ]),
        );
    return SheetFrame(
      title: s.pick('Telefonu bağla', 'Connect your phone'),
      subtitle: s.pick('Telefondaki Mel Capital bu kodla bilgisayarındaki verilere bağlanır.', 'Mel Capital on your phone connects to the data on this computer with this code.'),
      children: [
        Center(
          child: Container(
            key: const ValueKey<String>('pair-qr'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: QrView(link, size: 250),
          ),
        ),
        const SizedBox(height: 18),
        step(1, s.pick('Telefonuna Mel Capital\'in Android uygulamasını (APK) kur ve aç.', 'Install Mel Capital\'s Android app (APK) on your phone and open it.')),
        step(2, s.pick('"Bilgisayarıma bağlan"a dokun ve bu kodu okut.', 'Tap "Connect to my computer" and scan this code.')),
        step(3, s.pick('Telefon verileri indirir. Bundan sonra iki tarafta yaptığın her değişiklik diğerine geçer.', 'The phone downloads your data. From then on, every change on one side reaches the other.')),
        const SizedBox(height: 4),
        Text(
          s.pick('Bu kod verilerinin anahtarıdır: kimseyle paylaşma, fotoğrafını saklama.', 'This code is the key to your data: do not share it or keep a photo of it.'),
          style: sans(12.5, color: MC.dim, height: 1.4),
        ),
      ],
      actions: [
        GlassButton(
          label: s.pick('Bağlantıyı kopyala', 'Copy link'),
          icon: Icons.copy_outlined,
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: link));
            showToast(messenger, s.lang, s.pick('Bağlantı kopyalandı. Yalnızca kendi telefonunda aç.', 'Link copied. Open it only on your own phone.'), seconds: 5);
          },
        ),
        GoldButton(label: s.pick('Tamam', 'Done'), onTap: () => Navigator.of(context).maybePop()),
      ],
    );
  }
}

/// QR kodu (beyaz zemin, siyah kareler; çevresinde boşluk).
class QrView extends StatelessWidget {
  const QrView(this.data, {super.key, this.size = 240});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _QrPainter(image), size: Size.square(size)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    const quiet = 2;
    final cell = (size.width / (n + quiet * 2)).floorToDouble();
    final offset = (size.width - cell * n) / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()
      ..color = const Color(0xFF111111)
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (image.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(offset + c * cell, offset + r * cell, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

// ---------------------------------------------------------------- Telefon: bilgisayara bağlanma

/// Telefonda bilgisayardaki koda bağlanır: kodu tara ya da bağlantıyı yapıştır. Başarılıysa
/// bilgisayardaki verilerle yeni bir profil açılır.
Future<void> openPhonePairing(BuildContext context, {String? name}) =>
    showEditSheet<void>(context, builder: (_) => _PairSheet(name: name));

class _PairSheet extends StatefulWidget {
  const _PairSheet({this.name});

  final String? name;

  @override
  State<_PairSheet> createState() => _PairSheetState();
}

class _PairSheetState extends State<_PairSheet> {
  final _link = TextEditingController();
  bool _busy = false;
  bool _paste = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  String _errorText(Object e, S s) {
    final code = e is SyncError ? e.code : null;
    return switch (code) {
      'ag' => s.pick('İnternete ulaşılamadı. Bağlantını kontrol edip kodu yeniden okut.', 'Could not reach the internet. Check your connection and scan the code again.'),
      'yok' => s.pick('Bu kod artık geçerli değil. Bilgisayarda Ayarlar → Telefon → "Kodu göster" ile güncel kodu okut.',
          'This code is no longer valid. On the computer, open Settings → Phone → "Show code" and scan the current one.'),
      'kimlik' || 'sifre' || 'anahtar' => s.pick('Kod eksik ya da hatalı okundu. Kodu yeniden okut.', 'The code was read incompletely or wrongly. Scan it again.'),
      'bicim' => s.pick('Bilgisayardan gelen veri okunamadı. Bilgisayardaki Mel Capital\'i güncelleyip yeniden dene.',
          'The data from the computer could not be read. Update Mel Capital on the computer and try again.'),
      _ => s.pick('Bağlanılamadı (${code ?? e}). Biraz sonra yeniden dene.', 'Could not connect (${code ?? e}). Try again a bit later.'),
    };
  }

  Future<void> _connect(String text) async {
    final s = S.of(context);
    final parsed = parsePairLink(text);
    if (parsed == null) {
      setState(() => _error = s.pick('Bu bir Mel Capital eşleştirme bağlantısı değil.', 'This is not a Mel Capital pairing link.'));
      return;
    }
    final st = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await st.pairFromLink(parsed.$1, parsed.$2, name: widget.name);
      if (!mounted) return;
      nav.pop();
      showToast(messenger, st.lang, s.pick('Telefon bilgisayarla eşleşti.', 'The phone is now connected to your computer.'), seconds: 5);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e, s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(fullscreenDialog: true, builder: (_) => const _ScanPage()),
    );
    if (raw != null && mounted) await _connect(raw);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = AppScope.of(context);
    return SheetFrame(
      title: s.pick('Bilgisayarına bağlan', 'Connect to your computer'),
      subtitle: s.pick('Veriler bilgisayarında şifrelenir, telefonda açılır; aradaki sunucu içeriği okuyamaz.',
          'Data is encrypted on your computer and opened on the phone; the server in between cannot read it.'),
      error: _error,
      children: [
        Text(s.pick('1. Bilgisayarda Mel Capital\'i aç: Ayarlar → Telefon → Kodu göster.', '1. On the computer, open Mel Capital: Settings → Phone → Show code.'),
            style: sans(14, height: 1.45)),
        const SizedBox(height: 6),
        Text(s.pick('2. Aşağıdaki düğmeyle kodu okut ya da kopyaladığın bağlantıyı yapıştır.', '2. Scan the code with the button below or paste the link you copied.'),
            style: sans(14, height: 1.45)),
        const SizedBox(height: 16),
        if (_busy)
          Row(children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: MC.gold)),
            const SizedBox(width: 12),
            Expanded(child: Text(s.pick('Bilgisayardaki verilerin şifreli olarak indiriliyor…', 'Downloading your data from the computer, encrypted…'), style: sans(13.5, color: MC.muted))),
          ])
        else if (_paste)
          FieldBox(
            label: s.pick('Bilgisayarda "Bağlantıyı kopyala" ile aldığın bağlantı', 'The link from "Copy link" on the computer'),
            child: TextInput(controller: _link, hint: 'https://…/#e=…', autofocus: true, maxLines: 3, onSubmitted: _connect),
          ),
      ],
      leftActions: [
        if (!_busy && !_paste)
          GlassButton(
            key: const ValueKey<String>('pair-paste'),
            label: s.pick('Bağlantıyı yapıştır', 'Paste link'),
            onTap: () => setState(() => _paste = true),
          ),
      ],
      actions: [
        if (_paste)
          GoldButton(
            key: const ValueKey<String>('pair-connect'),
            label: s.pick('Bağlan', 'Connect'),
            onTap: _busy ? null : () => _connect(_link.text),
          )
        else if (st.phone)
          GoldButton(
            key: const ValueKey<String>('pair-scan'),
            label: s.pick('Kodu tara', 'Scan code'),
            icon: Icons.qr_code_scanner,
            onTap: _busy ? null : _scan,
          ),
      ],
    );
  }
}

/// Kamerayla kod okuma (yalnızca telefonda).
class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && parsePairLink(raw) != null) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(border: Border.all(color: MC.gold, width: 3), borderRadius: BorderRadius.circular(22)),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  s.pick('Bilgisayarda Ayarlar → Telefon\'daki kodu çerçeveye getir.', 'Bring the code from Settings → Phone on the computer into the frame.'),
                  textAlign: TextAlign.center,
                  style: sans(15, height: 1.4, shadows: kPhotoTextShadow),
                ),
                const SizedBox(height: 14),
                GlassButton(label: s.pick('Vazgeç', 'Cancel'), onTap: () => Navigator.of(context).pop()),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
