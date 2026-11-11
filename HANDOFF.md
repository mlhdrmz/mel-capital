# Mel Capital — Devir Teslim (HANDOFF)

Bu dosya, projede çalışan yapay zekâların (Claude ve Antigravity) birbirine işi devrettiği yerdir.
**İşe başlamadan önce bu dosyanın tamamını oku. İşin bitince "Son durum" ve "Devir kaydı"
bölümlerini güncelle.**

## 1. Kurallar (ikimiz için de geçerli)

1. **Aynı anda yalnızca biri çalışır.** Başlamadan önce `git pull`; bitince commit + `git push`.
   Diğeri o zamana kadar dokunmaz.
2. **Bu dosya her değişiklikte güncellenir** (Melih'in isteği): eklenen her özellik, her değişiklik
   ve her karar aynı commit'te "Son durum", "Kalan işler" ve "Devir kaydı" bölümlerine yazılır.
   Böylece öbür yapay zekâ projeyi her zaman güncel hâliyle devralır.
3. **Depo herkese açıktır.** Kişisel veri, gerçek tutarlar, banka ekstreleri, veri dosyası
   (`*.json` profil verisi), yedekler, PIN, kart/hesap numaraları, IBAN, TC kimlik, imza anahtarı
   (`*.jks`) ve şifreler **asla** depoya konmaz. Bu dosyaya da gerçek rakam yazılmaz. Testlerde
   yalnızca uydurma ya da `app/assets/sample/ornek.json` örnek verisi kullanılır.
4. **Kendi kafana göre değişiklik yok.** Melih'in istemediği hiçbir şey (tasarım, fotoğraf,
   içerik, davranış) değiştirilmez. Emin değilsen sor.
5. **Büyük işten önce numaralı sorular.** Yeni özellik ya da büyük değişiklikten önce Melih'e
   numaralı bir soru listesi sorulur; onay gelmeden başlanmaz.
6. **Testler geçmeden iş bitmiş sayılmaz.** `flutter analyze` ve `flutter test` temiz olmalı;
   GitHub Actions'taki "Derleme" iş akışı yeşil olmalı.
7. **Uygulama açıkken veri dosyasına yazılmaz.** Eski uygulamanın dosyaları (eski veri dosyası,
   `senkron.json`, `%LOCALAPPDATA%\Mel Capital` altındaki fotoğraf önbelleği ve `ayarlar.json`)
   yalnızca okunur, asla değiştirilmez.
8. Masaüstü uygulamasında şifre, kilit, şifreleme ve öneri/uyarı sistemi yoktur; uygulama
   internetsiz çalışır; yedekler Ayarlar'dan alınır.
9. Arka plan fotoğrafının tamamına karartma ya da bulanıklık konmaz (Melih'in istediği tek istisna:
   "sakin" sahnede yalnızca yazının tam arkasındaki yumuşak kenarlı hale). "Dikdörtgen + buğulu
   cam" görünümünden uzaklaşılıyor (bkz. 6. bölüm).
10. Arayüz dili Türkçe (İngilizcesi de var). Kod yorumları Türkçe.

## 2. Proje

Kişisel borç, kart, hesap ve harcama takibi. Windows ve Android'de aynı Flutter uygulaması.
Veri biçimi eski Mel Capital (JS) ile aynıdır (sürüm 4): eski veri dosyası, yedekler ve telefon
eşitlemesi aynen çalışır. Bilinmeyen alanlar korunur.

| Yer | İçerik |
|---|---|
| `app/lib/motor/` | **Motorlar**: bütün hesaplar ve veri değişiklikleri (bkz. 3. bölüm) |
| `app/lib/core/` | Veri modeli (`model.dart`), yükleme/onarım (`normalize.dart`), yardımcılar (`util.dart`), sabitler, logolar (`brands.dart`), fotoğraf listesi (`photos.dart`), eşitleme (`sync/`) |
| `app/lib/src/` | Arayüz: `state.dart` (uygulama durumu, tek değişiklik kapısı), `shell.dart` (çerçeve, menü, zil), `pages/` (sekmeler), `sheets/` (formlar), `sheet.dart`, `ui.dart`, `glass.dart`, `theme.dart`, `logos.dart`, `card_art.dart`, `background.dart` |
| `app/lib/storage/` | Dosyaya yazma, fotoğraf indirme, eşitleme taşıması, güncelleyici |
| `app/test/` | Testler (`calc_test` eski uygulamanın sonuçlarıyla karşılaştırır; `uyum_test` motorların uyumunu denetler) |
| `kurulum/` | Windows kurulum/güncelleme programı (Go) |
| `tool/` | Ekran görüntüsü (`screenshots.py`), yazı tipi (`yazi_tipi.py`) ve paketleme betikleri |
| `.github/workflows/derleme.yml` | Derleme: denetim + testler + web önizlemesi + ekran görüntüleri, Windows, Android, Yayın |

Yerelde derleme: Flutter 3.47.9. `cd app && flutter pub get && flutter analyze && flutter test`.
Windows için `flutter build windows --release` (Visual Studio 2022, C++ masaüstü).

Dallar: `main` (kod), `ekran-goruntuleri` (her derlemenin ekran görüntüleri, CI yazar),
`yazi-tipleri` (CI'ın ürettiği Manrope dosyaları; artık `main`'de de var).

Yayın: her `main` derlemesi "önizleme" sürümünü günceller. Resmî sürüm (kurulu uygulamalar
"yeni sürüm var" der) Actions → Derleme → Run workflow → "Resmi sürüm olarak yayınla" ile ve
yalnızca Melih'in onayıyla yapılır. İmzalı APK için `ANDROID_KEYSTORE` ve
`ANDROID_KEYSTORE_PASSWORD` gizli anahtarları gerekir (henüz eklenmedi).

## 3. Motorlar

Uygulama 1 çekirdek + 5 ana motor, Ekstre Motoru, uyum denetimi ve Performans Motoru'ndan oluşur
(`app/lib/motor/`, hepsi `motorlar.dart` ile içe aktarılır). Her dosyanın başında neyi yazdığı, neyi okuduğu ve kimlerin kullandığı yazar.

| Motor | Dosya | Sorumluluğu |
|---|---|---|
| Çekirdek (Hareket Defteri) | `cekirdek.dart` | Hareketler listesi, hesap bakiyeleri (bakiyeye yazan **tek** işlev `accAdjust`), hesaplar, aktarmalar, bankalar, kaynak adları |
| Gelir Motoru | `gelir.dart` | Maaş ve diğer gelirler, değişken gelir tahmini, "Maaşın yattı mı?" (yattı → çekirdeğe para girişi) |
| Gider Motoru | `gider.dart` | Harcamalar (tek tek, hızlı giriş, taksit), abonelik ve faturalar, sabit giderler, günlük harcama tahmini, kategori öğrenme |
| Borç Motoru | `borc.dart` | Kredi kartları (güncel borç, boş limit, ekstre, asgari), krediler, kart ödemesi, fiziksel kartlar, Findeks |
| Plan Motoru | `plan.dart` | `buildModel` ve `Ctx`: ay kalemleri, aylık özet, harcanabilir para, devir, yaklaşan ödemeler, ödeme işaretleme, ay kapatma, istek listesi |
| Ekstre Motoru | `ekstre.dart` | PDF ekstreyi okur (kart ekstresi ya da hesap dökümü), bankayı işaretlerinden tanır (`kBankaIzleri`), kartı son 4 haneden / hesabı IBAN son 4'ten bulur, elle girilenlerle eşleştirir, seçilenleri Gider Motoru ve Çekirdek üzerinden ekler, ekstreyi son güncel durum sayar |
| Uyum denetimi | `uyum.dart` | Motorların birbirini tuttuğunu denetler |
| Performans Motoru | `performans.dart` (+ `app/lib/src/performans.dart`) | Uygulamanın akıcı kalmasını denetler; para hesabı yapmaz. Hız bütçeleri (`PerfButce`: motor süreleri, sekme kurulumu, sayfa başına pahalı çizim sayısı) ve otomatik görsel kalite (`KaliteDenetcisi`) |

Kurallar:

1. **Sayfalar hesap yapmaz**, motorlara sorar (`st.ctx` ve motor işlevleri).
2. **Veri yalnızca `AppState.update((d) => ...)` içinde, motor işlevleriyle değişir.** Değişiklikten
   sonra `Ctx` yeniden kurulur ve bütün sayfalar aynı anda yenilenir.
3. Hiçbir motor başka bir motorun verisini kopyalamaz; aynı kaydı okur. Örnek: karttan harcama →
   Gider Motoru tek bir harcama kaydı yazar → Borç Motoru kart borcunu ve boş limiti o kayıttan
   hesaplar → Bankalar ve Plan aynı sonucu gösterir.
4. **Uyum denetimi** (`uyumDenetimi`): hata ayıklama modunda (testler dahil) her `update`ten sonra
   çalışır; bozulursa hata verir. Denetlenenler: hesap bakiyesi değişimi = hareketlerin değişimi
   (elle bakiye düzeltme hariç), maaş girişi = gelirin o ayki tutarı, ödemelerin sahibi var,
   kimlikler tek. Yeni bir veri değişikliği yazınca `test/uyum_test.dart`'a da adım ekle.
5. Tutarlar hesaplarda kuruş (tam sayı, `toK`/`fromK`), veride TL'dir. Aylar `YYYY-AA`.
6. **Performans Motoru kuralları** (Melih'in isteği: sonraki eklentiler de akıcı kalsın). Ölçüm
   (Melih'in bilgisayarı, s71): hesap ortalama 0,7 ms, çizim ortalama 23 ms; takılma motorlardan
   değil, çizimden geliyordu. Bu yüzden:
   - **Sayfalarda her karede bulanıklık hesaplanmaz.** Yazıya bulanık gölge (`Shadow.blurRadius >
     0`), `BackdropFilter`/`ImageFiltered`, kenar yumuşatmak için `MaskFilter` ve özel biçime
     (`ShapeDecoration` + `SignatureBorder`) bulanık gölge yasak; bütçeleri 0. Yazının arkası için
     `HaleZemini` / `Hale`, gölge için yuvarlak dikdörtgen `BoxDecoration.boxShadow` kullanılır.
   - `test/performans_test.dart` her derlemede büyük veriyle motor sürelerini, her sekmenin kurulum
     süresini ve pahalı çizim sayısını bütçeyle karşılaştırır; aşılırsa derleme durur. Yeni sekme
     ya da bölüm kendiliğinden denetlenir; **yeni motor işlevi eklenince teste bir `olc` satırı ve
     `PerfButce.motorMs`'e bütçesi eklenir.**
   - Yeni bir efekt (animasyon, geçiş, süs) eklenince `KaliteScope.of(context) ==
     GorselKalite.hafif` iken kapanmalıdır.
   - Uzun listeler `AzarAzar` ile, sayan/kıpırdayan küçük şeyler `RepaintBoundary` içinde çizilir.

## 4. Son durum

- Logolar (banka, mağaza, abonelik/fatura), eski arka plan fotoğrafları (75; içinde insan olan 2'si
  gösterilmiyor: `kPeoplePhotos`; içinde insan olan gömülü "lobby" kapağı silindi, yerine
  "highrise"), kart görselleri eski uygulamadaki gibi, tutarlar Manrope
  yazı tipiyle (tarih ve gün rakamları Manrope değil).
- Maaş ↔ banka bağlantısı: gelir hangi hesaba yatıyorsa seçilir; zilde "Maaşın yattı mı?" →
  "Yattı" o hesaba ekler. Abonelikler her ay "Ödedin mi?" diye sorulur. Net/brüt ve değişken gelir.
- Kod motorlara ayrıldı (davranış değişmedi) ve uyum denetimi eklendi.
- Bütün sekmeler ve giriş ekranları Özet gibi "sakin" sahnede (6. bölüm): siyah sayfalar yok,
  fotoğraf görünür; bölümlerin ve başlıkların arkasında yalnızca yumuşak kenarlı hafif
  bulanıklık. Açılır pencereler düz koyu ("pencere").
- Performans (Windows'ta sayfa değişirken takılma): canlı bulanıklık (BackdropFilter) kaldırıldı.
  Arka plan değişince fotoğrafın küçük bulanık kopyası bir kez hazırlanır (`bulanik.dart`:
  `bulanikKopyaHazirla`, `kBulanikArka`); bölümler arkalarına kopyanın ekranda kendilerine denk
  gelen yerini yumuşak kenarlı çizer (`BulanikZemin`). Fotoğraf geçişi 0,4 sn; sakin sahnede
  bölümler kayarak gelmez; rakamlar yalnızca Özet'te sayarak yükselir (`SayarakYukselir`). Arka
  plan ve sayan rakamlar ayrı katmanda (`RepaintBoundary`). Testte sekmelerde BackdropFilter
  olmadığı denetlenir. Dikkat: `BulanikZemin` ile kaydırılan içerik arasına `RepaintBoundary` ya
  da `ListView` konmamalı (kaydırınca kopya yerinden kayar).
- Performans 2: bilgisayarda görüntü önbelleği 512 MB (varsayılan 100 MB'ta 7 sekmenin ekran
  çözünürlüğündeki fotoğrafları sığmıyor, her sekme geçişinde fotoğraf yeniden çözülüyordu).
  Sekmelerin fotoğrafları ve bulanık kopyaları açılışta sırayla önceden hazırlanır
  (`_sekmeleriHazirla`, `bulanikKopyaOnceden`); bulanık kopyalar fotoğraf başına saklanır.
  Ölçüm testi: `test/performans_test.dart` (büyük veriyle motorlar ve sekme geçişleri; CI
  çıktısında "PERF" satırları). Ödeme ↔ para bağlantısı testi: `test/odeme_nakit_test.dart`
  (CI çıktısında "ODEME" satırları).
- Performans 4 (asıl düzeltme, Melih'in ölçümünden sonra): çizimi ağırlaştıran, bölümlerdeki her
  yazıya konan 2–3 bulanık gölge ve her bölümün yumuşak kenarı için her karede yapılan
  `MaskFilter` bulanıklığıydı. İkisi de kalktı:
  - Yazı gölgeleri bulanık değil (`kPhotoTextShadow`, `kBigTextShadow`, `kNetYaziGolgesi`);
    bölümlerin içindeki yazılarda gölge yok.
  - `BulanikZemin` bulanıklık hesaplamaz, ara katman açmaz: önceden hazırlanan bulanık kopyayı
    kenarda giderek saydamlaşan halkalarla (`drawDRRect` + `ImageShader`, kenar yumuşatma
    kapalı), koyu tonu kenarı yumuşak bir kafesle (`yumusakKafes` + `drawVertices`, yalnızca renk)
    çizer. Kopya daha güçlü bulanık (320 px, sigma 4).
  - **s71'deki "blur yetersiz" şikâyetinin asıl sebebi bir kilitlenmeydi:** `bulanik.dart`'ta
    `_hazirla(...).whenComplete(() => _hazirlaniyor.remove(anahtar))` yazılmıştı; `remove`
    haritadaki Future'ı (kendisini) döndürdüğü için `whenComplete` kendini bekliyor, kopya hiç
    "hazır" olmuyordu. Bulanık kopya ancak sekmeye ikinci gelişte (önbellekten) görünüyordu; ilk
    gelişte yazıların arkası yalnızca hafif koyu tondu. Düzeltildi (işlev artık bir şey
    döndürmüyor) ve `test/bulanik_test.dart` kopyanın gerçekten hazır olduğunu denetliyor.
  - Web önizlemesi her derlemede `web-onizleme` dalına konur (örnek verili); görünüm yerelde
    Playwright ile denenebilir (`?sekme=…&arka=hafif|orta|koyu&kalite=hafif|yuksek`; tarayıcı
    dili verilmeli, ör. `locale='tr-TR'`). Uygulama konsola `MC-TANI` ile başlayan satır yazarsa
    ekran görüntüsü adımı bunları `tani.txt`'ye toplar (tanı gerektiğinde kullanılır).
  - Okunabilirlik (Melih: "blur yetersiz, sayılar okunmuyor"): yazıların arkası daha koyu ve
    ayarlanabilir: Ayarlar → Dil ve görünüm → "Yazıların arkası" Hafif / Orta (varsayılan) / Koyu
    (`YaziArkasi`, ayar anahtarı `yaziArkasi`). Üst çubuktaki sekme adlarının ve "Mel Capital"
    yazısının arkasında da `Hale` var.
  - Fotoğrafın doğrudan üstündeki küçük düğme ve etiketler de aynı seçime göre koyulaşır
    (Melih'in kararı, 11.11.2026): arama kutusu, ‹ › düğmeleri, cam düğmeler ("Hızlı giriş",
    "Hesap", "Ekstre ekle"…), kategori etiketleri, Harcamalar/Abonelikler seçimi, kaynak seçme
    kutusu, zil, göz, eşitleme ve pencere düğmeleri, dil seçimi. Tek yerden: `kontrolZemini`
    (`sahne.dart`); düz renktir (bulanıklık, gölge, katman yok), tonu bulanık kopyasız bölümlerle
    aynıdır (`duzTon`: Hafif 0,52 · Orta 0,72 · Koyu 0,90). Bir bölümün ya da halenin içindeki
    (`HaleIci`) ve açılır pencerelerdeki düğmeler eski saydam zeminde kalır. Fotoğrafın üstüne yeni
    bir düğme ya da etiket konursa zemini `kontrolZemini(context)` ile verilir.
  - Alışveriş'teki bölüm başlıkları ("Alışveriş siteleri", "Alabilir miyim?", "İstek listesi",
    "Taksitli kart alışverişleri") ve altlarındaki satır fotoğrafın üstünde halesiz duruyordu
    (İstek listesi satırında rakam var); sayfa başlıklarındaki gibi `Hale` ile sarıldı.
  - Tanıtım, karşılama ve kurulum ekranlarındaki fotoğraf üstü yazılara dokunulmadı (yalnızca
    bulanık olmayan ince gölgeleri var; Melih'e sorulacak).
  - Otomatik kalite: Ayarlar → Performans → "Görsel kalite" Otomatik (varsayılan) / Yüksek /
    Hafif (ayar anahtarı `kalite`). Otomatikte art arda 2 × 90 karede karelerin %20'si 22 ms'den
    uzunsa hafife iner; 8 temiz bloktan sonra bir kez yüksek yeniden denenir; ikinci inişte oturum
    boyunca hafifte kalır. Hafifte: fotoğraf geçişi yok, Özet'te rakamlar saymaz, yazıların
    arkasında yalnızca koyu ton (bulanık kopya çizilmez).
  - Telefondaki alt menü hâlâ `BackdropFilter` kullanıyor (yalnızca telefonda; dokunulmadı).
- Ölçüm sonucu (CI, hata ayıklama modu, 5.051 harcama): motorların hepsi (Ctx) 12 ms, 13 ayın
  planı 55 ms; yani takılma motorlardan değil. Sekme kurulumu ağırdı (Harcamalar ~1 sn,
  Alışveriş ~0,8 sn hata ayıklama modunda). Performans 3: uzun listeler kare kare kurulur
  (`AzarAzar`: önce 24 satır, sonra her karede 24), marka logosu araması ada göre saklanır
  (`brandOf`), harcamalar bir kez aylara ayrılır (`Ctx.spendsOf`).
- Plan ödemeleri (Melih'in kararları, 07.11.2026):
  - Karttan ödenen aboneliğin "ödendi" işareti kart harcaması gibi sayılır: kartın son kesiminden
    (bakiye tarihinden) sonraysa kart borcuna eklenir, boş limitten düşer (`borclariHesapla`,
    `cardSubPays`). Kesimden önceki (ekstrede olan) ödeme eklenmez; iki kez sayılmaz.
  - Hesabı bilinmeyen kalemde (ilk kez ödeniyor, hesabı seçilmemiş) "Ödendi"ye basınca hangi
    hesaptan ödendiği sorulur (`_hesapSor`); "Hesaptan düşme" seçeneği de var. Seçilen hesap
    sonraki aylarda varsayılan olur (`lastFromFor`). `markPaid(..., from:, hesapsiz:)`.
  - Denetim testi `test/odeme_nakit_test.dart`: her kalem işaretlenir/kaldırılır; hesap, Özet'teki
    para, borç, kart borcu ve ay özeti birlikte değişir.
- Ayarlar → "Performans ölçümü" (`olcum.dart`, `KareOlcumu`): açıkken her karenin hesap (UI) ve
  çizim (raster) süresi toplanır; takılan kare sayısı, en uzun ve ortalama süreler gösterilir.
  Melih takılma olursa bu rakamları söyleyecek.
- Telefonda Özet'te fotoğrafçının adı sayfanın en altında (rakamların üstüne binmiyor); diğer
  sayfalarda alt menünün üstünde.
- Ekstre ekleme (Borçlar ve Bankalar'da "Ekstre ekle"): PDF seçilir (şifreliyse şifre sorulur,
  kaydedilmez), PDFium (`pdfrx`) ile cihazda okunur, panelde hedef kart/hesap, özet, yeni
  işlemler, "zaten var" ve "bu o mu?" gösterilir. Kart borcu ve limit kesim tarihindeki hâliyle,
  hesap bakiyesi dökümün kullanılabilir bakiyesiyle yazılır. Kart ödemeleri ve iadeler ekstre borcunda
  zaten var, ayrıca eklenmez. Testler uydurma ekstrelerle (`test/ekstre_test.dart`).
- Hesap dökümü okuma gerçek bir döküm düzeniyle denenip düzeltildi. Belge repoya konmadı;
  testteki döküm uydurma ("Hesap Hareketleri" düzeni). Düzeltilenler:
  - Satırlar PDF'in okuma sırasından kurulur (`satirlariKur`): virgül, nokta ve Ş ayrı satıra
    düşmez, kelimelerin içine boşluk girmez.
  - Döküm yeniden eskiye sıralı olabilir. Hesabın parası özetteki "Kullanılabilir Bakiye"den
    (Melih'in kararı: alt hesaplar, ör. Yanımda, dahil), yoksa "Bakiye"den, o da yoksa en yeni
    işlemden alınır. Dönemin son günü "gg/aa/yyyy - gg/aa/yyyy"den okunur.
  - Yön "+/-" işaretinden, yoksa yürüyen bakiyeden (iki sıralamada da) bulunur.
  - Tutar yalnızca tutar sütunundan alınır; açıklamadaki "10.00USD" ya da "Toplam: …" tutar
    sayılmaz.
  - Kendi hesapların arası harcama sayılmaz (tür `aktarma`): Yanımda, birikim, vadeli, virman,
    hesap sahibinin kendi adına havale/FAST. Hesap sahibinin adı yalnızca okurken kullanılır,
    kaydedilmez.
  - Bankanın "Etiket" sütunu kategoriye çevrilir: Kurum Ödemesi ve Telekomünikasyon → fatura,
    Faiz/Komisyon ve kesinti → banka, Para Transferi → transfer, Alışveriş → alışveriş.
  - Maaş satırı gelirle eşleşir: gelir o ay "yattı" olur, giriş Gelir Motoru'ndan yazılır.
    Fatura ve abonelik ödemeleri o ayki "ödendi" işareti olur; eşleştirme adla, markayla
    (`brandIndex`) ya da fatura şirketiyle yapılır (ör. Elektrik ↔ AESAŞ/BEDAŞ, Su ↔ İSKİ,
    Doğalgaz ↔ İGDAŞ).
- Ekstredeki işlemler kısa adlarıyla eklenir ve gösterilir (`ekstreAdi`): kart numarası parçası,
  "SATIŞ", döviz tutarı, ödeme aracısı (iyzico, YemekPay…), havale/FAST kuyruğu ve referans
  numaraları atılır. Bilinen işyerleri (`_bilinenler`: Anthropic, Google One, Amazon Prime,
  Netflix, Yemeksepeti, Uber Eats, Migros…) kendi adı ve kategorisiyle. Bilinen bir abonelik
  uygulamada kayıtlı değilse aboneliklere eklenir (adı, grubu, tutarı, günü ve kaynağı
  ekstreden) ve o ay ödendi olur; panelde "Aboneliklere eklenir" yazar.

## 5. Kalan işler

1. **Ekstre: resimli PDF** (2. aşama): yazısı olmayan (taranmış/fotoğraf) PDF'ler için cihazın
   kendi yazı tanıması: Windows'ta Windows.Media.Ocr, Android'de cihaz içi yazı tanıma; çıkan
   satırlar aynı `ekstreOku`'ya verilir. Bir bankada okuma yanlışsa Melih söyleyecek, o bankanın
   işaretleri/başlıkları `ekstre.dart`'ta düzeltilecek. Gerçek ekstreler ve kişisel bilgiler
   (ad, IBAN, hesap no, tutarlar) asla repoya, testlere ya da bu dosyaya konmaz.
2. **Alt hesaplar (ör. Yanımda)**: Melih'in son kararı: ayrı hesap açılmaz; hesabın parası her
   zaman dökümdeki "Kullanılabilir Bakiye" (alt hesaptaki para dahil). Alt hesaba giriş-çıkışlar
   harcama sayılmaz. Not: bazı bankalarda kullanılabilir bakiyeye artı hesap (KMH) limiti de
   girer; Melih'in hesabında yok, böyle bir durum çıkarsa sorulacak.
3. **Tasarım** (6. bölüm): bütün sekmeler sakin sahnede; yazı arkası koyuluğu ayarlanabilir.
   Melih s78'de takılmayı yeniden ölçecek (Ayarlar → Performans → Ölçüm); çizim süresi burada
   ölçülemedi, sonuç ondan beklenir.
4. **Borç kapatma hesaplayıcısı** (Melih'in sıradaki isteği, henüz başlanmadı): Borçlar'da ay,
   vade vb. girilip borcun ne zaman ve nasıl kapanacağını gösteren hesaplayıcı. Başlamadan önce
   Melih'e numaralı sorular sorulacak. Hesap Borç Motoru'na yazılır; Performans Motoru kuralları
   (6. kural) geçerli: `performans_test.dart`'a ölçümü eklenir.
5. Yatırımlar bölümü (henüz başlanmadı; sorular sorulacak).
6. İçinde insan olan diğer fotoğrafların taranması (75 fotoğrafın hepsine bakılamadı).
7. İmzalı APK (gizli anahtarlar eklenmedi; resmî sürümde yalnızca Windows dosyaları var).

## 6. Tasarım: sahneler

Okunabilirlik için dikdörtgen + buğulu cam yerine dört yön ("sahne") var. Uygulamada
`app/lib/src/sahne.dart`; her sekmenin sahnesi `kSekmeSahnesi`'nde. Paneller (`GlassPanel`, `Kpi`)
bulundukları sahneye göre çizilir. Sekmeler dışındaki ekranlar (tanıtım, karşılama, kurulum, veri
onarımı) da sakin. Açılır pencereler, düzenleme panelleri ve ipucu kartları "pencere" görünümünde
(düz koyu zemin, ince altın kenar, buğu yok). Eski buğulu cam kutular hiçbir yerde yok.

1. **Dergi sayfası**: solda düz koyu sayfa, fotoğraf sağda bütün.
2. **Kemerler**: kutular yerine fotoğrafın önünde kemer biçimli koyu pencereler.
3. **Fotoğrafın sakin yeri**: kutu yok; yazılar fotoğrafın üstünde, yalnızca yazının tam arkasında
   kenarları yumuşakça kaybolan hafif bulanıklık.
4. **Alttan açılan sayfa**: fotoğraf üstte, yazılar alttan açılan düz koyu sayfada.

Dağıtım (Melih'in kararı, 06.11.2026): siyah sayfalar gereksiz bulundu ve ekranda çok yer
kaplıyordu. Bütün sekmeler ve giriş ekranları (tanıtım, karşılama, kurulum, veri onarımı) 3
(sakin). Sakin sahnede paneller `HaleZemini` ile çizilir: kutu ve kenar yok; arkalarında yumuşak
kenarlı güçlü bulanıklık (fotoğrafın bir kez hazırlanan bulanık kopyası, `BulanikZemin`) ve koyu
ton; koyuluğu Ayarlar'dan seçilir (`YaziArkasi`). Yazılarda bulanık gölge yok (3. bölüm, 6.
kural). Sayfa
başlıkları da `Hale` ile sarılır. Açılır pencereler "pencere" kalır. Dergi, kemer ve sayfa
kodda duruyor ama kullanılmıyor. Gece modu yalnızca fotoğrafları değiştirir (19.00–07.00 gece
fotoğrafları); renkler aynıdır.

Ortak: espresso zemin `#15110d`, altın `#e3bf7c`, başlıklar Cormorant Garamond, metin Inter,
tutarlar Manrope.

## 7. Devir kaydı

| Tarih | Kim | Ne yapıldı |
|---|---|---|
| 2026-11-06 | Claude | HANDOFF.md oluşturuldu; kod 1 çekirdek + 5 motora ayrıldı; uyum denetimi ve testi eklendi; içinde insan olan 2 fotoğraf gizlendi |
| 2026-11-06 | Claude | Tasarım sahneleri uygulandı (`sahne.dart`); HANDOFF'un her değişiklikte güncellenmesi kurala eklendi |
| 2026-11-06 | Claude | Sayfa başlığı dar sütunda alt satıra iner; Özet'teki hale tasarım sayfasındaki kadar belirgin yapıldı; sekme testi taşmanın yerini yazar |
| 2026-11-06 | Claude | Tanıtım ve karşılama kemer, kurulum ve onarım dergi, açılır pencereler "pencere" görünümü; telefonda Özet'te fotoğrafçının adı en altta |
| 2026-11-06 | Claude | Ekstre Motoru (`motor/ekstre.dart`), PDF okuma (`storage/pdf_metin*.dart`, pdfrx), ekstre paneli (`src/sheets/ekstre.dart`), testleri |
| 2026-11-06 | Claude | Resmî sürüm yayınlandı: s56 (Mel Capital 06.11.2026-20.15), Melih'in onayıyla |
| 2026-11-06 | Claude | Hesap dökümü okuma düzeltildi (okuma sırasıyla satırlar, yeniden eskiye sıra, özetteki bakiye, kendi hesapların arası, etiketten kategori, maaş/fatura/abonelik eşleştirme); uydurma Garanti benzeri test eklendi |
| 2026-11-06 | Claude | Karar kaydedildi: Yanımda gibi alt hesaplar şimdilik sayılmaz (yalnızca vadesizin "Bakiye"si); kodda değişiklik yok |
| 2026-11-06 | Claude | Resmî sürüm yayınlandı: s60 (Mel Capital 06.11.2026-22.37), Melih'in onayıyla; hesap dökümü okuma düzeltmesi içinde |
| 2026-11-06 | Claude | Melih'in istekleri: hesap dökümünde para "Kullanılabilir Bakiye"den; işlemler kısa adla (`ekstreAdi`); kayıtsız bilinen abonelikler aboneliklere eklenir; bütün sekmeler ve giriş ekranları sakin sahne (siyah sayfalar kalktı, `HaleZemini`) |
| 2026-11-06 | Claude | Kısa adlarda Türkçe harf yoksa Latin büyük/küçük harf ("TEKNOSA ONLINE" → "Teknosa Online") |
| 2026-11-07 | Claude | Gömülü "lobby" kapağı (içinde 3 kişi) silindi, Melih'in onayıyla yerine "highrise"; tanıtımın 2. sayfası "lock"; kapak sırası testi yeniden hesaplandı |
| 2026-11-07 | Claude | Resmî sürüm yayınlandı: s65 (Mel Capital 07.11.2026-01.51), Melih'in onayıyla; kullanılabilir bakiye, kısa adlar, yeni abonelikler, sakin tasarım, lobby kapağının kaldırılması içinde |
| 2026-11-07 | Claude | Performans: canlı bulanıklık yerine bir kez hazırlanan bulanık kopya (`bulanik.dart`); fotoğraf geçişi 0,4 sn, bölümler kayarak gelmez, rakamlar yalnızca Özet'te sayar; arka plan ve sayan rakam ayrı katmanda (Melih'in onayıyla) |
| 2026-11-07 | Claude | Performans 2: görüntü önbelleği, sekme fotoğrafları ve bulanık kopyalar önceden; motor ölçüm testi ve Plan ödeme ↔ hesaplardaki para denetim testi |
| 2026-11-07 | Claude | Ölçüm: motorlar hızlı (Ctx 12 ms); Performans 3: uzun listeler kare kare (`AzarAzar`), marka araması önbellekte, `Ctx.spendsOf` |
| 2026-11-07 | Claude | Karttan ödenen abonelik kart borcuna eklenir; hesabı bilinmeyen kalemde "Ödendi" hesap sorar; Ayarlar'a performans ölçümü (Melih'in onayıyla) |
| 2026-11-07 | Claude | Resmî sürüm yayınlandı: s71 (Mel Capital 07.11.2026-04.21), Melih'in onayıyla; performans 1–3, kart aboneliği → kart borcu, hesap sorma, performans ölçümü içinde |
| 2026-11-10 | Claude | Performans Motoru (`motor/performans.dart`, `src/performans.dart`): hız ve çizim bütçeleri, otomatik görsel kalite. Takılmanın asıl sebebi giderildi: bulanık yazı gölgeleri ve her karede kenar bulanıklığı kalktı (`yumusakKafes`). Yazıların arkası koyulaştı ve ayarlanabilir (Hafif/Orta/Koyu). Borç kapatma hesaplayıcısı kalan işlere yazıldı |
| 2026-11-10 | Claude | s71'deki "blur yetersiz"in sebebi bulundu: bulanık kopyanın hazırlığı kendini bekleyip hiç bitmiyordu (`bulanik.dart`); düzeltildi, testi eklendi. Web önizlemesi `web-onizleme` dalında |
| 2026-11-11 | Claude | Fotoğrafın üstündeki küçük düğme ve etiketler "Yazıların arkası" seçimine göre koyulaşır (`kontrolZemini`, `HaleIci`); Alışveriş'teki bölüm başlıklarına hale (düğmeler Melih'in onayıyla; başlıklar aynı okunabilirlik şikâyeti kapsamında) |
| 2026-11-11 | Claude | Resmî sürüm yayınlandı: s78 (Mel Capital 11.11.2026-19.37), Melih'in onayıyla; Performans Motoru, bulanık kopya düzeltmesi, ayarlanabilir yazı arkası, koyulaşan düğmeler, Alışveriş başlıklarına hale içinde |
