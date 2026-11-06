// Mel Capital — UYUM DENETİMİ
//
// Motorların birbirini tuttuğunu denetler. Bir değişiklikten önceki ve sonraki veriye bakar;
// yalnızca bu değişikliğin getirdiği yeni sorunları bildirir (eski kayıtlardaki bilinen
// farklılıklar sorun sayılmaz).
//
// Kurallar:
//   1. Hesap uyumu: bir hesabın bakiyesi ne kadar değiştiyse, defterdeki hareketlerinin toplamı da
//      o kadar değişmelidir (Çekirdek'teki [defterK]). Bakiyenin elle düzeltilmesi (hesap formunda
//      yeni bakiye girilmesi) bunun dışındadır. Bir abonelik, sabit gider ya da borç silinince
//      geçmiş ödemeleri de silinir ama ödenen para hesaba geri dönmez; bu da bunun dışındadır.
//   2. Maaş uyumu: maaşın hesaba girişi (incomeRef'li aktarma) gelirin o ayki tutarıyla aynıdır ve
//      bir gelir bir ayda en çok bir kez hesaba girer. Gelir silinirse geçmiş girişleri kalır.
//   3. Ödeme uyumu: bir borcun ödemesi var olan bir borca, bir sabit giderin borçlara dağıttığı
//      ödeme var olan bir sabit gidere aittir.
//   4. Kimlik uyumu: her listede kimlikler tektir.
//
// Uygulama hata ayıklama modunda (testler dahil) her değişiklikten sonra bu denetimi çalıştırır
// (AppState.update); bir kural bozulursa hata verir. Testler geçmeden güncelleme yayınlanmaz.

import '../core/model.dart';
import '../core/util.dart';
import 'cekirdek.dart';

/// [once] → [sonra] değişikliğinin getirdiği uyum sorunları (boşsa her şey yolunda).
List<String> uyumDenetimi(Data once, Data sonra) => [
      ..._hesapUyumu(once, sonra),
      ..._yeniler(_maasSorunlari(once), _maasSorunlari(sonra)),
      ..._yeniler(_odemeSorunlari(once), _odemeSorunlari(sonra)),
      ..._yeniler(_kimlikSorunlari(once), _kimlikSorunlari(sonra)),
    ];

List<String> _yeniler(Set<String> once, Set<String> sonra) => [for (final s in sonra) if (!once.contains(s)) s];

List<String> _hesapUyumu(Data once, Data sonra) {
  // Sahibi silindiği için silinen ödemeler: parası hesaba geri dönmez, defterde kalmış sayılır.
  final kalanOdemeler = {for (final p in sonra.payments) p.id};
  final arsiv = <String, int>{};
  for (final p in once.payments) {
    final src = p.fromAccount;
    if (p.viaRefId != null || src == null || kalanOdemeler.contains(p.id)) continue;
    final sahipSilindi = switch (p.kind) {
      'sub' => once.subscription(p.refId) != null && sonra.subscription(p.refId) == null,
      'expense' => once.expense(p.refId) != null && sonra.expense(p.refId) == null,
      'debt' => once.debt(p.refId) != null && sonra.debt(p.refId) == null,
      _ => false,
    };
    if (sahipSilindi) arsiv[src] = (arsiv[src] ?? 0) - toK(p.paidAmount);
  }
  final out = <String>[];
  for (final a in sonra.accounts) {
    final b = once.account(a.id);
    if (b == null) continue; // yeni hesap
    if ('${a.j['setAt']}' != '${b.j['setAt']}') continue; // bakiye elle düzeltildi
    final bakiyeFarki = toK(a.balance) - toK(b.balance);
    final defterFarki = defterK(sonra, a.id) + (arsiv['acc:${a.id}'] ?? 0) - defterK(once, a.id);
    if (bakiyeFarki != defterFarki) {
      out.add('Hesap uyumu: "${a.name}" bakiyesi ${fromK(bakiyeFarki)} TL değişti ama hareketleri ${fromK(defterFarki)} TL değişti');
    }
  }
  return out;
}

Set<String> _maasSorunlari(Data d) {
  final out = <String>{};
  final gorulen = <String>{};
  for (final t in d.transfers) {
    final ref = t.incomeRef;
    if (ref == null) continue;
    if (!gorulen.add(ref)) out.add('Maaş uyumu: $ref hesaba iki kez girmiş');
    final i = ref.lastIndexOf('|');
    final id = i < 0 ? ref : ref.substring(0, i);
    final m = i < 0 ? '' : ref.substring(i + 1);
    Income? inc;
    for (final x in d.incomes) {
      if (x.id == id) inc = x;
    }
    final tutar = inc?.monthAmounts[m];
    // Gelir silindiyse geçmiş girişleri hesapta kalır (para gerçekten girmişti)
    if (inc != null && (tutar == null || toK(tutar) != toK(t.amount))) {
      out.add('Maaş uyumu: $ref girişi gelirin o ayki tutarıyla aynı değil');
    }
  }
  return out;
}

Set<String> _odemeSorunlari(Data d) {
  final out = <String>{};
  for (final p in d.payments) {
    if (p.kind == 'debt' && d.debt(p.refId) == null) out.add('Ödeme uyumu: ${p.id} silinmiş bir borca ait');
    final via = p.viaRefId;
    if (via != null && d.expense(via) == null) out.add('Ödeme uyumu: ${p.id} silinmiş bir sabit gidere ait');
  }
  return out;
}

Set<String> _kimlikSorunlari(Data d) {
  final out = <String>{};
  void tek(String ad, Iterable<String> ids) {
    final g = <String>{};
    for (final id in ids) {
      if (id.isNotEmpty && !g.add(id)) out.add('Kimlik uyumu: $ad listesinde "$id" iki kez var');
    }
  }

  tek('harcamalar', d.spends.map((x) => x.id));
  tek('aktarmalar', d.transfers.map((x) => x.id));
  tek('ödemeler', d.payments.map((x) => x.id));
  tek('hesaplar', d.accounts.map((x) => x.id));
  tek('borçlar', d.debts.map((x) => x.id));
  tek('abonelikler', d.subscriptions.map((x) => x.id));
  tek('gelirler', [...d.incomes.map((x) => x.id), ...d.oneOffIncomes.map((x) => x.id)]);
  tek('sabit giderler', d.recurringExpenses.map((x) => x.id));
  tek('istekler', d.goals.map((x) => x.id));
  tek('kartlar', d.cards.map((x) => x.id));
  return out;
}
