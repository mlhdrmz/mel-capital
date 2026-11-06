// Ekstre ekleme: PDF seçilir, Ekstre Motoru okur; panelde hangi karta/hesaba gideceği, yeni
// işlemler, zaten girilmiş olanlar ve "bu o mu?" soruları gösterilir; onaylanınca eklenir.

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/model.dart';
import '../../core/util.dart';
import '../../motor/motorlar.dart';
import '../../storage/pdf_metin.dart';
import '../../storage/pick_file.dart';
import '../dialogs.dart';
import '../i18n.dart';
import '../sheet.dart';
import '../state.dart';
import '../theme.dart';
import '../ui.dart';

/// PDF ekstre seçtirir, okur ve ekleme panelini açar.
Future<void> openStatementImport(BuildContext context) async {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final picked = await pickBytesFile(label: s.pick('PDF ekstre', 'PDF statement'), extensions: const ['pdf']);
  if (picked == null || !context.mounted) return;
  List<List<String>> sayfalar;
  try {
    sayfalar = await pdfSatirlariOku(
      picked.bytes,
      sifreSor: () => promptText(
        context,
        title: s.pick('PDF şifreli', 'The PDF is protected'),
        text: s.pick('Bankanın ekstre şifresini yaz (çoğu bankada kimlik numarasının ya da doğum tarihinin bir kısmı). Şifre hiçbir yere kaydedilmez.',
            'Type the statement password from your bank. It is not stored anywhere.'),
        ok: s.pick('Aç', 'Open'),
      ),
    );
  } on PdfOkunamadi catch (e) {
    showToast(messenger, s.lang, e.sifre ? s.pick('PDF açılamadı: şifre girilmedi ya da yanlış.', 'Could not open the PDF: no or wrong password.') : e.neden, seconds: 6);
    return;
  }
  if (!context.mounted) return;
  final okuma = ekstreOku(sayfalar);
  final bos = sayfalar.every((p) => p.isEmpty);
  if (bos) {
    showToast(
      messenger,
      s.lang,
      s.pick('Bu PDF\'in içinde yazı yok (taranmış ya da fotoğraf). Resim olan ekstreleri okuma yakında geliyor; bankanın gönderdiği PDF\'i dene.',
          'This PDF has no text (scanned or photo). Reading image statements is coming soon; try the PDF your bank sent.'),
      seconds: 8,
    );
    return;
  }
  if (!okuma.okundu) {
    showToast(messenger, s.lang, s.pick('Bu PDF ekstre olarak okunamadı. ${okuma.eksikler.join(' ')}', 'This PDF could not be read as a statement.'), seconds: 8);
    return;
  }
  await showEditSheet<void>(context, width: 680, builder: (_) => StatementSheet(okuma: okuma));
}

class StatementSheet extends StatefulWidget {
  const StatementSheet({super.key, required this.okuma});

  final EkstreOkuma okuma;

  @override
  State<StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends State<StatementSheet> {
  List<EkstreHedefi> _hedefler = const [];
  int _hedef = 0;
  List<EkstreEslesme> _eslesmeler = const [];

  /// İşlemin eklenip eklenmeyeceği (eşleşmenin sırasıyla).
  List<bool> _ekle = const [];
  bool _init = false;
  bool _varAcik = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final d = AppScope.of(context).data;
    _hedefler = ekstreHedefleri(d, widget.okuma);
    _hedef = 0;
    _eslestir(d);
  }

  void _eslestir(Data d) {
    _eslesmeler = ekstreEslestir(d, widget.okuma, _hedefler[_hedef]);
    _ekle = [for (final e in _eslesmeler) e.durum == EslesmeDurumu.yeni];
  }

  Outcome _read() {
    final o = widget.okuma;
    final h = _hedefler[_hedef];
    final ekle = [
      for (var i = 0; i < _eslesmeler.length; i++)
        if (_ekle[i] && _eslesmeler[i].durum != EslesmeDurumu.var_ && _eslesmeler[i].durum != EslesmeDurumu.eklenmez) _eslesmeler[i],
    ];
    return Outcome.ok((d) => ekstreUygula(d, o, h, ekle), focus: currentMonth(), cardId: h.kart ? h.id : null, source: h.yeni ? null : h.kaynak);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = S.of(context);
    final o = widget.okuma;
    String money(int k) => fmtMoney(k, lang: s.lang, hidden: st.hidden);
    final h = _hedefler[_hedef];
    final banka = o.banka == null ? s.pick('Banka tanınamadı', 'Bank not recognised') : bankName(o.banka, s.lang);
    final tur = o.tur == EkstreTuru.kart ? s.pick('Kredi kartı ekstresi', 'Credit card statement') : s.pick('Hesap dökümü', 'Account statement');
    final no = o.son4 != null ? ' · •••• ${o.son4}' : (o.iban4 != null ? ' · IBAN •••• ${o.iban4}' : '');
    final out = _read();

    final yeni = <int>[], supheli = <int>[], var_ = <int>[], eklenmez = <int>[];
    for (var i = 0; i < _eslesmeler.length; i++) {
      switch (_eslesmeler[i].durum) {
        case EslesmeDurumu.yeni:
          yeni.add(i);
        case EslesmeDurumu.supheli:
          supheli.add(i);
        case EslesmeDurumu.var_:
          var_.add(i);
        case EslesmeDurumu.eklenmez:
          eklenmez.add(i);
      }
    }
    final eklenecek = [for (var i = 0; i < _eslesmeler.length; i++) if (_ekle[i] && (_eslesmeler[i].durum == EslesmeDurumu.yeni || _eslesmeler[i].durum == EslesmeDurumu.supheli)) i].length;

    final ozet = <(String, String)>[
      if (o.tur == EkstreTuru.kart) ...[
        if (o.kesim != null) (s.pick('Hesap kesim', 'Statement date'), fmtDate(o.kesim, s.lang)),
        if (o.sonOdeme != null) (s.pick('Son ödeme', 'Due date'), fmtDate(o.sonOdeme, s.lang)),
        if (o.donemBorcu != null) (s.pick('Dönem borcu', 'Statement balance'), money(o.donemBorcu!)),
        if (o.asgari != null) (s.pick('Asgari ödeme', 'Minimum payment'), money(o.asgari!)),
        if (o.limit != null) (s.pick('Kart limiti', 'Credit limit'), money(o.limit!)),
        if (o.guncelBorc != null) (s.pick('Güncel borç (kesimde)', 'Debt at statement date'), money(o.guncelBorc!)),
      ] else ...[
        if (o.donemSonu != null) (s.pick('Döküm tarihi', 'Statement date'), fmtDate(o.donemSonu, s.lang)),
        if (o.kapanisBakiye != null) (s.pick('Son bakiye', 'Closing balance'), money(o.kapanisBakiye!)),
      ],
    ];

    return SheetFrame(
      title: s.pick('Ekstre ekle', 'Add statement'),
      subtitle: '$banka · $tur$no',
      error: _error,
      impact: ImpactBox(outcome: out.ok ? out : null, noFree: o.tur == EkstreTuru.hesap),
      actions: [
        GoldButton(
          key: const ValueKey<String>('ekstre-ekle'),
          label: eklenecek > 0 ? s.pick('$eklenecek işlemi ekle', 'Add $eklenecek items') : s.pick('Güncelle', 'Update'),
          icon: Icons.check,
          onTap: () {
            if (!out.ok) return setState(() => _error = out.error);
            commitOutcome(
              context,
              out,
              s.pick('Ekstre eklendi: ${h.ad}${eklenecek > 0 ? ' · $eklenecek yeni işlem' : ''}.', 'Statement added: ${h.ad}.'),
            );
          },
        ),
      ],
      children: [
        FieldBox(
          label: o.tur == EkstreTuru.kart ? s.pick('Hangi kart?', 'Which card?') : s.pick('Hangi hesap?', 'Which account?'),
          help: h.yeni
              ? s.pick('Uygulamada bu ${o.tur == EkstreTuru.kart ? 'kart' : 'hesap'} yok; ekstredeki bilgilerle yeni kayıt açılır.',
                  'Not in the app yet; a new one is created from the statement.')
              : (h.kesin ? s.pick('Kendiliğinden bulundu (${h.neden}).', 'Found automatically (${h.neden}).') : s.pick('Emin olunamadı; doğru olanı seç.', 'Not sure; pick the right one.')),
          child: GlassSelect<int>(
            value: _hedef,
            items: [
              for (var i = 0; i < _hedefler.length; i++) (i, _hedefler[i].yeni ? s.pick('Yeni: ${_hedefler[i].ad}', 'New: ${_hedefler[i].ad}') : _hedefler[i].ad),
            ],
            onChanged: (v) => setState(() {
              if (v == null) return;
              _hedef = v;
              _eslestir(st.data);
            }),
          ),
        ),
        if (ozet.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(children: [
              for (final r in ozet)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(r.$1, style: sans(13, color: MC.muted))),
                    Text(r.$2, style: numStyle(sans(13.5, weight: FontWeight.w700))),
                  ]),
                ),
            ]),
          ),
        for (final e in o.eksikler)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 16, color: MC.rose),
              const SizedBox(width: 8),
              Expanded(child: Text(e, style: sans(12.5, color: MC.rose))),
            ]),
          ),
        if (yeni.isNotEmpty) ...[
          _Baslik(s.pick('Yeni işlemler', 'New items'), yeni.length),
          for (final i in yeni)
            _Satir(
              e: _eslesmeler[i],
              money: money,
              leading: Checkbox(
                value: _ekle[i],
                activeColor: MC.gold,
                checkColor: MC.ink,
                onChanged: (v) => setState(() => _ekle[i] = v ?? false),
              ),
            ),
        ],
        if (supheli.isNotEmpty) ...[
          _Baslik(s.pick('Bu o mu?', 'Is this the same?'), supheli.length),
          for (final i in supheli)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Satir(e: _eslesmeler[i], money: money),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    s.pick('Uygulamada: ${_eslesmeler[i].kayitAdi ?? ''} · ${fmtDayShort(_eslesmeler[i].kayitTarihi, s.lang)}',
                        'In the app: ${_eslesmeler[i].kayitAdi ?? ''} · ${fmtDayShort(_eslesmeler[i].kayitTarihi, s.lang)}'),
                    style: sans(12, color: MC.dim),
                  ),
                ),
                Seg<bool>(
                  value: _ekle[i],
                  options: [(false, s.pick('Evet, aynısı', 'Yes, the same')), (true, s.pick('Hayır, ayrı ekle', 'No, add it'))],
                  onChanged: (v) => setState(() => _ekle[i] = v),
                ),
              ]),
            ),
        ],
        if (var_.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(() => _varAcik = !_varAcik),
            child: _Baslik(s.pick('Zaten var, atlanacak', 'Already in the app, skipped'), var_.length, acik: _varAcik),
          ),
          if (_varAcik)
            for (final i in var_) _Satir(e: _eslesmeler[i], money: money, soluk: true),
        ],
        if (eklenmez.isNotEmpty) ...[
          _Baslik(s.pick('Ödemeler ve iadeler', 'Payments and refunds'), eklenmez.length),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(s.pick('Bunlar ekstredeki borçta zaten hesaba katıldı; ayrıca eklenmez.', 'These are already counted in the statement balance.'), style: sans(12, color: MC.dim)),
          ),
          for (final i in eklenmez) _Satir(e: _eslesmeler[i], money: money, soluk: true),
        ],
        if (_eslesmeler.isEmpty)
          Text(s.pick('Ekstrede işlem satırı okunamadı; yalnızca özet bilgiler güncellenecek.', 'No transaction lines were read; only the summary will be updated.'),
              style: sans(12.5, color: MC.muted)),
      ],
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin, this.sayi, {this.acik});

  final String metin;
  final int sayi;
  final bool? acik;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(children: [
        Text(metin, style: serif(20)),
        const SizedBox(width: 8),
        Text('$sayi', style: sans(12, weight: FontWeight.w700, color: MC.gold)),
        if (acik != null) ...[const Spacer(), Icon(acik! ? Icons.expand_less : Icons.expand_more, color: MC.muted, size: 20)],
      ]),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({required this.e, required this.money, this.leading, this.soluk = false});

  final EkstreEslesme e;
  final String Function(int) money;
  final Widget? leading;
  final bool soluk;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final i = e.islem;
    final taksit = i.taksitli ? ' · ${s.pick('taksit', 'instalment')} ${i.taksitNo}/${i.taksitSayisi}' : '';
    final giris = i.tur == 'giris' || i.tur == 'odeme' || i.tur == 'iade';
    final renk = soluk ? MC.dim : MC.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        if (leading != null) SizedBox(width: 36, child: leading) else const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.aciklama, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(13.5, weight: FontWeight.w600, color: renk)),
            Text('${fmtDayShort(i.tarih, s.lang)}$taksit', style: sans(11.5, color: MC.dim)),
          ]),
        ),
        const SizedBox(width: 10),
        Text('${giris ? '+' : '−'}${money(i.k)}', style: numStyle(sans(13.5, weight: FontWeight.w700, color: soluk ? MC.dim : (giris ? MC.mint : MC.text)))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Önizleme (web, ekran görüntüsü)

/// Örnek profil için uydurma bir kart ekstresi (gerçek kişi ya da kart bilgisi değildir).
EkstreOkuma ornekEkstre() => ekstreOku(kOrnekEkstreSatirlari);

const List<List<String>> kOrnekEkstreSatirlari = [
  [
    'AKBANK T.A.Ş.\tKREDİ KARTI HESAP ÖZETİ',
    'Axess\tKart No: **** **** **** 4821',
    'Hesap Kesim Tarihi\tSon Ödeme Tarihi\tDönem Borcu\tAsgari Ödeme Tutarı',
    '03.11.2026\t13.11.2026\t2.560,00 TL\t512,00 TL',
    'Kart Limiti\t15.000,00 TL\tKullanılabilir Limit\t12.440,00 TL',
    'İşlem Tarihi\tAçıklama\tTutar',
    '06.10.2026\tÖDEMENİZ İÇİN TEŞEKKÜR EDERİZ\t1.640,00 TL -',
    '12.10.2026\tMİGROS KADIKÖY\t412,35 TL',
    '14.10.2026\tSPOTIFY PREMIUM\t99,00 TL',
    '19.10.2026\tSTARBUCKS BAĞDAT CAD\t185,00 TL',
    '24.10.2026\tTEKNOSA ONLINE 1/3\t1.000,00 TL',
    '28.10.2026\tİSTANBULKART DOLUM\t250,00 TL',
    'www.akbank.com\t444 25 25',
  ],
];
