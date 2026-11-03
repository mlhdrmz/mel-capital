// Para hareketleri: harcama, hızlı giriş, aktarma, kart borcu ödeme, ödeme düzenleme, hesap ve kart.

import 'package:flutter/material.dart';

import '../../core/actions.dart';
import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../dialogs.dart';
import '../i18n.dart';
import '../pages/common.dart';
import '../sheet.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

// ---------------------------------------------------------------- Harcama

class SpendSheet extends StatefulWidget {
  const SpendSheet({super.key, this.spend, this.prefill});

  final Spend? spend;
  final Json? prefill;

  @override
  State<SpendSheet> createState() => _SpendSheetState();
}

class _SpendSheetState extends State<SpendSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _place = TextEditingController();
  final _note = TextEditingController();
  final _url = TextEditingController();
  String _date = todayISO();
  String? _source;
  int _inst = 1;
  String? _first;
  bool _firstTouched = false;
  String _cat = '';
  bool _catTouched = false;
  bool _srcTouched = false;
  bool _showUrl = false;
  String? _error;
  LearnedSpend? _learned;
  String? _goalId;

  @override
  void initState() {
    super.initState();
    final sp = widget.spend;
    final pre = widget.prefill ?? const <String, dynamic>{};
    _goalId = pre['goalId'] as String?;
    if (sp != null) {
      _name.text = sp.name;
      _amount.text = fmtNum(toK(sp.amount));
      _place.text = sp.place;
      _note.text = sp.note;
      _url.text = sp.url;
      _date = sp.date;
      _source = sp.source;
      _inst = sp.installments;
      _first = sp.firstMonth;
      _firstTouched = sp.firstMonth != null;
      _cat = sp.category;
      _catTouched = true;
      _srcTouched = true;
    } else {
      _name.text = (pre['name'] ?? '').toString();
      final a = pre['amount'];
      if (a is num && a > 0) _amount.text = fmtNum(toK(a));
      _place.text = (pre['place'] ?? '').toString();
      _url.text = (pre['url'] ?? '').toString();
      if (isDate(pre['date'])) _date = pre['date'] as String;
      _inst = pre['installments'] is int ? pre['installments'] as int : 1;
      _cat = (pre['category'] ?? '').toString();
      _catTouched = _cat.isNotEmpty;
      if (pre.containsKey('source')) {
        _source = pre['source'] as String?;
        _srcTouched = true;
      }
    }
    _showUrl = _url.text.isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final st = AppScope.of(context);
    if (widget.spend == null && !_srcTouched && _source == null) _source = favSource(st.data);
    if (!_catTouched && _cat.isEmpty) _cat = _name.text.isEmpty ? 'diger' : smartCategory(st.data, _name.text);
    _syncFirst();
    if (widget.spend == null && _name.text.isNotEmpty) _suggest();
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _place, _note, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFirst() {
    final cid = srcCard(_source);
    if (cid != null && !_firstTouched) {
      _first = nextStatementMonth(AppScope.of(context).data.debt(cid), isDate(_date) ? _date : todayISO());
    }
  }

  void _guess() {
    if (_catTouched) return;
    _cat = smartCategory(AppScope.of(context).data, '${_name.text} ${_place.text}');
  }

  void _suggest() {
    if (widget.spend != null) return;
    final d = AppScope.of(context).data;
    final l = learned(d, _name.text) ?? learned(d, _place.text);
    _learned = l != null && l.k > 0 ? l : null;
    final src = l?.source;
    if (src != null && !_srcTouched && (d.account(srcAcc(src)) != null || d.debt(srcCard(src)) != null)) {
      _source = src;
      _syncFirst();
    }
  }

  Outcome _read() {
    final s = S.of(context);
    final name = _name.text.trim();
    final place = _place.text.trim();
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil (ör. 85 veya 340,50).', 'The amount is not valid (e.g. 85 or 340.50).'));
    if (name.isEmpty && place.isEmpty) return Outcome.err(s.pick('Ne aldığını yaz.', 'Write what you bought.'));
    if (!isDate(_date)) return Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.'));
    final cid = srcCard(_source);
    var inst = 1;
    String? first;
    if (cid != null) {
      inst = _inst;
      first = _first;
      if (!isMonth(first)) return Outcome.err(s.pick('İlk taksit ayı seçilmeli.', 'Pick the month of the first instalment.'));
    }
    final cat = _cat.trim().isEmpty ? 'diger' : _cat.trim();
    final ur = _url.text.trim();
    final url = ur.isEmpty ? '' : safeUrl(ur);
    if (ur.isNotEmpty && url.isEmpty) return Outcome.err(s.pick('Link geçerli değil (https:// ile başlamalı).', 'The link is not valid (it should start with https://).'));
    final rec = <String, dynamic>{
      'date': _date,
      'name': name.isEmpty ? place : name,
      'place': place,
      'category': cat,
      'amount': fromK(k),
      'source': _source,
      'installments': inst,
      'firstMonth': first,
      'note': _note.text.trim(),
      'url': url,
    };
    final id = widget.spend?.id;
    final goalId = _goalId;
    return Outcome.ok((d) => saveSpend(d, rec, id: id, goalId: goalId), focus: cid != null ? first : _date.substring(0, 7), cardId: cid, source: _source);
  }

  void _save({bool again = false}) {
    final s = S.of(context);
    final o = _read();
    if (!o.ok) {
      setState(() => _error = o.error);
      return;
    }
    final edit = widget.spend != null;
    if (again) {
      commitOutcome(context, o, s.pick('Harcama eklendi.', 'Spend added.'), close: false);
      setState(() {
        _name.clear();
        _amount.clear();
        _place.clear();
        _note.clear();
        _url.clear();
        _catTouched = false;
        _cat = 'diger';
        _learned = null;
        _error = null;
      });
      return;
    }
    commitOutcome(
      context,
      o,
      party: _goalId != null,
      _goalId != null ? s.pick('Alındı olarak işaretlendi. 🎉', 'Marked as bought. 🎉') : (edit ? s.pick('Harcama güncellendi.', 'Spend updated.') : s.pick('Harcama eklendi.', 'Spend added.')),
    );
  }

  void _delete() {
    final st = AppScope.of(context);
    final s = S.of(context);
    final sp = widget.spend;
    if (sp == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final snap = st.snapshot();
    st.update((d) => deleteSpend(d, sp.id));
    Navigator.of(context).pop();
    showToast(messenger, s.lang, s.pick('"${sp.name.isEmpty ? 'Harcama' : sp.name}" silindi${srcAcc(sp.source) != null ? '; tutar hesaba geri eklendi' : ''}.', '"${sp.name.isEmpty ? 'Spend' : sp.name}" deleted${srcAcc(sp.source) != null ? '; the amount went back to the account' : ''}.'),
        undo: () => st.restore(snap), seconds: 6);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final sp = widget.spend;
    final goal = _goalId == null ? null : d.goal(_goalId);
    final cid = srcCard(_source);
    final o = _read();
    final instOpts = {...kInstallmentOptions, _inst}.toList()..sort();
    final saved = goal == null ? 0 : (st.ctx.model.goals[goal.id]?.saved ?? 0);
    return SheetFrame(
      title: sp != null ? s.pick('Harcamayı düzenle', 'Edit spend') : (goal != null ? s.pick('${goal.emoji} ${goal.name} alındı', '${goal.emoji} ${goal.name} bought') : s.pick('Harcama ekle', 'Add a spend')),
      subtitle: goal != null
          ? s.pick('Hedef "alındı" olarak işaretlenir.${saved > 0 ? ' Ayırdığın ${fmtMoney(saved, lang: s.lang)} birikimden çıkıp bütçeye döner; harcamanın tamamı seçtiğin yerden düşer.' : ''}',
              'The goal is marked as bought.${saved > 0 ? ' The ${fmtMoney(saved, lang: s.lang)} you set aside returns to the budget; the full amount comes from the source you pick.' : ''}')
          : null,
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, noLiquid: true, extra: (b, a) => sourceImpact(b, a, _source, s.lang)),
      leftActions: [
        if (sp != null) GlassButton(label: s.pick('Sil', 'Delete'), icon: Icons.delete_outline, danger: true, onTap: _delete),
      ],
      actions: [
        if (sp == null && goal == null) GlassButton(label: s.pick('Kaydet ve yeni', 'Save and new'), onTap: () => _save(again: true)),
        GoldButton(label: s.pick('Kaydet', 'Save'), icon: Icons.check, onTap: _save),
      ],
      children: [
        FieldBox(
          label: s.pick('Ne aldın?', 'What did you buy?'),
          child: TextInput(
            controller: _name,
            autofocus: sp == null,
            hint: s.pick('ör. Kahve, market, kulaklık', 'e.g. Coffee, groceries, headphones'),
            onChanged: (_) => setState(() {
              _guess();
              _suggest();
              _error = null;
            }),
            onSubmitted: (_) => _save(),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Tutar', 'Amount'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextInput(controller: _amount, big: true, number: true, suffix: 'TL', hint: s.pick('ör. 85', 'e.g. 85'), onChanged: (_) => setState(() => _error = null), onSubmitted: (_) => _save()),
              if (_learned != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SmallButton(
                      label: s.pick('Son: ', 'Last: ') + fmtMoney(_learned!.k, lang: s.lang) + (_learned!.date.isNotEmpty ? ' · ${fmtDayShort(_learned!.date, s.lang)}' : ''),
                      icon: Icons.history,
                      onTap: () => setState(() => _amount.text = fmtNum(_learned!.k, lang: s.lang)),
                    ),
                  ),
                ),
            ]),
          ),
          right: FieldBox(
            label: s.pick('Tarih', 'Date'),
            child: DateInput(value: _date, onChanged: (v) => setState(() {
                  _date = v;
                  _syncFirst();
                })),
          ),
        ),
        FieldBox(
          label: s.pick('Nereden ödedin?', 'Paid from'),
          child: SourceSelect(
            value: _source,
            none: s.pick('Kaynak seçme (bakiyeye dokunma)', 'No source (leave balances as they are)'),
            onChanged: (v) => setState(() {
              _source = v;
              _srcTouched = true;
              _syncFirst();
            }),
          ),
        ),
        if (cid != null)
          FieldPair(
            left: FieldBox(
              label: s.pick('Taksit', 'Instalments'),
              child: GlassSelect<int>(
                value: _inst,
                items: [for (final n in instOpts) (n, n == 1 ? s.pick('Tek çekim', 'Single payment') : s.pick('$n taksit', '$n instalments'))],
                onChanged: (v) => setState(() => _inst = v ?? 1),
              ),
            ),
            right: FieldBox(
              label: s.pick('İlk taksitin ekstre ayı', 'Statement month of the first instalment'),
              child: MonthInput(value: _first, onChanged: (v) => setState(() {
                    _first = v;
                    _firstTouched = true;
                  })),
            ),
          ),
        FieldBox(
          label: s.pick('Kategori', 'Category'),
          child: CategoryPicker(value: _cat, onChanged: (v) => setState(() {
                _cat = v;
                _catTouched = true;
              })),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Nerede? (isteğe bağlı)', 'Where? (optional)'),
            child: TextInput(controller: _place, hint: s.pick('ör. Migros, Trendyol', 'e.g. a shop'), onChanged: (_) => setState(_guess)),
          ),
          right: FieldBox(label: s.pick('Not (isteğe bağlı)', 'Note (optional)'), child: TextInput(controller: _note)),
        ),
        if (_showUrl)
          FieldBox(label: s.pick('Ürün linki', 'Product link'), child: TextInput(controller: _url, hint: 'https://...', onChanged: (_) => setState(() {})))
        else
          Align(
            alignment: Alignment.centerLeft,
            child: SmallButton(label: s.pick('Ürün linki ekle', 'Add a product link'), icon: Icons.link, onTap: () => setState(() => _showUrl = true)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Hızlı giriş

class QuickSpendSheet extends StatefulWidget {
  const QuickSpendSheet({super.key, this.source});

  final String? source;

  @override
  State<QuickSpendSheet> createState() => _QuickSpendSheetState();
}

class _QuickSpendSheetState extends State<QuickSpendSheet> {
  bool _total = false;
  final _text = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  String _cat = 'diger';
  String? _source;
  String _date = todayISO();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = S.of(context);
    _source = widget.source ?? favSource(AppScope.of(context).data);
    _name.text = s.pick('Günlük harcamalar', 'Everyday spending');
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  (Outcome, List<QuickLine>) _read() {
    final s = S.of(context);
    final d = AppScope.of(context).data;
    final lines = parseQuickLines(d, _text.text);
    if (!isDate(_date)) return (Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.')), lines);
    List<(String, int, String)> rows;
    if (!_total) {
      final ok = lines.where((r) => r.ok).toList();
      if (ok.isEmpty) return (Outcome.err(s.pick('En az bir satıra ad ve tutar yaz (ör. kahve 85).', 'Write a name and an amount on at least one line (e.g. coffee 85).')), lines);
      if (ok.length < lines.length) {
        return (Outcome.err(s.pick('${lines.length - ok.length} satırda tutar bulunamadı; düzelt ya da sil.', 'No amount found on ${lines.length - ok.length} lines; fix or remove them.')), lines);
      }
      rows = [for (final r in ok) (r.name, r.k, r.cat)];
    } else {
      final k = parseAmount(_amount.text);
      if (k == null || k <= 0) return (Outcome.err(s.pick('Toplam tutar geçerli değil.', 'The total is not valid.')), lines);
      rows = [(_name.text.trim().isEmpty ? s.pick('Günlük harcamalar', 'Everyday spending') : _name.text.trim(), k, _cat.isEmpty ? 'diger' : _cat)];
    }
    final cid = srcCard(_source);
    final first = cid != null ? nextStatementMonth(d.debt(cid), _date) : null;
    final source = _source;
    final date = _date;
    return (Outcome.ok((data) => saveQuickSpends(data, rows, date: date, source: source, firstMonth: first), focus: first ?? date.substring(0, 7), cardId: cid, source: source), lines);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (o, lines) = _read();
    final okLines = lines.where((r) => r.ok).toList();
    String money(int k) => fmtMoney(k, lang: s.lang);
    return SheetFrame(
      title: s.pick('Hızlı giriş', 'Quick entry'),
      subtitle: s.pick('Birçok küçük harcamayı tek seferde gir.', 'Enter many small spends at once.'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, noLiquid: true, extra: (b, a) => sourceImpact(b, a, _source, s.lang)),
      actions: [
        GoldButton(
          label: !_total && okLines.isNotEmpty ? s.pick('Kaydet (${okLines.length})', 'Save (${okLines.length})') : s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) {
              setState(() => _error = o.error);
              return;
            }
            final n = _total ? 1 : okLines.length;
            final total = _total ? (parseAmount(_amount.text) ?? 0) : sumK(okLines, (QuickLine r) => r.k);
            commitOutcome(context, o, s.pick('$n harcama eklendi (${money(total)}).', '$n spends added (${money(total)}).'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Nasıl?', 'How?'),
          child: Seg<bool>(
            value: _total,
            options: [(false, s.pick('Satır satır', 'Line by line')), (true, s.pick('Tek toplam', 'One total'))],
            onChanged: (v) => setState(() {
              _total = v;
              _error = null;
            }),
          ),
        ),
        if (!_total) ...[
          FieldBox(
            label: s.pick('Her satıra ad ve tutar', 'A name and amount on each line'),
            help: s.pick('Virgülle de ayırabilirsin: "kahve 85, market 340". Kategori addan tahmin edilir.', 'Commas work too: "coffee 85, groceries 340". The category is guessed from the name.'),
            child: TextInput(controller: _text, maxLines: 6, autofocus: true, hint: s.pick('kahve 85\nmarket 340,50\nsimit 15, otobüs 27', 'coffee 85\ngroceries 340.50'), onChanged: (_) => setState(() => _error = null)),
          ),
          if (lines.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              decoration: BoxDecoration(color: const Color(0x26000000), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                for (final r in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: r.ok ? catColor(r.cat) : MC.rose, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.ok ? r.name : r.raw, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(13))),
                      Text(r.ok ? catLabel(r.cat, s.lang) : s.pick('tutar bulunamadı', 'no amount found'), style: sans(11.5, color: r.ok ? MC.muted : MC.rose)),
                      const SizedBox(width: 10),
                      SizedBox(width: 92, child: Text(r.ok ? money(r.k) : '—', textAlign: TextAlign.right, style: sans(13, weight: FontWeight.w700))),
                    ]),
                  ),
                const Hairline(),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(child: Text(s.pick('${okLines.length} harcama', '${okLines.length} spends'), style: sans(13, weight: FontWeight.w700))),
                    Text(money(sumK(okLines, (QuickLine r) => r.k)), style: sans(13.5, weight: FontWeight.w700, color: MC.gold)),
                  ]),
                ),
              ]),
            ),
        ] else ...[
          FieldPair(
            left: FieldBox(label: s.pick('Ad', 'Name'), child: TextInput(controller: _name, onChanged: (_) => setState(() => _cat = smartCategory(AppScope.of(context).data, _name.text)))),
            right: FieldBox(label: s.pick('Toplam tutar', 'Total amount'), child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, onChanged: (_) => setState(() {}))),
          ),
          FieldBox(label: s.pick('Kategori', 'Category'), child: CategoryPicker(value: _cat, onChanged: (v) => setState(() => _cat = v))),
        ],
        FieldPair(
          left: FieldBox(
            label: s.pick('Nereden ödendi?', 'Paid from'),
            child: SourceSelect(value: _source, none: s.pick('Kaynak seçme (bakiyeye dokunma)', 'No source (leave balances as they are)'), onChanged: (v) => setState(() => _source = v)),
          ),
          right: FieldBox(label: s.pick('Tarih', 'Date'), child: DateInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Aktarma

class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, this.transfer, this.from, this.to});

  final Transfer? transfer;
  final String? from;
  final String? to;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _from = 'ext';
  String? _to;
  String _date = todayISO();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final d = AppScope.of(context).data;
    final t = widget.transfer;
    final accs = accountsSorted(d);
    if (t != null) {
      _from = t.from;
      _to = t.to;
      _amount.text = fmtNum(toK(t.amount));
      _note.text = t.note;
      _date = t.date;
      return;
    }
    _from = widget.from ?? (accs.isNotEmpty ? 'acc:${accs.first.id}' : 'ext');
    if (widget.to != null) {
      _to = widget.to;
    } else {
      Account? cash;
      for (final a in accs) {
        if ('acc:${a.id}' != _from && a.isCash) cash = a;
      }
      _to = cash != null ? 'acc:${cash.id}' : (accs.length > 1 ? 'acc:${accs[1].id}' : null);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final st = AppScope.of(context);
    final from = _from, to = _to;
    if (to == null || to.isEmpty) return Outcome.err(s.pick('Nereye aktarılacağını seç.', 'Pick where the money goes.'));
    if (from == to) return Outcome.err(s.pick('Kaynak ve hedef aynı olamaz.', 'The source and target cannot be the same.'));
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil.', 'The amount is not valid.'));
    if (!isDate(_date)) return Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.'));
    final note = _note.text.trim();
    final date = _date;
    final cid = srcCard(to);
    if (cid != null) {
      final debt = st.data.debt(cid);
      if (debt == null) return Outcome.err(s.pick('Kart bulunamadı.', 'Card not found.'));
      final m = cardPayMonth(st.ctx, debt);
      return Outcome.ok((d) => payCard(d, cid, m, k, date, from), focus: m, cardId: cid);
    }
    final id = widget.transfer?.id;
    return Outcome.ok((d) => saveTransfer(d, id: id, from: from, to: to, k: k, date: date, note: note), focus: date.substring(0, 7));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    final t = widget.transfer;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final accs = accountsSorted(d);
    final fromItems = <(String, String)>[
      ('ext', s.pick('Dışarıdan para girişi (maaş, gelen havale)', 'Money coming in (salary, incoming transfer)')),
      for (final a in accs) ('acc:${a.id}', '${accLabel(a, s.lang)} · ${money(toK(a.balance))}'),
    ];
    final toItems = <(String, String)>[
      for (final a in accs) ('acc:${a.id}', '${accLabel(a, s.lang)} · ${money(toK(a.balance))}'),
      if (t == null)
        for (final x in d.debts.where((x) => x.isCard))
          ('card:${x.id}', s.pick('${x.creditor} borcuna · borç ${money(ctx.model.debts[x.id]?.current ?? 0)}', 'To ${x.creditor} · debt ${money(ctx.model.debts[x.id]?.current ?? 0)}')),
    ];
    final o = _read();
    final info = srcCard(_to) != null
        ? s.pick('Karta yapılan aktarma, kart borcu ödemesi olarak kaydedilir: borç düşer, limit açılır.', 'A transfer to a card is saved as a card payment: the debt goes down and the limit frees up.')
        : _from == 'ext'
            ? s.pick('Dışarıdan giren para yalnızca hesabın bakiyesini artırır; gelir planını değiştirmez.', 'Money coming in only raises the account balance; it does not change the income plan.')
            : null;
    return SheetFrame(
      title: t != null ? s.pick('Aktarmayı düzenle', 'Edit transfer') : s.pick('Para aktar', 'Move money'),
      subtitle: s.pick('Hesaplar arası para, bankadan nakit çekme, maaşın hesaba girmesi ya da karta ödeme.', 'Between accounts, cash withdrawal, salary coming in or paying a card.'),
      error: _error,
      impact: ImpactBox(
        outcome: o.ok ? o : null,
        noFree: true,
        noLiquid: true,
        extra: (b, a) => [
          ...sourceImpact(b, a, _from, s.lang),
          if (srcAcc(_to) != null) ...sourceImpact(b, a, _to, s.lang),
          if (srcCard(_to) != null) ...cardDebtImpact(b, a, srcCard(_to)!, s.lang),
        ],
      ),
      leftActions: [
        if (t != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              final snap = st.snapshot();
              st.update((data) => deleteTransfer(data, t.id));
              Navigator.of(context).pop();
              showToast(messenger, s.lang, s.pick('Aktarma silindi; bakiyeler geri alındı.', 'Transfer deleted; balances restored.'), undo: () => st.restore(snap));
            },
          ),
      ],
      actions: [
        GoldButton(
          label: t != null ? s.pick('Kaydet', 'Save') : s.pick('Aktar', 'Move'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) {
              setState(() => _error = o.error);
              return;
            }
            commitOutcome(context, o, srcCard(_to) != null ? s.pick('Kart ödemesi kaydedildi.', 'Card payment saved.') : (t != null ? s.pick('Aktarma güncellendi.', 'Transfer updated.') : s.pick('Aktarıldı.', 'Moved.')));
          },
        ),
      ],
      children: [
        FieldBox(label: s.pick('Nereden?', 'From'), child: GlassSelect<String>(value: _from, items: fromItems, onChanged: (v) => setState(() => _from = v ?? 'ext'))),
        Align(
          alignment: Alignment.center,
          child: IconButton(
            tooltip: s.pick('Yönü değiştir', 'Swap'),
            onPressed: _from == 'ext' || srcCard(_to) != null || _to == null
                ? null
                : () => setState(() {
                      final a = _from;
                      _from = _to!;
                      _to = a;
                    }),
            icon: const Icon(Icons.swap_vert, color: MC.gold),
          ),
        ),
        FieldBox(label: s.pick('Nereye?', 'To'), child: GlassSelect<String>(value: _to, items: toItems, onChanged: (v) => setState(() => _to = v))),
        FieldPair(
          left: FieldBox(label: s.pick('Tutar', 'Amount'), child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, hint: s.pick('ör. 1.000', 'e.g. 1,000'), onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(label: s.pick('Tarih', 'Date'), child: DateInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        ),
        FieldBox(label: s.pick('Not (isteğe bağlı)', 'Note (optional)'), child: TextInput(controller: _note)),
        if (info != null) Text(info, style: sans(12, color: MC.dim, height: 1.4)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Kart borcu öde

class CardPaySheet extends StatefulWidget {
  const CardPaySheet({super.key, this.debt});

  final Debt? debt;

  @override
  State<CardPaySheet> createState() => _CardPaySheetState();
}

class _CardPaySheetState extends State<CardPaySheet> {
  final _amount = TextEditingController();
  String? _sel;
  String? _from;
  String _date = todayISO();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final ctx = AppScope.of(context).ctx;
    final cards = ctx.data.debts.where((x) => x.isCard).toList()..sort((a, b) => (ctx.model.debts[b.id]?.current ?? 0) - (ctx.model.debts[a.id]?.current ?? 0));
    _sel = widget.debt != null && cards.any((c) => c.id == widget.debt!.id) ? widget.debt!.id : (cards.isEmpty ? null : cards.first.id);
    final accs = accountsSorted(ctx.data);
    _from = (_sel == null ? null : lastFromFor(ctx.data, 'debt', _sel!)) ?? (accs.isNotEmpty ? 'acc:${accs.first.id}' : null);
    _fillQuick();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  List<(String, int)> _quick() {
    final ctx = AppScope.of(context).ctx;
    final s = S.of(context);
    final sel = _sel;
    if (sel == null) return const [];
    final debt = ctx.data.debt(sel);
    final info = ctx.model.debts[sel];
    if (debt == null || info == null) return const [];
    final m = cardPayMonth(ctx, debt);
    Statement? st;
    for (final x in debt.statements) {
      if (x.month == m) st = x;
    }
    final paidK = ctx.model.pay('debt', sel, m)?.k ?? 0;
    final q = <(String, int)>[];
    final stx = st;
    if (stx != null && stx.minimum != null && toK(stx.minimum) > paidK) q.add((s.pick('Asgari kalan', 'Minimum left'), toK(stx.minimum) - paidK));
    if (stx != null && toK(stx.total) > paidK) {
      final left = toK(stx.total) - paidK;
      q.add((s.pick('Ekstre kalan', 'Statement left'), left < info.current ? left : info.current));
    }
    if (info.current > 0) q.add((s.pick('Tüm borç', 'Whole debt'), info.current));
    return q;
  }

  void _fillQuick() {
    final q = _quick();
    if (_amount.text.isEmpty && q.isNotEmpty) _amount.text = fmtNum(q.first.$2, lang: S.of(context).lang);
  }

  Outcome _read() {
    final s = S.of(context);
    final st = AppScope.of(context);
    final sel = _sel;
    if (sel == null) return Outcome.err(s.pick('Kart seç.', 'Pick a card.'));
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) return Outcome.err(s.pick('Tutar geçerli değil (ör. 1.500 veya 1499,90).', 'The amount is not valid (e.g. 1,500 or 1499.90).'));
    if (!isDate(_date)) return Outcome.err(s.pick('Tarih geçerli değil.', 'The date is not valid.'));
    final debt = st.data.debt(sel);
    if (debt == null) return Outcome.err(s.pick('Kart bulunamadı.', 'Card not found.'));
    final m = cardPayMonth(st.ctx, debt);
    final from = _from, date = _date;
    return Outcome.ok((d) => payCard(d, sel, m, k, date, from), focus: m, cardId: sel);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final cards = ctx.data.debts.where((x) => x.isCard).toList();
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    if (cards.isEmpty) {
      return SheetFrame(
        title: s.pick('Kredi kartı yok', 'No credit card'),
        actions: [GoldButton(label: s.pick('Tamam', 'OK'), onTap: () => Navigator.of(context).pop())],
        children: [Text(s.pick('Önce Borçlar sayfasından bir kredi kartı ekle.', 'Add a credit card on the Debts page first.'), style: sans(14, color: MC.muted))],
      );
    }
    final o = _read();
    final sel = _sel;
    final debt = sel == null ? null : ctx.data.debt(sel);
    String? info;
    if (debt != null) {
      final m = cardPayMonth(ctx, debt);
      Statement? stm;
      for (final x in debt.statements) {
        if (x.month == m) stm = x;
      }
      final paidK = ctx.model.pay('debt', debt.id, m)?.k ?? 0;
      info = s.pick('${monthLabel(m, s.lang)} ödemesi olarak kaydedilir.', 'Saved as the ${monthLabel(m, s.lang)} payment.') +
          (stm != null
              ? s.pick(
                  ' Ekstre ${money(toK(stm.total))}${stm.minimum != null ? ', asgari ${money(toK(stm.minimum))}' : ''}${paidK > 0 ? ', ödenen ${money(paidK)}' : ''}.',
                  ' Statement ${money(toK(stm.total))}${stm.minimum != null ? ', minimum ${money(toK(stm.minimum))}' : ''}${paidK > 0 ? ', paid ${money(paidK)}' : ''}.')
              : '');
    }
    return SheetFrame(
      title: s.pick('Kart borcu öde', 'Pay a card'),
      subtitle: s.pick('Ödeme kart borcundan düşer, limit açılır; seçtiğin hesabın bakiyesi azalır.', 'The payment comes off the card debt and frees the limit; the account you pick goes down.'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, noFree: true, extra: (b, a) => sel == null ? const [] : cardDebtImpact(b, a, sel, s.lang)),
      actions: [
        GoldButton(
          label: s.pick('Öde', 'Pay'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) {
              setState(() => _error = o.error);
              return;
            }
            commitOutcome(context, o, s.pick('Kart ödemesi kaydedildi.', 'Card payment saved.'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Hangi kart?', 'Which card?'),
          child: Column(children: [
            for (final c in cards)
              Builder(builder: (_) {
                final info = ctx.model.debts[c.id];
                final on = c.id == _sel;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _sel = c.id;
                      _amount.clear();
                      final lf = lastFromFor(ctx.data, 'debt', c.id);
                      if (lf != null) _from = lf;
                      _fillQuick();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: on ? MC.gold.withValues(alpha: 0.16) : const Color(0x26000000),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: on ? MC.gold : const Color(0x26FFFFFF)),
                      ),
                      child: Row(children: [
                        Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: on ? MC.gold : MC.muted),
                        const SizedBox(width: 10),
                        BankPlate(bankKey: bankKeyOf(c), name: c.creditor, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.creditor, style: sans(14, weight: FontWeight.w600)),
                            Text(
                              s.pick('Borç ${money(info?.current ?? 0)}', 'Debt ${money(info?.current ?? 0)}') +
                                  (info?.limit != null ? s.pick(' · boş ${money(info!.available ?? 0)}', ' · available ${money(info.available ?? 0)}') : ''),
                              style: sans(12, color: MC.muted),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
          ]),
        ),
        FieldBox(
          label: s.pick('Tutar', 'Amount'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final q in _quick()) SmallButton(label: '${q.$1} ${fmtMoney(q.$2, lang: s.lang, hidden: st.hidden)}', icon: Icons.bolt, onTap: () => setState(() => _amount.text = fmtNum(q.$2, lang: s.lang))),
            ]),
            const SizedBox(height: 6),
            TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, onChanged: (_) => setState(() => _error = null)),
          ]),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Hangi hesaptan?', 'From which account?'),
            child: SourceSelect(value: _from, cards: false, none: s.pick('Hesap seçme (bakiyeye dokunma)', 'No account (leave balances as they are)'), onChanged: (v) => setState(() => _from = v)),
          ),
          right: FieldBox(label: s.pick('Tarih', 'Date'), child: DateInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        ),
        if (info != null) Text(info, style: sans(12, color: MC.dim, height: 1.4)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Ödeme düzenleme

class PaySheet extends StatefulWidget {
  const PaySheet({super.key, required this.kind, required this.refId, required this.month});

  final String kind;
  final String refId;
  final String month;

  @override
  State<PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<PaySheet> {
  final _amount = TextEditingController();
  final Map<String, TextEditingController> _alloc = {};
  String _date = todayISO();
  String? _from;
  String? _error;
  bool _init = false;

  PlanItem? _item(Ctx ctx) {
    for (final x in ctx.items(widget.month)) {
      if (x.kind == widget.kind && x.refId == widget.refId && !x.carry) return x;
    }
    return null;
  }

  List<String> _linked(Ctx ctx, PlanItem it) => widget.kind == 'expense' ? it.linked.where((id) => ctx.data.debt(id) != null).toList() : const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final st = AppScope.of(context);
    final ctx = st.ctx;
    final lang = S.of(context).lang;
    final it = _item(ctx);
    if (it == null) return;
    final pay = it.pay;
    _amount.text = fmtNum(pay?.k ?? it.planned, lang: lang);
    if (pay != null && isDate(pay.paidDate)) _date = pay.paidDate!;
    if (pay != null) {
      for (final p in pay.list) {
        if (p.fromAccount != null) {
          _from = p.fromAccount;
          break;
        }
      }
    } else {
      _from = defaultPayFrom(ctx.data, it);
    }
    final linked = _linked(ctx, it);
    final defaults = pay != null ? const <(String, int)>[] : (linked.length > 1 ? proportionalSplit(ctx.model, it.planned, linked) : [for (final id in linked) (id, it.planned)]);
    for (final id in linked) {
      int v;
      if (pay != null) {
        v = sumK(ctx.data.payments.where((p) => p.viaRefId == widget.refId && p.kind == 'debt' && p.refId == id && p.month == widget.month), (Payment p) => toK(p.paidAmount));
      } else {
        v = 0;
        for (final x in defaults) {
          if (x.$1 == id) v = x.$2;
        }
      }
      _alloc[id] = TextEditingController(text: v > 0 ? fmtNum(v, lang: lang) : '');
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    for (final c in _alloc.values) {
      c.dispose();
    }
    super.dispose();
  }

  Outcome _read() {
    final s = S.of(context);
    final k = parseAmount(_amount.text);
    if (k == null || k <= 0) {
      return Outcome.err(s.pick('Ödenen tutar geçerli değil (ör. 2.500 veya 2500,50). Ödeme yapılmadıysa işareti kaldır.', 'The paid amount is not valid (e.g. 2,500 or 2500.50). If nothing was paid, remove the mark.'));
    }
    if (!isDate(_date)) return Outcome.err(s.pick('Ödeme tarihi geçerli değil.', 'The payment date is not valid.'));
    final allocs = <(String, int)>[];
    for (final e in _alloc.entries) {
      final raw = e.value.text.trim();
      if (raw.isEmpty) continue;
      final v = parseAmount(raw);
      if (v == null) return Outcome.err(s.pick('Borç dağılımındaki bir tutar geçerli değil.', 'An amount in the debt split is not valid.'));
      if (v > 0) allocs.add((e.key, v));
    }
    if (allocs.fold<int>(0, (a, x) => a + x.$2) > k) return Outcome.err(s.pick('Borçlara dağıtılan toplam, ödenen tutarı geçemez.', 'The split cannot be more than the amount paid.'));
    final kind = widget.kind, refId = widget.refId, m = widget.month, date = _date, from = _from;
    return Outcome.ok((d) => savePayment(d, kind: kind, refId: refId, month: m, k: k, date: date, from: from, allocs: allocs), focus: m);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final it = _item(ctx);
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    if (it == null) {
      return SheetFrame(
        title: s.pick('Kalem bulunamadı', 'Item not found'),
        actions: [GoldButton(label: s.pick('Tamam', 'OK'), onTap: () => Navigator.of(context).pop())],
        children: const [],
      );
    }
    final m = widget.month;
    final o = _read();
    final pct = (kMinPayRate * 100).round();
    final planTxt = it.est ? s.pick("${money(it.planned)} (ekstre girilmedi; borcun %$pct'si kadar tahmini asgari)", '${money(it.planned)} (no statement; estimated minimum of $pct% of the debt)') : money(it.planned);
    final stx = it.st;
    final stTxt = stx != null
        ? s.pick(' · ekstre ${money(toK(stx.total))}${stx.minimum != null ? ', asgari ${money(toK(stx.minimum))}' : ''}', ' · statement ${money(toK(stx.total))}${stx.minimum != null ? ', minimum ${money(toK(stx.minimum))}' : ''}')
        : '';
    final info = widget.kind == 'debt' ? ctx.model.debts[widget.refId] : null;
    final linked = _linked(ctx, it);
    return SheetFrame(
      title: it.name,
      subtitle: s.pick('${monthLabel(m, s.lang)} · Planlanan: $planTxt$stTxt', '${monthLabel(m, s.lang)} · Planned: $planTxt$stTxt'),
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, extra: (b, a) => [...sourceImpact(b, a, _from, s.lang), if (it.card) ...cardDebtImpact(b, a, it.refId, s.lang)]),
      leftActions: [
        if (it.pay != null)
          GlassButton(
            label: s.pick('İşareti kaldır', 'Remove mark'),
            danger: true,
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              final snap = st.snapshot();
              st.update((d) => removePaymentFor(d, widget.kind, widget.refId, m));
              Navigator.of(context).pop();
              showToast(messenger, s.lang, s.pick('"Ödendi" işareti kaldırıldı.', '"Paid" mark removed.'), undo: () => st.restore(snap));
            },
          ),
        if (it.card) ...[
          const SizedBox(width: 8),
          GlassButton(
            label: it.st != null ? s.pick('Ekstreyi düzenle', 'Edit statement') : s.pick('Ekstre gir', 'Enter statement'),
            icon: Icons.receipt_long_outlined,
            onTap: () {
              final debt = ctx.data.debt(it.refId);
              Navigator.of(context).pop();
              if (debt != null) openStatementSheet(context, debt);
            },
          ),
        ],
      ],
      actions: [
        GoldButton(
          label: it.pay != null ? s.pick('Kaydet', 'Save') : s.pick('Ödendi olarak kaydet', 'Save as paid'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) {
              setState(() => _error = o.error);
              return;
            }
            commitOutcome(context, o, s.pick('Ödeme kaydedildi.', 'Payment saved.'));
          },
        ),
      ],
      children: [
        FieldPair(
          left: FieldBox(label: s.pick('Ödenen tutar', 'Amount paid'), child: TextInput(controller: _amount, big: true, number: true, suffix: 'TL', autofocus: true, onChanged: (_) => setState(() => _error = null))),
          right: FieldBox(label: s.pick('Ödeme tarihi', 'Payment date'), child: DateInput(value: _date, onChanged: (v) => setState(() => _date = v))),
        ),
        FieldBox(
          label: s.pick('Hangi hesaptan ödendi?', 'Paid from which account?'),
          help: s.pick('Seçersen tutar o hesabın bakiyesinden düşülür; işaret kaldırılınca geri eklenir.', 'If you pick one, the amount comes off its balance; it goes back if you remove the mark.'),
          child: SourceSelect(value: _from, cards: false, none: s.pick('Hesap seçme (bakiyeye dokunma)', 'No account (leave balances as they are)'), onChanged: (v) => setState(() => _from = v)),
        ),
        if (it.card && info?.snap != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              s.pick('Kart bakiyesi ${fmtDate(info!.snap, s.lang)} tarihinde girildi; bu tarihte ya da önce yapılan ödemeler o bakiyeye dahil sayılır.',
                  'The card balance was entered on ${fmtDate(info.snap, s.lang)}; payments on or before that date count as included in it.'),
              style: sans(12, color: MC.dim, height: 1.4),
            ),
          ),
        if (linked.isNotEmpty)
          FieldBox(
            label: s.pick('Borçlara dağılım', 'Split across debts'),
            help: s.pick('Bu ödemenin hangi borca ne kadar gittiği. Toplam, ödenen tutarı geçemez.', 'How much of this payment went to each debt. The total cannot exceed the amount paid.'),
            child: Column(children: [
              for (final id in linked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ctx.data.debt(id)?.creditor ?? '', style: sans(13.5, weight: FontWeight.w600)),
                        Text(s.pick('Borç: ', 'Debt: ') + money(ctx.model.debts[id]?.current ?? 0), style: sans(11.5, color: MC.muted)),
                      ]),
                    ),
                    SizedBox(width: 160, child: TextInput(controller: _alloc[id]!, number: true, suffix: 'TL', hint: '0', onChanged: (_) => setState(() {}))),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Hesap

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key, this.account, this.bank, this.type});

  final Account? account;
  final String? bank;
  final String? type;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final _balance = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();
  String _bank = '';
  String _type = 'vadesiz';
  bool _nameTouched = false;
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final lang = S.of(context).lang;
    final a = widget.account;
    if (a != null) {
      _bank = a.bank;
      _type = a.type.isEmpty ? 'diger' : a.type;
      _name.text = a.name;
      _note.text = a.note;
      final k = toK(a.balance);
      _balance.text = k < 0 ? '-${fmtNum(-k, lang: lang)}' : fmtNum(k, lang: lang);
      _nameTouched = true;
    } else {
      _bank = widget.bank ?? '';
      _type = widget.type ?? ((kBanks[_bank]?.wallet ?? false) ? 'cuzdan' : (_bank.isNotEmpty ? 'vadesiz' : 'nakit'));
      _autoName();
    }
  }

  @override
  void dispose() {
    _balance.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _autoName() {
    if (_nameTouched) return;
    final s = S.of(context);
    _name.text = _bank.isNotEmpty
        ? bankName(_bank, s.lang) + (_type == 'vadesiz' ? s.pick(' vadesiz', ' current') : '')
        : (_type == 'nakit' ? s.pick('Elde nakit', 'Cash') : '');
  }

  Outcome _read() {
    final s = S.of(context);
    if (_bank.isEmpty && _type != 'nakit' && _type != 'diger') return Outcome.err(s.pick('Banka seçilmeli (nakit için türü "Elde nakit" yap).', 'Pick a bank (for cash, set the type to "Cash").'));
    final name = _name.text.trim();
    if (name.isEmpty) return Outcome.err(s.pick('Hesap adı gerekli.', 'The account needs a name.'));
    final k = parseSigned(_balance.text);
    if (k == null) return Outcome.err(s.pick('Bakiye geçerli bir tutar değil (ör. 3.250,40).', 'The balance is not a valid amount (e.g. 3,250.40).'));
    final id = widget.account?.id, bank = _bank, type = _type, note = _note.text.trim();
    return Outcome.ok((d) => saveAccount(d, id: id, bank: bank, name: name, type: type, balanceK: k, note: note), focus: currentMonth());
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final a = widget.account;
    final keys = kBanks.entries.where((e) => !e.value.notBank).map((e) => e.key).toList();
    if (_bank.isNotEmpty && !keys.contains(_bank)) keys.add(_bank);
    final o = _read();
    return SheetFrame(
      title: a != null ? accLabel(a, s.lang) : s.pick('Hesap ekle', 'Add an account'),
      subtitle: a != null ? s.pick('Son güncelleme ${fmtDate(a.asOf, s.lang)}', 'Last updated ${fmtDate(a.asOf, s.lang)}') : null,
      error: _error,
      impact: ImpactBox(outcome: o.ok ? o : null, noFree: true),
      leftActions: [
        if (a != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: s.pick('Hesabı sil', 'Delete the account'),
                text: s.pick('"${a.name}" hesabı silinecek. Bu hesaba bağlı kartların bağlantısı kaldırılır; geçmiş harcama ve aktarmalar kayıtta kalır.',
                    '"${a.name}" will be deleted. Cards linked to it are unlinked; past spends and transfers stay on record.'),
                danger: true,
              );
              if (!ok || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              final snap = st.snapshot();
              st.update((d) => deleteAccount(d, a.id));
              Navigator.of(context).pop();
              showToast(messenger, s.lang, s.pick('Hesap silindi.', 'Account deleted.'), undo: () => st.restore(snap));
            },
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (!o.ok) {
              setState(() => _error = o.error);
              return;
            }
            commitOutcome(context, o, a != null ? s.pick('Bakiye güncellendi.', 'Balance updated.') : s.pick('Hesap eklendi.', 'Account added.'));
          },
        ),
      ],
      children: [
        FieldBox(
          label: s.pick('Bakiye', 'Balance'),
          help: s.pick('Bankanın uygulamasındaki güncel bakiyeyi yaz. Eksi bakiye için başına "-" koy.', 'Type the current balance from your bank app. Use "-" for a negative balance.'),
          child: TextInput(controller: _balance, big: true, number: true, suffix: 'TL', autofocus: true, hint: s.pick('ör. 3.250,40', 'e.g. 3,250.40'), onChanged: (_) => setState(() => _error = null)),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Banka', 'Bank'),
            child: GlassSelect<String>(
              value: _bank,
              items: [('', s.pick('Banka yok (nakit vb.)', 'No bank (cash etc.)')), for (final k in keys) (k, bankName(k, s.lang))],
              onChanged: (v) => setState(() {
                _bank = v ?? '';
                _autoName();
              }),
            ),
          ),
          right: FieldBox(
            label: s.pick('Tür', 'Type'),
            child: GlassSelect<String>(
              value: _type,
              items: [for (final e in kAccountTypes.entries) (e.key, e.value.of(s.lang))],
              onChanged: (v) => setState(() {
                _type = v ?? 'diger';
                _autoName();
              }),
            ),
          ),
        ),
        FieldBox(
          label: s.pick('Hesap adı', 'Account name'),
          child: TextInput(controller: _name, hint: s.pick('ör. Maaş hesabı', 'e.g. Salary account'), onChanged: (_) => setState(() => _nameTouched = true)),
        ),
        FieldBox(label: s.pick('Not', 'Note'), child: TextInput(controller: _note, maxLines: 2)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Kart (görünüm ve bağlantılar)

const Map<String, Lbl> _patternNames = {
  'none': Lbl('Düz', 'Plain'),
  'lines': Lbl('Çizgiler', 'Lines'),
  'waves': Lbl('Dalgalar', 'Waves'),
  'dots': Lbl('Noktalar', 'Dots'),
  'rings': Lbl('Halkalar', 'Rings'),
  'geo': Lbl('Geometrik', 'Geometric'),
  'glow': Lbl('Işıltı', 'Glow'),
  'confetti': Lbl('Konfeti', 'Confetti'),
};

const Map<String, Lbl> _inkNames = {
  'light': Lbl('Açık', 'Light'),
  'dark': Lbl('Koyu', 'Dark'),
  'gold': Lbl('Altın', 'Gold'),
};

const List<String> _swatches = [
  '#e2322f', '#7a0f12', '#a24d9e', '#2c1235', '#1f6fb2', '#0c2a4a', '#0f8a6c', '#08372c',
  '#f2a900', '#6b4a00', '#3a3a3a', '#111111', '#c9c2b8', '#5a534a', '#d64f8a', '#4a1430',
];

class CardSheet extends StatefulWidget {
  const CardSheet({super.key, this.card, this.bank});

  final BankCard? card;
  final String? bank;

  @override
  State<CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<CardSheet> {
  final _name = TextEditingController();
  String _bank = '';
  String _kind = 'banka';
  bool _active = true;
  String? _network = 'Mastercard';
  String? _accountId;
  String? _debtId;
  String _c1 = '#3a3a3a', _c2 = '#111111', _ink = 'light', _pattern = 'lines';
  String? _accent;
  bool _colorsTouched = false;
  String? _error;
  bool _init = false;

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  void _defaultColors() {
    final b = kBanks[_bank];
    _c1 = b != null ? _hex(b.c1) : '#3a3a3a';
    _c2 = b != null ? _hex(b.c2) : '#111111';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final c = widget.card;
    if (c != null) {
      _name.text = c.name;
      _bank = c.bank;
      _kind = c.kind.isEmpty ? 'banka' : c.kind;
      _active = c.active;
      _network = c.network;
      _accountId = c.accountId;
      _debtId = c.debtId;
      final st = c.style;
      _c1 = st.c1.isEmpty ? _c1 : st.c1;
      _c2 = st.c2.isEmpty ? _c2 : st.c2;
      _ink = st.ink;
      _pattern = st.pattern;
      _accent = st.accent;
      _colorsTouched = true;
    } else {
      _bank = widget.bank ?? '';
      _defaultColors();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final d = st.data;
    final c = widget.card;
    final keys = kBanks.entries.where((e) => !e.value.notBank).map((e) => e.key).toList();
    if (_bank.isNotEmpty && !keys.contains(_bank)) keys.add(_bank);
    final look = CardLook(hexColor(_c1, const Color(0xFF3A3A3A)), hexColor(_c2, const Color(0xFF111111)), _ink, _pattern, _accent == null ? null : hexColor(_accent, MC.gold));
    Widget colorRow(String current, ValueChanged<String> onPick) => Wrap(spacing: 6, runSpacing: 6, children: [
          for (final h in _swatches)
            InkWell(
              onTap: () => onPick(h),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: hexColor(h, Colors.black),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: current.toLowerCase() == h ? MC.gold : const Color(0x40FFFFFF), width: current.toLowerCase() == h ? 2.4 : 1),
                ),
              ),
            ),
        ]);
    return SheetFrame(
      title: c != null ? s.pick('Kartı düzenle', 'Edit card') : s.pick('Kart ekle', 'Add a card'),
      error: _error,
      leftActions: [
        if (c != null)
          GlassButton(
            label: s.pick('Sil', 'Delete'),
            icon: Icons.delete_outline,
            danger: true,
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: s.pick('Kartı sil', 'Delete the card'),
                text: s.pick('"${c.name}" kartının görseli ve bağlantıları silinecek. Bağlı borç ve hesap kayıtları silinmez.', 'The "${c.name}" card and its links will be deleted. Linked debt and account records stay.'),
                danger: true,
              );
              if (!ok || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              final snap = st.snapshot();
              st.update((data) => deleteCard(data, c.id));
              Navigator.of(context).pop();
              showToast(messenger, s.lang, s.pick('Kart silindi.', 'Card deleted.'), undo: () => st.restore(snap));
            },
          ),
      ],
      actions: [
        GoldButton(
          label: s.pick('Kaydet', 'Save'),
          icon: Icons.check,
          onTap: () {
            if (_bank.isEmpty) return setState(() => _error = s.pick('Banka seçilmeli.', 'Pick a bank.'));
            final name = _name.text.trim();
            if (name.isEmpty) return setState(() => _error = s.pick('Kart adı gerekli.', 'The card needs a name.'));
            final rec = <String, dynamic>{
              'bank': _bank,
              'name': name,
              'kind': _kind,
              'status': _active ? 'aktif' : 'kapali',
              'network': _network,
              'accountId': _accountId,
              'debtId': _debtId,
              'style': <String, dynamic>{'c1': _c1, 'c2': _c2, 'ink': _ink, 'pattern': _pattern, 'accent': _accent},
            };
            final id = c?.id;
            commitOutcome(context, Outcome.ok((data) => saveCard(data, rec, id: id)), c != null ? s.pick('Kart güncellendi.', 'Card updated.') : s.pick('Kart eklendi.', 'Card added.'));
          },
        ),
      ],
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CardTile(
              look: look,
              bankKey: _bank.isEmpty ? null : _bank,
              name: _name.text.isEmpty ? s.pick('Kart adı', 'Card name') : _name.text,
              kindLabel: kCardKinds[_kind] ?? const Lbl('Kart', 'Card'),
              midLabel: const Lbl('', ''),
              network: _network,
              closed: !_active,
              onTap: () {},
            ),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Banka', 'Bank'),
            child: GlassSelect<String>(
              value: _bank,
              items: [('', s.pick('Seç…', 'Pick…')), for (final k in keys) (k, bankName(k, s.lang))],
              onChanged: (v) => setState(() {
                _bank = v ?? '';
                if (!_colorsTouched) _defaultColors();
              }),
            ),
          ),
          right: FieldBox(label: s.pick('Kart adı', 'Card name'), child: TextInput(controller: _name, hint: s.pick('ör. Platinum', 'e.g. Platinum'), onChanged: (_) => setState(() {}))),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Tür', 'Type'),
            child: GlassSelect<String>(value: _kind, items: [for (final e in kCardKinds.entries) (e.key, e.value.of(s.lang))], onChanged: (v) => setState(() => _kind = v ?? 'banka')),
          ),
          right: FieldBox(
            label: s.pick('Durum', 'Status'),
            child: Seg<bool>(value: _active, options: [(true, s.pick('Açık', 'Open')), (false, s.pick('Kapalı', 'Closed'))], onChanged: (v) => setState(() => _active = v)),
          ),
        ),
        FieldPair(
          left: FieldBox(
            label: s.pick('Kart ağı', 'Network'),
            child: GlassSelect<String>(
              value: _network ?? '',
              items: [('', s.pick('belirtilmemiş', 'not set')), for (final n in kNetworks) (n, n)],
              onChanged: (v) => setState(() => _network = v == null || v.isEmpty ? null : v),
            ),
          ),
          right: FieldBox(
            label: s.pick('Bağlı hesap', 'Linked account'),
            child: GlassSelect<String>(
              value: _accountId ?? '',
              items: [('', s.pick('Yok', 'None')), for (final a in d.accounts) (a.id, accLabel(a, s.lang))],
              onChanged: (v) => setState(() => _accountId = v == null || v.isEmpty ? null : v),
            ),
          ),
        ),
        FieldBox(
          label: s.pick('Bağlı borç kaydı', 'Linked debt record'),
          help: s.pick('Kredi kartında limit ve borç bu kayıttan gelir. Kapalı bir kartın yapılandırmasını da buradan bağlayabilirsin.',
              'For a credit card, the limit and debt come from this record. You can also link a closed card\'s restructured debt here.'),
          child: GlassSelect<String>(
            value: _debtId ?? '',
            items: [('', s.pick('Yok', 'None')), for (final x in d.debts) (x.id, '${x.creditor} (${(kDebtTypes[x.type] ?? const Lbl('Borç', 'Debt')).of(s.lang)})')],
            onChanged: (v) => setState(() => _debtId = v == null || v.isEmpty ? null : v),
          ),
        ),
        FieldBox(label: s.pick('Renk 1', 'Colour 1'), child: colorRow(_c1, (h) => setState(() {
              _c1 = h;
              _colorsTouched = true;
            }))),
        FieldBox(label: s.pick('Renk 2', 'Colour 2'), child: colorRow(_c2, (h) => setState(() {
              _c2 = h;
              _colorsTouched = true;
            }))),
        FieldPair(
          left: FieldBox(
            label: s.pick('Yazı rengi', 'Text colour'),
            child: GlassSelect<String>(value: _ink, items: [for (final e in _inkNames.entries) (e.key, e.value.of(s.lang))], onChanged: (v) => setState(() => _ink = v ?? 'light')),
          ),
          right: FieldBox(
            label: s.pick('Desen', 'Pattern'),
            child: GlassSelect<String>(value: _pattern, items: [for (final e in _patternNames.entries) (e.key, e.value.of(s.lang))], onChanged: (v) => setState(() => _pattern = v ?? 'none')),
          ),
        ),
        Text(
          s.pick('Kart görseli gerçek kartın kopyası değil; banka rengi, desen ve kart adıyla hatırlatıcı bir çizim. Kart numarası gibi bilgiler girilmez, saklanmaz.',
              'The card picture is not a copy of the real card, just a reminder drawn with the bank colour, a pattern and the card name. Card numbers and similar details are never entered or stored.'),
          style: sans(12, color: MC.dim, height: 1.4),
        ),
      ],
    );
  }
}
