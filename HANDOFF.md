# Mel Capital — Devir Teslim (HANDOFF)

Bu dosya, projede çalışan yapay zekâların (Claude ve Antigravity) birbirine işi devrettiği yerdir.
**İşe başlamadan önce bu dosyanın tamamını oku. İşin bitince "Son durum" ve "Devir kaydı"
bölümlerini güncelle.**

## 1. Kurallar (ikimiz için de geçerli)

1. **Aynı anda yalnızca biri çalışır.** Başlamadan önce `git pull`; bitince commit + `git push` ve
   bu dosyayı güncelle. Diğeri o zamana kadar dokunmaz.
2. **Depo herkese açıktır.** Kişisel veri, gerçek tutarlar, banka ekstreleri, veri dosyası
   (`*.json` profil verisi), yedekler, PIN, kart/hesap numaraları, IBAN, TC kimlik, imza anahtarı
   (`*.jks`) ve şifreler **asla** depoya konmaz. Bu dosyaya da gerçek rakam yazılmaz. Testlerde
   yalnızca uydurma ya da `app/assets/sample/ornek.json` örnek verisi kullanılır.
3. **Kendi kafana göre değişiklik yok.** Melih'in istemediği hiçbir şey (tasarım, fotoğraf,
   içerik, davranış) değiştirilmez. Emin değilsen sor.
4. **Büyük işten önce numaralı sorular.** Yeni özellik ya da büyük değişiklikten önce Melih'e
   numaralı bir soru listesi sorulur; onay gelmeden başlanmaz.
5. **Testler geçmeden iş bitmiş sayılmaz.** `flutter analyze` ve `flutter test` temiz olmalı;
   GitHub Actions'taki "Derleme" iş akışı yeşil olmalı.
6. **Uygulama açıkken veri dosyasına yazılmaz.** Eski uygulamanın dosyaları (eski veri dosyası,
   `senkron.json`, `%LOCALAPPDATA%\Mel Capital` altındaki fotoğraf önbelleği ve `ayarlar.json`)
   yalnızca okunur, asla değiştirilmez.
7. Masaüstü uygulamasında şifre, kilit, şifreleme ve öneri/uyarı sistemi yoktur; uygulama
   internetsiz çalışır; yedekler Ayarlar'dan alınır.
8. Arka plan fotoğraflarının üstüne karartma ya da bulanıklık konmaz. "Dikdörtgen + buğulu cam"
   görünümünden uzaklaşılıyor (bkz. 6. bölüm, tasarım yönleri).
9. Arayüz dili Türkçe (İngilizcesi de var). Kod yorumları Türkçe.

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
| Ekstre Motoru | (sırada) | PDF ekstreyi okur, bankayı tanır, elle girilenlerle eşleştirir, yenileri önerir; Gider ve Borç motorları üzerinden ekler |
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

## 5. Kalan işler

1. **Ekstre Motoru** (onaylandı, sırada): Melih bankalardan aldığı PDF ekstreleri ekleyecek.
   Eklenen ekstre kartın son güncel durumu sayılır; banka otomatik tanınır; elle girilmiş
   harcamalarla üst üste binmez (eşleşenler atlanır ya da "Bu o mu?" diye sorulur); eklenmeden
   önce bir analiz ekranı gösterilir. Açık sorular: hangi bankalar, yalnızca kredi kartı mı,
   eşleştirme kuralı (aynı tutar, ±2 gün, benzer ad), örnek PDF'ler (yalnızca yerelde, depoya asla).
2. **Tasarım yönleri** (6. bölüm): dört yön de beğenildi, sayfalara dağıtım onay bekliyor.
3. Yatırımlar bölümü (henüz başlanmadı; sorular sorulacak).
4. İçinde insan olan diğer fotoğrafların taranması (75 fotoğrafın hepsine bakılamadı).
5. Resmî sürüm (Melih'in onayı) ve imzalı APK (gizli anahtarlar).

## 6. Tasarım yönleri

Okunabilirlik için dikdörtgen + buğulu cam yerine dört yön hazırlandı (Claude'daki tasarım
sayfasında, bilgisayar ve telefon hâlleriyle):

1. **Dergi sayfası**: solda düz koyu sayfa, fotoğraf sağda bütün.
2. **Kemerler**: kutular yerine fotoğrafın önünde kemer biçimli koyu pencereler.
3. **Fotoğrafın sakin yeri**: kutu yok; yazılar fotoğrafın üstünde, yalnızca yazının tam arkasında
   kenarları yumuşakça kaybolan hafif bulanıklık.
4. **Alttan açılan sayfa**: fotoğraf üstte, yazılar alttan açılan düz koyu sayfada.

Önerilen dağıtım (onay bekliyor): Özet → 3, Bankalar → 2, Harcamalar ve Plan → 4,
Borçlar, Alışveriş, Ayarlar → 1.

Ortak: espresso zemin `#15110d`, altın `#e3bf7c`, başlıklar Cormorant Garamond, metin Inter,
tutarlar Manrope.

## 7. Devir kaydı

| Tarih | Kim | Ne yapıldı |
|---|---|---|
| 2026-11-06 | Claude | HANDOFF.md oluşturuldu; kod 1 çekirdek + 5 motora ayrıldı; uyum denetimi ve testi eklendi; içinde insan olan 2 fotoğraf gizlendi |
