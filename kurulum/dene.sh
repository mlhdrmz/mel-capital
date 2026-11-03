#!/bin/bash
# Kurulum, güncelleme ve kaldırma programlarını Linux'ta dener: Windows klasörleri MC_HOME altında
# taklit edilir (bkz. sys_other.go). Eski uygulamanın yerine kurma, güncelleme ve kaldırma akışı.
set -euo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
H="$T/ev"
export MC_HOME="$H"
PF="$H/ProgramFiles/Mel Capital"
DOCS="$H/Documents/Mel Capital"

fail() { echo "HATA: $*" >&2; exit 1; }
check() { [ -e "$1" ] || fail "$1 yok"; }
absent() { [ ! -e "$1" ] || fail "$1 kalmış"; }

# 1) Sahte uygulama arşivi ve kaldırma programı
python3 - "$T/uygulama.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('MelCapital.exe', 'yeni uygulama')
    z.writestr('flutter_windows.dll', 'dll')
    z.writestr('data/app.so', 'so')
    z.writestr('data/flutter_assets/AssetManifest.bin', 'assets')
PY
mkdir -p payload
cp "$T/uygulama.zip" payload/uygulama.zip
go build -ldflags "-X main.mode=kaldir -X main.version=05.11.2026-14.20" -o payload/kaldir.exe .
go build -tags payload -ldflags "-X main.mode=kurulum -X main.version=03.11.2026-22.39 -X main.build=150" -o "$T/kurulum" .
go build -tags payload -ldflags "-X main.mode=guncelleme -X main.version=05.11.2026-14.20 -X main.build=151" -o "$T/guncelleme" .

# 2) Güncelleme, kurulum yokken çalışmaz
"$T/guncelleme" --sessiz --sonuc "$T/s0" --dil tr || true
grep -q "kurulu değil" "$T/s0" || fail "kurulu değilken güncelleme: $(cat "$T/s0")"

# 3) Eski uygulama kurulu: tek dosya, eski veri, eski önbellekler
mkdir -p "$PF" "$DOCS" "$H/AppData/Mel Capital/Pencere" "$H/AppData/Mel Capital/Fotograflar"
echo "eski uygulama" > "$PF/Mel Capital.exe"
echo '{"v":4}' > "$DOCS/mel-capital-veri.json"
echo '{}' > "$H/AppData/Mel Capital/senkron.json"

# Windows izni verilmezse kurulum olmaz, eski uygulama yerinde kalır
MC_IZIN=hayir "$T/kurulum" --sessiz --sonuc "$T/s1" --dil tr || true
grep -q "izni verilmedi" "$T/s1" || fail "izin reddi: $(cat "$T/s1")"
[ "$(cat "$PF/Mel Capital.exe")" = "eski uygulama" ] || fail "izin yokken eski uygulama değişti"

"$T/kurulum" --sessiz --sonuc "$T/s2" --dil tr
[ "$(cat "$T/s2")" = "ok" ] || fail "kurulum: $(cat "$T/s2")"
[ "$(cat "$PF/Mel Capital.exe")" = "yeni uygulama" ] || fail "yeni uygulama kurulmadı"
check "$PF/data/flutter_assets/AssetManifest.bin"
check "$PF/Kaldır.exe"
[ "$(cat "$PF/surum.txt")" = "03.11.2026-22.39" ] || fail "surum.txt"
[ "$(cat "$PF/derleme.txt")" = "150" ] || fail "derleme.txt"
grep -q '"DisplayVersion":"03.11.2026-22.39"' "$H/registry/MelCapital.json" || fail "Windows kaydı"
check "$H/StartMenuAll/Mel Capital.lnk"
check "$H/Desktop/Mel Capital.lnk"
ls "$DOCS/Yedekler/"kurulum-oncesi_*.json >/dev/null || fail "eski veri yedeklenmedi"
[ "$(cat "$DOCS/mel-capital-veri.json")" = '{"v":4}' ] || fail "eski veri değişti"
absent "$H/AppData/Mel Capital/Pencere"
absent "$H/AppData/Mel Capital/Fotograflar"
check "$H/AppData/Mel Capital/senkron.json"
absent "$PF.yeni"
absent "$PF.eski"

# 4) Güncelleme: profil verisi yedeklenir, sürüm değişir
mkdir -p "$DOCS/Profiller/melih"
echo '{"v":4,"accounts":[]}' > "$DOCS/Profiller/melih/veri.json"
"$T/guncelleme" --sessiz --sonuc "$T/s3" --dil tr
[ "$(cat "$T/s3")" = "ok" ] || fail "güncelleme: $(cat "$T/s3")"
[ "$(cat "$PF/surum.txt")" = "05.11.2026-14.20" ] || fail "güncelleme sürümü"
ls "$DOCS/Profiller/melih/Yedekler/"guncelleme-oncesi_*.json >/dev/null || fail "profil yedeklenmedi"

# 5) Kaldırma (verilerle birlikte): geçici kopyadan çalışır, bitmesi beklenir
"$PF/Kaldır.exe" --sessiz --veriyi-sil --sonuc "$T/s4"
for _ in $(seq 1 60); do [ -e "$PF" ] || break; sleep 0.25; done
absent "$PF"
for _ in $(seq 1 40); do [ -e "$T/s4" ] && break; sleep 0.25; done
[ "$(cat "$T/s4" 2>/dev/null)" = "ok" ] || fail "kaldırma: $(cat "$T/s4" 2>/dev/null)"
absent "$H/registry/MelCapital.json"
absent "$H/StartMenuAll/Mel Capital.lnk"
absent "$H/Desktop/Mel Capital.lnk"
absent "$DOCS"
absent "$H/AppData/Mel Capital"
rm -f payload/uygulama.zip payload/kaldir.exe
echo "kurulum denemesi: tamam"
