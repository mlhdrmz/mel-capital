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

Uygulama 1 çekirdek + 5 ana motordan oluşur (`app/lib/motor/`, hepsi `motorlar.dart` ile
içe aktarılır). Her dosyanın başında neyi yazdığı, neyi okuduğu ve kimlerin kullandığı yazar.

| Motor | Dosya | Sorumluluğu |
|---|---|---|
| Çekirdek (Hareket Defteri) | `cekirdek.dart` | Hareketler listesi, hesap bakiyeleri (bakiyeye yazan **tek** işlev `accAdjust`), hesaplar, aktarmalar, bankalar, kaynak adları |
| Gelir Motoru | `gelir.dart` | Maaş ve diğer gelirler, değişken gelir tahmini, "Maaşın yattı mı?" (yattı → çekirdeğe para girişi) |
| Gider Motoru | `gider.dart` | Harcamalar (tek tek, hızlı giriş, taksit), abonelik ve faturalar, sabit giderler, günlük harcama tahmini, kategori öğrenme |
| Borç Motoru | `borc.dart` | Kredi kartları (güncel borç, boş limit, ekstre, asgari), krediler, kart ödemesi, fiziksel kartlar, Findeks |
| Plan Motoru | `plan.dart` | `buildModel` ve `Ctx`: ay kalemleri, aylık özet, harcanabilir para, devir, yaklaşan ödemeler, ödeme işaretleme, ay kapatma, istek listesi |
| Ekstre Motoru | `ekstre.dart` | PDF ekstreyi okur (kart ekstresi ya da hesap dökümü), bankayı işaretlerinden tanır (`kBankaIzleri`), kartı son 4 haneden / hesabı IBAN son 4'ten bulur, elle girilenlerle eşleştirir, seçilenleri Gider Motoru ve Çekirdek üzerinden ekler, ekstreyi son güncel durum sayar |
| Uyum denetimi | `uyum.dart` | Motorların birbirini tuttuğunu denetler |

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

## 4. Son durum

- Logolar (banka, mağaza, abonelik/fatura), eski arka plan fotoğrafları (75; içinde insan olan 2'si
  gösterilmiyor: `kPeoplePhotos`), kart görselleri eski uygulamadaki gibi, tutarlar Manrope
  yazı tipiyle (tarih ve gün rakamları Manrope değil).
- Maaş ↔ banka bağlantısı: gelir hangi hesaba yatıyorsa seçilir; zilde "Maaşın yattı mı?" →
  "Yattı" o hesaba ekler. Abonelikler her ay "Ödedin mi?" diye sorulur. Net/brüt ve değişken gelir.
- Kod motorlara ayrıldı (davranış değişmedi) ve uyum denetimi eklendi.
- Sekmeler dört sahneyle çiziliyor (6. bölüm): Özet'te yazıların arkasında hale, Bankalar'da
  kemer pencereler, Harcamalar ve Plan'da alttan açılan yaprak, diğerlerinde dergi sayfası.
  Tanıtım, karşılama, kurulum, veri onarımı ve açılır pencereler de yeni görünümde.
- Telefonda Özet'te fotoğrafçının adı sayfanın en altında (rakamların üstüne binmiyor).
- Ekstre ekleme (Borçlar ve Bankalar'da "Ekstre ekle"): PDF seçilir (şifreliyse şifre sorulur,
  kaydedilmez), PDFium (`pdfrx`) ile cihazda okunur, panelde hedef kart/hesap, özet, yeni
  işlemler, "zaten var" ve "bu o mu?" gösterilir. Kart borcu ve limit kesim tarihindeki hâliyle,
  hesap bakiyesi dökümün son bakiyesiyle yazılır. Kart ödemeleri ve iadeler ekstre borcunda
  zaten var, ayrıca eklenmez. Testler uydurma ekstrelerle (`test/ekstre_test.dart`).
- Hesap dökümü okuma gerçek bir döküm düzeniyle denenip düzeltildi. Belge repoya konmadı;
  testteki döküm uydurma ("Hesap Hareketleri" düzeni). Düzeltilenler:
  - Satırlar PDF'in okuma sırasından kurulur (`satirlariKur`): virgül, nokta ve Ş ayrı satıra
    düşmez, kelimelerin içine boşluk girmez.
  - Döküm yeniden eskiye sıralı olabilir. Son bakiye özetteki "Bakiye"den, yoksa en yeni işlemden
    alınır. Dönemin son günü "gg/aa/yyyy - gg/aa/yyyy"den okunur.
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

## 5. Kalan işler

1. **Ekstre: resimli PDF** (2. aşama): yazısı olmayan (taranmış/fotoğraf) PDF'ler için cihazın
   kendi yazı tanıması: Windows'ta Windows.Media.Ocr, Android'de cihaz içi yazı tanıma; çıkan
   satırlar aynı `ekstreOku`'ya verilir. Bir bankada okuma yanlışsa Melih söyleyecek, o bankanın
   işaretleri/başlıkları `ekstre.dart`'ta düzeltilecek. Gerçek ekstreler ve kişisel bilgiler
   (ad, IBAN, hesap no, tutarlar) asla repoya, testlere ya da bu dosyaya konmaz.
2. **Alt hesaplar (ör. Yanımda)**: dökümdeki "Bakiye" vadesiz hesabındır; "Kullanılabilir
   Bakiye" alt hesaptaki parayı da içerir. Melih'in kararı (şimdilik): alt hesap ayrı hesap
   olarak açılmaz, bakiyeye de eklenmez; yalnızca vadesizin "Bakiye"si yazılır. Alt hesaba
   giriş-çıkışlar harcama sayılmaz. Melih isterse sonra yeniden ele alınacak.
3. **Tasarım sahneleri** (6. bölüm): bütün ekranlara uygulandı; Melih'in yorumu bekleniyor.
4. Yatırımlar bölümü (henüz başlanmadı; sorular sorulacak).
5. İçinde insan olan diğer fotoğrafların taranması (75 fotoğrafın hepsine bakılamadı).
6. İmzalı APK (gizli anahtarlar eklenmedi; resmî sürümde yalnızca Windows dosyaları var).

## 6. Tasarım: sahneler

Okunabilirlik için dikdörtgen + buğulu cam yerine dört yön ("sahne") var. Uygulamada
`app/lib/src/sahne.dart`; her sekmenin sahnesi `kSekmeSahnesi`'nde. Paneller (`GlassPanel`, `Kpi`)
bulundukları sahneye göre çizilir. Sekmeler dışındaki ekranlar: tanıtım ve karşılama kemer,
kurulum ve veri onarımı dergi. Açılır pencereler, düzenleme panelleri ve ipucu kartları "pencere"
görünümünde (düz koyu zemin, ince altın kenar, buğu yok). Artık hiçbir yerde buğulu cam yok.

1. **Dergi sayfası**: solda düz koyu sayfa, fotoğraf sağda bütün.
2. **Kemerler**: kutular yerine fotoğrafın önünde kemer biçimli koyu pencereler.
3. **Fotoğrafın sakin yeri**: kutu yok; yazılar fotoğrafın üstünde, yalnızca yazının tam arkasında
   kenarları yumuşakça kaybolan hafif bulanıklık.
4. **Alttan açılan sayfa**: fotoğraf üstte, yazılar alttan açılan düz koyu sayfada.

Dağıtım (Claude belirledi, Melih beğenmezse değişecek): Özet → 3 (sakin), Bankalar → 2 (kemer),
Harcamalar ve Plan → 4 (sayfa), Borçlar, Alışveriş, Ayarlar → 1 (dergi). Telefonda da aynı.

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
