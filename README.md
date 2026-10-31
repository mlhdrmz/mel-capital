# Mel Capital

Kişisel borç, kart, hesap ve harcama takibi. Windows ve telefonda (Android) aynı uygulama,
Türkçe ve İngilizce.

> Durum: **1. aşama (altyapı)**. Tasarım ve pencere hazır; ekranlarda şimdilik örnek rakamlar var.

## Klasörler

| Klasör | İçerik |
|---|---|
| `app/` | Flutter uygulaması (Dart). `lib/` kod, `assets/` yazı tipleri ve fotoğraflar, `windows/` Windows penceresi |
| `.github/workflows/` | Otomatik derleme: her değişiklikte denetim, testler, web önizlemesi ve Windows sürümü |

## Derleme

Her `main` değişikliğinde GitHub Actions şunları yapar:

1. Kod denetimi ve testler (Ubuntu)
2. Web önizlemesi (tasarımı kontrol etmek için)
3. Windows sürümü: **Actions → son çalışma → MelCapital-Windows** içinden indirilir.
   Zip'i bir klasöre açıp `MelCapital.exe`'yi çalıştırmak yeterli.

Elle derlemek için Flutter 3.47 ve (Windows için) Visual Studio 2022 "Desktop development with C++" gerekir:

```
cd app
flutter pub get
flutter build windows --release
```

## Tasarım

"İmza köşe" cam paneller: her panelin yalnızca sol üst köşesi kesik, arkadaki fotoğraf bulanık,
sol üstten hafif ışık; üstteki rakam kutuları anlamına göre renkli (gelir yeşil, ödeme kırmızımsı,
serbest para altın). Pencere tam ekran ve başlık çubuğu olmadan açılır; Küçült / Kapat düğmeleri
uygulamanın üst menüsündedir.

Yazı tipleri: Inter ve Cormorant Garamond (SIL Open Font License, `app/assets/fonts/OFL-*.txt`).
Fotoğraflar: Unsplash.
