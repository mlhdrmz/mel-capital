// Borçlar: borç / kredi kartı kaydı, ödeme planı satırları, ekstre ve kart bakiyesi.

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

/// 1–31 arası gün (boş = belirtilmemiş).
(int?, String?) readDay(String text, String label, String lang) {
  final v = text.trim();
  if (v.isEmpty) return (null, null);
  final n = int.tryParse(v);
  if (n == null || n < 1 || n > 31) return (null, lang == 'tr' ? '$label 1 ile 31 arasında olmalı.' : '$label must be between 1 and 31.');
  return (n, null);
}

String moneyText(double? tl, String lang) => tl == null ? '' : fmtNum(toK(tl), lang: lang);

// ---------------------------------------------------------------- Plan satırları

class SchedRow {
  SchedRow(this.from, this.to, String amount) : amount = TextEditingController(text: amount);
  String? from;
  String? to;
  final TextEditingController amount;
}

/// Aylık ödeme / gelir planı: her satır bir dönem ve o dönemdeki aylık tutar.
class SchedEditor extends StatefulWidget {
  const SchedEditor({super.key, required this.rows, required this.openEnd, required this.defaultStart, required this.onChanged});

  final List<SchedRow> rows;
  final bool openEnd;
  final String defaultStart;
  final VoidCallback onChanged;

  @override
  State<SchedEditor> createState() => _SchedEditorState();
}

class _SchedEditorState extends State<SchedEditor> {
  void _add() {
    final rows = widget.rows;
    final last = rows.isEmpty ? null : rows.last;
    var start = widget.defaultStart;
    if (last != null && isMonth(last.to)) {
      start = addM(last.to!, 1);
    } else if (last != null && widget.openEnd && isMonth(last.from)) {
      start = maxMonth(addM(last.from!, 1), currentMonth());
      last.to = addM(start, -1);
    }
    setState(() => rows.add(SchedRow(start, null, last?.amount.text ?? '')));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < widget.rows.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(color: const Color(0x26000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x1FFFFFFF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FieldPair(
              left: FieldBox(
                label: s.pick('Başlangıç ayı', 'Start month'),
                bottom: 8,
                child: MonthInput(value: widget.rows[i].from, allowEmpty: true, onChanged: (v) {
                  setState(() => widget.rows[i].from = v);
                  widget.onChanged();
                }),
              ),
              right: FieldBox(
                label: widget.openEnd ? s.pick('Bitiş ayı (boş = süresiz)', 'End month (empty = open-ended)') : s.pick('Bitiş ayı', 'End month'),
                bottom: 8,
                child: MonthInput(value: widget.rows[i].to, allowEmpty: true, onChanged: (v) {
                  setState(() => widget.rows[i].to = v);
                  widget.onChanged();
                }),
              ),
            ),
            Row(children: [
              Expanded(child: TextInput(controller: widget.rows[i].amount, number: true, suffix: 'TL', hint: s.pick('Aylık tutar', 'Monthly amount'), onChanged: (_) => widget.onChanged())),
              IconButton(
                tooltip: s.pick('Satırı sil', 'Delete row'),
                onPressed: () {
                  setState(() => widget.rows.removeAt(i).amount.dispose());
                  widget.onChanged();
                },
                icon: const Icon(Icons.delete_outline, color: MC.rose),
              ),
            ]),
          ]),
        ),
      GlassButton(label: s.pick('Plan satırı ekle', 'Add a plan row'), icon: Icons.add, onTap: _add),
    ]);
  }
}

List<(String?, String?, int?)> readSched(List<SchedRow> rows) => [for (final r in rows) (r.from, r.to, parseAmount(r.amount.text))];

// ---------------------------------------------------------------- Borç / kredi kartı

class DebtSheet extends StatefulWidget {
  const DebtSheet({super.key, this.debt, this.type});

  final Debt? debt;
  final String? type;

  @override
  State<DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<DebtSheet> {
  final _cred = TextEditingController();
  final _rem = TextEditingController();
  final _limit = TextEditingController();
  final _stDay = TextEditingController();
  final _dueDay = TextEditingController();
  final _payDay = TextEditingController();
  final _note = TextEditingController();
  final List<SchedRow> _rows = [];
  String _type = '';
  String _bank = '';
  bool _bankTouched = false;
  String _plan = 'asgari';
  String _bDate = todayISO();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final lang = S.of(context).lang;
    final x = widget.debt;
    if (x != null) {
      _cred.text = x.creditor;
      _type = x.type;
      _bank = bankKeyOf(x) ?? '';
      _bankTouched = true;
      _rem.text = fmtNum(toK(x.remaining), lang: lang);
      _limit.text = moneyText(x.limit, lang);
      _stDay.text = x.statementDay?.toString() ?? '';
      _dueDay.text = x.dueDay?.toString() ?? '';
      _payDay.text = x.payDay?.toString() ?? '';
      _note.text = x.note;
      _plan = x.payPlan;
      if (isDate(x.balanceDate)) _bDate = x.balanceDate!;
      final sched = x.schedule.toList()..sort((a, b) => a.from.compareTo(b.from));
      for (final r in sched) {
        _rows.add(SchedRow(r.from, r.to, fmtNum(toK(r.amount), lang: lang)));
      }
    } else {
      _type = widget.type ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_cred, _rem, _limit, _stDay, _dueDay, _payDay, _note]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final d = AppScope.of(context).data;
    final creditor = _cred.text.trim();
    if (creditor.isEmpty) return Outcome.err(s.pick('Ad gerekli.', 'A name is needed.'));
    if (_type.isEmpty) return Outcome.err(s.pick('Tür seçilmeli.', 'Pick a type.'));
    final remK = parseAmount(_rem.text);
    if (remK == null) return Outcome.err(s.pick('Bakiye geçerli bir tutar değil (ör. 12.500,50).', 'The balance is not a valid amount (e.g. 12,500.50).'));
    final cc = _type == 'kredi_karti';
    double? limit;
    String? balanceDate;
    int? statementDay, dueDay, payDay;
    var sched = <Json>[];
    if (cc) {
      final lr = _limit.text.trim();
      if (lr.isNotEmpty) {
        final lk = parseAmount(lr);
        if (lk == null) return Outcome.err(s.pick('Kart limiti geçerli bir tutar değil.', 'The card limit is not a valid amount.'));
        limit = fromK(lk);
      }
      if (!isDate(_bDate)) return Outcome.err(s.pick('Bakiye tarihi geçerli değil.', 'The balance date is not valid.'));
      balanceDate = _bDate;
      final (sd, e1) = readDay(_stDay.text, s.pick('Hesap kesim günü', 'Statement day'), s.lang);
      if (e1 != null) return Outcome.err(e1);
      final (dd, e2) = readDay(_dueDay.text, s.pick('Son ödeme günü', 'Due day'), s.lang);
      if (e2 != null) return Outcome.err(e2);
      statementDay = sd;
      dueDay = dd;
    } else {
      final (pd, e3) = readDay(_payDay.text, s.pick('Ödeme günü', 'Payment day'), s.lang);
      if (e3 != null) return Outcome.err(e3);
      payDay = pd;
      final (v, e4) = validateSched(readSched(_rows), openEnd: false, lang: s.lang);
      if (e4 != null) return Outcome.err(e4);
      sched = v;
    }
    final x = widget.debt;
    final changedBal = x == null || toK(x.remaining) != remK || x.balanceDate != balanceDate;
    final rec = <String, dynamic>{
      'creditor': creditor,
      'type': _type,
      'bank': _bank,
      'remaining': fromK(remK),
      'limit': limit,
      'schedule': sched,
      'note': _note.text.trim(),
      'payDay': payDay,
      'statementDay': statementDay,
      'dueDay': dueDay,
      'balanceDate': balanceDate,
      'payPlan': _plan,
      if (cc && changedBal) 'balanceAt': nowISO(),
    };
    final id = x?.id;
    return Outcome.ok((data) => saveDebt(data, rec, id: id), focus: maxMonth(currentMonth(), isMonth(d.balancesAsOf) ? d.balancesAsOf : currentMonth()));
  }

  Future<void> _delete() async {
    final st = AppScope.of(context);
    final s = S.of(context);
    final x = widget.debt;
    if (x == null) return;
    final n = st.data.payments.where((p) => p.kind == 'debt' && p.refId == x.id).length;
    final sp = st.data.spends.where((p) => srcCard(p.source) == x.id).length;
    final ok = await confirmDialog(
      context,
      title: s.pick('Borcu sil', 'Delete the debt'),
      text: s.pick(
        '"${x.creditor}" kaydı${n > 0 ? ' ve ona ait $n ödeme işareti' : ''} silinecek.${sp > 0 ? ' Bu kartla yapılan $sp harcama kayıtta kalır ama kaynağı boşalır.' : ''} Hesaplardan yapılmış ödemeler bakiyelere geri eklenmez.',
        '"${x.creditor}"${n > 0 ? ' and its $n payment marks' : ''} will be deleted.${sp > 0 ? ' $sp spends made with this card stay, without a source.' : ''} Payments made from accounts are not added back to balances.',
      ),
      danger: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final snap = st.snapshot();
    st.update((d) => deleteDebt(d, x.id));
    Navigator.of(context).pop();
    showToast(messenger, s.lang, s.pick('Borç silindi.', 'Debt deleted.'), undo: () => st.restore(snap));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final x = widget.debt;
    final cc = _type == 'kredi_karti';
    final types = <String, Lbl>{...kDebtTypes};
    if (x != null && x.type.isNotEmpty && !types.containsKey(x.type)) types[x.type] = Lbl(x.type, x.type);
    final o = _read();
    final base = isMonth(d.balancesAsOf) ? d.balancesAsOf : currentMonth();
    return SheetFrame(
      title: x != null ? x.creditor : s.pick('Borç ya da kredi kartı ekle', 'Add a debt or credit card'),
      subtitle: x != null
          ? '${(kDebtTypes[x.type] ?? const Lbl('Borç', 'Debt')).of(s.lang)} · ${s.pick('kalan', 'left')} ${fmtMoney(st.ctx.model.debts[x.id]?.current ?? 0, lang: s.lang, hidden: st.hidden)}'
          : null,
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null),
      leftActions: [if (x != null) GlassButton(label: s.pick('Sil', 'Delete'), icon: Icons.delete_outline, danger: true, onTap: _delete)],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, x != null ? s.pick('Borç güncellendi.', 'Debt updated.') : s.pick('Borç eklendi.', 'Debt added.'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Ad', 'Name'),
          child: TextInput(
            controller: _cred,
            autofocus: x == null,
            hint: s.pick('ör. Kart yapılandırması, Gold kredi kartı', 'e.g. Restructured card debt, Gold credit card'),
            onChanged: (v) => setState(() {
              if (x == null && !_bankTouched) _bank = detectBank(v) ?? '';
              _error = null;
            }),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Tür', 'Type'),
            child: GlassSelect<String>(
              value: _type,
              items: [('', s.pick('Seç…', 'Pick…')), for (final e in types.entries) (e.key, e.value.of(s.lang))],
              onChanged: (v) => setState(() => _type = v ?? ''),
            ),
          ),
          right: FieldBox(
            label: s.pick('Banka (logo)', 'Bank (logo)'),
            child: GlassSelect<String>(
              value: _bank,
              items: [('', s.pick('Logo yok / diğer', 'No logo / other')), for (final k in kBanks.keys) (k, kBanks[k]!.name)],
              onChanged: (v) => setState(() {
                _bank = v ?? '';
                _bankTouched = true;
              }),
            ),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: cc ? s.pick('Güncel borç', 'Current debt') : s.pick('Kalan bakiye', 'Remaining balance'),
            child: TextInput(controller: _rem, number: true, suffix: 'TL', hint: s.pick('ör. 12.500,50', 'e.g. 12,500.50'), onChanged: (_) => setState(() => _error = null)),
          ),
          right: cc
              ? FieldBox(label: s.pick('Bakiye tarihi', 'Balance date'), child: DateInput(value: _bDate, onChanged: (v) => setState(() => _bDate = v)))
              : FieldBox(label: s.pick('Ödeme günü', 'Payment day'), child: TextInput(controller: _payDay, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            cc
                ? s.pick('Bankanın uygulamasında görünen güncel borç. Bakiyeyi sonradan güncellemek için Borçlar › kalem simgesini kullan.', 'The current debt shown in your bank app. To update it later, use the pencil on the Debts page.')
                : s.pick('${monthLabel(base, s.lang)} başındaki bakiye. O tarihten sonra "ödendi" işaretlenen ödemeler bundan düşülür.', 'The balance at the start of ${monthLabel(base, s.lang)}. Payments marked as paid after that come off it.'),
            style: sans(11.5, color: MC.dim, height: 1.4),
          ),
        ),
        if (cc) ...[
          FieldPair(
            left: FieldBox(label: s.pick('Kart limiti', 'Card limit'), child: TextInput(controller: _limit, number: true, suffix: 'TL', hint: s.pick('ör. 5.000', 'e.g. 5,000'), onChanged: (_) => setState(() {}))),
            right: FieldBox(
              label: s.pick('Ekstre ödemesi', 'Statement payment'),
              child: Seg<String>(value: _plan, options: [('asgari', s.pick('Asgari öde', 'Pay minimum')), ('tamami', s.pick('Tamamını öde', 'Pay in full'))], onChanged: (v) => setState(() => _plan = v)),
            ),
          ),
          FieldPair(
            left: FieldBox(label: s.pick('Hesap kesim günü', 'Statement day'), child: TextInput(controller: _stDay, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
            right: FieldBox(label: s.pick('Son ödeme günü', 'Due day'), child: TextInput(controller: _dueDay, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
          ),
        ] else
          FieldBox(
            label: s.pick('Aylık ödeme planı', 'Monthly payment plan'),
            help: s.pick('Her satır bir dönem ve o dönemdeki aylık tutar.', 'Each row is a period and its monthly amount.'),
            child: SchedEditor(rows: _rows, openEnd: false, defaultStart: maxMonth(currentMonth(), base), onChanged: () => setState(() {})),
          ),
        FieldBox(label: s.pick('Not', 'Note'), child: TextInput(controller: _note, maxLines: 2)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Ekstre

class StatementSheet extends StatefulWidget {
  const StatementSheet({super.key, required this.debt, this.month});

  final Debt debt;
  final String? month;

  @override
  State<StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends State<StatementSheet> {
  final _total = TextEditingController();
  final _min = TextEditingController();
  final _cut = TextEditingController();
  final _due = TextEditingController();
  String? _month;
  String _plan = 'asgari';
  String? _error;
  bool _init = false;

  Statement? _existing(String? m) {
    for (final s in widget.debt.statements) {
      if (s.month == m) return s;
    }
    return null;
  }

  void _fill() {
    final lang = S.of(context).lang;
    final ex = _existing(_month);
    if (ex != null) {
      _total.text = fmtNum(toK(ex.total), lang: lang);
      _min.text = moneyText(ex.minimum, lang);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final debt = widget.debt;
    var m = isMonth(widget.month) ? widget.month : null;
    if (m == null) {
      final t = todayISO(), day = dayOf(t), cm = monthOf(t);
      final sd = debt.statementDay, dd = debt.dueDay;
      final lastCut = sd != null ? (day >= sd ? cm : addM(cm, -1)) : cm;
      m = dd != null && sd != null && dd < sd ? addM(lastCut, 1) : lastCut;
      if (_existing(m) != null) m = addM(m, 1);
    }
    _month = m;
    _plan = debt.payPlan;
    _cut.text = debt.statementDay?.toString() ?? '';
    _due.text = debt.dueDay?.toString() ?? '';
    _fill();
  }

  @override
  void dispose() {
    for (final c in [_total, _min, _cut, _due]) {
      c.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final m = _month;
    if (!isMonth(m)) return Outcome.err(s.pick('Ekstre ayı seçilmeli.', 'Pick the statement month.'));
    final tk = parseAmount(_total.text);
    if (tk == null) return Outcome.err(s.pick('Ekstre borcu geçerli bir tutar değil (ör. 4.320,15).', 'The statement amount is not valid (e.g. 4,320.15).'));
    int? mk;
    final mr = _min.text.trim();
    if (mr.isNotEmpty) {
      mk = parseAmount(mr);
      if (mk == null) return Outcome.err(s.pick('Asgari ödeme geçerli bir tutar değil.', 'The minimum payment is not valid.'));
      if (mk > tk) return Outcome.err(s.pick('Asgari ödeme ekstre borcundan büyük olamaz.', 'The minimum cannot be more than the statement.'));
    }
    final (cut, e1) = readDay(_cut.text, s.pick('Hesap kesim günü', 'Statement day'), s.lang);
    if (e1 != null) return Outcome.err(e1);
    final (due, e2) = readDay(_due.text, s.pick('Son ödeme günü', 'Due day'), s.lang);
    if (e2 != null) return Outcome.err(e2);
    final id = widget.debt.id, plan = _plan;
    return Outcome.ok((d) => saveStatement(d, id, month: m!, totalK: tk, minK: mk, cutDay: cut, dueDay: due, payPlan: plan), focus: m);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final debt = widget.debt;
    final o = _read();
    final ex = _existing(_month);
    return SheetFrame(
      title: s.pick('${debt.creditor} · ekstre', '${debt.creditor} · statement'),
      subtitle: s.pick('Bankanın gönderdiği hesap özetindeki tutarları gir. Ekstre, son ödeme gününün olduğu aya yazılır.', 'Enter the figures from the statement your bank sent. It is filed under the month of the due date.'),
      error: _error,
      impact: ImpactBox(
        outcome: o.ok ? o : null,
        extra: (b, a) {
          final m = o.focus;
          if (m == null) return const [];
          PlanItem? before, after;
          for (final x in b.items(m)) {
            if (x.refId == debt.id) before = x;
          }
          for (final x in a.items(m)) {
            if (x.refId == debt.id) after = x;
          }
          return after == null ? const [] : [ImpactLine(s.pick('${monthLabel(m, s.lang)} kart ödemesi', '${monthLabel(m, s.lang)} card payment'), before?.planned ?? 0, after.planned, upIsGood: false)];
        },
      ),
      leftActions: [
        if (ex != null)
          GlassButton(
            label: s.pick('Ekstreyi sil', 'Delete statement'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () async {
              final m = ex.month;
              final ok = await confirmDialog(context, title: s.pick('Ekstreyi sil', 'Delete statement'), text: s.pick('${monthLabel(m, s.lang)} ekstresi silinecek. Ödeme kayıtları silinmez.', 'The ${monthLabel(m, s.lang)} statement will be deleted. Payments stay.'), danger: true);
              if (!ok || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              final snap = st.snapshot();
              st.update((d) => deleteStatement(d, debt.id, m));
              Navigator.of(context).pop();
              showToast(messenger, s.lang, s.pick('Ekstre silindi.', 'Statement deleted.'), undo: () => st.restore(snap));
            },
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, s.pick('Ekstre kaydedildi; plan güncellendi.', 'Statement saved; the plan is updated.'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Ekstre ayı (son ödeme ayı)', 'Statement month (due month)'),
          child: MonthInput(value: _month, onChanged: (v) => setState(() {
                _month = v;
                _fill();
              })),
        ),
        FieldPair(
          left: FieldBox(label: s.pick('Ekstre borcu', 'Statement amount'), child: TextInput(controller: _total, number: true, suffix: 'TL', autofocus: true, hint: s.pick('ör. 4.320,15', 'e.g. 4,320.15'), onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(label: s.pick('Asgari ödeme', 'Minimum payment'), child: TextInput(controller: _min, number: true, suffix: 'TL', hint: s.pick('bilmiyorsan boş bırak', 'leave empty if unknown'), onChanged: (_) => setState(() {}))),
        ),
        FieldPair(
          left: FieldBox(label: s.pick('Hesap kesim günü', 'Statement day'), child: TextInput(controller: _cut, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
          right: FieldBox(label: s.pick('Son ödeme günü', 'Due day'), child: TextInput(controller: _due, number: true, hint: '1–31', onChanged: (_) => setState(() {}))),
        ),
        FieldBox(
          label: s.pick('Bu kartta ödeme planın', 'Your plan for this card'),
          help: s.pick('Plan ve kalan bütçe bu seçime göre hesaplanır. Ekstre girmek kart borcunu değiştirmez; borç ödemelerle düşer.', 'The plan and budget follow this choice. Entering a statement does not change the card debt; payments bring it down.'),
          child: Seg<String>(value: _plan, options: [('asgari', s.pick('Asgari öde', 'Pay minimum')), ('tamami', s.pick('Tamamını öde', 'Pay in full'))], onChanged: (v) => setState(() => _plan = v)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Kart bakiyesi

class CardBalanceSheet extends StatefulWidget {
  const CardBalanceSheet({super.key, required this.debt});

  final Debt debt;

  @override
  State<CardBalanceSheet> createState() => _CardBalanceSheetState();
}

class _CardBalanceSheetState extends State<CardBalanceSheet> {
  final _limit = TextEditingController();
  final _avail = TextEditingController();
  final _debt = TextEditingController();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final st = AppScope.of(context);
    final lang = S.of(context).lang;
    final info = st.ctx.model.debts[widget.debt.id];
    _limit.text = moneyText(widget.debt.limit, lang);
    if (info != null) {
      final av = info.available;
      if (info.limit != null && av != null && av >= 0) _avail.text = fmtNum(av, lang: lang);
      _debt.text = fmtNum(info.current, lang: lang);
    }
  }

  @override
  void dispose() {
    _limit.dispose();
    _avail.dispose();
    _debt.dispose();
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final lr = _limit.text.trim();
    int? l;
    if (lr.isNotEmpty) {
      l = parseAmount(lr);
      if (l == null) return Outcome.err(s.pick('Limit geçerli bir tutar değil.', 'The limit is not a valid amount.'));
    }
    final b = parseAmount(_debt.text);
    if (b == null) return Outcome.err(s.pick('Güncel borç geçerli bir tutar değil (ör. 2.750,40).', 'The current debt is not valid (e.g. 2,750.40).'));
    final id = widget.debt.id;
    return Outcome.ok((d) => setCardBalance(d, id, debtK: b, limitK: l), focus: currentMonth());
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final debt = widget.debt;
    final info = st.ctx.model.debts[debt.id];
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final o = _read();
    return SheetFrame(
      title: s.pick('${debt.creditor} · bakiye', '${debt.creditor} · balance'),
      subtitle: s.pick('Uygulamadaki güncel borç ${money(info?.current ?? 0)}${info?.limit != null ? ' · kullanılabilir ${money(info!.available ?? 0)}' : ''}',
          'Current debt in the app ${money(info?.current ?? 0)}${info?.limit != null ? ' · available ${money(info!.available ?? 0)}' : ''}'),
      error: _error,
      impact: ImpactBox(
        outcome: o.ok ? o : null,
        noFree: true,
        extra: (b, a) {
          final bD = b.model.debts[debt.id], aD = a.model.debts[debt.id];
          return aD != null && bD != null && aD.limit != null && bD.limit != null ? [ImpactLine(s.pick('Kullanılabilir limit', 'Available limit'), bD.available ?? 0, aD.available ?? 0)] : const [];
        },
      ),
      leftActions: [
        GlassButton(
          label: s.pick('Kart bilgileri', 'Card details'),
          onTap: () {
            Navigator.of(context).pop();
            showEditSheet<void>(context, builder: (_) => DebtSheet(debt: debt));
          },
        ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) return setState(() => _error = o.error);
            commitOutcome(context, o, s.pick('Kart bakiyesi güncellendi.', 'Card balance updated.'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Kart limiti', 'Card limit'),
          child: TextInput(controller: _limit, number: true, suffix: 'TL', hint: s.pick('ör. 5.000', 'e.g. 5,000'), onChanged: (_) {
            final l = parseAmount(_limit.text), b = parseAmount(_debt.text);
            if (l != null && b != null && l >= b) _avail.text = fmtNum(l - b, lang: s.lang);
            setState(() {});
          }),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Kullanılabilir limit', 'Available limit'),
            child: TextInput(controller: _avail, number: true, suffix: 'TL', autofocus: true, onChanged: (_) {
              final l = parseAmount(_limit.text), a = parseAmount(_avail.text);
              if (l != null && a != null) _debt.text = fmtNum(l - a > 0 ? l - a : 0, lang: s.lang);
              setState(() {});
            }),
          ),
          right: FieldBox(
            label: s.pick('Güncel borç', 'Current debt'),
            child: TextInput(controller: _debt, number: true, suffix: 'TL', onChanged: (_) {
              final l = parseAmount(_limit.text), b = parseAmount(_debt.text);
              if (l != null && b != null && l >= b) _avail.text = fmtNum(l - b, lang: s.lang);
              setState(() {});
            }),
          ),
        ),
        Text(
          s.pick('Bankanın uygulamasındaki kullanılabilir limiti ya da güncel borcu yaz; biri girilince diğeri limitten hesaplanır. Bu andan önce girilen ödeme ve harcamalar bu bakiyeye dahil sayılır, sonrakiler eklenir.',
              'Type the available limit or the current debt from your bank app; the other is worked out from the limit. Payments and spends entered before now count as included; later ones are added.'),
          style: sans(12, color: MC.dim, height: 1.4),
        ),
      ],
    );
  }
}
