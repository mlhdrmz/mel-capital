package main

// Program klasörünü kurma işleri: uygulama arşivini açma, eski klasörle değiştirme, yedekler.
// Bu dosyadaki işlevler Windows'a bağlı değildir; Linux'ta testlerle denenir.

import (
	"archive/zip"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// Flutter derlemesindeki çalıştırılabilir dosyanın adı; kurulurken "Mel Capital.exe" olur
// (Başlat menüsü ve görev çubuğu kısayolları eski uygulamadakiyle aynı dosyayı gösterir).
const (
	builtExeName = "MelCapital.exe"
	appExeName   = "Mel Capital.exe"
)

// extractApp, uygulama arşivini dir klasörüne açar ve açılan toplam boyutu döner.
// Arşivdeki yollar klasörün dışına çıkamaz ("..", mutlak yol); MelCapital.exe adı değiştirilir.
func extractApp(archive []byte, dir string) (int64, error) {
	zr, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return 0, fmt.Errorf("uygulama arşivi okunamadı: %v", err)
	}
	var total int64
	found := false
	for _, f := range zr.File {
		name := strings.ReplaceAll(f.Name, `\`, "/")
		if name == "" || strings.HasSuffix(name, "/") {
			continue
		}
		clean := path.Clean(name)
		if clean == "." || strings.HasPrefix(clean, "../") || clean == ".." || path.IsAbs(clean) || strings.Contains(clean, ":") {
			return 0, fmt.Errorf("arşivde geçersiz yol: %s", f.Name)
		}
		if clean == builtExeName {
			clean = appExeName
			found = true
		} else if clean == appExeName {
			found = true
		}
		dst := filepath.Join(dir, filepath.FromSlash(clean))
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return 0, err
		}
		n, err := writeZipFile(f, dst)
		if err != nil {
			return 0, fmt.Errorf("%s yazılamadı: %v", clean, err)
		}
		total += n
	}
	if !found {
		return 0, errors.New("arşivde Mel Capital uygulaması yok")
	}
	return total, nil
}

func writeZipFile(f *zip.File, dst string) (int64, error) {
	rc, err := f.Open()
	if err != nil {
		return 0, err
	}
	defer rc.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		return 0, err
	}
	n, err := io.Copy(out, rc)
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	return n, err
}

// retry, işi birkaç kez dener (dosyalar bir an kilitli olabilir: virüs taraması, kapanan süreç).
func retry(times int, wait time.Duration, job func() error) error {
	var err error
	for i := 0; i < times; i++ {
		if err = job(); err == nil {
			return nil
		}
		time.Sleep(wait)
	}
	return err
}

// installTree, uygulamayı dir klasörüne kurar ve kurulan toplam boyutu döner.
//
// Önce yanındaki "<dir>.yeni" klasörüne açılır; sonra eski klasör "<dir>.eski" yapılıp yenisi
// yerine konur. Böylece yarıda kalan bir kurulum çalışan sürümü bozmaz. Eski klasör yeniden
// adlandırılamazsa (ör. bir dosyası açık) içi silinip yeni dosyalar taşınır.
func installTree(archive, uninstaller []byte, dir, label, build string) (int64, error) {
	stage := dir + ".yeni"
	old := dir + ".eski"
	_ = os.RemoveAll(stage)
	_ = os.RemoveAll(old)
	if err := os.MkdirAll(stage, 0o755); err != nil {
		return 0, fmt.Errorf("klasör oluşturulamadı: %v", err)
	}
	size, err := extractApp(archive, stage)
	if err != nil {
		_ = os.RemoveAll(stage)
		return 0, err
	}
	if len(uninstaller) > 0 {
		if err := os.WriteFile(filepath.Join(stage, "Kaldır.exe"), uninstaller, 0o755); err != nil {
			_ = os.RemoveAll(stage)
			return 0, fmt.Errorf("Kaldır.exe yazılamadı: %v", err)
		}
		size += int64(len(uninstaller))
	}
	_ = os.WriteFile(filepath.Join(stage, "surum.txt"), []byte(label), 0o644)
	_ = os.WriteFile(filepath.Join(stage, "derleme.txt"), []byte(build), 0o644)

	if _, err := os.Stat(dir); err == nil {
		if err := retry(16, 500*time.Millisecond, func() error { return os.Rename(dir, old) }); err != nil {
			// Klasör yeniden adlandırılamadı: içini değiştir.
			if err := replaceContents(stage, dir); err != nil {
				_ = os.RemoveAll(stage)
				return 0, fmt.Errorf("eski sürümün dosyaları değiştirilemedi (Mel Capital açık olabilir): %v", err)
			}
			_ = os.RemoveAll(stage)
			return size, nil
		}
	}
	if err := retry(10, 300*time.Millisecond, func() error { return os.Rename(stage, dir) }); err != nil {
		if _, serr := os.Stat(old); serr == nil {
			_ = os.Rename(old, dir) // eski sürümü geri koy
		}
		return 0, fmt.Errorf("yeni sürüm yerine konamadı: %v", err)
	}
	_ = retry(10, 300*time.Millisecond, func() error { return os.RemoveAll(old) })
	return size, nil
}

// replaceContents, dir içindekileri silip stage içindekileri oraya taşır.
func replaceContents(stage, dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		p := filepath.Join(dir, e.Name())
		if err := retry(10, 300*time.Millisecond, func() error { return os.RemoveAll(p) }); err != nil {
			return err
		}
	}
	news, err := os.ReadDir(stage)
	if err != nil {
		return err
	}
	for _, e := range news {
		if err := os.Rename(filepath.Join(stage, e.Name()), filepath.Join(dir, e.Name())); err != nil {
			return err
		}
	}
	return nil
}

// isFlutterApp: klasördeki Mel Capital yeni (Flutter) uygulama mı? Eskisi tek dosyalık bir programdı.
func isFlutterApp(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, "data", "flutter_assets"))
	return err == nil
}

// ---------------------------------------------------------------- yedekler

func stampNow() string { return time.Now().Format("2006-01-02_1504") }

// uniqueName, klasörde olmayan bir dosya adı bulur (base.json, base_2.json, ...).
func uniqueName(dir, base, ext string) string {
	name := base + ext
	for i := 2; ; i++ {
		if _, err := os.Stat(filepath.Join(dir, name)); os.IsNotExist(err) {
			return name
		}
		name = fmt.Sprintf("%s_%d%s", base, i, ext)
	}
}

// backupAll, kurmadan önce verilerin kopyasını alır: eski uygulamanın veri dosyası ve her profilin
// verisi kendi "Yedekler" klasörüne (uygulamanın Ayarlar › Yedekler listesinde görünür). Kaç dosya
// yedeklendiğini döner. Veriler hiçbir zaman değiştirilmez ya da silinmez.
func backupAll(dataRoot, prefix string) int {
	count := 0
	stamp := stampNow()
	if b, err := os.ReadFile(filepath.Join(dataRoot, legacyDataFile)); err == nil {
		dir := filepath.Join(dataRoot, "Yedekler")
		if os.MkdirAll(dir, 0o755) == nil && os.WriteFile(filepath.Join(dir, uniqueName(dir, prefix+"_"+stamp, ".json")), b, 0o644) == nil {
			count++
		}
	}
	profiles := filepath.Join(dataRoot, "Profiller")
	entries, _ := os.ReadDir(profiles)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		b, err := os.ReadFile(filepath.Join(profiles, e.Name(), "veri.json"))
		if err != nil {
			continue
		}
		dir := filepath.Join(profiles, e.Name(), "Yedekler")
		if os.MkdirAll(dir, 0o755) == nil && os.WriteFile(filepath.Join(dir, uniqueName(dir, prefix+"_"+stamp, ".json")), b, 0o644) == nil {
			count++
		}
	}
	return count
}
