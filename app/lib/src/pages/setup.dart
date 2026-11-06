// Kurulum sihirbazı: yeni profilde ekstreler, hesaplar, kredi kartları, krediler, gelir ve düzenli
// ödemeler adım adım eklenir. Her adım atlanabilir; uygulama yarıda kapanırsa kaldığı adımdan
// açılır. Ayarlar › Veri › Kurulum sihirbazı ile yeniden açılır.

import 'package:flutter/material.dart';

import '../../motor/motorlar.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../celebrate.dart';
import '../glass.dart';
import '../i18n.dart';
import '../sheet.dart';
import '../sheets/debts.dart' show readDay;
import '../state.dart';
import '../theme.dart';
import '../ui.dart';
import 'common.dart';

/// Sihirbaz adımlarının arka plan fotoğrafları (eklenenlerin sonra görüneceği sayfanınki).
const Map<String, String> kSetupCovers = {
  'ekstre': 'highrise',
  'hesaplar': 'villa',
  'kartlar': 'mountain',
  'krediler': 'mountain',
  'gelir': 'highrise',
  'giderler': 'courtyard',
  'bitti': 'highrise',
};

class _StepInfo {
  const _StepInfo(this.label, this.icon, this.title, this.lead);
  final Lbl label;
  final IconData icon;
  final Lbl title;
  final Lbl lead;
}

const Map<String, _StepInfo> _steps = {
  'ekstre': _StepInfo(
    Lbl('Ekstreler', 'Statements'),
    Icons.description_outlined,
    Lbl('Elinde ekstre var mı?', 'Do you have statements?'),
    Lbl('Kredi kartı ve banka hesabı ekstrelerin (PDF ya da Excel) varsa, Mel Capital onları okuyup kartlarını, hesaplarını ve harcamalarını kendisi ekleyebilecek.',
        'If you have credit card and bank statements (PDF or Excel), Mel Capital will be able to read them and fill in your cards, accounts and spending by itself.'),
  ),
  'hesaplar': _StepInfo(
    Lbl('Hesaplar', 'Accounts'),
    Icons.account_balance_outlined,
    Lbl('Banka hesapların', 'Your bank accounts'),
    Lbl('Hangi bankalarda hesabın var, içinde ne kadar para var? Bugün harcayabileceğin para bunlardan hesaplanır.',
        'Which banks do you have accounts with, and how much is in them? What you can spend today is worked out from these.'),
  ),
  'kartlar': _StepInfo(
    Lbl('Kredi kartları', 'Credit cards'),
    Icons.credit_card,
    Lbl('Kredi kartların', 'Your credit cards'),
    Lbl('Bankanın uygulamasında gördüğün limiti ve güncel borcu yaz. Kesim ve son ödeme günleriyle kart ödemelerin takvime girer.',
        'Type the limit and current debt your bank app shows. With the statement and due days, card payments go on your calendar.'),
  ),
  'krediler': _StepInfo(
    Lbl('Krediler', 'Loans'),
    Icons.request_quote_outlined,
    Lbl('Kredilerin', 'Your loans'),
    Lbl('İhtiyaç kredisi, KYK, taşıt kredisi ya da yapılandırma… Aylık taksiti ve kalan taksit sayısını yazman yeterli.',
        'Personal loan, student loan, car loan or a restructured debt… The monthly instalment and how many are left is enough.'),
  ),
  'gelir': _StepInfo(
    Lbl('Gelir', 'Income'),
    Icons.payments_outlined,
    Lbl('Gelirin', 'Your income'),
    Lbl('Maaşın ya da düzenli gelirin. Ay sonuna kadar ne kadar serbest paran kalacağı buna göre hesaplanır.',
        'Your salary or regular income. How much is left free until the end of the month is worked out from it.'),
  ),
  'giderler': _StepInfo(
    Lbl('Düzenli ödemeler', 'Regular payments'),
    Icons.autorenew,
    Lbl('Düzenli ödemelerin', 'Your regular payments'),
    Lbl('Kira, faturalar ve abonelikler. Birine dokun, aylık tutarını yaz, ekle.',
        'Rent, bills and subscriptions. Tap one, type the monthly amount, add it.'),
  ),
  'bitti': _StepInfo(
    Lbl('Hazır', 'Ready'),
    Icons.flag_outlined,
    Lbl('Hazırsın!', 'You\'re all set!'),
    Lbl('Mel Capital artık senin rakamlarınla çalışıyor.', 'Mel Capital now runs on your own figures.'),
  ),
};

/// Adımdaki yarım kalmış formu "İleri"de kaydetmek için: form kendini buraya bağlar.
class _StepHook {
  bool Function()? flush;
}

abstract class _HookedStep extends StatefulWidget {
  const _HookedStep({required this.hook});
  final _StepHook hook;
}

/// Formun yarım kalan girişini kaydeder: boşsa true, geçerliyse ekleyip true, hatalıysa false.
mixin _Flushable<T extends _HookedStep> on State<T> {
  bool flush();

  @override
  void initState() {
    super.initState();
    widget.hook.flush = flush;
  }

  @override
  void dispose() {
    if (widget.hook.flush == flush) widget.hook.flush = null;
    super.dispose();
  }
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _hook = _StepHook();

  static int _count(Data d, String step) => switch (step) {
        'hesaplar' => d.accounts.length,
        'kartlar' => d.debts.where((x) => x.isCard).length,
        'krediler' => d.debts.where((x) => !x.isCard).length,
        'gelir' => d.incomes.length,
        'giderler' => d.subscriptions.length + d.recurringExpenses.length,
        _ => 0,
      };

  /// Adım değiştirir; formda yarım kalan geçerli bir giriş varsa önce eklenir.
  void _go(AppState st, String step) {
    final f = _hook.flush;
    if (f != null && !f()) return;
    st.setSetupStep(step);
  }

  void _later(BuildContext context, AppState st) {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final f = _hook.flush;
    if (f != null && !f()) return;
    st.setSetupStep(null);
    showToast(
      messenger,
      s.lang,
      s.pick('Kurulumu Ayarlar › Veri bölümünden istediğin zaman yeniden açabilirsin.', 'You can reopen the setup any time from Settings › Data.'),
      seconds: 5,
    );
  }

  void _finish(BuildContext context, AppState st) {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final overlay = Overlay.of(context, rootOverlay: true);
    st.setSetupStep(null);
    st.setTab(AppTab.ozet);
    showToast(messenger, s.lang, s.pick('Kurulum tamam. Hoş geldin!', 'Setup complete. Welcome!'));
    celebrateOn(overlay);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final step = st.setupStep ?? kFirstSetupStep;
    final i = kSetupSteps.indexOf(step);
    final info = _steps[step]!;
    final name = st.profile?.name ?? '';
    final title = step == 'bitti' && name.isNotEmpty ? s.pick('Hazırsın, $name!', 'You\'re all set, $name!') : info.title.of(s.lang);
    final counts = {for (final x in kSetupSteps) x: _count(d, x)};
    final Widget content = switch (step) {
      'ekstre' => _StatementStep(onNext: () => _go(st, 'hesaplar')),
      'hesaplar' => _AccountsStep(hook: _hook),
      'kartlar' => _CardsStep(hook: _hook),
      'krediler' => _LoansStep(hook: _hook),
      'gelir' => _IncomeStep(hook: _hook),
      'giderler' => _CostsStep(hook: _hook),
      _ => const _DoneStep(),
    };
    final nav = Row(
      children: [
        if (i > 0) ...[
          GlassButton(
            key: const ValueKey<String>('setup-back'),
            label: s.pick('Geri', 'Back'),
            icon: Icons.arrow_back,
            onTap: () => st.setSetupStep(kSetupSteps[i - 1]),
          ),
          const SizedBox(width: 6),
        ],
        // Dar ekranda kısa yazılır ve gerekirse kısalır; düğmeler hiç taşmaz.
        Expanded(
          child: step == 'bitti'
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey<String>('setup-later'),
                    onPressed: () => _later(context, st),
                    style: TextButton.styleFrom(foregroundColor: MC.text),
                    child: Text(
                      isPhoneLayout(context) ? s.pick('Sonra bitir', 'Later') : s.pick('Kurulumu sonra bitir', 'Finish setup later'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13.5, weight: FontWeight.w600, shadows: kPhotoTextShadow),
                    ),
                  ),
                ),
        ),
        if (step == 'bitti')
          GoldButton(
            key: const ValueKey<String>('setup-finish'),
            label: s.pick('Mel Capital\'i aç', 'Open Mel Capital'),
            icon: Icons.check,
            onTap: () => _finish(context, st),
          )
        else if (step != 'ekstre')
          GoldButton(
            key: const ValueKey<String>('setup-next'),
            label: counts[step]! > 0 ? s.pick('İleri', 'Next') : s.pick('Bu adımı geç', 'Skip this step'),
            icon: Icons.arrow_forward,
            onTap: () => _go(st, kSetupSteps[i + 1]),
          ),
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          key: ValueKey<String>('head-$step'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.pick('KURULUM · ADIM ${i + 1} / ${kSetupSteps.length}', 'SETUP · STEP ${i + 1} OF ${kSetupSteps.length}'),
                style: sans(11.5, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.6, shadows: kPhotoTextShadow),
              ),
              const SizedBox(height: 6),
              Text(title, style: serif(46, shadows: kPhotoTextShadow)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(info.lead.of(s.lang), style: sans(15, color: MC.muted, height: 1.45, shadows: kPhotoTextShadow)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        KeyedSubtree(key: ValueKey<String>('step-$step'), child: content),
        const SizedBox(height: 12),
      ],
    );
    Widget limit(Widget child) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: child),
        );
    // İçerik kayar; alttaki düğmeler hep görünür kalır.
    final column = Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: limit(body),
          ),
        ),
        // Düğmeler açık renkli fotoğraflarda da okunsun diye ince bir cam şerit üstünde durur
        // (ekstre adımında yalnızca "sonra bitir" olduğu için şeritsiz).
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
          child: limit(
            step == 'ekstre'
                ? nav
                : GlassPanel(radius: 18, cut: 18, animate: false, padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), child: nav),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 1100) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepStrip(current: step, onTap: (x) => _go(st, x)),
                const SizedBox(height: 8),
                Expanded(child: column),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 250,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 16, bottom: 16),
                  child: _StepRail(current: step, counts: counts, onTap: (x) => _go(st, x)),
                ),
              ),
              const SizedBox(width: 40),
              Expanded(child: column),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Adım listesi

/// Soldaki adım listesi: geçilen adımlar işaretli, açık adım altın halkalı.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.current, required this.counts, required this.onTap});

  final String current;
  final Map<String, int> counts;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ci = kSetupSteps.indexOf(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var n = 0; n < kSetupSteps.length; n++)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(kSetupSteps[n]),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      _StepDot(state: n < ci ? 2 : (n == ci ? 1 : 0), icon: _steps[kSetupSteps[n]]!.icon),
                      if (n < kSetupSteps.length - 1)
                        Container(
                          width: 2,
                          height: 24,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: n < ci ? MC.gold.withValues(alpha: 0.6) : const Color(0x38FFFFFF),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: _steps[kSetupSteps[n]]!.label.of(s.lang)),
                          if ((counts[kSetupSteps[n]] ?? 0) > 0)
                            TextSpan(text: '  ${counts[kSetupSteps[n]]}', style: const TextStyle(color: MC.gold)),
                        ]),
                        style: sans(
                          15,
                          weight: n == ci ? FontWeight.w700 : FontWeight.w600,
                          color: n == ci ? MC.text : (n < ci ? MC.muted : MC.dim),
                          shadows: kPhotoTextShadow,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Adım noktası: 0 sıradaki, 1 açık, 2 geçildi.
class _StepDot extends StatelessWidget {
  const _StepDot({required this.state, required this.icon});

  final int state;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: state == 2 ? MC.gold : (state == 1 ? const Color(0x59000000) : const Color(0x33000000)),
        shape: SignatureBorder(
          cut: 9,
          radius: 10,
          side: BorderSide(color: state == 0 ? const Color(0x52FFFFFF) : MC.gold, width: state == 1 ? 2 : 1),
        ),
        shadows: const [BoxShadow(color: Color(0x59000000), blurRadius: 10)],
      ),
      child: Icon(state == 2 ? Icons.check : icon, size: 17, color: state == 2 ? MC.ink : (state == 1 ? MC.gold : MC.dim)),
    );
  }
}

/// Dar ekranda adımlar: yatay sıra.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.current, required this.onTap});

  final String current;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final ci = kSetupSteps.indexOf(current);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var n = 0; n < kSetupSteps.length; n++) ...[
            GestureDetector(
              onTap: () => onTap(kSetupSteps[n]),
              child: _StepDot(state: n < ci ? 2 : (n == ci ? 1 : 0), icon: _steps[kSetupSteps[n]]!.icon),
            ),
            if (n < kSetupSteps.length - 1)
              Container(
                width: 22,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: n < ci ? MC.gold.withValues(alpha: 0.6) : const Color(0x38FFFFFF),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Ortak parçalar

/// Adım paneli: üstte ekleme formu, altta eklenenler.
class _StepPanel extends StatelessWidget {
  const _StepPanel({
    required this.formTitle,
    required this.form,
    required this.listTitle,
    required this.items,
    required this.empty,
    this.addLabel,
    this.onAdd,
    this.error,
    this.extra,
  });

  final String formTitle;
  final List<Widget> form;
  final String? addLabel;
  final VoidCallback? onAdd;
  final String? error;
  final Widget? extra;
  final String listTitle;
  final List<Widget> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 28,
      cut: 28,
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(formTitle, style: serif(26)),
          const SizedBox(height: 14),
          ...form,
          if (error != null && error!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: MC.rose, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error!, style: sans(13, color: MC.rose))),
                ],
              ),
            ),
          if (addLabel != null || extra != null)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (addLabel != null)
                  GoldButton(key: const ValueKey<String>('setup-add'), label: addLabel!, icon: Icons.add, onTap: onAdd),
                if (extra != null) extra!,
              ],
            ),
          const SizedBox(height: 18),
          const Hairline(),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(listTitle, style: serif(22)),
              if (items.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('${items.length}', style: sans(13, color: MC.gold, weight: FontWeight.w700)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty) Text(empty, style: sans(13, color: MC.muted, height: 1.4)) else ...items,
        ],
      ),
    );
  }
}

/// Eklenen kayıt satırı: dokununca ayrıntılı düzenleme paneli açılır.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.leading, required this.title, this.subtitle, this.k, required this.onEdit, this.onDelete});

  final Widget leading;
  final String title;
  final String? subtitle;
  final int? k;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return RowItem(
      leading: leading,
      title: title,
      subtitle: subtitle,
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (k != null) MoneyText(k!, style: sans(14.5, weight: FontWeight.w700)),
          // Telefonda satıra dokunmak düzenler; ayrı düğmeye yer yok.
          if (!isPhoneLayout(context))
            IconButton(
              tooltip: s.pick('Düzenle', 'Edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18, color: MC.muted),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: s.pick('Sil', 'Delete'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18, color: MC.rose),
            ),
        ],
      ),
    );
  }
}

/// Silme (geri alınabilir).
void _remove(BuildContext context, String message, void Function(Data d) change) {
  final st = AppScope.of(context);
  final snap = st.snapshot();
  st.update(change);
  toast(context, message, undo: () => st.restore(snap));
}

/// Banka seçimi: logolu küçük düğmeler.
class _BankChips extends StatelessWidget {
  const _BankChips({required this.value, required this.onChanged, this.wallets = false, this.kyk = false, this.other = false});

  /// Seçili banka ('' = Diğer, null = seçilmedi).
  final String? value;
  final ValueChanged<String> onChanged;
  final bool wallets;
  final bool kyk;
  final bool other;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget chip(String key, String label) {
      final on = value == key;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey<String>('bank-${key.isEmpty ? 'diger' : key}'),
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: ShapeDecoration(
              color: on ? MC.gold.withValues(alpha: 0.2) : const Color(0x33000000),
              shape: SignatureBorder(cut: 9, radius: 10, side: BorderSide(color: on ? MC.gold : const Color(0x33FFFFFF), width: on ? 1.5 : 1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BankPlate(bankKey: key.isEmpty ? null : key, name: label, size: 20, icon: key.isEmpty ? Icons.more_horiz : null),
                const SizedBox(width: 8),
                Text(label, style: sans(13, weight: FontWeight.w600, color: on ? MC.text : MC.muted)),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in kBanks.entries)
          if ((!e.value.wallet || wallets) && (!e.value.notBank || kyk)) chip(e.key, e.value.name),
        if (other) chip('', s.pick('Diğer', 'Other')),
      ],
    );
  }
}

/// Satır alt yazısı parçalarını birleştirir.
String _join(List<String?> parts) => parts.where((p) => p != null && p.isNotEmpty).join(' · ');

// ---------------------------------------------------------------- 1. Ekstreler

class _StatementStep extends StatelessWidget {
  const _StatementStep({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    Widget doc(IconData icon, String label, Color color) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 76,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: color.withValues(alpha: 0.16),
                shape: SignatureBorder(cut: 14, radius: 12, side: BorderSide(color: color.withValues(alpha: 0.6))),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 8),
            Text(label, style: sans(12, weight: FontWeight.w700, color: MC.muted, letterSpacing: 0.6)),
          ],
        );
    const arrow = Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 22),
      child: Icon(Icons.arrow_forward, color: MC.gold, size: 22),
    );
    return GlassPanel(
      radius: 28,
      cut: 28,
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              doc(Icons.picture_as_pdf_outlined, 'PDF', MC.rose),
              const SizedBox(width: 10),
              doc(Icons.table_chart_outlined, 'EXCEL', MC.mint),
              arrow,
              doc(Icons.auto_awesome_outlined, 'MEL CAPITAL', MC.gold),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: MC.gold, borderRadius: BorderRadius.circular(20)),
                child: Text(s.pick('YAKINDA', 'COMING SOON'), style: sans(10.5, color: MC.ink, weight: FontWeight.w700, letterSpacing: 1.4, shadows: const [])),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.pick('Ekstre okuma bir sonraki güncellemede geliyor.', 'Statement reading arrives in the next update.'),
                    style: sans(15, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.pick(
              'Kart ekstrenden borcun, harcamaların ve taksitlerin; hesap ekstrenden de bakiyen ve hesap hareketlerin kendiliğinden eklenecek. Şimdilik bilgilerini birkaç adımda elle ekleyelim; ekstre okuma gelince eksikleri ekstrelerinle tamamlarsın.',
              'Your card statement will fill in your debt, spending and instalments; your bank statement your balance and transactions. For now let\'s add your details by hand in a few steps; once statement reading arrives, your statements fill the gaps.',
            ),
            style: sans(14, color: MC.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              GoldButton(
                key: const ValueKey<String>('setup-statements-later'),
                label: s.pick('Ekstrelerim var, gelince hatırlat', 'I have statements, remind me'),
                icon: Icons.notifications_active_outlined,
                onTap: () {
                  st.setSetting('statementsLater', true);
                  onNext();
                },
              ),
              GlassButton(
                key: const ValueKey<String>('setup-manual'),
                label: s.pick('Elle gireceğim', 'I\'ll type them in'),
                icon: Icons.edit_outlined,
                onTap: () {
                  st.setSetting('statementsLater', false);
                  onNext();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 2. Hesaplar

class _AccountsStep extends _HookedStep {
  const _AccountsStep({required super.hook});

  @override
  State<_AccountsStep> createState() => _AccountsStepState();
}

class _AccountsStepState extends State<_AccountsStep> with _Flushable<_AccountsStep> {
  final _balance = TextEditingController();
  String _bank = '';
  String _type = 'vadesiz';
  String? _error;

  @override
  void dispose() {
    _balance.dispose();
    super.dispose();
  }

  @override
  bool flush() => _add(quiet: true);

  bool _fail(String message) {
    setState(() => _error = message);
    return false;
  }

  bool _add({bool quiet = false}) {
    final s = S.of(context);
    final raw = _balance.text.trim();
    if (quiet && raw.isEmpty) return true;
    if (_bank.isEmpty) return _fail(s.pick('Önce bankayı seç.', 'Pick the bank first.'));
    final k = raw.isEmpty ? 0 : parseSigned(raw);
    if (k == null) return _fail(s.pick('Bakiye geçerli bir tutar değil (ör. 12.500,50).', 'The balance is not a valid amount (e.g. 12,500.50).'));
    final bank = _bank;
    final type = kBanks[bank]?.wallet == true ? 'cuzdan' : _type;
    final suffix = switch (type) {
      'vadesiz' => s.pick(' vadesiz', ' current'),
      'birikim' => s.pick(' birikim', ' savings'),
      _ => '',
    };
    final name = bankName(bank, s.lang) + suffix;
    AppScope.of(context).update((d) => saveAccount(d, bank: bank, name: name, type: type, balanceK: k));
    setState(() {
      _balance.clear();
      _bank = '';
      _error = null;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final wallet = kBanks[_bank]?.wallet == true;
    return _StepPanel(
      formTitle: s.pick('Hesap ekle', 'Add an account'),
      form: [
        FieldBox(
          label: s.pick('Banka', 'Bank'),
          child: _BankChips(value: _bank, wallets: true, onChanged: (v) => setState(() {
                _bank = v;
                _error = null;
              })),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Hesap türü', 'Account type'),
            child: wallet
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(s.pick('Dijital cüzdan', 'Digital wallet'), style: sans(14.5, weight: FontWeight.w600)),
                  )
                : Seg<String>(
                    value: _type,
                    options: [('vadesiz', s.pick('Vadesiz', 'Current')), ('birikim', s.pick('Birikim', 'Savings'))],
                    onChanged: (v) => setState(() => _type = v),
                  ),
          ),
          right: FieldBox(
            label: s.pick('İçindeki para', 'Balance'),
            child: TextInput(
              key: const ValueKey<String>('setup-acc-balance'),
              controller: _balance,
              number: true,
              suffix: 'TL',
              hint: s.pick('ör. 12.500', 'e.g. 12,500'),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _add(),
            ),
          ),
        ),
      ],
      error: _error,
      addLabel: s.pick('Hesabı ekle', 'Add account'),
      onAdd: () => _add(),
      extra: SmallButton(
        label: s.pick('Listede olmayan bir hesap', 'An account not listed'),
        icon: Icons.add_card_outlined,
        onTap: () => openAccountSheet(context, type: 'diger'),
      ),
      listTitle: s.pick('Hesapların', 'Your accounts'),
      empty: s.pick('Henüz hesap eklemedin.', 'No accounts yet.'),
      items: [
        for (final a in accountsSorted(d))
          _ItemRow(
            leading: BankPlate(bankKey: a.bank.isEmpty ? null : a.bank, name: a.name, size: 28, icon: a.isCash ? Icons.payments_outlined : null),
            title: accLabel(a, s.lang),
            subtitle: a.isCash && toK(a.balance) == 0
                ? s.pick('Cüzdanındaki nakdi yazmak için dokun', 'Tap to enter the cash in your wallet')
                : (kAccountTypes[a.type] ?? const Lbl('Hesap', 'Account')).of(s.lang),
            k: toK(a.balance),
            onEdit: () => openAccountSheet(context, account: a),
            onDelete: () => _remove(context, s.pick('Hesap silindi.', 'Account deleted.'), (data) => deleteAccount(data, a.id)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 3. Kredi kartları

class _CardsStep extends _HookedStep {
  const _CardsStep({required super.hook});

  @override
  State<_CardsStep> createState() => _CardsStepState();
}

class _CardsStepState extends State<_CardsStep> with _Flushable<_CardsStep> {
  final _name = TextEditingController();
  final _limit = TextEditingController();
  final _debt = TextEditingController();
  final _cut = TextEditingController();
  final _due = TextEditingController();
  String _bank = '';
  bool _bankTouched = false;
  String? _error;

  List<TextEditingController> get _all => [_name, _limit, _debt, _cut, _due];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  bool flush() => _add(quiet: true);

  bool _fail(String message) {
    setState(() => _error = message);
    return false;
  }

  bool _add({bool quiet = false}) {
    final s = S.of(context);
    if (quiet && _all.every((c) => c.text.trim().isEmpty)) return true;
    final name = _name.text.trim();
    if (name.isEmpty) return _fail(s.pick('Kartın adını yaz (ör. Axess, Bonus).', 'Type the card\'s name (e.g. Gold, Platinum).'));
    int? limitK;
    if (_limit.text.trim().isNotEmpty) {
      limitK = parseAmount(_limit.text);
      if (limitK == null) return _fail(s.pick('Limit geçerli bir tutar değil (ör. 25.000).', 'The limit is not a valid amount (e.g. 25,000).'));
    }
    final debtK = _debt.text.trim().isEmpty ? 0 : parseAmount(_debt.text);
    if (debtK == null) return _fail(s.pick('Güncel borç geçerli bir tutar değil (ör. 3.250,40).', 'The current debt is not a valid amount (e.g. 3,250.40).'));
    final (cut, e1) = readDay(_cut.text, s.pick('Hesap kesim günü', 'Statement day'), s.lang);
    if (e1 != null) return _fail(e1);
    final (due, e2) = readDay(_due.text, s.pick('Son ödeme günü', 'Due day'), s.lang);
    if (e2 != null) return _fail(e2);
    final bank = _bank;
    AppScope.of(context).update((d) => addSetupCard(d, name: name, bank: bank, debtK: debtK, limitK: limitK, cutDay: cut, dueDay: due));
    setState(() {
      for (final c in _all) {
        c.clear();
      }
      _bank = '';
      _bankTouched = false;
      _error = null;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final m = st.ctx.model;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    void changed(String _) => setState(() => _error = null);
    return _StepPanel(
      formTitle: s.pick('Kart ekle', 'Add a card'),
      form: [
        FieldBox(
          label: s.pick('Kartın adı', 'Card name'),
          child: TextInput(
            key: const ValueKey<String>('setup-card-name'),
            controller: _name,
            hint: s.pick('ör. Axess, Bonus, World', 'e.g. Gold, Platinum'),
            onChanged: (v) => setState(() {
              if (!_bankTouched) _bank = detectBank(v) ?? _bank;
              _error = null;
            }),
            onSubmitted: (_) => _add(),
          ),
        ),
        FieldBox(
          label: s.pick('Banka', 'Bank'),
          child: _BankChips(
            value: _bankTouched || _bank.isNotEmpty ? _bank : null,
            other: true,
            onChanged: (v) => setState(() {
              _bank = v;
              _bankTouched = true;
            }),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Limit', 'Limit'),
            child: TextInput(key: const ValueKey<String>('setup-card-limit'), controller: _limit, number: true, suffix: 'TL', hint: s.pick('ör. 25.000', 'e.g. 25,000'), onChanged: changed),
          ),
          right: FieldBox(
            label: s.pick('Güncel borç', 'Current debt'),
            child: TextInput(key: const ValueKey<String>('setup-card-debt'), controller: _debt, number: true, suffix: 'TL', hint: s.pick('ör. 3.250,40', 'e.g. 3,250.40'), onChanged: changed),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Hesap kesim günü', 'Statement day'),
            child: TextInput(key: const ValueKey<String>('setup-card-cut'), controller: _cut, number: true, hint: '1–31', onChanged: changed),
          ),
          right: FieldBox(
            label: s.pick('Son ödeme günü', 'Due day'),
            child: TextInput(key: const ValueKey<String>('setup-card-due'), controller: _due, number: true, hint: '1–31', onChanged: changed, onSubmitted: (_) => _add()),
          ),
        ),
      ],
      error: _error,
      addLabel: s.pick('Kartı ekle', 'Add card'),
      onAdd: () => _add(),
      listTitle: s.pick('Kartların', 'Your cards'),
      empty: s.pick('Henüz kart eklemedin. Kredi kartın yoksa bu adımı geçebilirsin.', 'No cards yet. If you have no credit card, skip this step.'),
      items: [
        for (final x in d.debts.where((x) => x.isCard))
          _ItemRow(
            leading: BankPlate(bankKey: bankKeyOf(x), name: x.creditor, size: 28),
            title: x.creditor,
            subtitle: _join([
              x.limit != null ? s.pick('limit ', 'limit ') + money(toK(x.limit)) : null,
              x.dueDay != null ? s.pick('son ödeme ${dayOfMonthText(x.dueDay!, 'tr')}', 'due ${dayOfMonthText(x.dueDay!, 'en')}') : null,
              paidBeforeStart(d, 'debt', x.id) ? s.pick('bu ayki ödeme yapılmış sayıldı', 'this month\'s payment counted as made') : null,
            ]),
            k: m.debts[x.id]?.current,
            onEdit: () => openDebtSheet(context, debt: x),
            onDelete: () => _remove(context, s.pick('Kart silindi.', 'Card deleted.'), (data) => deleteDebt(data, x.id)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 4. Krediler

class _LoansStep extends _HookedStep {
  const _LoansStep({required super.hook});

  @override
  State<_LoansStep> createState() => _LoansStepState();
}

class _LoansStepState extends State<_LoansStep> with _Flushable<_LoansStep> {
  final _name = TextEditingController();
  final _monthly = TextEditingController();
  final _count = TextEditingController();
  final _day = TextEditingController();
  final _rest = TextEditingController();
  String _type = 'kredi';
  String _bank = '';
  bool _bankTouched = false;
  String? _first;
  String? _error;

  List<TextEditingController> get _all => [_name, _monthly, _count, _day, _rest];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  bool flush() => _add(quiet: true);

  bool _fail(String message) {
    setState(() => _error = message);
    return false;
  }

  int? get _dayValue {
    final n = int.tryParse(_day.text.trim());
    return n != null && n >= 1 && n <= 31 ? n : null;
  }

  bool _add({bool quiet = false}) {
    final s = S.of(context);
    if (quiet && _all.every((c) => c.text.trim().isEmpty)) return true;
    final name = _name.text.trim();
    if (name.isEmpty) return _fail(s.pick('Kredinin adını yaz (ör. İhtiyaç kredisi).', 'Type the loan\'s name (e.g. Personal loan).'));
    final monthlyK = parseAmount(_monthly.text);
    if (monthlyK == null || monthlyK <= 0) return _fail(s.pick('Aylık taksiti yaz (ör. 2.730).', 'Type the monthly instalment (e.g. 2,730).'));
    final count = int.tryParse(_count.text.trim());
    if (count == null || count < 1 || count > 480) return _fail(s.pick('Kalan taksit sayısı 1 ile 480 arasında olmalı.', 'Instalments left must be between 1 and 480.'));
    final (day, e1) = readDay(_day.text, s.pick('Ödeme günü', 'Payment day'), s.lang);
    if (e1 != null) return _fail(e1);
    int? restK;
    if (_rest.text.trim().isNotEmpty) {
      restK = parseAmount(_rest.text);
      if (restK == null || restK <= 0) return _fail(s.pick('Kalan borç geçerli bir tutar değil.', 'The remaining balance is not a valid amount.'));
    }
    final first = _first ?? nextInstallmentMonth(day);
    final type = _type, bank = _bank;
    AppScope.of(context).update((d) => addSetupLoan(d, name: name, type: type, bank: bank, monthlyK: monthlyK, count: count, first: first, payDay: day, restK: restK));
    setState(() {
      for (final c in _all) {
        c.clear();
      }
      _type = 'kredi';
      _bank = '';
      _bankTouched = false;
      _first = null;
      _error = null;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final m = st.ctx.model;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    void changed(String _) => setState(() => _error = null);
    final monthlyK = parseAmount(_monthly.text);
    final count = int.tryParse(_count.text.trim());
    final restHint = monthlyK != null && count != null && count > 0
        ? s.pick('Boş bırakırsan taksit × taksit sayısı sayılır: ${money(monthlyK * count)}.', 'If left empty, instalment × count is used: ${money(monthlyK * count)}.')
        : s.pick('Boş bırakırsan taksit × taksit sayısı sayılır.', 'If left empty, instalment × count is used.');
    return _StepPanel(
      formTitle: s.pick('Kredi ekle', 'Add a loan'),
      form: [
        FieldBox(
          label: s.pick('Adı', 'Name'),
          child: TextInput(
            key: const ValueKey<String>('setup-loan-name'),
            controller: _name,
            hint: s.pick('ör. İhtiyaç kredisi, KYK', 'e.g. Personal loan'),
            onChanged: (v) => setState(() {
              if (!_bankTouched) _bank = detectBank(v) ?? _bank;
              _error = null;
            }),
          ),
        ),
        FieldBox(
          label: s.pick('Türü', 'Type'),
          child: Seg<String>(
            value: _type,
            options: [
              ('kredi', s.pick('Kredi', 'Loan')),
              ('kyk', 'KYK'),
              ('yapilandirma', s.pick('Yapılandırma', 'Restructured')),
              ('diger', s.pick('Diğer', 'Other')),
            ],
            onChanged: (v) => setState(() {
              _type = v;
              if (v == 'kyk' && !_bankTouched) _bank = 'kyk';
            }),
          ),
        ),
        FieldBox(
          label: s.pick('Banka (isteğe bağlı)', 'Bank (optional)'),
          child: _BankChips(
            value: _bankTouched || _bank.isNotEmpty ? _bank : null,
            kyk: true,
            other: true,
            onChanged: (v) => setState(() {
              _bank = v;
              _bankTouched = true;
            }),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Aylık taksit', 'Monthly instalment'),
            child: TextInput(key: const ValueKey<String>('setup-loan-monthly'), controller: _monthly, number: true, suffix: 'TL', hint: s.pick('ör. 2.730', 'e.g. 2,730'), onChanged: changed),
          ),
          right: FieldBox(
            label: s.pick('Kalan taksit sayısı', 'Instalments left'),
            child: TextInput(key: const ValueKey<String>('setup-loan-count'), controller: _count, number: true, hint: s.pick('ör. 13', 'e.g. 13'), onChanged: changed),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Ödeme günü', 'Payment day'),
            child: TextInput(key: const ValueKey<String>('setup-loan-day'), controller: _day, number: true, hint: '1–31', onChanged: changed),
          ),
          right: FieldBox(
            label: s.pick('Sıradaki taksit', 'Next instalment'),
            child: MonthInput(value: _first ?? nextInstallmentMonth(_dayValue), onChanged: (v) => setState(() => _first = v)),
          ),
        ),
        FieldBox(
          label: s.pick('Kalan borç (isteğe bağlı)', 'Remaining balance (optional)'),
          help: restHint,
          child: TextInput(key: const ValueKey<String>('setup-loan-rest'), controller: _rest, number: true, suffix: 'TL', onChanged: changed, onSubmitted: (_) => _add()),
        ),
      ],
      error: _error,
      addLabel: s.pick('Krediyi ekle', 'Add loan'),
      onAdd: () => _add(),
      listTitle: s.pick('Kredilerin', 'Your loans'),
      empty: s.pick('Henüz kredi eklemedin. Kredin yoksa bu adımı geçebilirsin.', 'No loans yet. If you have none, skip this step.'),
      items: [
        for (final x in d.debts.where((x) => !x.isCard))
          _ItemRow(
            leading: BankPlate(bankKey: bankKeyOf(x), name: x.creditor, size: 28),
            title: x.creditor,
            subtitle: _loanLine(x, s, money),
            k: m.debts[x.id]?.current,
            onEdit: () => openDebtSheet(context, debt: x),
            onDelete: () => _remove(context, s.pick('Kredi silindi.', 'Loan deleted.'), (data) => deleteDebt(data, x.id)),
          ),
      ],
    );
  }

  static String _loanLine(Debt x, S s, String Function(int) money) {
    final cur = currentMonth();
    final rows = x.schedule.where((r) => r.to == null || r.to!.compareTo(cur) >= 0).toList()..sort((a, b) => a.from.compareTo(b.from));
    final last = rows.isEmpty ? null : rows.last.to;
    var left = 0;
    for (final r in rows) {
      final from = maxMonth(r.from, cur);
      if (r.to != null) left += mDiff(from, r.to!) + 1;
    }
    return _join([
      rows.isEmpty ? null : s.pick('${money(toK(rows.first.amount))}/ay', '${money(toK(rows.first.amount))}/mo'),
      left > 0 ? s.pick('$left taksit', '$left instalments') : null,
      x.payDay != null ? dayOfMonthText(x.payDay!, s.lang) : null,
      last != null ? s.pick('son taksit ${monthLabel(last, 'tr')}', 'last ${monthLabel(last, 'en')}') : null,
    ]);
  }
}

// ---------------------------------------------------------------- 5. Gelir

class _IncomeStep extends _HookedStep {
  const _IncomeStep({required super.hook});

  @override
  State<_IncomeStep> createState() => _IncomeStepState();
}

class _IncomeStepState extends State<_IncomeStep> with _Flushable<_IncomeStep> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController();
  final _gross = TextEditingController();
  String? _account;
  bool _isGross = false;
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _name.text = S.of(context).pick('Maaş', 'Salary');
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _day, _gross]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  bool flush() => _add(quiet: true);

  bool _fail(String message) {
    setState(() => _error = message);
    return false;
  }

  bool _add({bool quiet = false}) {
    final s = S.of(context);
    if (quiet && _amount.text.trim().isEmpty) return true;
    final name = _name.text.trim();
    if (name.isEmpty) return _fail(s.pick('Gelirin adını yaz (ör. Maaş).', 'Type a name (e.g. Salary).'));
    int? grossK;
    if (_isGross) {
      grossK = parseAmount(_gross.text);
      if (grossK == null || grossK <= 0) return _fail(s.pick('Brüt tutarı yaz (ör. 60.000).', 'Type the gross amount (e.g. 60,000).'));
    }
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) {
      return _fail(_isGross
          ? s.pick('Hesabına yatan net tutarı da yaz (ör. 45.000).', 'Also type the net amount you receive (e.g. 45,000).')
          : s.pick('Aylık tutarı yaz (ör. 45.000).', 'Type the monthly amount (e.g. 45,000).'));
    }
    final (day, e) = readDay(_day.text, s.pick('Yatış günü', 'Pay day'), s.lang);
    if (e != null) return _fail(e);
    final account = _account, gross = _isGross;
    AppScope.of(context).update((d) => addSetupIncome(d, name: name, k: k, payDay: day, account: account, gross: gross, grossK: grossK));
    setState(() {
      _name.text = s.pick('Ek gelir', 'Other income');
      _amount.clear();
      _day.clear();
      _gross.clear();
      _isGross = false;
      _error = null;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final cur = currentMonth();
    void changed(String _) => setState(() => _error = null);
    return _StepPanel(
      formTitle: s.pick('Gelir ekle', 'Add income'),
      form: [
        FieldBox(
          label: s.pick('Adı', 'Name'),
          child: TextInput(key: const ValueKey<String>('setup-income-name'), controller: _name, onChanged: changed),
        ),
        FieldBox(
          label: s.pick('Tutar net mi, brüt mü?', 'Is the amount net or gross?'),
          child: Seg<bool>(
            key: const ValueKey<String>('setup-income-basis'),
            value: _isGross,
            options: [(false, s.pick('Net (hesabına yatan)', 'Net (what you receive)')), (true, s.pick('Brüt', 'Gross'))],
            onChanged: (v) => setState(() {
              _isGross = v;
              _error = null;
            }),
          ),
        ),
        if (_isGross)
          FieldBox(
            label: s.pick('Brüt tutar', 'Gross amount'),
            help: s.pick('Bilgi olarak saklanır; plan hesabına yatan net tutarla çalışır.', 'Kept for reference; the plan works with what you actually receive.'),
            child: TextInput(key: const ValueKey<String>('setup-income-gross'), controller: _gross, number: true, suffix: 'TL', onChanged: changed),
          ),
        FieldPair(
          left: FieldBox(
            label: _isGross ? s.pick('Hesabına yatan net tutar', 'Net amount you receive') : s.pick('Aylık tutar', 'Monthly amount'),
            child: TextInput(key: const ValueKey<String>('setup-income-amount'), controller: _amount, number: true, suffix: 'TL', hint: s.pick('ör. 45.000', 'e.g. 45,000'), onChanged: changed),
          ),
          right: FieldBox(
            label: s.pick('Yatış günü', 'Pay day'),
            child: TextInput(key: const ValueKey<String>('setup-income-day'), controller: _day, number: true, hint: '1–31', onChanged: changed, onSubmitted: (_) => _add()),
          ),
        ),
        FieldBox(
          label: s.pick('Hangi hesaba yatıyor?', 'Paid into which account?'),
          help: s.pick('Yattığını onaylayınca bu hesabın bakiyesine eklenir.', 'When you confirm it arrived, it is added to this account.'),
          child: SourceSelect(key: const ValueKey<String>('setup-income-account'), value: _account, cards: false, none: s.pick('Seçilmedi', 'Not chosen'), onChanged: (v) => setState(() => _account = v)),
        ),
      ],
      error: _error,
      addLabel: s.pick('Geliri ekle', 'Add income'),
      onAdd: () => _add(),
      listTitle: s.pick('Gelirlerin', 'Your income'),
      empty: s.pick('Henüz gelir eklemedin.', 'No income yet.'),
      items: [
        for (final x in d.incomes)
          _ItemRow(
            leading: const CategoryMark('nakit', size: 34, icon: Icons.payments_outlined),
            title: x.name,
            subtitle: _join([s.pick('her ay', 'monthly'), x.payDay != null ? dayOfMonthText(x.payDay!, s.lang) : null]),
            k: schedK(x.schedule, cur),
            onEdit: () => openIncomeSheet(context, income: x),
            onDelete: () => _remove(context, s.pick('Gelir silindi.', 'Income deleted.'), (data) => deleteIncome(data, x.id)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 6. Düzenli ödemeler

class _Preset {
  const _Preset(this.tr, this.en, this.group, this.icon, {this.expense = false});
  final String tr;
  final String en;
  final String group;
  final IconData icon;
  final bool expense;
  String name(String lang) => lang == 'tr' ? tr : en;
}

const List<_Preset> _homePresets = [
  _Preset('Kira', 'Rent', 'kira', Icons.home_outlined, expense: true),
  _Preset('Aidat', 'Building fee', 'fatura', Icons.apartment_outlined),
  _Preset('Elektrik', 'Electricity', 'fatura', Icons.bolt_outlined),
  _Preset('Doğalgaz', 'Gas', 'fatura', Icons.local_fire_department_outlined),
  _Preset('Su', 'Water', 'fatura', Icons.water_drop_outlined),
  _Preset('İnternet', 'Internet', 'fatura', Icons.wifi),
  _Preset('Telefon', 'Phone', 'fatura', Icons.smartphone),
];

const List<_Preset> _subPresets = [
  _Preset('Netflix', 'Netflix', 'video', Icons.movie_outlined),
  _Preset('Spotify Premium', 'Spotify Premium', 'muzik', Icons.music_note_outlined),
  _Preset('YouTube Premium', 'YouTube Premium', 'video', Icons.smart_display_outlined),
  _Preset('Amazon Prime', 'Amazon Prime', 'video', Icons.local_shipping_outlined),
  _Preset('Disney+', 'Disney+', 'video', Icons.movie_outlined),
  _Preset('ChatGPT Plus', 'ChatGPT Plus', 'yz', Icons.auto_awesome_outlined),
  _Preset('Claude Pro', 'Claude Pro', 'yz', Icons.auto_awesome_outlined),
  _Preset('iCloud+', 'iCloud+', 'bulut', Icons.cloud_outlined),
  _Preset('Google One', 'Google One', 'bulut', Icons.cloud_outlined),
  _Preset('Xbox Game Pass', 'Xbox Game Pass', 'oyun', Icons.sports_esports_outlined),
  _Preset('PlayStation Plus', 'PlayStation Plus', 'oyun', Icons.sports_esports_outlined),
  _Preset('Spor salonu', 'Gym', 'spor', Icons.fitness_center),
];

/// "Başka bir şey" (adı ve türü elle seçilir).
const _Preset _custom = _Preset('', '', 'diger', Icons.add);

class _CostsStep extends _HookedStep {
  const _CostsStep({required super.hook});

  @override
  State<_CostsStep> createState() => _CostsStepState();
}

class _CostsStepState extends State<_CostsStep> with _Flushable<_CostsStep> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController();
  _Preset? _sel;
  String _kind = 'sub';
  String? _source;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _amount, _day]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  bool flush() => _add(quiet: true);

  bool _fail(String message) {
    setState(() => _error = message);
    return false;
  }

  void _pick(_Preset p, String lang) {
    setState(() {
      _sel = p;
      _name.text = p.name(lang);
      _kind = 'sub';
      _error = null;
    });
  }

  bool _add({bool quiet = false}) {
    final p = _sel;
    if (p == null) return true;
    final s = S.of(context);
    if (quiet && _amount.text.trim().isEmpty) return true;
    final name = _name.text.trim();
    if (name.isEmpty) return _fail(s.pick('Adını yaz.', 'Type a name.'));
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) return _fail(s.pick('Aylık tutarı yaz (ör. 229,99).', 'Type the monthly amount (e.g. 229.99).'));
    final (day, e) = readDay(_day.text, s.pick('Ödeme günü', 'Payment day'), s.lang);
    if (e != null) return _fail(e);
    final custom = identical(p, _custom);
    final expense = custom ? _kind == 'expense' : p.expense;
    final group = custom ? (_kind == 'expense' ? guessCategory(name) : (_kind == 'fatura' ? 'fatura' : 'diger')) : p.group;
    final source = expense ? null : _source;
    AppScope.of(context).update((d) => addSetupCost(d, name: name, expense: expense, group: group, k: k, day: day, source: source));
    setState(() {
      _sel = null;
      _name.clear();
      _amount.clear();
      _day.clear();
      _source = null;
      _error = null;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final cur = currentMonth();
    final have = {
      for (final x in d.subscriptions) normTxt(x.name),
      for (final x in d.recurringExpenses) normTxt(x.name),
    };
    Widget chip(_Preset p) {
      final on = identical(_sel, p);
      final label = identical(p, _custom) ? s.pick('Başka bir şey', 'Something else') : p.name(s.lang);
      final added = !identical(p, _custom) && have.contains(normTxt(label));
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey<String>('cost-${slugify(identical(p, _custom) ? 'baska' : p.tr)}'),
          onTap: () => _pick(p, s.lang),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            decoration: ShapeDecoration(
              color: on ? MC.gold.withValues(alpha: 0.22) : (added ? MC.mint.withValues(alpha: 0.12) : const Color(0x33000000)),
              shape: SignatureBorder(
                cut: 9,
                radius: 10,
                side: BorderSide(color: on ? MC.gold : (added ? MC.mint.withValues(alpha: 0.6) : const Color(0x33FFFFFF)), width: on ? 1.5 : 1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(added ? Icons.check : p.icon, size: 16, color: added ? MC.mint : (on ? MC.gold : MC.muted)),
                const SizedBox(width: 7),
                Text(label, style: sans(13, weight: FontWeight.w600, color: on ? MC.text : MC.muted)),
              ],
            ),
          ),
        ),
      );
    }

    final p = _sel;
    final custom = p != null && identical(p, _custom);
    final expense = p != null && (custom ? _kind == 'expense' : p.expense);
    void changed(String _) => setState(() => _error = null);
    final items = <Widget>[
      for (final x in d.recurringExpenses)
        _ItemRow(
          leading: CategoryMark(x.category, size: 34),
          title: x.name,
          subtitle: _join([
            s.pick('her ay', 'monthly'),
            x.day != null ? dayOfMonthText(x.day!, s.lang) : null,
            paidBeforeStart(d, 'expense', x.id) ? s.pick('bu ayki ödenmiş sayıldı', 'this month counted as paid') : null,
          ]),
          k: toK(x.amount),
          onEdit: () => openExpenseSheet(context, expense: x),
          onDelete: () => _remove(context, s.pick('Silindi.', 'Deleted.'), (data) => deleteExpense(data, x.id)),
        ),
      for (final x in d.subscriptions)
        _ItemRow(
          leading: CategoryMark(x.isBill ? 'fatura' : 'abonelik', size: 34),
          title: x.name,
          subtitle: _join([
            x.period == 'yil' ? s.pick('her yıl', 'yearly') : s.pick('her ay', 'monthly'),
            x.day != null ? dayOfMonthText(x.day!, s.lang) : null,
            x.source != null ? sourceName(d, x.source, s.lang) : null,
            paidBeforeStart(d, 'sub', x.id) ? s.pick('bu ayki ödenmiş sayıldı', 'this month counted as paid') : null,
          ]),
          k: subAmountK(x, cur),
          onEdit: () => openSubSheet(context, sub: x),
          onDelete: () => _remove(context, s.pick('Silindi.', 'Deleted.'), (data) => deleteSubscription(data, x.id)),
        ),
    ];
    return _StepPanel(
      formTitle: s.pick('Ne ödüyorsun?', 'What do you pay?'),
      form: [
        Text(s.pick('Ev', 'Home'), style: sans(12.5, weight: FontWeight.w600, color: MC.label)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final x in _homePresets) chip(x)]),
        const SizedBox(height: 14),
        Text(s.pick('Abonelikler', 'Subscriptions'), style: sans(12.5, weight: FontWeight.w600, color: MC.label)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final x in _subPresets) chip(x), chip(_custom)]),
        const SizedBox(height: 16),
        if (p != null) ...[
          if (custom)
            FieldBox(
              label: s.pick('Türü', 'Type'),
              child: Seg<String>(
                value: _kind,
                options: [
                  ('sub', s.pick('Abonelik', 'Subscription')),
                  ('fatura', s.pick('Fatura', 'Bill')),
                  ('expense', s.pick('Sabit gider', 'Fixed cost')),
                ],
                onChanged: (v) => setState(() => _kind = v),
              ),
            ),
          FieldPair(
            left: FieldBox(
              label: s.pick('Adı', 'Name'),
              child: TextInput(key: const ValueKey<String>('setup-cost-name'), controller: _name, autofocus: custom, onChanged: changed),
            ),
            right: FieldBox(
              label: s.pick('Aylık tutar', 'Monthly amount'),
              child: TextInput(
                key: const ValueKey<String>('setup-cost-amount'),
                controller: _amount,
                number: true,
                suffix: 'TL',
                autofocus: !custom,
                hint: s.pick('ör. 229,99', 'e.g. 229.99'),
                onChanged: changed,
                onSubmitted: (_) => _add(),
              ),
            ),
          ),
          FieldPair(
            left: FieldBox(
              label: s.pick('Ödeme günü', 'Payment day'),
              child: TextInput(key: const ValueKey<String>('setup-cost-day'), controller: _day, number: true, hint: '1–31', onChanged: changed, onSubmitted: (_) => _add()),
            ),
            right: expense
                ? const SizedBox.shrink()
                : FieldBox(
                    label: s.pick('Nereden ödeniyor?', 'Paid from'),
                    child: SourceSelect(value: _source, none: s.pick('Belirtmeyeceğim', 'Not specified'), onChanged: (v) => setState(() => _source = v)),
                  ),
          ),
        ],
      ],
      error: _error,
      addLabel: p != null ? s.pick('Ekle', 'Add') : null,
      onAdd: () => _add(),
      extra: p != null
          ? GlassButton(
              label: s.pick('Vazgeç', 'Cancel'),
              onTap: () => setState(() {
                _sel = null;
                _error = null;
              }),
            )
          : null,
      listTitle: s.pick('Düzenli ödemelerin', 'Your regular payments'),
      empty: s.pick('Henüz bir şey eklemedin. Yukarıdan birine dokun.', 'Nothing added yet. Tap one above.'),
      items: items,
    );
  }
}

// ---------------------------------------------------------------- 7. Hazır

class _DoneStep extends StatelessWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final m = st.ctx.model;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final acc = d.accounts.where((a) => !a.isCash || toK(a.balance) != 0).length;
    final cards = d.debts.where((x) => x.isCard).length;
    final loans = d.debts.length - cards;
    final incomes = d.incomes.length;
    final costs = d.subscriptions.length + d.recurringExpenses.length;
    final parts = [
      if (acc > 0) s.pick('$acc hesap', '$acc accounts'),
      if (cards > 0) s.pick('$cards kredi kartı', '$cards credit cards'),
      if (loans > 0) s.pick('$loans kredi', '$loans loans'),
      if (incomes > 0) s.pick('$incomes gelir', '$incomes incomes'),
      if (costs > 0) s.pick('$costs düzenli ödeme', '$costs regular payments'),
    ];
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: MC.gold),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: sans(14.5, height: 1.45))),
            ],
          ),
        );
    return GlassPanel(
      tint: MC.gold,
      radius: 30,
      cut: 30,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.pick('BUGÜN HARCAYABİLECEĞİN', 'WHAT YOU CAN SPEND TODAY'),
              style: sans(12, color: MC.eyebrow, weight: FontWeight.w700, letterSpacing: 2.2)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(m.liquid + m.cardAvail, count: true, style: serif(80, height: 1.0)),
          ),
          const SizedBox(height: 6),
          Text(
            s.pick('Hesaplarda ${money(m.liquid)} · kartlarda boş limit ${money(m.cardAvail)}',
                'In accounts ${money(m.liquid)} · available card limit ${money(m.cardAvail)}'),
            style: sans(13.5, color: MC.muted),
          ),
          const SizedBox(height: 18),
          const Hairline(),
          const SizedBox(height: 16),
          line(
            Icons.check_circle_outline,
            parts.isEmpty
                ? s.pick('Henüz bir şey eklemedin; hesaplarını ve kartlarını sayfalardan da ekleyebilirsin.',
                    'You haven\'t added anything yet; you can also add your accounts and cards from the pages.')
                : s.pick('${parts.join(', ')} eklendi.', 'Added ${parts.join(', ')}.'),
          ),
          if (m.totalRemaining > 0)
            line(
              Icons.balance_outlined,
              m.debtFree != null
                  ? s.pick('Toplam borcun ${money(m.totalRemaining)}. Bu gidişle son kredi taksitin: ${monthLabel(m.debtFree, 'tr')}.',
                      'Your total debt is ${money(m.totalRemaining)}. At this pace your last loan instalment is in ${monthLabel(m.debtFree, 'en')}.')
                  : s.pick('Toplam borcun ${money(m.totalRemaining)}.', 'Your total debt is ${money(m.totalRemaining)}.'),
            ),
          if (st.settings['statementsLater'] == true)
            line(Icons.notifications_active_outlined,
                s.pick('Ekstre okuma geldiğinde Mel Capital sana hatırlatacak.', 'Mel Capital will remind you when statement reading arrives.')),
          line(Icons.tune, s.pick('Bu kurulumu Ayarlar › Veri bölümünden istediğin zaman yeniden açabilirsin.', 'You can reopen this setup any time from Settings › Data.')),
        ],
      ),
    );
  }
}
