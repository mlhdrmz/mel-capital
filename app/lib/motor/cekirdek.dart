// Mel Capital — ÇEKİRDEK (Hareket Defteri)
//
// Paranın her hareketi tek bir kayıttır: harcama (Gider Motoru), aktarma ve para girişi (bu
// dosya, maaş girişleri Gelir Motoru'ndan), ödeme (Plan ve Borç motorları). Bu dosya:
//   • hareketleri tek listede verir ([movements]),
//   • hesap bakiyelerini değiştiren TEK yerdir ([accAdjust]); başka hiçbir yer bakiyeye yazmaz,
//   • hesapları, aktarmaları ve bankaları yönetir,
//   • hesapların defterle tuttuğu [defterK] ile denetlenir (bkz. uyum.dart).
//
// Bütün değişiklikler arayüzde tek kapıdan geçer: AppState.update. Değişiklikten sonra bütün
// hesaplar (Ctx) yeniden kurulur ve bütün sayfalar aynı anda yenilenir; böylece Harcamalar,
// Borçlar, Bankalar ve Plan hep aynı rakamı gösterir.

import '../core/constants.dart';
import '../core/model.dart';
import '../core/util.dart';
import 'borc.dart';
import 'plan.dart';

// ---------------------------------------------------------------- Ortak hesaplar

int schedK(List<Sched> sched, String m) {
  for (final s in sched) {
    if (s.from.compareTo(m) <= 0 && (s.to == null || m.compareTo(s.to!) <= 0)) return toK(s.amount);
  }
  return 0;
}

/// Plan satırlarını denetler ve sıralar: (satırlar, hata).
(List<Json>, String?) validateSched(List<(String?, String?, int?)> rows, {required bool openEnd, required String lang}) {
  String pick(String tr, String en) => lang == 'tr' ? tr : en;
  final sched = <Json>[];
  for (var i = 0; i < rows.length; i++) {
    final (from, to, k) = rows[i];
    final n = i + 1;
    if (!isMonth(from)) return (const [], pick('$n. satırda başlangıç ayı seçilmeli.', 'Row $n needs a start month.'));
    if (!openEnd && !isMonth(to)) return (const [], pick('$n. satırda bitiş ayı seçilmeli.', 'Row $n needs an end month.'));
    if (to != null && !isMonth(to)) return (const [], pick('$n. satırda bitiş ayı için hem ay hem yıl seç.', 'Row $n: pick both month and year for the end.'));
    if (to != null && from!.compareTo(to) > 0) return (const [], pick('$n. satırda bitiş ayı başlangıçtan önce olamaz.', 'Row $n ends before it starts.'));
    if (k == null || k <= 0) return (const [], pick('$n. satırda aylık tutar geçerli değil.', 'Row $n has no valid monthly amount.'));
    sched.add(<String, dynamic>{'from': from, 'to': to, 'amount': fromK(k)});
  }
  sched.sort((a, b) => (a['from'] as String).compareTo(b['from'] as String));
  for (var i = 1; i < sched.length; i++) {
    final prevTo = sched[i - 1]['to'] as String?;
    if (prevTo == null || (sched[i]['from'] as String).compareTo(prevTo) <= 0) {
      return (const [], pick('Plan satırlarının dönemleri çakışıyor (süresiz bir dönemden sonra yeni dönem eklenemez).', 'The plan rows overlap (no new period can follow an open-ended one).'));
    }
  }
  return (sched, null);
}

// ---------------------------------------------------------------- Hesap bakiyesi (tek yazma noktası)

/// Hesap bakiyesini kuruş cinsinden değiştirir (kaynak "acc:" değilse bir şey yapmaz).
void accAdjust(Data data, String? src, int deltaK) {
  final aid = srcAcc(src);
  if (aid == null || deltaK == 0) return;
  final a = data.account(aid);
  if (a == null) return;
  a.balance = fromK(toK(a.balance) + deltaK);
}

/// Bakiyeyi elle (ya da bankanın dökümüyle) düzeltir: bu bir hareket değil, yeni başlangıç
/// noktasıdır ("setAt" yazılır; uyum denetimi bunu hareketlerle karşılaştırmaz).
void bakiyeyiDuzelt(Data data, String accountId, int k) {
  data.account(accountId)?.j.addAll(<String, dynamic>{'balance': fromK(k), 'asOf': todayISO(), 'setAt': nowISO()});
}

/// Hesaplardaki toplam para (kuruş).
int liquidK(Data d) => sumK(d.accounts, (Account a) => toK(a.balance));

/// Elde nakit (kuruş).
int cashK(Data d) => sumK(d.accounts.where((a) => a.isCash), (Account a) => toK(a.balance));

/// Hesabın defterdeki hareketlerinin toplamı (kuruş): harcamalar ve ödemeler eksi, gelen aktarmalar
/// artı, giden aktarmalar eksi. Bakiyenin her değişimi bu toplamın değişimiyle aynı olmalıdır.
int defterK(Data d, String accountId) {
  final src = 'acc:$accountId';
  var k = 0;
  for (final s in d.spends) {
    if (s.source == src) k -= toK(s.amount);
  }
  for (final t in d.transfers) {
    if (t.to == src) k += toK(t.amount);
    if (t.from == src) k -= toK(t.amount);
  }
  for (final p in d.payments) {
    if (p.viaRefId == null && p.fromAccount == src) k -= toK(p.paidAmount);
  }
  return k;
}

// ---------------------------------------------------------------- Hesaplar ve aktarmalar

/// Hesap ekler ya da günceller.
void saveAccount(Data data, {String? id, required String bank, required String name, required String type, required int balanceK, String note = ''}) {
  final rec = <String, dynamic>{'bank': bank, 'name': name, 'type': type, 'balance': fromK(balanceK), 'asOf': todayISO(), 'note': note};
  if (id != null) {
    final a = data.account(id);
    if (a == null) return;
    final changed = toK(a.balance) != balanceK;
    a.j.addAll(rec);
    if (changed) a.j['setAt'] = nowISO();
    return;
  }
  data.accounts.add(Account(<String, dynamic>{
    'id': uniqueId(slugify('${bank.isEmpty ? 'nakit' : bank}-$name'), data.accounts.map((x) => x.id)),
    ...rec,
    'setAt': nowISO(),
  }));
}

/// Hesabı siler; bu hesaba bağlı kartların bağlantısı kaldırılır (geçmiş kayıtlar kalır).
void deleteAccount(Data data, String id) {
  data.accounts.removeWhere((x) => x.id == id);
  for (final c in data.cards) {
    if (c.accountId == id) c.j['accountId'] = null;
  }
}

/// Aktarma ekler ya da günceller (hesaplar arası ya da dışarıdan giriş).
void saveTransfer(Data data, {String? id, required String from, required String to, required int k, required String date, String note = ''}) {
  if (id != null) {
    for (final x in data.transfers) {
      if (x.id != id) continue;
      if (x.from != 'ext') accAdjust(data, x.from, toK(x.amount));
      accAdjust(data, x.to, -toK(x.amount));
      x.j.addAll(<String, dynamic>{'from': from, 'to': to, 'amount': fromK(k), 'date': date, 'note': note, 'updatedAt': nowISO()});
    }
  } else {
    data.transfers.add(Transfer(<String, dynamic>{
      'id': rid('akt'),
      'date': date,
      'from': from,
      'to': to,
      'amount': fromK(k),
      'note': note,
      'createdAt': nowISO(),
    }));
  }
  if (from != 'ext') accAdjust(data, from, -k);
  accAdjust(data, to, k);
}

void deleteTransfer(Data data, String id) {
  for (final x in data.transfers) {
    if (x.id != id) continue;
    if (x.from != 'ext') accAdjust(data, x.from, toK(x.amount));
    accAdjust(data, x.to, -toK(x.amount));
  }
  data.transfers.removeWhere((x) => x.id == id);
}

// ---------------------------------------------------------------- Bankalar

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

/// Bankaya bağlı olmayan hesaplar (nakit ve diğerleri).
List<Account> looseAccounts(Data d, List<String> keys) =>
    d.accounts.where((a) => a.bank.isEmpty || !keys.contains(a.bank)).toList();

/// Bir bankanın hesapları, kartları, borçları ve toplamları.
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

/// Hesaplar (bakiye sırasıyla).
List<Account> accountsSorted(Data d) {
  const order = {'nakit': 0, 'vadesiz': 1, 'cuzdan': 2, 'on_odemeli': 3, 'birikim': 4, 'diger': 5};
  final list = d.accounts.toList();
  list.sort((a, b) {
    final pa = toK(a.balance) > 0 ? 0 : 1, pb = toK(b.balance) > 0 ? 0 : 1;
    if (pa != pb) return pa - pb;
    final t = (order[a.type] ?? 5) - (order[b.type] ?? 5);
    if (t != 0) return t;
    return accLabel(a, 'tr').compareTo(accLabel(b, 'tr'));
  });
  return list;
}

// ---------------------------------------------------------------- Kaynaklar (hesap ya da kart)

String accLabel(Account? a, String lang) {
  if (a == null) return lang == 'tr' ? 'silinmiş hesap' : 'deleted account';
  if (a.isCash) return a.name;
  if (a.bank.isNotEmpty && kBanks.containsKey(a.bank)) {
    final bn = bankName(a.bank, lang);
    return a.name.startsWith(bn) ? a.name : '$bn · ${a.name}';
  }
  return a.name;
}

String sourceName(Data d, String? src, String lang) {
  final aid = srcAcc(src);
  final cid = srcCard(src);
  if (aid != null) return accLabel(d.account(aid), lang);
  if (cid != null) {
    final x = d.debt(cid);
    return x != null ? x.creditor : (lang == 'tr' ? 'silinmiş kart' : 'deleted card');
  }
  return '';
}

class SourceBank {
  const SourceBank(this.key, this.name, {this.cash = false});
  final String? key;
  final String name;
  final bool cash;
}

SourceBank? sourceBank(Data d, String? src) {
  final aid = srcAcc(src);
  final cid = srcCard(src);
  if (aid != null) {
    final a = d.account(aid);
    return a == null ? null : SourceBank(a.bank.isEmpty ? null : a.bank, a.name, cash: a.isCash);
  }
  if (cid != null) {
    final x = d.debt(cid);
    return x == null ? null : SourceBank(bankKeyOf(x), x.creditor);
  }
  return null;
}

// ---------------------------------------------------------------- Hareket defteri

/// Harcamalar, aktarmalar ve ödemeler tek listede (yeniden eskiye).
class Movement {
  const Movement({
    required this.t,
    required this.id,
    required this.date,
    required this.at,
    required this.k,
    required this.name,
    this.place = '',
    this.src,
    this.from,
    this.cat,
    this.inst = 0,
    this.kind,
    this.ref,
    this.month,
  });

  final String t; // spend | transfer | pay
  final String id;
  final String date;
  final String at;
  final int k;
  final String name;
  final String place;
  final String? src;
  final String? from;
  final String? cat;
  final int inst;
  final String? kind;
  final String? ref;
  final String? month;
}

List<Movement> movements(Data d, String lang) {
  final out = <Movement>[];
  for (final s in d.spends) {
    out.add(Movement(
      t: 'spend', id: s.id, date: s.date, at: s.createdAt ?? '', k: -toK(s.amount),
      name: s.name.isEmpty ? catLabel(s.category, lang) : s.name, place: s.place, src: s.source, cat: s.category,
      inst: srcCard(s.source) != null && s.installments > 1 ? s.installments : 0,
    ));
  }
  for (final t in d.transfers) {
    out.add(Movement(
      t: 'transfer', id: t.id, date: t.date, at: t.createdAt ?? '', k: toK(t.amount),
      name: t.external ? (lang == 'tr' ? 'Para girişi' : 'Money in') : (lang == 'tr' ? 'Aktarma' : 'Transfer'),
      src: t.to, from: t.from,
    ));
  }
  for (final p in d.payments) {
    if (p.viaRefId != null || !isDate(p.paidDate)) continue;
    var name = lang == 'tr' ? 'Ödeme' : 'Payment';
    if (p.kind == 'debt') {
      name = d.debt(p.refId)?.creditor ?? (lang == 'tr' ? 'Borç' : 'Debt');
    } else if (p.kind == 'expense') {
      name = d.expense(p.refId)?.name ?? (lang == 'tr' ? 'Gider' : 'Expense');
    } else if (p.kind == 'sub') {
      name = d.subscription(p.refId)?.name ?? (lang == 'tr' ? 'Abonelik' : 'Subscription');
    }
    out.add(Movement(
      t: 'pay', id: p.id, kind: p.kind, ref: p.refId, month: p.month, date: p.paidDate!,
      at: p.createdAt ?? '', k: -toK(p.paidAmount), name: name, src: p.fromAccount,
    ));
  }
  out.sort((a, b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.at.compareTo(a.at);
  });
  return out;
}
