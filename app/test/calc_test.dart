// Hesap modelinin eski Mel Capital ile birebir aynı sonuç verdiğini denetler.
//
// test/fixtures/beklenen_*.json dosyaları, eski uygulamanın JavaScript hesaplarının
// assets/sample/ornek.json (örnek veri) üzerinde verdiği sonuçlardır.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mel_capital/core/calc.dart';
import 'package:mel_capital/core/model.dart';
import 'package:mel_capital/core/normalize.dart';
import 'package:mel_capital/core/util.dart';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Eski uygulamadan bilerek ayrılan sonuçlar (kullanıcının isteğiyle). Günü geçmiş ama "yattı" denmemiş maaş
/// hâlâ beklenen gelir sayılır: örnek veride 15'inde yatan maaş 20'sinde onaylanmamış, "ay sonuna kadar
/// serbest" ondan düşmez (eski uygulamada 45.000 TL düşüyordu).
const Map<String, Map<String, Map<String, Object?>>> _deliberate = {
  '2026-10-20': {
    '2026-10': {'incomeRest': 4500000, 'safe': 6929818},
  },
};

void main() {
  for (final day in ['2026-10-10', '2026-10-20']) {
    group('örnek veri, bugün $day', () {
      late Map<String, dynamic> exp;
      late Ctx ctx;
      late Data data;

      setUpAll(() {
        final parts = day.split('-').map(int.parse).toList();
        clock = () => DateTime(parts[0], parts[1], parts[2], 12);
        exp = _json('test/fixtures/beklenen_$day.json');
        final n = normalizeData(_json('assets/sample/ornek.json'));
        expect(n.errors, isEmpty);
        data = n.data!;
        ctx = Ctx(data);
      });

      tearDownAll(() => clock = DateTime.now);

      test('genel toplamlar', () {
        final m = ctx.model;
        final e = exp['model'] as Map<String, dynamic>;
        expect(ctx.cur, exp['cur']);
        expect(m.base, e['base']);
        expect(m.maxM, e['maxM']);
        expect(m.liquid, e['liquid']);
        expect(m.cash, e['cash']);
        expect(m.cardDebt, e['cardDebt']);
        expect(m.cardLimit, e['cardLimit']);
        expect(m.cardAvail, e['cardAvail']);
        expect(m.cardCount, e['cardCount']);
        expect(m.loanDebt, e['loanDebt']);
        expect(m.totalRemaining, e['totalRemaining']);
        expect(m.debtFree, e['debtFree']);
        expect(m.subsMonthly, e['subsMonthly']);
        expect(m.netWorth, e['netWorth']);
      });

      test('borçlar tek tek', () {
        final e = exp['model']['debts'] as Map<String, dynamic>;
        for (final entry in e.entries) {
          final v = entry.value as Map<String, dynamic>;
          final d = ctx.model.debts[entry.key]!;
          final where = entry.key;
          expect(d.initial, v['initial'], reason: '$where initial');
          expect(d.purchAdd, v['purchAdd'], reason: '$where purchAdd');
          expect(d.current, v['current'], reason: '$where current');
          expect(d.unbilled, v['unbilled'], reason: '$where unbilled');
          expect(d.limit, v['limit'], reason: '$where limit');
          expect(d.available, v['available'], reason: '$where available');
          expect(d.outstanding, v['outstanding'], reason: '$where outstanding');
          expect(d.unplanned, v['unplanned'], reason: '$where unplanned');
          expect(d.lastPlanned, v['lastPlanned'], reason: '$where lastPlanned');
          expect(d.nextPlanned, v['nextPlanned'], reason: '$where nextPlanned');
          expect(d.installmentsLeft(ctx.cur), v['left'], reason: '$where left');
        }
      });

      test('hedefler', () {
        final e = exp['model']['goals'] as Map<String, dynamic>;
        for (final entry in e.entries) {
          final v = entry.value as Map<String, dynamic>;
          final g = ctx.model.goals[entry.key]!;
          expect(g.saved, v['saved'], reason: entry.key);
          expect(g.target, v['target'], reason: entry.key);
          expect(g.completion, v['completion'], reason: entry.key);
          final projected = [for (final p in v['projected'] as List) (p[0] as String, p[1] as int)];
          expect([for (final p in g.projected.entries) (p.key, p.value)], projected, reason: entry.key);
        }
      });

      test('ay özetleri ve kalemler', () {
        final e = exp['months'] as Map<String, dynamic>;
        for (final entry in e.entries) {
          final v = entry.value as Map<String, dynamic>;
          final s = ctx.sum(entry.key);
          final w = entry.key;
          for (final f in [
            ('total', s.total), ('taksit', s.taksit), ('sabit', s.sabit), ('abonelik', s.abonelik), ('kart', s.kart),
            ('paid', s.paid), ('unpaid', s.unpaid), ('allPaid', s.allPaid), ('pendingCards', s.pendingCards),
            ('estK', s.estK), ('carriedK', s.carriedK), ('carryIn', s.carryIn), ('income', s.income),
            ('savingsActual', s.savingsActual), ('savingsPlanned', s.savingsPlanned), ('spent', s.spent),
            ('spentCard', s.spentCard), ('estSpend', s.estSpend), ('free', s.free), ('safe', s.safe),
            ('incomeRest', s.incomeRest),
          ]) {
            final o = _deliberate[day]?[w];
            final want = o != null && o.containsKey(f.$1) ? o[f.$1] : v[f.$1];
            expect(f.$2, want, reason: '$w ${f.$1}');
          }
          final items = v['items'] as List;
          expect(s.items.length, items.length, reason: '$w kalem sayısı');
          for (var i = 0; i < items.length; i++) {
            final x = items[i] as Map<String, dynamic>;
            final it = s.items[i];
            final r = '$w kalem $i (${x['refId']})';
            expect(it.kind, x['kind'], reason: r);
            expect(it.refId, x['refId'], reason: r);
            expect(it.group, x['group'], reason: r);
            expect(it.planned, x['planned'], reason: r);
            expect(it.pay?.k, x['pay'], reason: r);
            expect(it.carry, x['carry'], reason: r);
            expect(it.fromMonth, x['fromMonth'], reason: r);
            expect(it.carriedOut, x['carriedOut'], reason: r);
            expect(it.est, x['est'], reason: r);
            expect(it.pending, x['pending'], reason: r);
            expect(it.day, x['day'], reason: r);
            expect(it.instK, x['instK'], reason: r);
          }
        }
      });

      test('tahmin, yaklaşan ödemeler, sıradaki ödeme', () {
        final est = exp['est'] as Map<String, dynamic>;
        expect(ctx.est.k, est['k']);
        expect(ctx.est.manual, est['manual']);
        expect(ctx.est.auto, est['auto']);

        final up = [for (final u in ctx.upcoming(10)) [u.item.refId, u.month, u.date, u.late]];
        expect(up, [for (final u in exp['upcoming'] as List) [u['refId'], u['month'], u['date'], u['late']]]);

        final np = ctx.nextPayment();
        final enp = exp['nextPayment'] as Map<String, dynamic>?;
        if (enp == null) {
          expect(np, isNull);
        } else {
          expect(np!.month, enp['month']);
          expect(np.amount, enp['amount']);
          expect([for (final it in np.items) it.refId], enp['refIds']);
        }
        expect([for (final o in ctx.overdueMonths()) [o.$1, o.$2]], exp['overdue']);
      });

      test('öğrenme, kaynaklar, hareketler, taksit, tutar okuma', () {
        final l = learned(data, 'migros');
        final el = exp['learned'] as Map<String, dynamic>;
        expect(l!.cat, el['cat']);
        expect(l.k, el['k']);
        expect(l.source, el['source']);
        expect(
          [smartCategory(data, 'Kahve Dünyası'), smartCategory(data, 'Uber Eats'), smartCategory(data, 'İlaç')],
          exp['smart'],
        );
        final mv = movements(data, 'tr').take(6).map((x) => [x.t, x.id, x.k]).toList();
        expect(mv, exp['movements']);
        final ps = ctx.purchaseState(data.spends.firstWhere((s) => s.id == 's6'));
        final ep = exp['purchase'] as Map<String, dynamic>;
        expect(ps.billedN, ep['billedN']);
        expect(ps.remainK, ep['remainK']);
        expect(ps.monthly, ep['monthly']);
        expect(ps.end, ep['end']);
        expect(
          ['12.500,50', '12500.50', '12.500', '1.234.567,8', '2500', '0,5', 'abc', ''].map(parseAmount).toList(),
          exp['parse'],
        );
        expect(favSource(data), exp['fav']);
        expect(lastFromFor(data, 'debt', 'kyk'), exp['lastFrom']);
      });
    });
  }

  test('bozuk veri yakalanır', () {
    final r = normalizeData({
      'version': 4,
      'balancesAsOf': '2026-13',
      'debts': [
        {'id': 'a', 'remaining': -5, 'schedule': []},
        {'id': 'a', 'remaining': 10},
      ],
    });
    expect(r.ok, isFalse);
    expect(r.errors.any((e) => e.contains('balancesAsOf')), isTrue);
    expect(r.errors.any((e) => e.contains('remaining')), isTrue);
    expect(r.errors.any((e) => e.contains('tekrar')), isTrue);
  });

  test('boş veri geçerli', () {
    final r = normalizeData(emptyData().j);
    expect(r.errors, isEmpty);
    expect(r.data!.accounts.single.isCash, isTrue);
  });

  test('biçimler', () {
    expect(fmtNum(1234567), '12.345,67');
    expect(fmtNum(1234500), '12.345');
    expect(fmtNum(-50, lang: 'en'), '−0.50');
    expect(fmtNum(100000000, lang: 'en'), '1,000,000');
    expect(slugify('Doğalgaz Faturası'), 'dogalgaz-faturasi');
    expect(normTxt('  İSTANBUL  Kart '), 'istanbul kart');
    expect(uniqueId('Kira', ['kira', 'kira-2']), 'kira-3');
    expect(addM('2026-12', 1), '2027-01');
    expect(addM('2026-01', -1), '2025-12');
    expect(mDiff('2026-10', '2027-03'), 5);
    expect(isDate('2026-02-30'), isFalse);
    expect(isDate('2028-02-29'), isTrue);
    expect(daysInMonth('2028-02'), 29);
    expect(addDays('2026-12-30', 3), '2027-01-02');
    expect(weekdayIndex('2026-11-01'), 0);
    expect(dayPoss(13), "13'ü");
    expect(dayPoss(16), "16'sı");
    expect(parseSigned('-250'), -25000);
  });
}
