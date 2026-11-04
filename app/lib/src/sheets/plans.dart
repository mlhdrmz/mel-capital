// Plan kayıtları: abonelik, fatura tutarı, sabit gider, gelir, istek listesi, Findeks,
// harcama tahmini ve ay kapatma.

import 'package:flutter/material.dart';

import '../../core/actions.dart';
import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../dialogs.dart';
import '../i18n.dart';
import '../sheet.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';
import 'debts.dart';

/// Silme onayı ve geri alınabilir bildirim.
Future<void> confirmDelete(BuildContext context, {required String title, required String text, required void Function(Data d) apply, required String done}) async {
  final st = AppScope.of(context);
  final s = S.of(context);
  final ok = await confirmDialog(context, title: title, text: text, danger: true);
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final snap = st.snapshot();
  st.update(apply);
  Navigator.of(context).pop();
  showToast(messenger, s.lang, done, undo: () => st.restore(snap));
}

// ---------------------------------------------------------------- Abonelik

class SubSheet extends StatefulWidget {
  const SubSheet({super.key, this.sub, this.prefill});

  final Subscription? sub;
  final Json? prefill;

  @override
  State<SubSheet> createState() => _SubSheetState();
}

class _SubSheetState extends State<SubSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController();
  final _note = TextEditingController();
  String _group = 'diger';
  String _period = 'ay';
  bool _active = true;
  String? _source;
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final lang = S.of(context).lang;
    final x = widget.sub;
    final pre = widget.prefill ?? const <String, dynamic>{};
    if (x != null) {
      _name.text = x.name;
      _amount.text = x.amount == null ? '' : fmtNum(toK(x.amount), lang: lang);
      _day.text = x.day?.toString() ?? '';
      _note.text = x.note;
      _group = x.group.isEmpty ? 'diger' : x.group;
      _period = x.period;
      _active = x.active;
      _source = x.source;
    } else {
      _name.text = (pre['name'] ?? '').toString();
      _group = (pre['group'] ?? 'diger').toString();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _day, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return Outcome.err(s.pick('Ad gerekli.', 'A name is needed.'));
    double? amount;
    final raw = _amount.text.trim();
    if (raw.isNotEmpty) {
      final k = parseAmount(raw);
      if (k == null) return Outcome.err(s.pick('Fiyat geçerli değil (ör. 99,99).', 'The price is not valid (e.g. 99.99).'));
      amount = fromK(k);
    }
    final (day, e) = readDay(_day.text, s.pick('Ödeme günü', 'Payment day'), s.lang);
    if (e != null) return Outcome.err(e);
    final rec = <String, dynamic>{
      'name': name,
      'group': _group,
      'amount': amount,
      'period': _period,
      'day': day,
      'source': _source,
      'active': _active,
      'note': _note.text.trim(),
    };
    final id = widget.sub?.id;
    return Outcome.ok((d) => saveSubscription(d, rec, id: id), focus: currentMonth());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final x = widget.sub;
    final o = _read();
    final groups = <String, Lbl>{...kSubGroups};
    if (!groups.containsKey(_group)) groups[_group] = Lbl(_group, _group);
    return SheetFrame(
      title: x != null ? x.name : s.pick('Abonelik ekle', 'Add a subscription'),
      error: _error,
      impact: ImpactBox(
        outcome: o.ok ? o : null,
        noLiquid: true,
        extra: (b, a) => [ImpactLine(s.pick('Aboneliklerin aylık toplamı', 'Monthly total of subscriptions'), b.model.subsMonthly, a.model.subsMonthly, upIsGood: false)],
      ),
      leftActions: [
        if (x != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () => confirmDelete(
              context,
              title: s.pick('Aboneliği sil', 'Delete the subscription'),
              text: s.pick('"${x.name}" listeden silinecek. Kullanmıyorsan silmek yerine dondurabilirsin.', '"${x.name}" will be removed. If you just stopped using it, you can pause it instead.'),
              apply: (d) => deleteSubscription(d, x.id),
              done: s.pick('Abonelik silindi.', 'Subscription deleted.'),
            ),
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, x != null ? s.pick('Abonelik güncellendi.', 'Subscription updated.') : s.pick('Abonelik eklendi.', 'Subscription added.'));
          },
        ),
      ],
      children: [
        FieldPair(
          left: FieldBox(label: s.pick('Ad', 'Name'), child: TextInput(controller: _name, autofocus: x == null && _name.text.isEmpty, hint: s.pick('ör. Spotify Premium', 'e.g. Spotify Premium'), onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(
            label: s.pick('Grup', 'Group'),
            child: GlassSelect<String>(value: _group, items: [for (final e in groups.entries) (e.key, e.value.of(s.lang))], onChanged: (v) => setState(() => _group = v ?? 'diger')),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Fiyat', 'Price'),
            child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: x == null && _name.text.isNotEmpty, hint: s.pick('boş = henüz bilinmiyor', 'empty = not known yet'), onChanged: (_) => setState(() {})),
          ),
          right: FieldBox(
            label: s.pick('Ödeme sıklığı', 'Billing'),
            child: Seg<String>(value: _period, options: [('ay', s.pick('Aylık', 'Monthly')), ('yil', s.pick('Yıllık', 'Yearly'))], onChanged: (v) => setState(() => _period = v)),
          ),
        ),
        FieldPair(
          left: FieldBox(label: s.pick('Nereden ödeniyor?', 'Paid from'), child: SourceSelect(value: _source, none: s.pick('Seçilmedi', 'Not set'), onChanged: (v) => setState(() => _source = v))),
          right: FieldBox(label: s.pick('Ödeme günü', 'Payment day'), child: TextInput(controller: _day, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
        ),
        FieldBox(
          label: s.pick('Durum', 'Status'),
          help: s.pick('Dondurulan abonelik listede kalır ama plana ve bilançoya katılmaz. Fiyatı boş olan da katılmaz.', 'A paused subscription stays listed but is left out of the plan and balance. One without a price is left out too.'),
          child: Seg<bool>(value: _active, options: [(true, s.pick('Kullanıyorum', 'In use')), (false, s.pick('Dondurulmuş', 'Paused'))], onChanged: (v) => setState(() => _active = v)),
        ),
        FieldBox(label: s.pick('Not', 'Note'), child: TextInput(controller: _note)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Fatura tutarı

class BillAmountSheet extends StatefulWidget {
  const BillAmountSheet({super.key, required this.sub, required this.month});

  final Subscription sub;
  final String month;

  @override
  State<BillAmountSheet> createState() => _BillAmountSheetState();
}

class _BillAmountSheetState extends State<BillAmountSheet> {
  final _amount = TextEditingController();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final v = widget.sub.monthAmounts[widget.month];
    if (v != null) _amount.text = fmtNum(toK(v), lang: S.of(context).lang);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final k = parseAmount(_amount.text);
    if (k == null || k < 0) return Outcome.err(s.pick('Tutar geçerli değil (ör. 850 ya da 1.240,50).', 'The amount is not valid (e.g. 850 or 1,240.50).'));
    final id = widget.sub.id, m = widget.month;
    return Outcome.ok((d) => setBillAmount(d, id, m, k), focus: m);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final x = widget.sub;
    final m = widget.month;
    final base = (x.amount ?? 0) > 0 ? toK(x.amount) : 0;
    final cur = x.monthAmounts[m];
    final o = _read();
    return SheetFrame(
      title: '${x.name} · ${monthLabel(m, s.lang)}',
      subtitle: (base > 0 ? s.pick('Her zamanki tutar ${fmtMoney(base, lang: s.lang, hidden: st.hidden)}. ', 'Usual amount ${fmtMoney(base, lang: s.lang, hidden: st.hidden)}. ') : '') +
          s.pick('Girdiğin tutar yalnızca ${monthName(m, s.lang)} için geçerli.', 'The amount you enter applies to ${monthName(m, s.lang)} only.'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, noLiquid: true),
      leftActions: [
        if (cur != null)
          GlassButton(
            label: s.pick('Kaldır', 'Remove'),
            danger: true,
            onTap: () => commitOutcome(context, Outcome.ok((d) => setBillAmount(d, x.id, m, null), focus: m), s.pick('${monthName(m, s.lang)} tutarı kaldırıldı.', 'The ${monthName(m, s.lang)} amount was removed.')),
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, s.pick('${x.name}: ${monthName(m, s.lang)} tutarı kaydedildi.', '${x.name}: ${monthName(m, s.lang)} amount saved.'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('${monthName(m, s.lang)} faturası', '${monthName(m, s.lang)} bill'),
          child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, hint: base > 0 ? fmtNum(base, lang: s.lang) : s.pick('ör. 850', 'e.g. 850'), onChanged: (_) => setState(() => _error = null)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Sabit gider

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key, this.expense});

  final RecurringExpense? expense;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController();
  final _note = TextEditingController();
  String _cat = 'fatura';
  String? _start;
  String? _end;
  final Set<String> _linked = {};
  bool _showLinks = false;
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final st = AppScope.of(context);
    final lang = S.of(context).lang;
    final x = widget.expense;
    if (x != null) {
      _name.text = x.name;
      _amount.text = fmtNum(toK(x.amount), lang: lang);
      _day.text = x.day?.toString() ?? '';
      _note.text = x.note;
      _cat = x.category.isEmpty ? 'diger' : x.category;
      _start = x.startMonth;
      _end = x.endMonth;
      _linked.addAll(x.linkedDebtIds);
      _showLinks = _linked.isNotEmpty;
    } else {
      final b = st.data.balancesAsOf;
      _start = maxMonth(currentMonth(), isMonth(b) ? b : currentMonth());
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _day, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return Outcome.err(s.pick('Ad gerekli.', 'A name is needed.'));
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil (ör. 4.000 veya 4000,50).', 'The amount is not valid (e.g. 4,000 or 4000.50).'));
    final start = _start, end = _end;
    if (!isMonth(start)) return Outcome.err(s.pick('Başlangıç ayı seçilmeli.', 'Pick a start month.'));
    if (end != null && end.compareTo(start!) < 0) return Outcome.err(s.pick('Bitiş ayı başlangıçtan önce olamaz.', 'The end month cannot be before the start.'));
    final (day, e) = readDay(_day.text, s.pick('Ödeme günü', 'Payment day'), s.lang);
    if (e != null) return Outcome.err(e);
    final rec = <String, dynamic>{
      'name': name,
      'category': _cat,
      'amount': fromK(k),
      'startMonth': start,
      'endMonth': end,
      'day': day,
      'linkedDebtIds': _linked.toList(),
      'note': _note.text.trim(),
    };
    final id = widget.expense?.id;
    return Outcome.ok((d) => saveExpense(d, rec, id: id), focus: maxMonth(start!, currentMonth()));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final x = widget.expense;
    final o = _read();
    final cats = [...allCategories(d, s.lang), ('kart_asgari', catLabel('kart_asgari', s.lang))];
    if (!cats.any((c) => c.$1 == _cat)) cats.add((_cat, _cat));
    return SheetFrame(
      title: x != null ? x.name : s.pick('Sabit gider ekle', 'Add a fixed cost'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null),
      leftActions: [
        if (x != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () {
              final n = d.payments.where((p) => p.kind == 'expense' && p.refId == x.id && p.viaRefId == null).length;
              confirmDelete(
                context,
                title: s.pick('Gideri sil', 'Delete the cost'),
                text: s.pick('"${x.name}" gideri${n > 0 ? ' ve ona ait $n ödeme işareti' : ''} silinecek. Hesaplardan yapılmış ödemeler bakiyelere geri eklenmez.',
                    '"${x.name}"${n > 0 ? ' and its $n payment marks' : ''} will be deleted. Payments made from accounts are not added back.'),
                apply: (data) => deleteExpense(data, x.id),
                done: s.pick('Gider silindi.', 'Cost deleted.'),
              );
            },
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, x != null ? s.pick('Gider güncellendi.', 'Cost updated.') : s.pick('Gider eklendi.', 'Cost added.'));
          },
        ),
      ],
      children: [
        FieldPair(
          left: FieldBox(label: s.pick('Ad', 'Name'), child: TextInput(controller: _name, autofocus: x == null, hint: s.pick('ör. Elektrik, kira', 'e.g. Electricity, rent'), onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(label: s.pick('Aylık tutar', 'Monthly amount'), child: TextInput(controller: _amount, number: true, suffix: 'TL', hint: s.pick('ör. 4.000', 'e.g. 4,000'), onChanged: (_) => setState(() {}))),
        ),
        FieldPair(
          left: FieldBox(label: s.pick('Kategori', 'Category'), child: GlassSelect<String>(value: _cat, items: cats, onChanged: (v) => setState(() => _cat = v ?? 'diger'))),
          right: FieldBox(label: s.pick('Ödeme günü', 'Payment day'), child: TextInput(controller: _day, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
        ),
        FieldPair(
          left: FieldBox(label: s.pick('Başlangıç ayı', 'Start month'), child: MonthInput(value: _start, onChanged: (v) => setState(() => _start = v))),
          right: FieldBox(label: s.pick('Bitiş ayı (boş = süresiz)', 'End month (empty = open-ended)'), child: MonthInput(value: _end, allowEmpty: true, onChanged: (v) => setState(() => _end = v))),
        ),
        if (d.debts.isNotEmpty)
          _showLinks
              ? FieldBox(
                  label: s.pick('Bir borcun ödemesi mi?', 'Is it a debt payment?'),
                  help: s.pick('İşaretlersen o borçların ödemesi ayrıca sayılmaz; ödendi işaretlenince borçlara dağıtılır.', 'If you tick debts, their payments are not counted separately; when marked paid, it is split across them.'),
                  child: Column(children: [
                    for (final debt in d.debts)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: MC.gold,
                        checkColor: MC.ink,
                        value: _linked.contains(debt.id),
                        onChanged: (v) => setState(() => v == true ? _linked.add(debt.id) : _linked.remove(debt.id)),
                        title: Text(debt.creditor, style: sans(13.5, weight: FontWeight.w600)),
                        subtitle: Text((kDebtTypes[debt.type] ?? const Lbl('Borç', 'Debt')).of(s.lang), style: sans(11.5, color: MC.muted)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ]),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SmallButton(label: s.pick('Bir borcun ödemesi mi?', 'Is it a debt payment?'), icon: Icons.link, onTap: () => setState(() => _showLinks = true)),
                  ),
                ),
        FieldBox(label: s.pick('Not', 'Note'), child: TextInput(controller: _note)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Gelir

class IncomeSheet extends StatefulWidget {
  const IncomeSheet({super.key, this.income});

  final Income? income;

  @override
  State<IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends State<IncomeSheet> {
  final _name = TextEditingController();
  final _day = TextEditingController();
  final _note = TextEditingController();
  final _gross = TextEditingController();
  final List<SchedRow> _rows = [];
  bool _oneOff = false;
  String? _account;
  bool _isGross = false;
  bool _variable = false;
  final _oneAmount = TextEditingController();
  String _oneDate = todayISO();
  String? _error;
  bool _init = false;

  String _defaultStart() {
    final b = AppScope.of(context).data.balancesAsOf;
    return maxMonth(currentMonth(), isMonth(b) ? b : currentMonth());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = S.of(context);
    final x = widget.income;
    if (x != null) {
      _name.text = x.name;
      _day.text = x.payDay?.toString() ?? '';
      _note.text = x.note;
      _account = x.account;
      _isGross = x.gross;
      _variable = x.variable;
      final g = x.grossAmount;
      if (g != null) _gross.text = fmtNum(toK(g), lang: s.lang);
      final sched = x.schedule.toList()..sort((a, b) => a.from.compareTo(b.from));
      for (final r in sched) {
        _rows.add(SchedRow(r.from, r.to, fmtNum(toK(r.amount), lang: s.lang)));
      }
    } else {
      _name.text = s.pick('Maaş', 'Salary');
      _rows.add(SchedRow(_defaultStart(), null, ''));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _day, _note, _oneAmount, _gross]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return Outcome.err(s.pick('Ad gerekli.', 'A name is needed.'));
    if (_oneOff) {
      final k = parseAmount(_oneAmount.text);
      if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil.', 'The amount is not valid.'));
      if (!isDate(_oneDate)) return Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.'));
      final date = _oneDate;
      return Outcome.ok((d) => saveOneOffIncome(d, name: name, k: k, date: date), focus: date.substring(0, 7));
    }
    final (pd, e1) = readDay(_day.text, s.pick('Ödeme günü', 'Pay day'), s.lang);
    if (e1 != null) return Outcome.err(e1);
    if (_rows.isEmpty) return Outcome.err(s.pick('En az bir tutar dönemi ekle.', 'Add at least one period.'));
    final (sched, e2) = validateSched(readSched(_rows), openEnd: true, lang: s.lang);
    if (e2 != null) return Outcome.err(e2);
    int? grossK;
    if (_isGross) {
      grossK = parseAmount(_gross.text);
      if (grossK == null || grossK <= 0) return Outcome.err(s.pick('Brüt tutarı yaz (ör. 60.000).', 'Type the gross amount (e.g. 60,000).'));
    }
    final id = widget.income?.id, note = _note.text.trim(), account = _account, gross = _isGross, variable = _variable;
    return Outcome.ok(
      (d) => saveIncome(d, id: id, name: name, payDay: pd, schedule: sched, note: note, account: account, gross: gross, grossK: grossK, variable: variable),
      focus: maxMonth(currentMonth(), sched.first['from'] as String),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final x = widget.income;
    final o = _read();
    return SheetFrame(
      title: x != null ? x.name : s.pick('Gelir ekle', 'Add income'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null),
      leftActions: [
        if (x != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () => confirmDelete(
              context,
              title: s.pick('Geliri sil', 'Delete the income'),
              text: s.pick('"${x.name}" geliri silinecek. Kalan bütçe ve plan buna göre yeniden hesaplanır.', '"${x.name}" will be deleted. The budget and plan are worked out again.'),
              apply: (d) => deleteIncome(d, x.id),
              done: s.pick('Gelir silindi.', 'Income deleted.'),
            ),
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, x != null ? s.pick('Gelir güncellendi.', 'Income updated.') : s.pick('Gelir eklendi.', 'Income added.'));
          },
        ),
      ],
      children: [
        if (x == null)
          FieldBox(
            label: s.pick('Ne tür?', 'What kind?'),
            child: Seg<bool>(value: _oneOff, options: [(false, s.pick('Düzenli (maaş vb.)', 'Regular (salary etc.)')), (true, s.pick('Tek seferlik', 'One-off'))], onChanged: (v) => setState(() {
                  _oneOff = v;
                  if (v && _name.text == s.pick('Maaş', 'Salary')) _name.text = '';
                  _error = null;
                })),
          ),
        if (_oneOff) ...[
          FieldBox(label: s.pick('Ad', 'Name'), child: TextInput(controller: _name, autofocus: true, hint: s.pick('ör. İkramiye', 'e.g. Bonus'), onChanged: (_) => setState(() {}))),
          FieldPair(
            left: FieldBox(label: s.pick('Tutar', 'Amount'), child: TextInput(controller: _oneAmount, number: true, suffix: 'TL', onChanged: (_) => setState(() {}))),
            right: FieldBox(label: s.pick('Tarih', 'Date'), child: DateInput(value: _oneDate, onChanged: (v) => setState(() => _oneDate = v))),
          ),
          Text(s.pick('Gelir planına ve kalan bütçeye eklenir. Paranın hesaba girdiğini göstermek için ayrıca "Para aktar › Dışarıdan para girişi" kullan.',
              'It is added to the income plan and budget. To show the money arriving in an account, also use "Move money › Money coming in".'),
              style: sans(12, color: MC.dim, height: 1.4)),
        ] else ...[
          FieldPair(
            left: FieldBox(label: s.pick('Ad', 'Name'), child: TextInput(controller: _name, onChanged: (_) => setState(() {}))),
            right: FieldBox(label: s.pick('Ödeme günü', 'Pay day'), child: TextInput(controller: _day, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
          ),
          FieldBox(
            label: s.pick('Hangi hesaba yatıyor?', 'Paid into which account?'),
            help: s.pick('Yattığını onaylayınca tutar bu hesabın bakiyesine eklenir; bu hesaptan yaptığın harcamalar da buradan düşer.',
                'When you confirm it arrived, the amount is added to this account; spending from this account comes off it.'),
            child: SourceSelect(key: const ValueKey<String>('income-account'), value: _account, cards: false, none: s.pick('Seçilmedi', 'Not chosen'), onChanged: (v) => setState(() => _account = v)),
          ),
          FieldBox(
            label: s.pick('Tutar net mi, brüt mü?', 'Is the amount net or gross?'),
            child: Seg<bool>(
              key: const ValueKey<String>('income-basis'),
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
              help: s.pick('Bilgi olarak saklanır. Plan hesabına yatan net tutarla çalışır: aşağıya net tutarı yaz.',
                  'Kept for reference. The plan works with what you actually receive: type the net amount below.'),
              child: TextInput(key: const ValueKey<String>('income-gross'), controller: _gross, number: true, suffix: 'TL', onChanged: (_) => setState(() => _error = null)),
            ),
          FieldBox(
            label: s.pick('Her ay aynı mı?', 'The same every month?'),
            help: _variable
                ? s.pick('Henüz yatmamış aylarda son yatan tutar "tahmini" olarak kullanılır; yattıkça gerçek tutarı girersin.',
                    'Months not received yet use the last amount received, marked "estimated"; enter the real amount as it arrives.')
                : null,
            child: Seg<bool>(
              key: const ValueKey<String>('income-variable'),
              value: _variable,
              options: [(false, s.pick('Her ay aynı', 'Fixed')), (true, s.pick('Değişken', 'Varies'))],
              onChanged: (v) => setState(() => _variable = v),
            ),
          ),
          FieldBox(
            label: _isGross ? s.pick('Hesabına yatan net tutar', 'Net amount you receive') : s.pick('Tutar dönemleri', 'Amount periods'),
            help: s.pick('Zam gelirse yeni dönem ekle; önceki dönemin bitişi otomatik ayarlanır, geçmiş aylar bozulmaz.', 'After a raise, add a new period; the previous one ends automatically and past months stay intact.'),
            child: SchedEditor(rows: _rows, openEnd: true, defaultStart: _defaultStart(), onChanged: () => setState(() {})),
          ),
          FieldBox(label: s.pick('Not', 'Note'), child: TextInput(controller: _note)),
        ],
      ],
    );
  }
}

class OneOffIncomeSheet extends StatefulWidget {
  const OneOffIncomeSheet({super.key, required this.income});

  final OneOffIncome income;

  @override
  State<OneOffIncomeSheet> createState() => _OneOffIncomeSheetState();
}

class _OneOffIncomeSheetState extends State<OneOffIncomeSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  String _date = todayISO();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _name.text = widget.income.name;
    _amount.text = fmtNum(toK(widget.income.amount), lang: S.of(context).lang);
    if (isDate(widget.income.date)) _date = widget.income.date;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final x = widget.income;
    Outcome read() {
      final name = _name.text.trim();
      if (name.isEmpty) return Outcome.err(s.pick('Ad gerekli.', 'A name is needed.'));
      final k = parseAmount(_amount.text);
      if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil.', 'The amount is not valid.'));
      if (!isDate(_date)) return Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.'));
      final date = _date;
      return Outcome.ok((d) => saveOneOffIncome(d, id: x.id, name: name, k: k, date: date), focus: date.substring(0, 7));
    }

    final o = read();
    return SheetFrame(
      title: x.name,
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null),
      leftActions: [
        GlassButton(
          label: s.pick('Sil', 'Delete'),
          icon: Icons.delete_outline,
          danger: true,
          onTap: () => confirmDelete(
            context,
            title: s.pick('Geliri sil', 'Delete the income'),
            text: s.pick('"${x.name}" geliri silinecek.', '"${x.name}" will be deleted.'),
            apply: (d) => deleteOneOffIncome(d, x.id),
            done: s.pick('Gelir silindi.', 'Income deleted.'),
          ),
        ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, s.pick('Gelir güncellendi.', 'Income updated.'));
          },
        ),
      ],
      children: [
        FieldBox(label: s.pick('Ad', 'Name'), child: TextInput(controller: _name, onChanged: (_) => setState(() {}))),
        FieldPair(
          left: FieldBox(label: s.pick('Tutar', 'Amount'), child: TextInput(controller: _amount, number: true, suffix: 'TL', onChanged: (_) => setState(() {}))),
          right: FieldBox(label: s.pick('Tarih', 'Date'), child: DateInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        ),
      ],
    );
  }
}

/// Bir ayda gerçekte yatan gelir.
class IncomeActualSheet extends StatefulWidget {
  const IncomeActualSheet({super.key, required this.income, required this.month});

  final Income income;
  final String month;

  @override
  State<IncomeActualSheet> createState() => _IncomeActualSheetState();
}

class _IncomeActualSheetState extends State<IncomeActualSheet> {
  final _amount = TextEditingController();
  late String _date;
  String? _to;
  String? _error;
  bool _init = false;

  String get _ref => '${widget.income.id}|${widget.month}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final st = AppScope.of(context);
    final lang = S.of(context).lang;
    final inc = widget.income;
    final m = widget.month;
    final planned = schedK(inc.schedule, m);
    final cur = inc.monthAmounts[m];
    _amount.text = fmtNum(cur != null ? toK(cur) : planned, lang: lang);
    Transfer? tr;
    for (final t in st.data.transfers) {
      if (t.incomeRef == _ref) tr = t;
    }
    final day = inc.payDay == null ? 1 : (inc.payDay! < daysInMonth(m) ? inc.payDay! : daysInMonth(m));
    _date = tr?.date ?? '$m-${two(day)}';
    // Yatırılmışsa o hesap; değilse gelirin her zaman yattığı hesap
    _to = tr?.to ?? (st.data.account(srcAcc(inc.account)) != null ? inc.account : null);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final inc = widget.income;
    final m = widget.month;
    final planned = schedK(inc.schedule, m);
    final cur = inc.monthAmounts[m];
    Outcome read() {
      final k = parseAmount(_amount.text);
      if (k == null) return Outcome.err(s.pick('Tutar geçerli değil (ör. 42.640,40).', 'The amount is not valid (e.g. 42,640.40).'));
      if (!isDate(_date)) return Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.'));
      final date = _date, to = _to;
      return Outcome.ok((d) => setIncomeActual(d, inc.id, m, k: k, date: date, to: to), focus: m);
    }

    final o = read();
    return SheetFrame(
      title: '${inc.name.isEmpty ? s.pick('Gelir', 'Income') : inc.name} · ${monthLabel(m, s.lang)}',
      subtitle: s.pick('Plandaki tutar ${fmtMoney(planned, lang: s.lang, hidden: st.hidden)}. Girdiğin tutar yalnızca ${monthName(m, s.lang)} için geçerli; sonraki aylar plandaki tutarla devam eder.',
          'The planned amount is ${fmtMoney(planned, lang: s.lang, hidden: st.hidden)}. What you enter applies to ${monthName(m, s.lang)} only; later months keep the planned amount.'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null),
      leftActions: [
        if (cur != null)
          GlassButton(
            label: s.pick('Kaldır', 'Remove'),
            danger: true,
            onTap: () => commitOutcome(context, Outcome.ok((d) => setIncomeActual(d, inc.id, m), focus: m),
                s.pick('${monthName(m, s.lang)} için girilen tutar kaldırıldı; plandaki tutar geçerli.', 'The ${monthName(m, s.lang)} amount was removed; the planned amount applies.')),
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, s.pick('${monthName(m, s.lang)} ayında yatan tutar kaydedildi.', 'The amount received in ${monthName(m, s.lang)} is saved.'));
          },
        ),
      ],
      children: [
        FieldPair(
          left: FieldBox(label: s.pick('Yatan tutar', 'Amount received'), child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(label: s.pick('Tarih', 'Date'), child: DateInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        ),
        FieldBox(
          label: s.pick('Hangi hesaba yattı?', 'Paid into which account?'),
          help: s.pick('Seçtiğin hesabın bakiyesine eklenir ve bu gelir için hatırlanır; kaldırırsan geri düşülür.',
              'It is added to the chosen account and remembered for this income; it comes off again if you remove it.'),
          child: SourceSelect(value: _to, cards: false, none: s.pick('Bakiyeye dokunma (bakiyeyi kendim güncelliyorum)', 'Leave balances (I update them myself)'), onChanged: (v) => setState(() => _to = v)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- İstek listesi

const List<String> kGoalEmojis = ['🎯', '📱', '💻', '🎮', '⌚', '🚗', '🏠', '✈️', '🎧', '📷', '👟', '☕', '🛋️', '🎁', '💍', '📚'];

class GoalSheet extends StatefulWidget {
  const GoalSheet({super.key, this.goal, this.prefill});

  final Goal? goal;
  final Json? prefill;

  @override
  State<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<GoalSheet> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _plan = TextEditingController();
  final _url = TextEditingController();
  final _note = TextEditingController();
  String _emoji = kGoalEmojis.first;
  String _priority = 'orta';
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final lang = S.of(context).lang;
    final g = widget.goal;
    final pre = widget.prefill ?? const <String, dynamic>{};
    if (g != null) {
      _name.text = g.name;
      _target.text = fmtNum(toK(g.target), lang: lang);
      _plan.text = g.monthlyPlan == null ? '' : fmtNum(toK(g.monthlyPlan), lang: lang);
      _url.text = g.url;
      _note.text = g.note;
      _emoji = g.emoji;
      _priority = g.priority;
    } else {
      _name.text = (pre['name'] ?? '').toString();
      if (pre['target'] is num) _target.text = fmtNum(toK(pre['target']), lang: lang);
      if (pre['monthlyPlan'] is num) _plan.text = fmtNum(toK(pre['monthlyPlan']), lang: lang);
      _url.text = (pre['url'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _target, _plan, _url, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return Outcome.err(s.pick('Hedefin adını yaz.', 'Write the goal\'s name.'));
    final t = parseAmount(_target.text);
    if (t == null || t <= 0) return Outcome.err(s.pick('Hedef tutar geçerli değil.', 'The target amount is not valid.'));
    double? mp;
    final pr = _plan.text.trim();
    if (pr.isNotEmpty) {
      final v = parseAmount(pr);
      if (v == null) return Outcome.err(s.pick('Aylık ayırma tutarı geçerli değil.', 'The monthly amount is not valid.'));
      mp = v > 0 ? fromK(v) : null;
    }
    final ur = _url.text.trim();
    final url = ur.isEmpty ? '' : safeUrl(ur);
    if (ur.isNotEmpty && url.isEmpty) return Outcome.err(s.pick('Link geçerli değil (https:// ile başlamalı).', 'The link is not valid (it should start with https://).'));
    final rec = <String, dynamic>{'name': name, 'emoji': _emoji, 'target': fromK(t), 'monthlyPlan': mp, 'priority': _priority, 'url': url, 'note': _note.text.trim()};
    final id = widget.goal?.id;
    return Outcome.ok((d) => saveGoal(d, rec, id: id), focus: addM(currentMonth(), 1));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final g = widget.goal;
    final o = _read();
    return SheetFrame(
      title: g != null ? s.pick('Hedefi düzenle', 'Edit goal') : s.pick('İstek listesine ekle', 'Add to wish list'),
      error: _error,
      impact: ImpactBox(
        outcome: o.ok ? o : null,
        extra: (b, a) {
          GoalInfo? info;
          if (g != null) {
            info = a.model.goals[g.id];
          } else if (a.model.goals.isNotEmpty) {
            info = a.model.goals.values.last;
          }
          final c = info?.completion;
          return c == null ? const [] : [ImpactLine(s.pick('Tahmini tamamlanma: ${monthLabel(c, s.lang)}', 'Expected completion: ${monthLabel(c, s.lang)}'), 0, 0)];
        },
      ),
      leftActions: [
        if (g != null) ...[
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () {
              final n = st.data.goalContributions.where((c) => c.goalId == g.id).length;
              confirmDelete(
                context,
                title: s.pick('Hedefi sil', 'Delete the goal'),
                text: s.pick('"${g.name}" hedefi${n > 0 ? ' ve $n para ayırma kaydı' : ''} silinecek. Ayrılan para serbest paraya döner. Alışveriş kaydı varsa silinmez.',
                    '"${g.name}"${n > 0 ? ' and its $n set-aside records' : ''} will be deleted. The money set aside returns to free money. A purchase record, if any, stays.'),
                apply: (d) => deleteGoal(d, g.id),
                done: s.pick('Hedef silindi.', 'Goal deleted.'),
              );
            },
          ),
          if (!g.isActive) ...[
            const SizedBox(width: 8),
            GlassButton(
              label: s.pick('Listeye geri al', 'Back to the list'),
              icon: Icons.undo,
              onTap: () => commitOutcome(context, Outcome.ok((d) => reopenGoal(d, g.id)), s.pick('Hedef listeye geri alındı.', 'The goal is back on the list.')),
            ),
          ] else ...[
            const SizedBox(width: 8),
            GlassButton(
              label: s.pick('Geçmiş', 'History'),
              icon: Icons.history,
              onTap: () {
                Navigator.of(context).pop();
                showEditSheet<void>(context, builder: (_) => GoalHistorySheet(goal: g));
              },
            ),
          ],
        ],
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, g != null ? s.pick('Hedef güncellendi.', 'Goal updated.') : s.pick('İstek listesine eklendi.', 'Added to the wish list.'));
          },
        ),
      ],
      children: [
        FieldBox(label: s.pick('Ne almak istiyorsun?', 'What do you want to buy?'), child: TextInput(controller: _name, autofocus: g == null, hint: s.pick('ör. Yeni telefon', 'e.g. A new phone'), onChanged: (_) => setState(() => _error = null))),
        FieldBox(
          label: s.pick('Simge', 'Icon'),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in kGoalEmojis)
              InkWell(
                onTap: () => setState(() => _emoji = e),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _emoji == e ? MC.gold.withValues(alpha: 0.25) : const Color(0x26000000),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _emoji == e ? MC.gold : const Color(0x26FFFFFF)),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              ),
          ]),
        ),
        FieldPair(
          left: FieldBox(label: s.pick('Hedef tutar', 'Target amount'), child: TextInput(controller: _target, number: true, suffix: 'TL', hint: s.pick('ör. 25.000', 'e.g. 25,000'), onChanged: (_) => setState(() {}))),
          right: FieldBox(
            label: s.pick('Öncelik', 'Priority'),
            child: GlassSelect<String>(value: _priority, items: [for (final e in kPriorities.entries) (e.key, e.value.of(s.lang))], onChanged: (v) => setState(() => _priority = v ?? 'orta')),
          ),
        ),
        FieldBox(
          label: s.pick('Aylık ayırma tutarı (isteğe bağlı)', 'Monthly amount to set aside (optional)'),
          help: s.pick('Girersen tamamlanma ayı tahmin edilir ve gelecek ayların planına "planlanan birikim" olarak eklenir.', 'If you enter one, the completion month is estimated and it is added to coming months as planned savings.'),
          child: TextInput(controller: _plan, number: true, suffix: 'TL', hint: s.pick('ör. 2.000', 'e.g. 2,000'), onChanged: (_) => setState(() {})),
        ),
        FieldBox(label: s.pick('Ürün linki (isteğe bağlı)', 'Product link (optional)'), child: TextInput(controller: _url, hint: 'https://...', onChanged: (_) => setState(() {}))),
        FieldBox(label: s.pick('Not', 'Note'), child: TextInput(controller: _note)),
      ],
    );
  }
}

class ContributionSheet extends StatefulWidget {
  const ContributionSheet({super.key, required this.goal});

  final Goal goal;

  @override
  State<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<ContributionSheet> {
  final _amount = TextEditingController();
  bool _take = false;
  String? _month = currentMonth();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final st = AppScope.of(context);
    final g = widget.goal;
    final info = st.ctx.model.goals[g.id];
    final mp = g.monthlyPlan;
    if (mp != null && info != null) {
      final k = toK(mp);
      final rem = info.remaining > 0 ? info.remaining : k;
      _amount.text = fmtNum(k < rem ? k : rem, lang: S.of(context).lang);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final g = widget.goal;
    final info = st.ctx.model.goals[g.id];
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    Outcome read() {
      final k = parseAmount(_amount.text);
      if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil.', 'The amount is not valid.'));
      if (_take && k > (info?.saved ?? 0)) return Outcome.err(s.pick('En fazla ${money(info?.saved ?? 0)} geri alınabilir.', 'At most ${money(info?.saved ?? 0)} can be taken back.'));
      final m = _month;
      if (!isMonth(m)) return Outcome.err(s.pick('Ay seçilmeli.', 'Pick a month.'));
      final signed = _take ? -k : k;
      return Outcome.ok((d) => addContribution(d, g.id, signed, m!), focus: m);
    }

    final o = read();
    return SheetFrame(
      title: '${g.emoji} ${g.name}',
      subtitle: info == null
          ? null
          : s.pick('Biriken ${money(info.saved)} / ${money(info.target)} · kalan ${money(info.remaining)}', 'Saved ${money(info.saved)} / ${money(info.target)} · ${money(info.remaining)} to go'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null),
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            final reached0 = info != null && info.target > 0 && info.saved >= info.target;
            final k = parseAmount(_amount.text) ?? 0;
            final reached1 = info != null && info.target > 0 && info.saved + (_take ? -k : k) >= info.target;
            commitOutcome(
              context,
              o,
              party: !reached0 && reached1,
              !reached0 && reached1
                  ? s.pick('"${g.name}" için hedefe ulaştın! 🎉', 'You reached the goal for "${g.name}"! 🎉')
                  : (_take ? s.pick('Para geri alındı; serbest paraya döndü.', 'Money taken back; it is free again.') : s.pick('Para ayrıldı.', 'Money set aside.')),
            );
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Ne yapıyorsun?', 'What are you doing?'),
          child: Seg<bool>(value: _take, options: [(false, s.pick('Para ayır', 'Set aside')), (true, s.pick('Geri al', 'Take back'))], onChanged: (v) => setState(() => _take = v)),
        ),
        FieldBox(label: s.pick('Tutar', 'Amount'), child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, hint: s.pick('ör. 2.000', 'e.g. 2,000'), onChanged: (_) => setState(() => _error = null))),
        FieldBox(label: s.pick('Hangi ayın parasından?', 'From which month\'s money?'), child: MonthInput(value: _month, onChanged: (v) => setState(() => _month = v))),
      ],
    );
  }
}

class GoalHistorySheet extends StatelessWidget {
  const GoalHistorySheet({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final g = goal;
    final list = st.data.goalContributions.where((c) => c.goalId == g.id).toList()..sort((a, b) => b.month.compareTo(a.month));
    return SheetFrame(
      title: s.pick('${g.emoji} ${g.name} · geçmiş', '${g.emoji} ${g.name} · history'),
      actions: [GoldButton(label: s.pick('Kapat', 'Close'), onTap: () => Navigator.of(context).pop())],
      children: [
        if (list.isEmpty) Text(s.pick('Henüz para ayrılmadı.', 'Nothing set aside yet.'), style: sans(14, color: MC.muted)),
        for (final c in list)
          RowItem(
            title: monthLabel(c.month, s.lang),
            subtitle: (c.amount < 0 ? s.pick('Geri alındı', 'Taken back') : s.pick('Ayrıldı', 'Set aside')) + (c.date != null ? ' · ${fmtDate(c.date, s.lang)}' : ''),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              MoneyText(toK(c.amount), signed: true, style: sans(14, weight: FontWeight.w700), color: c.amount < 0 ? MC.rose : MC.mint),
              IconButton(
                tooltip: s.pick('Kaydı sil', 'Delete record'),
                onPressed: () {
                  final snap = st.snapshot();
                  st.update((d) => deleteContribution(d, c.id));
                  toast(context, s.pick('Kayıt silindi.', 'Record deleted.'), undo: () => st.restore(snap));
                },
                icon: const Icon(Icons.delete_outline, size: 19, color: MC.rose),
              ),
            ]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Findeks

class FindeksSheet extends StatefulWidget {
  const FindeksSheet({super.key, this.index});

  final int? index;

  @override
  State<FindeksSheet> createState() => _FindeksSheetState();
}

class _FindeksSheetState extends State<FindeksSheet> {
  final _score = TextEditingController();
  final _late = TextEditingController();
  final _band = TextEditingController();
  String? _date = currentMonth();
  String? _error;
  bool _init = false;

  Findeks? _entry(Data d) {
    final i = widget.index;
    return i != null && i >= 0 && i < d.findeks.length ? d.findeks[i] : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final f = _entry(AppScope.of(context).data);
    if (f != null) {
      _date = f.date;
      _score.text = f.score.round().toString();
      _late.text = f.lateCount?.toString() ?? '';
      _band.text = f.band ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_score, _late, _band]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final f = _entry(st.data);
    void save() {
      final date = _date;
      if (!isMonth(date)) return setState(() => _error = s.pick('Tarih seçilmeli.', 'Pick a month.'));
      final score = int.tryParse(_score.text.trim());
      if (score == null) return setState(() => _error = s.pick('Puan tam sayı olmalı.', 'The score must be a whole number.'));
      if (score < 1 || score > 1900) return setState(() => _error = s.pick('Puan 1 ile 1900 arasında olmalı.', 'The score must be between 1 and 1900.'));
      final lr = _late.text.trim();
      final late = lr.isEmpty ? null : int.tryParse(lr);
      if (lr.isNotEmpty && late == null) return setState(() => _error = s.pick('Gecikme sayısı tam sayı olmalı.', 'The number of late accounts must be a whole number.'));
      final band = _band.text.trim().isEmpty ? null : _band.text.trim();
      for (var i = 0; i < st.data.findeks.length; i++) {
        if (st.data.findeks[i].date == date && i != widget.index) {
          return setState(() => _error = s.pick('Bu ay için zaten bir kayıt var; onu düzenle.', 'There is already an entry for this month; edit that one.'));
        }
      }
      final idx = widget.index;
      commitOutcome(context, Outcome.ok((d) => saveFindeks(d, index: idx, date: date!, score: score, lateCount: late, band: band)), f != null ? s.pick('Kayıt güncellendi.', 'Entry updated.') : s.pick('Puan eklendi.', 'Score added.'));
    }

    return SheetFrame(
      title: f != null ? s.pick('Findeks kaydını düzenle', 'Edit the Findeks entry') : s.pick('Findeks puanı ekle', 'Add a Findeks score'),
      error: _error,
      leftActions: [
        if (f != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () => confirmDelete(
              context,
              title: s.pick('Kaydı sil', 'Delete entry'),
              text: s.pick('${monthLabel(f.date, s.lang)} Findeks kaydı silinecek.', 'The ${monthLabel(f.date, s.lang)} Findeks entry will be deleted.'),
              apply: (d) => deleteFindeks(d, widget.index!),
              done: s.pick('Kayıt silindi.', 'Entry deleted.'),
            ),
          ),
      ],
      actions: [GoldButton(label: s.pick('Kaydet', 'Save'), icon: Icons.check, onTap: save)],
      children: [
        FieldBox(label: s.pick('Tarih (ay)', 'Month'), child: MonthInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        FieldPair(
          left: FieldBox(label: s.pick('Puan (1–1900)', 'Score (1–1900)'), child: TextInput(controller: _score, number: true, autofocus: true, onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(label: s.pick('Gecikme sayısı', 'Late accounts'), child: TextInput(controller: _late, number: true, hint: s.pick('ör. 0', 'e.g. 0'))),
        ),
        FieldBox(label: s.pick('Risk etiketi (raporda yazan, isteğe bağlı)', 'Risk label (as in the report, optional)'), child: TextInput(controller: _band, hint: s.pick('ör. Orta Riskli', 'e.g. Medium risk'))),
      ],
    );
  }
}

// ---------------------------------------------------------------- Günlük harcama tahmini

class SpendEstimateSheet extends StatefulWidget {
  const SpendEstimateSheet({super.key});

  @override
  State<SpendEstimateSheet> createState() => _SpendEstimateSheetState();
}

class _SpendEstimateSheetState extends State<SpendEstimateSheet> {
  final _amount = TextEditingController();
  bool _manual = false;
  bool _init = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final e = AppScope.of(context).ctx.est;
    _manual = e.manual;
    if (e.manual) _amount.text = fmtNum(e.k, lang: S.of(context).lang);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final e = ctx.est;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    Outcome read() {
      if (!_manual) return Outcome.ok((d) => setSpendEstimate(d, null), focus: addM(currentMonth(), 1));
      final k = parseAmount(_amount.text);
      if (k == null) return Outcome.err(s.pick('Tutar geçerli değil (ör. 15.000).', 'The amount is not valid (e.g. 15,000).'));
      return Outcome.ok((d) => setSpendEstimate(d, k), focus: addM(currentMonth(), 1));
    }

    final o = read();
    final basis = e.basisMonths.map((m) => monthShortLabel(m, s.lang)).join(', ');
    return SheetFrame(
      title: s.pick('Günlük harcama tahmini', 'Everyday spending estimate'),
      subtitle: s.pick('Gelecek ayların serbest parası hesaplanırken her aydan düşülür. Hesaptan ve nakit yaptığın harcamalar içindir; kira, abonelik, borç taksitleri ve karttan yapılan harcamalar planda zaten ayrıca sayılıyor.',
          'It comes off each coming month\'s free money. It covers spending from accounts and cash; rent, subscriptions, instalments and card spending are already counted separately.'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, noLiquid: true),
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, s.pick('Harcama tahmini kaydedildi; gelecek aylar yeniden hesaplandı.', 'Estimate saved; the coming months are worked out again.'));
          },
        ),
      ],
      children: [
        if (e.basisMonths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(spacing: 18, runSpacing: 8, children: [
              for (final m in e.basisMonths)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(monthLabel(m, s.lang), style: sans(11.5, color: MC.muted)),
                  Text(money(variableSpentK(ctx.data, m)), style: sans(14.5, weight: FontWeight.w700)),
                ]),
            ]),
          ),
        FieldBox(
          label: s.pick('Nasıl?', 'How?'),
          help: e.auto != null
              ? s.pick('Otomatik tahmin: ${money(e.auto!)} / ay ($basis ortalaması).', 'Automatic estimate: ${money(e.auto!)} / month (average of $basis).')
              : s.pick('Henüz yeterli harcama kaydı yok; otomatik tahmin 0 TL.', 'Not enough spending recorded yet; the automatic estimate is 0 TL.'),
          child: Seg<bool>(value: _manual, options: [(false, s.pick('Otomatik', 'Automatic')), (true, s.pick('Kendim yazacağım', 'I\'ll type it'))], onChanged: (v) => setState(() => _manual = v)),
        ),
        if (_manual)
          FieldBox(
            label: s.pick('Aylık tutar', 'Monthly amount'),
            child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, hint: e.auto != null ? fmtNum(e.auto!, lang: s.lang) : s.pick('ör. 15.000', 'e.g. 15,000'), onChanged: (_) => setState(() => _error = null)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Ay kapatma

class CloseMonthSheet extends StatefulWidget {
  const CloseMonthSheet({super.key, required this.month});

  final String month;

  @override
  State<CloseMonthSheet> createState() => _CloseMonthSheetState();
}

class _CloseMonthSheetState extends State<CloseMonthSheet> {
  final Set<int> _picked = {};
  bool _carryCash = true;
  bool _init = false;

  List<PlanItem> _open(Ctx ctx) => ctx.sum(widget.month).items.where((it) => it.pay == null && !it.carriedOut && it.planned > 0).toList()
    ..sort((a, b) => (a.day ?? 32) - (b.day ?? 32));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    _picked.addAll(List.generate(_open(AppScope.of(context).ctx).length, (i) => i));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final m = widget.month;
    final nm = addM(m, 1);
    final sum = ctx.sum(m);
    final open = _open(ctx);
    final paidN = sum.items.where((it) => it.pay != null && !it.carriedOut).length;
    final hasInc = sum.income > 0 || sum.carryIn != 0;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final picked = [for (var i = 0; i < open.length; i++) if (_picked.contains(i)) open[i]];
    final free = sum.free + sumK(picked, (PlanItem it) => it.planned);
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: sans(11.5, color: MC.muted)),
            const SizedBox(height: 2),
            Text(value, style: sans(14, weight: FontWeight.w700, color: color ?? MC.text)),
          ]),
        );
    return SheetFrame(
      title: s.pick('${monthLabel(m, s.lang)} ayını kapat', 'Close ${monthLabel(m, s.lang)}'),
      subtitle: s.pick('Ay arşivlenir, plan ${monthLabel(nm, s.lang)} ayından devam eder. Sonradan geri açabilirsin.', 'The month is archived and the plan continues from ${monthLabel(nm, s.lang)}. You can reopen it later.'),
      actions: [
        GoldButton(
          label: s.pick('Ayı kapat', 'Close the month'),
          icon: Icons.lock_outline,
          onTap: () {
            final carryCash = hasInc && _carryCash;
            final withSnap = m.compareTo(addM(ctx.cur, -1)) >= 0;
            final model = ctx.model;
            commitOutcome(
              context,
              Outcome.ok((d) => closeMonth(d, model, m, carry: picked, carryCash: carryCash, withSnapshot: withSnap)),
              s.pick('${monthLabel(m, s.lang)} kapatıldı${picked.isNotEmpty ? ' · ${picked.length} kalem ${monthName(nm, s.lang)} ayına taşındı' : ''}.',
                  '${monthLabel(m, s.lang)} is closed${picked.isNotEmpty ? ' · ${picked.length} items moved to ${monthName(nm, s.lang)}' : ''}.'),
            );
          },
        ),
      ],
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: const Color(0x26000000), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            stat(s.pick('Ödenen', 'Paid'), s.pick('$paidN kalem · ${money(sum.paid)}', '$paidN items · ${money(sum.paid)}')),
            stat(s.pick('Ödenmeyen', 'Unpaid'), s.pick('${open.length} kalem · ${money(sum.unpaid)}', '${open.length} items · ${money(sum.unpaid)}'), color: open.isNotEmpty ? MC.rose : null),
            if (hasInc) stat(s.pick('Serbest kalan', 'Left free'), money(sum.free), color: sum.free < 0 ? MC.rose : MC.gold),
          ]),
        ),
        if (open.isEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(s.pick('Bu ayın tüm ödemeleri yapılmış.', 'Every payment this month is done.'), style: sans(13.5, color: MC.mint)))
        else
          FieldBox(
            label: s.pick('Ödenmeyenler · işaretliler ${monthName(nm, s.lang)} ayına taşınır', 'Unpaid · ticked ones move to ${monthName(nm, s.lang)}'),
            help: s.pick('Taşınan kalemi ödediğinde ödeme yine ${monthName(m, s.lang)} ayına yazılır; borç hesabı bozulmaz. Taşımadıkların bu ayda ödenmemiş olarak kalır.',
                'When you pay a moved item, the payment is still filed under ${monthName(m, s.lang)}; debts stay correct. Items you do not move stay unpaid in this month.'),
            child: Column(children: [
              for (var i = 0; i < open.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: MC.gold,
                  checkColor: MC.ink,
                  value: _picked.contains(i),
                  onChanged: (v) => setState(() => v == true ? _picked.add(i) : _picked.remove(i)),
                  title: Text(open[i].name, style: sans(13.5, weight: FontWeight.w600)),
                  subtitle: Text(open[i].day != null ? dayMonth(open[i].day, m, s.lang) : s.pick('günü yok', 'no day'), style: sans(11.5, color: MC.muted)),
                  secondary: Text(open[i].est ? '(${money(open[i].planned)})' : money(open[i].planned), style: sans(13.5, weight: FontWeight.w700)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              Row(children: [
                SmallButton(label: s.pick('Hepsini seç', 'Select all'), icon: Icons.done_all, onTap: () => setState(() => _picked.addAll(List.generate(open.length, (i) => i)))),
                SmallButton(label: s.pick('Hiçbirini seçme', 'Select none'), icon: Icons.remove_done, onTap: () => setState(_picked.clear)),
              ]),
            ]),
          ),
        if (hasInc)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: MC.gold,
            checkColor: MC.ink,
            value: _carryCash,
            onChanged: (v) => setState(() => _carryCash = v ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              free >= 0
                  ? s.pick('Serbest kalan ${money(free)} ${monthName(nm, s.lang)} ayının gelirine eklensin', 'Add the ${money(free)} left free to ${monthName(nm, s.lang)}\'s income')
                  : s.pick('Açık (${money(free)}) ${monthName(nm, s.lang)} ayına devretsin', 'Carry the shortfall (${money(free)}) over to ${monthName(nm, s.lang)}'),
              style: sans(13.5),
            ),
          ),
      ],
    );
  }
}

/// Ayı geri açar (sonraki ay kapalıysa önce o açılmalı).
Future<void> reopenMonthDialog(BuildContext context, String m) async {
  final st = AppScope.of(context);
  final s = S.of(context);
  final nm = addM(m, 1);
  if (st.data.closeOf(nm) != null) {
    toast(context, s.pick('Önce ${monthLabel(nm, s.lang)} ayını geri aç.', 'Reopen ${monthLabel(nm, s.lang)} first.'));
    return;
  }
  final ok = await confirmDialog(
    context,
    title: s.pick('${monthLabel(m, s.lang)} geri açılsın mı?', 'Reopen ${monthLabel(m, s.lang)}?'),
    text: s.pick('Taşınan kalemler ${monthName(m, s.lang)} ayına geri döner, ${monthName(nm, s.lang)} ayına devredilen tutar çıkarılır. Ödemelere dokunulmaz.',
        'Moved items return to ${monthName(m, s.lang)} and the amount carried to ${monthName(nm, s.lang)} is removed. Payments are not touched.'),
    ok: s.pick('Geri aç', 'Reopen'),
  );
  if (!ok || !context.mounted) return;
  final snap = st.snapshot();
  st.update((d) => reopenMonth(d, m));
  toast(context, s.pick('${monthLabel(m, s.lang)} yeniden açıldı.', '${monthLabel(m, s.lang)} is open again.'), undo: () => st.restore(snap));
}
