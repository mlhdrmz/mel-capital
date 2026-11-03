import 'package:flutter/material.dart';

import '../../core/calc.dart';
import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../glass.dart';
import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';
import 'common.dart';

const String kCashKey = '__cash';

/// Kullanılan bankalar: hesap, kart ya da kredi kartı borcu olanlar (en "dolu" olan önce).
List<String> bankKeysInUse(Ctx ctx) {
  final d = ctx.data;
  final keys = <String>{};
  for (final a in d.accounts) {
    if (a.bank.isNotEmpty) keys.add(a.bank);
  }
  for (final c in d.cards) {
    if (c.bank.isNotEmpty) keys.add(c.bank);
  }
  for (final x in d.debts) {
    final k = bankKeyOf(x);
    if (k != null && x.isCard) keys.add(k);
  }
  int score(String k) {
    final ds = d.debts.where((x) => bankKeyOf(x) == k).toList();
    final debt = sumK(ds, (Debt x) => ctx.model.debts[x.id]?.current ?? 0);
    final bal = sumK(d.accounts.where((a) => a.bank == k), (Account a) => toK(a.balance));
    return (bal != 0 ? 4 : 0) + (ds.any((x) => x.isCard) ? 2 : 0) + (debt > 0 ? 1 : 0);
  }

  final list = keys.where((k) => !(kBanks[k]?.notBank ?? false)).toList();
  list.sort((a, b) {
    final c = score(b) - score(a);
    return c != 0 ? c : bankName(a, 'tr').compareTo(bankName(b, 'tr'));
  });
  return list;
}

List<Account> looseAccounts(Data d, List<String> keys) =>
    d.accounts.where((a) => a.bank.isEmpty || !keys.contains(a.bank)).toList();

class BankStats {
  BankStats(this.accts, this.cards, this.debts, this.bal, this.debtK, this.lim, this.avail);
  final List<Account> accts;
  final List<BankCard> cards;
  final List<Debt> debts;
  final int bal;
  final int debtK;
  final int lim;
  final int avail;
}

BankStats bankStats(Ctx ctx, String key) {
  final d = ctx.data;
  final accts = d.accounts.where((a) => a.bank == key).toList();
  final cards = d.cards.where((c) => c.bank == key).toList();
  final debts = d.debts.where((x) => bankKeyOf(x) == key).toList();
  final cardDebts = debts.where((x) => x.isCard);
  var lim = 0, avail = 0;
  for (final x in cardDebts) {
    final info = ctx.model.debts[x.id];
    if (info?.limit != null) {
      lim += info!.limit!;
      avail += info.available ?? 0;
    }
  }
  return BankStats(
    accts,
    cards,
    debts,
    sumK(accts, (Account a) => toK(a.balance)),
    sumK(debts, (Debt x) => ctx.model.debts[x.id]?.current ?? 0),
    lim,
    avail,
  );
}

class BankalarPage extends StatefulWidget {
  const BankalarPage({super.key});

  @override
  State<BankalarPage> createState() => _BankalarPageState();
}

class _BankalarPageState extends State<BankalarPage> {
  String? _bank;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Web önizlemesi: ?banka=akbank
    final p = AppScope.of(context).preview.remove('banka');
    if (p != null) _bank = p;
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final keys = bankKeysInUse(ctx);
    final loose = looseAccounts(ctx.data, keys);
    final sel = _bank;
    if (sel != null && (sel == kCashKey ? loose.isNotEmpty : keys.contains(sel))) {
      return _BankDetail(bankKey: sel, onBack: () => setState(() => _bank = null));
    }
    final actions = [
      GoldButton(label: s.pick('Para aktar', 'Transfer'), icon: Icons.swap_horiz, onTap: () => openTransferSheet(context)),
      GlassButton(label: s.pick('Hesap', 'Account'), icon: Icons.add, onTap: () => openAccountSheet(context)),
      GlassButton(label: s.pick('Kart', 'Card'), icon: Icons.add, onTap: () => openCardSheet(context)),
    ];
    if (keys.isEmpty && loose.isEmpty) {
      return PageFrame(
        eyebrow: s.pick('BANKALAR VE HESAPLAR', 'BANKS AND ACCOUNTS'),
        title: s.pick('Bankalarım', 'My banks'),
        actions: actions,
        children: [
          EmptyCard(
            icon: Icons.account_balance_outlined,
            title: s.pick('Henüz banka eklenmedi', 'No banks yet'),
            text: s.pick('Hesaplarını ve kartlarını ekle; bakiyeler, limitler ve ekstreler burada toplanır.',
                'Add your accounts and cards; balances, limits and statements come together here.'),
          ),
        ],
      );
    }
    final rows = <Widget>[];
    for (final k in [...keys, if (loose.isNotEmpty) kCashKey]) {
      if (rows.isNotEmpty) rows.add(const Hairline());
      rows.add(_bankRow(context, ctx, k, loose));
    }
    return PageFrame(
      eyebrow: s.pick('BANKALAR VE HESAPLAR', 'BANKS AND ACCOUNTS'),
      title: s.pick('Bankalarım', 'My banks'),
      actions: actions,
      children: [
        KpiRow(children: [
          Kpi(label: s.pick('Hesaplarda', 'In accounts'), k: ctx.model.liquid, sub: s.pick('${ctx.data.accounts.length} hesap', '${ctx.data.accounts.length} accounts'), color: MC.mint, delay: const Duration(milliseconds: 40)),
          Kpi(
            label: s.pick('Kartlarda boş limit', 'Available card limit'),
            k: ctx.model.cardAvail,
            sub: s.pick('Limit ${fmtMoney(ctx.model.cardLimit, lang: s.lang, hidden: st.hidden)}', 'Limit ${fmtMoney(ctx.model.cardLimit, lang: s.lang, hidden: st.hidden)}'),
            color: MC.gold,
            delay: const Duration(milliseconds: 100),
          ),
          Kpi(label: s.pick('Toplam borç', 'Total debt'), k: ctx.model.totalRemaining, sub: s.pick('kartlar ve krediler', 'cards and loans'), color: MC.rose, delay: const Duration(milliseconds: 160)),
        ]),
        const SizedBox(height: 14),
        GlassPanel(
          delay: const Duration(milliseconds: 220),
          radius: 30,
          cut: 30,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _bankRow(BuildContext context, Ctx ctx, String key, List<Account> loose) {
    final s = S.of(context);
    final st = AppScope.of(context);
    String name, label;
    int value;
    List<String> names;
    Widget logo;
    if (key == kCashKey) {
      logo = const BankPlate(icon: Icons.payments_outlined, name: 'Nakit');
      name = s.pick('Nakit ve diğer', 'Cash and other');
      names = [for (final a in loose) a.name.isEmpty ? s.pick('Hesap', 'Account') : a.name];
      label = s.pick('Toplam', 'Total');
      value = sumK(loose, (Account a) => toK(a.balance));
    } else {
      final b = bankStats(ctx, key);
      logo = BankPlate(bankKey: key, name: bankName(key, s.lang));
      name = bankName(key, s.lang);
      names = [
        for (final a in b.accts) a.name.isEmpty ? s.pick('Hesap', 'Account') : a.name,
        for (final c in b.cards) c.name.isEmpty ? s.pick('Kart', 'Card') : c.name,
      ];
      if (b.bal != 0) {
        label = s.pick('Hesaplarda', 'In accounts');
        value = b.bal;
      } else if (b.lim > 0) {
        label = s.pick('Kartlarda boş limit', 'Available card limit');
        value = b.avail;
      } else if (b.debtK > 0) {
        label = s.pick('Borç', 'Debt');
        value = b.debtK;
      } else {
        label = s.pick('Hesaplarda', 'In accounts');
        value = 0;
      }
      if (b.debtK > 0 && label != s.pick('Borç', 'Debt')) {
        names.add(s.pick('borç ${fmtMoney(b.debtK, lang: s.lang, hidden: st.hidden)}', 'debt ${fmtMoney(b.debtK, lang: s.lang, hidden: st.hidden)}'));
      }
    }
    return RowItem(
      leading: logo,
      title: name,
      subtitle: names.isEmpty ? s.pick('kayıt yok', 'no records') : names.join(' · '),
      onTap: () => setState(() => _bank = key),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label, style: sans(11.5, color: MC.muted, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              MoneyText(value, style: serif(28, color: value < 0 ? MC.rose : MC.text)),
            ],
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right, color: MC.muted),
        ],
      ),
    );
  }
}

class _BankDetail extends StatelessWidget {
  const _BankDetail({required this.bankKey, required this.onBack});

  final String bankKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final ctx = st.ctx;
    final d = ctx.data;
    final isCash = bankKey == kCashKey;
    final back = GlassButton(label: s.pick('Tüm bankalar', 'All banks'), icon: Icons.arrow_back, onTap: onBack);
    if (isCash) {
      final loose = looseAccounts(d, bankKeysInUse(ctx));
      final ids = {for (final a in loose) 'acc:${a.id}'};
      return PageFrame(
        eyebrow: s.pick('BANKALAR', 'BANKS'),
        title: s.pick('Nakit ve diğer', 'Cash and other'),
        leading: const BankPlate(icon: Icons.payments_outlined, size: 54),
        actions: [
          back,
          GoldButton(label: s.pick('Aktar', 'Transfer'), icon: Icons.swap_horiz, onTap: () => openTransferSheet(context)),
          GlassButton(label: s.pick('Nakit hesabı', 'Cash account'), icon: Icons.add, onTap: () => openAccountSheet(context, type: 'nakit')),
        ],
        children: [
          KpiRow(children: [
            Kpi(label: s.pick('Toplam', 'Total'), k: sumK(loose, (Account a) => toK(a.balance)), sub: s.pick('${loose.length} hesap', '${loose.length} accounts'), color: MC.gold),
            Kpi(label: s.pick('Tüm hesaplar', 'All accounts'), k: ctx.model.liquid, sub: s.pick('Bankalar dahil', 'Banks included'), color: MC.sky, delay: const Duration(milliseconds: 60)),
          ]),
          const SizedBox(height: 14),
          TwoColumns(
            left: _AccountsPanel(accounts: loose),
            right: Column(children: [
              MonthMovesPanel(accIds: ids),
              const SizedBox(height: 14),
              TransfersPanel(filter: (t) => ids.contains(t.from) || ids.contains(t.to)),
            ]),
          ),
        ],
      );
    }
    final b = bankStats(ctx, bankKey);
    final linked = {for (final c in b.cards) if (c.debtId != null) c.debtId!};
    final looseCredit = b.debts.where((x) => x.isCard && !linked.contains(x.id)).toList();
    int order(BankCard c) => !c.active ? 3 : (c.kind == 'kredi' ? 0 : (c.kind == 'banka' ? 1 : 2));
    final cards = b.cards.toList()..sort((x, y) => order(x) - order(y));
    final loans = b.debts.where((x) => !x.isCard).toList();
    final accIds = {for (final a in b.accts) 'acc:${a.id}'};
    final tiles = <Widget>[
      for (final x in looseCredit) CardTile.forDebt(ctx: ctx, debt: x, bankKey: bankKey),
      for (final c in cards) CardTile.forCard(ctx: ctx, card: c),
    ];
    return PageFrame(
      eyebrow: s.pick('BANKALAR', 'BANKS'),
      title: bankName(bankKey, s.lang),
      leading: BankPlate(bankKey: bankKey, size: 54),
      actions: [
        back,
        GoldButton(label: s.pick('Aktar', 'Transfer'), icon: Icons.swap_horiz, onTap: () => openTransferSheet(context)),
        GlassButton(label: s.pick('Hesap', 'Account'), icon: Icons.add, onTap: () => openAccountSheet(context, bank: bankKey)),
        GlassButton(label: s.pick('Kart', 'Card'), icon: Icons.add, onTap: () => openCardSheet(context, bank: bankKey)),
      ],
      children: [
        KpiRow(children: [
          Kpi(label: s.pick('Hesaplarda', 'In accounts'), k: b.bal, sub: s.pick('${b.accts.length} hesap', '${b.accts.length} accounts'), color: MC.gold),
          if (b.lim > 0)
            Kpi(
              label: s.pick('Boş limit', 'Available limit'),
              k: b.avail,
              sub: s.pick('Limit ${fmtMoney(b.lim, lang: s.lang, hidden: st.hidden)}', 'Limit ${fmtMoney(b.lim, lang: s.lang, hidden: st.hidden)}'),
              color: MC.sky,
              delay: const Duration(milliseconds: 60),
              footer: ProgressLine((b.lim - b.avail) / b.lim, color: (b.lim - b.avail) / b.lim > 0.9 ? MC.rose : MC.sky),
            ),
          Kpi(label: s.pick('Borç', 'Debt'), k: b.debtK, sub: b.debts.isEmpty ? s.pick('Borç yok', 'No debt') : s.pick('${b.debts.length} kayıt', '${b.debts.length} records'), color: MC.rose, delay: const Duration(milliseconds: 120)),
          Kpi(
            label: s.pick('Kartlar', 'Cards'),
            k: 0,
            text: '${b.cards.length + looseCredit.length}',
            sub: s.pick('${b.cards.where((c) => c.active).length + looseCredit.length} açık', '${b.cards.where((c) => c.active).length + looseCredit.length} open'),
            color: MC.violet,
            delay: const Duration(milliseconds: 180),
          ),
        ]),
        const SizedBox(height: 14),
        TwoColumns(
          left: Column(children: [
            GlassPanel(
              delay: const Duration(milliseconds: 220),
              radius: 30,
              cut: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PanelHead(s.pick('Kartlar', 'Cards'), subtitle: s.pick('Karta dokununca kart kaydı açılır', 'Tap a card to open it'),
                      trailing: SmallButton(label: s.pick('Kart', 'Card'), onTap: () => openCardSheet(context, bank: bankKey))),
                  if (tiles.isEmpty)
                    Text(s.pick('Bu bankada kart yok.', 'No cards at this bank.'), style: sans(13, color: MC.muted))
                  else
                    Wrap(spacing: 14, runSpacing: 14, children: tiles),
                ],
              ),
            ),
            if (loans.isNotEmpty) ...[
              const SizedBox(height: 14),
              GlassPanel(
                delay: const Duration(milliseconds: 260),
                radius: 30,
                cut: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PanelHead(
                      s.pick('Krediler', 'Loans'),
                      subtitle: s.pick('Kalan ', 'Remaining ') +
                          fmtMoney(sumK(loans, (Debt x) => ctx.model.debts[x.id]?.current ?? 0), lang: s.lang, hidden: st.hidden),
                    ),
                    for (final x in loans) LoanRow(debt: x),
                  ],
                ),
              ),
            ],
          ]),
          right: Column(children: [
            _AccountsPanel(accounts: b.accts, bank: bankKey),
            if (b.accts.isNotEmpty) ...[const SizedBox(height: 14), MonthMovesPanel(accIds: accIds)],
            const SizedBox(height: 14),
            TransfersPanel(filter: (t) => accIds.contains(t.from) || accIds.contains(t.to)),
          ]),
        ),
      ],
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  const _AccountsPanel({required this.accounts, this.bank});

  final List<Account> accounts;
  final String? bank;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GlassPanel(
      delay: const Duration(milliseconds: 240),
      radius: 30,
      cut: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHead(s.pick('Hesaplar', 'Accounts'), subtitle: s.pick('Hesaba dokununca düzenlenir', 'Tap an account to edit'),
              trailing: SmallButton(label: s.pick('Hesap', 'Account'), onTap: () => openAccountSheet(context, bank: bank))),
          if (accounts.isEmpty) Text(s.pick('Hesap yok.', 'No accounts.'), style: sans(13, color: MC.muted)),
          for (var i = 0; i < accounts.length; i++) ...[
            if (i > 0) const Hairline(),
            RowItem(
              leading: CategoryMark(accounts[i].isCash ? 'nakit' : 'banka', size: 38),
              title: accounts[i].name.isEmpty ? s.pick('Hesap', 'Account') : accounts[i].name,
              subtitle: (kAccountTypes[accounts[i].type] ?? const Lbl('Diğer', 'Other')).of(s.lang) +
                  (accounts[i].asOf != null ? ' · ${fmtDayShort(accounts[i].asOf, s.lang)}' : ''),
              trailing: MoneyText(toK(accounts[i].balance), style: sans(15, weight: FontWeight.w700), color: accounts[i].balance < 0 ? MC.rose : null),
              onTap: () => openAccountSheet(context, account: accounts[i]),
            ),
          ],
        ],
      ),
    );
  }
}
