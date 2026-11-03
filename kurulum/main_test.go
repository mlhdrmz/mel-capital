package main

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func makeZip(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range files {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func appZipForTest(t *testing.T, marker string) []byte {
	return makeZip(t, map[string]string{
		"MelCapital.exe":                        "uygulama " + marker,
		"flutter_windows.dll":                   "dll",
		"url_launcher_windows_plugin.dll":       "dll",
		"data/app.so":                           "so " + marker,
		"data/icudtl.dat":                       "icu",
		"data/flutter_assets/AssetManifest.bin": "assets",
	})
}

func read(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("%s okunamadı: %v", p, err)
	}
	return string(b)
}

func exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func TestExtractRenamesExe(t *testing.T) {
	dir := t.TempDir()
	n, err := extractApp(appZipForTest(t, "1"), dir)
	if err != nil {
		t.Fatal(err)
	}
	if n <= 0 {
		t.Fatalf("boyut %d", n)
	}
	if !exists(filepath.Join(dir, "Mel Capital.exe")) || exists(filepath.Join(dir, "MelCapital.exe")) {
		t.Fatal("uygulama dosyasının adı değişmedi")
	}
	if !isFlutterApp(dir) {
		t.Fatal("data/flutter_assets yok")
	}
}

func TestExtractRejectsBadPaths(t *testing.T) {
	for _, bad := range []string{"../disari.txt", "/etc/passwd", "C:/Windows/x.dll", "data/../../x"} {
		z := makeZip(t, map[string]string{"MelCapital.exe": "x", bad: "kötü"})
		if _, err := extractApp(z, t.TempDir()); err == nil {
			t.Fatalf("%q kabul edildi", bad)
		}
	}
	if _, err := extractApp(makeZip(t, map[string]string{"baska.exe": "x"}), t.TempDir()); err == nil {
		t.Fatal("uygulamasız arşiv kabul edildi")
	}
}

func TestInstallTreeReplacesOldApp(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "Mel Capital")
	// Eski (tek dosyalık) uygulama
	_ = os.MkdirAll(dir, 0o755)
	_ = os.WriteFile(filepath.Join(dir, "Mel Capital.exe"), []byte("eski"), 0o755)
	_ = os.WriteFile(filepath.Join(dir, "Kaldır.exe"), []byte("eski kaldır"), 0o755)
	_ = os.WriteFile(filepath.Join(dir, "surum.txt"), []byte("29.10.2026-22.39"), 0o644)
	if isFlutterApp(dir) {
		t.Fatal("eski uygulama yeni sanıldı")
	}

	size, err := installTree(appZipForTest(t, "2"), []byte("yeni kaldır"), dir, "03.11.2026-22.39", "150")
	if err != nil {
		t.Fatal(err)
	}
	if size <= 0 {
		t.Fatalf("boyut %d", size)
	}
	if got := read(t, filepath.Join(dir, "Mel Capital.exe")); got != "uygulama 2" {
		t.Fatalf("uygulama: %q", got)
	}
	if read(t, filepath.Join(dir, "Kaldır.exe")) != "yeni kaldır" || read(t, filepath.Join(dir, "surum.txt")) != "03.11.2026-22.39" || read(t, filepath.Join(dir, "derleme.txt")) != "150" {
		t.Fatal("kaldırma programı ya da sürüm dosyaları yazılmadı")
	}
	if !isFlutterApp(dir) {
		t.Fatal("yeni uygulama kurulmadı")
	}
	if exists(dir+".yeni") || exists(dir+".eski") {
		t.Fatal("geçici klasörler kaldı")
	}

	// Güncelleme: eski sürümün fazladan dosyası kalmaz
	_ = os.WriteFile(filepath.Join(dir, "data", "eski.bin"), []byte("x"), 0o644)
	if _, err := installTree(appZipForTest(t, "3"), []byte("k"), dir, "05.11.2026-14.20", "151"); err != nil {
		t.Fatal(err)
	}
	if read(t, filepath.Join(dir, "data", "app.so")) != "so 3" || exists(filepath.Join(dir, "data", "eski.bin")) {
		t.Fatal("güncelleme eski dosyaları temizlemedi")
	}
}

func TestReplaceContents(t *testing.T) {
	root := t.TempDir()
	dir, stage := filepath.Join(root, "d"), filepath.Join(root, "s")
	_ = os.MkdirAll(filepath.Join(dir, "alt"), 0o755)
	_ = os.WriteFile(filepath.Join(dir, "alt", "eski.txt"), []byte("e"), 0o644)
	_ = os.MkdirAll(filepath.Join(stage, "data"), 0o755)
	_ = os.WriteFile(filepath.Join(stage, "data", "yeni.txt"), []byte("y"), 0o644)
	if err := replaceContents(stage, dir); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(dir, "alt")) || read(t, filepath.Join(dir, "data", "yeni.txt")) != "y" {
		t.Fatal("içerik değişmedi")
	}
}

func TestBackupAll(t *testing.T) {
	root := t.TempDir()
	_ = os.WriteFile(filepath.Join(root, legacyDataFile), []byte(`{"v":4}`), 0o644)
	for _, id := range []string{"melih", "deniz"} {
		_ = os.MkdirAll(filepath.Join(root, "Profiller", id), 0o755)
		_ = os.WriteFile(filepath.Join(root, "Profiller", id, "veri.json"), []byte(`{"v":4,"id":"`+id+`"}`), 0o644)
	}
	_ = os.MkdirAll(filepath.Join(root, "Profiller", "Silinen profiller", "eski_2026"), 0o755)
	_ = os.WriteFile(filepath.Join(root, "Profiller", "profiller.json"), []byte(`{}`), 0o644)

	if n := backupAll(root, "guncelleme-oncesi"); n != 3 {
		t.Fatalf("%d dosya yedeklendi, 3 bekleniyordu", n)
	}
	if n := backupAll(root, "guncelleme-oncesi"); n != 3 {
		t.Fatalf("ikinci yedek: %d", n)
	}
	list, _ := os.ReadDir(filepath.Join(root, "Profiller", "melih", "Yedekler"))
	if len(list) != 2 {
		t.Fatalf("aynı dakikadaki iki yedek ayrı adla yazılmalı: %d", len(list))
	}
	for _, e := range list {
		if !strings.HasPrefix(e.Name(), "guncelleme-oncesi_") || !strings.HasSuffix(e.Name(), ".json") {
			t.Fatalf("yedek adı: %s", e.Name())
		}
	}
	if read(t, filepath.Join(root, "Profiller", "melih", "veri.json")) != `{"v":4,"id":"melih"}` {
		t.Fatal("veri değişti")
	}
}

func TestLanguage(t *testing.T) {
	t.Setenv("MC_HOME", t.TempDir())
	setLanguage("en")
	if T("a", "b") != "b" {
		t.Fatal("İngilizce seçilmedi")
	}
	// Uygulamanın dil ayarı Windows dilinden önce gelir
	_ = os.MkdirAll(filepath.Join(dataDir(), "Profiller"), 0o755)
	_ = os.WriteFile(filepath.Join(dataDir(), "Profiller", "profiller.json"), []byte(`{"lang":"tr"}`), 0o644)
	t.Setenv("MC_WINDOWS_DILI", "en")
	setLanguage("")
	if lang != "tr" {
		t.Fatalf("dil %s", lang)
	}
	_ = os.Remove(filepath.Join(dataDir(), "Profiller", "profiller.json"))
	setLanguage("")
	if lang != "en" {
		t.Fatalf("Windows dili: %s", lang)
	}
	setLanguage("tr")
}

func TestParseArgs(t *testing.T) {
	o := parseArgs([]string{"--sessiz", "--sonuc", "/tmp/x", "--dil", "en", "--veriyi-sil", "--uygulamadan"})
	if !o.silent || o.result != "/tmp/x" || o.lang != "en" || !o.wipe || !o.fromApp {
		t.Fatalf("%+v", o)
	}
}
