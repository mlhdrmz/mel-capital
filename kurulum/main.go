package main

// Mel Capital kurulum, güncelleme ve kaldırma programı.
//
// Aynı kaynak üç ayrı dosyaya derlenir (-X main.mode=...):
//   kurulum    → "MelCapital-Kurulum.exe": uygulamayı C:\Program Files\Mel Capital içine kurar
//   guncelleme → "MelCapital-Guncelleme-<sürüm>.exe": kurulu uygulamayı yeni sürümle değiştirir;
//                açılır açılmaz "Güncelleniyor" ekranıyla başlar
//   kaldir     → "Kaldır.exe": Program Files'a kopyalanır; Windows "Uygulamalar" listesindeki Kaldır bunu çalıştırır
//
// Arayüz normal kullanıcı yetkisiyle çalışır. Yalnızca Program Files'a yazma, Windows kaydı ve
// herkes için Başlat menüsü kısayolu için program kendini bir kez yönetici olarak başlatır
// (Windows "Evet" diye sorar). Uygulama hiçbir zaman yönetici olarak açılmaz.
//
// Eski Mel Capital (tek dosyalık program) kuruluysa yeni sürüm onun yerine geçer. Veriler
// (Belgeler\Mel Capital) hiçbir zaman değiştirilmez; kurmadan önce yedeklenir.
//
// Komut satırı:
//   --sessiz          pencere ve soru olmadan çalışır (derleme hattındaki deneme kurulumu için)
//   --sonuc <dosya>   sessiz çalışmanın sonucunu ("ok" ya da hata metni) dosyaya yazar
//   --ac              sessiz güncellemeden sonra uygulamayı açar
//   --veriyi-sil      sessiz kaldırmada verileri de siler
//   --dil tr|en       arayüz dili
//   --uygulamadan     uygulamanın "Güncellemeyi kur" düğmesiyle başlatıldı

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var (
	mode    = "kurulum" // kurulum | guncelleme | kaldir
	version = "dev"     // tarih-saat etiketi: 03.11.2026-22.39
	build   = "0"       // derleme numarası
)

const (
	appName        = "Mel Capital"
	legacyPort     = 47860 // eski uygulamanın yerel sunucusu
	uiPort         = 47862
	regKey         = `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MelCapital`
	publisher      = "Melih Durmaz"
	legacyDataFile = "mel-capital-veri.json"
)

//go:embed ui.html assets
var uiFS embed.FS

// ---------------------------------------------------------------- yollar

func installDir() string     { return filepath.Join(programFilesDir(), appName) }
func installedExe() string   { return filepath.Join(installDir(), appExeName) }
func uninstallerExe() string { return filepath.Join(installDir(), "Kaldır.exe") }
func stateDir() string       { return filepath.Join(localAppDataDir(), appName) }
func legacyDir() string      { return filepath.Join(localAppDataDir(), "Programs", appName) }
func dataDir() string        { return filepath.Join(documentsDir(), appName) }

func installedVersion() string {
	b, err := os.ReadFile(filepath.Join(installDir(), "surum.txt"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func isInstalled() bool {
	_, err := os.Stat(installedExe())
	return err == nil
}

// Eski (tek dosyalık) Mel Capital Program Files'ta kurulu mu?
func oldAppInstalled() bool { return isInstalled() && !isFlutterApp(installDir()) }

func legacyInstalled() bool {
	_, err := os.Stat(filepath.Join(legacyDir(), appExeName))
	return err == nil
}

// ---------------------------------------------------------------- giriş

type options struct {
	silent, open, wipe, temp, fromApp bool
	result, lang                      string
}

func parseArgs(args []string) options {
	var o options
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--sessiz":
			o.silent = true
		case "--ac":
			o.open = true
		case "--veriyi-sil":
			o.wipe = true
		case "--gecici":
			o.temp = true
		case "--uygulamadan":
			o.fromApp = true
		case "--sonuc":
			if i+1 < len(args) {
				o.result = args[i+1]
				i++
			}
		case "--dil":
			if i+1 < len(args) {
				o.lang = args[i+1]
				i++
			}
		}
	}
	return o
}

// passArgs, geçici kopyaya aynı seçenekleri aktarır.
func (o options) passArgs() []string {
	var a []string
	if o.silent {
		a = append(a, "--sessiz")
	}
	if o.wipe {
		a = append(a, "--veriyi-sil")
	}
	if o.result != "" {
		a = append(a, "--sonuc", o.result)
	}
	a = append(a, "--dil", lang)
	return a
}

func writeResult(path string, err error) {
	if path == "" {
		return
	}
	msg := "ok"
	if err != nil {
		msg = err.Error()
	}
	_ = os.WriteFile(path, []byte(msg), 0o644)
}

func main() {
	args := os.Args[1:]
	if len(args) >= 3 && args[0] == "--yonetici" {
		// Yönetici olarak başlatılan yardımcı: arayüz yok, işi yapar, sonucu dosyaya yazar.
		setLanguage(parseArgs(args[3:]).lang)
		err := adminTask(args[1])
		writeResult(args[2], err)
		if err != nil {
			os.Exit(1)
		}
		return
	}
	opts := parseArgs(args)
	setLanguage(opts.lang)
	switch {
	case mode == "kaldir":
		runUninstall(opts)
	case opts.silent:
		os.Exit(runSilent(opts))
	default:
		runWizard()
	}
}

// ---------------------------------------------------------------- yönetici adımları

func adminTask(op string) error {
	switch op {
	case "kur":
		return adminInstall()
	case "kaldir":
		return adminUninstall()
	}
	return fmt.Errorf("bilinmeyen işlem: %s", op)
}

func adminInstall() error {
	if len(appZip) == 0 {
		return errors.New(T("Bu dosyada Mel Capital yok (eksik derlenmiş).", "This file does not contain Mel Capital (incomplete build)."))
	}
	size, err := installTree(appZip, kaldirExe, installDir(), version, build)
	if err != nil {
		return err
	}
	makeShortcut(filepath.Join(commonProgramsDir(), appName+".lnk"), installedExe())
	return registerUninstall(map[string]string{
		"DisplayName":     appName,
		"DisplayVersion":  version,
		"Publisher":       publisher,
		"DisplayIcon":     installedExe() + ",0",
		"InstallLocation": installDir(),
		"UninstallString": `"` + uninstallerExe() + `"`,
		"InstallDate":     time.Now().Format("20060102"),
		"URLInfoAbout":    "https://github.com/mlhdrmz/mel-capital",
	}, map[string]uint32{"NoModify": 1, "NoRepair": 1, "EstimatedSize": uint32(size / 1024)})
}

func adminUninstall() error {
	_ = os.Remove(filepath.Join(commonProgramsDir(), appName+".lnk"))
	unregisterUninstall()
	for _, d := range []string{installDir() + ".yeni", installDir() + ".eski"} {
		_ = os.RemoveAll(d)
	}
	err := retry(20, 500*time.Millisecond, func() error { return os.RemoveAll(installDir()) })
	if err != nil {
		return fmt.Errorf(T("program klasörü silinemedi: %v", "the program folder could not be deleted: %v"), err)
	}
	return nil
}

// ---------------------------------------------------------------- açık uygulamayı kapatma

// closeRunningApp: yeni uygulamanın penceresine "kapan" denir (bekleyen kaydını bitirip kapanır);
// eski uygulama yerel sunucusundan kapatılır; hâlâ açık kalan varsa sonlandırılır.
func closeRunningApp() {
	closeFlutterApp(10 * time.Second)
	closeLegacyApp()
	killApp()
}

func closeLegacyApp() {
	tokPath := filepath.Join(stateDir(), "calisiyor.txt")
	tok, err := os.ReadFile(tokPath)
	if err != nil && portFree(legacyPort) {
		return
	}
	c := http.Client{Timeout: 2 * time.Second}
	if req, err := http.NewRequest("POST", fmt.Sprintf("http://127.0.0.1:%d/api/quit", legacyPort), nil); err == nil {
		req.Header.Set("X-MC-Token", strings.TrimSpace(string(tok)))
		if resp, err := c.Do(req); err == nil {
			resp.Body.Close()
		}
	}
	if !waitPortFree(legacyPort, 4*time.Second) {
		killLegacyPort()
		waitPortFree(legacyPort, 6*time.Second)
	}
	closeLegacyWindows()
	_ = os.Remove(tokPath)
}

func portFree(port int) bool {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return false
	}
	ln.Close()
	return true
}

func waitPortFree(port int, d time.Duration) bool {
	end := time.Now().Add(d)
	for {
		if portFree(port) {
			return true
		}
		if time.Now().After(end) {
			return false
		}
		time.Sleep(150 * time.Millisecond)
	}
}

// Eski düzenden kalanlar: AppData'daki kopya, kullanıcı Başlat menüsü kısayolu, işaret dosyası.
func cleanupLegacy() {
	_ = os.Remove(filepath.Join(userProgramsDir(), appName+".lnk"))
	_ = os.RemoveAll(legacyDir())
	_ = os.Remove(filepath.Join(stateDir(), "kisayollar.txt"))
}

// Eski uygulamanın önbellekleri (tarayıcı penceresi profili, fotoğraflar). Eşitleme bilgisi kalır.
func cleanupOldAppCaches() {
	for _, n := range []string{"Pencere", "Fotograflar", "foto-istek.json", "calisiyor.txt", "baslangic-yuklendi.txt"} {
		_ = os.RemoveAll(filepath.Join(stateDir(), n))
	}
}

// ---------------------------------------------------------------- kurulum / güncelleme

type wizard struct {
	mu       sync.Mutex
	State    string   `json:"state"` // hazir | calisiyor | bitti | hata
	Step     int      `json:"step"`
	Steps    []string `json:"steps"`
	Error    string   `json:"error"`
	fast     bool     // sessiz kip: adımlar arasında bekleme yok
	oldApp   bool     // başlarken eski uygulama kuruluydu
	lastPoll time.Time
	seen     chan struct{}
	seenOnce sync.Once
	token    string
}

func (w *wizard) set(f func()) {
	w.mu.Lock()
	f()
	w.mu.Unlock()
}

func stepsFor() []string {
	if mode == "guncelleme" {
		return []string{
			T("Mel Capital kapatılıyor", "Closing Mel Capital"),
			T("Verilerin yedekleniyor", "Backing up your data"),
			T("Yeni sürüm kuruluyor", "Installing the new version"),
			T("Son hazırlıklar yapılıyor", "Finishing up"),
		}
	}
	return []string{
		T("Açık olan Mel Capital kapatılıyor", "Closing Mel Capital if it is open"),
		T("Verilerin yedekleniyor", "Backing up your data"),
		T("Program Files'a kuruluyor", "Installing to Program Files"),
		T("Kısayollar hazırlanıyor", "Creating shortcuts"),
	}
}

func windowTitle() string {
	if mode == "guncelleme" {
		return appName + T(" Güncelleme", " Update")
	}
	return appName + T(" Kurulum", " Setup")
}

func (w *wizard) pause(t time.Time, d time.Duration) {
	if w.fast {
		return
	}
	if el := time.Since(t); el < d {
		time.Sleep(d - el)
	}
}

func (w *wizard) run() {
	w.set(func() { w.State, w.Step, w.Error = "calisiyor", 0, "" })
	err := w.work()
	w.set(func() {
		if err != nil {
			w.State, w.Error = "hata", err.Error()
		} else {
			w.State, w.Step = "bitti", len(w.Steps)
		}
	})
	if err == nil && mode == "guncelleme" {
		time.Sleep(1500 * time.Millisecond)
		launchInstalledApp()
		time.Sleep(2500 * time.Millisecond)
		closeWindowTitled(windowTitle())
		os.Exit(0)
	}
}

func (w *wizard) work() error {
	if mode == "guncelleme" && !isInstalled() && !legacyInstalled() {
		return errors.New(T(`Mel Capital bu bilgisayarda kurulu değil. Önce "Mel Capital Kurulum" dosyasını çalıştır.`,
			`Mel Capital is not installed on this computer. Run the "Mel Capital Setup" file first.`))
	}
	t := time.Now()
	w.set(func() { w.Step = 0 })
	closeRunningApp()
	w.pause(t, 1000*time.Millisecond)

	t = time.Now()
	w.set(func() { w.Step = 1 })
	if mode == "guncelleme" {
		backupAll(dataDir(), "guncelleme-oncesi")
	} else {
		backupAll(dataDir(), "kurulum-oncesi")
	}
	w.pause(t, 800*time.Millisecond)

	t = time.Now()
	w.set(func() { w.Step = 2 })
	if err := runElevated("kur"); err != nil {
		return err
	}
	w.pause(t, 1000*time.Millisecond)

	t = time.Now()
	w.set(func() { w.Step = 3 })
	desk := filepath.Join(desktopDir(), appName+".lnk")
	if _, err := os.Stat(desk); mode != "guncelleme" || err == nil || legacyInstalled() {
		makeShortcut(desk, installedExe())
	}
	cleanupLegacy()
	if w.oldApp {
		cleanupOldAppCaches()
	}
	w.pause(t, 800*time.Millisecond)
	return nil
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func runSilent(o options) int {
	w := &wizard{Steps: stepsFor(), fast: true, oldApp: oldAppInstalled()}
	if len(appZip) == 0 {
		writeResult(o.result, errors.New("payload yok"))
		return 1
	}
	err := w.work()
	if err == nil && mode == "guncelleme" && o.open {
		launchInstalledApp()
	}
	writeResult(o.result, err)
	if err != nil {
		return 1
	}
	return 0
}

func runWizard() {
	if len(appZip) == 0 {
		messageBox(T("Bu dosya eksik derlenmiş: içinde Mel Capital yok.", "This file is incomplete: it does not contain Mel Capital."), true)
		return
	}
	w := &wizard{State: "hazir", Steps: stepsFor(), oldApp: oldAppInstalled(), seen: make(chan struct{}), token: randHex(16), lastPoll: time.Now()}
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", uiPort))
	if err != nil { // başka bir kurulum penceresi açık
		messageBox(T("Mel Capital kurulum ya da güncelleme penceresi zaten açık.", "A Mel Capital setup or update window is already open."), false)
		return
	}
	srv := &http.Server{Handler: w.handler(), ReadHeaderTimeout: 10 * time.Second}
	go func() { _ = srv.Serve(ln) }()
	url := fmt.Sprintf("http://127.0.0.1:%d/k/%s/", uiPort, w.token)
	if !openWizardWindow(url) {
		w.headless()
		return
	}
	select {
	case <-w.seen:
	case <-time.After(25 * time.Second):
		w.headless() // pencere açılamadı: arayüzsüz devam et
		return
	}
	if mode == "guncelleme" {
		go w.run() // güncelleme beklemeden başlar
	}
	// Pencere kapatılırsa (iş sürmüyorsa) programdan çık
	for {
		time.Sleep(time.Second)
		w.mu.Lock()
		idle := w.State != "calisiyor" && time.Since(w.lastPoll) > 8*time.Second
		w.mu.Unlock()
		if idle {
			os.Exit(0)
		}
	}
}

// Tarayıcı bulunamazsa: soru sor, kur, sonucu mesajla bildir.
func (w *wizard) headless() {
	if mode != "guncelleme" && !askYesNo(fmt.Sprintf(T("Mel Capital (%s), %s klasörüne kurulsun mu?", "Install Mel Capital (%s) to %s?"), version, installDir()), false) {
		return
	}
	if err := w.work(); err != nil {
		messageBox(err.Error(), true)
		return
	}
	if mode == "guncelleme" {
		launchInstalledApp()
		return
	}
	if askYesNo(T("Kurulum tamamlandı. Mel Capital şimdi açılsın mı?", "Setup is complete. Open Mel Capital now?"), false) {
		launchInstalledApp()
	}
}

func (w *wizard) handler() http.Handler {
	prefix := "/k/" + w.token + "/"
	return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		if r.Host != fmt.Sprintf("127.0.0.1:%d", uiPort) || !strings.HasPrefix(r.URL.Path, prefix) {
			http.Error(rw, "yasak", http.StatusForbidden)
			return
		}
		rw.Header().Set("Cache-Control", "no-store")
		rw.Header().Set("X-Content-Type-Options", "nosniff")
		p := strings.TrimPrefix(r.URL.Path, prefix)
		switch {
		case p == "":
			b, _ := uiFS.ReadFile("ui.html")
			page := strings.NewReplacer("{{TITLE}}", windowTitle(), "{{LANG}}", lang).Replace(string(b))
			rw.Header().Set("Content-Type", "text/html; charset=utf-8")
			io.WriteString(rw, page)
		case p == "durum":
			w.seenOnce.Do(func() { close(w.seen) })
			w.mu.Lock()
			w.lastPoll = time.Now()
			out := map[string]any{"mode": mode, "lang": lang, "version": version, "state": w.State, "step": w.Step, "steps": w.Steps, "error": w.Error,
				"installDir": installDir(), "installed": isInstalled(), "installedVersion": installedVersion(), "oldApp": w.oldApp, "legacy": legacyInstalled()}
			w.mu.Unlock()
			rw.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(rw).Encode(out)
		case p == "basla" && r.Method == http.MethodPost:
			w.mu.Lock()
			busy := w.State == "calisiyor"
			w.mu.Unlock()
			if !busy {
				go w.run()
			}
			rw.WriteHeader(http.StatusNoContent)
		case p == "ac" && r.Method == http.MethodPost:
			rw.WriteHeader(http.StatusNoContent)
			go func() {
				launchInstalledApp()
				time.Sleep(2500 * time.Millisecond)
				closeWindowTitled(windowTitle())
				os.Exit(0)
			}()
		case p == "kapat" && r.Method == http.MethodPost:
			rw.WriteHeader(http.StatusNoContent)
			go func() {
				time.Sleep(200 * time.Millisecond)
				closeWindowTitled(windowTitle())
				os.Exit(0)
			}()
		case strings.HasPrefix(p, "assets/") && !strings.Contains(p, ".."):
			b, err := uiFS.ReadFile(p)
			if err != nil {
				http.NotFound(rw, r)
				return
			}
			switch filepath.Ext(p) {
			case ".ttf":
				rw.Header().Set("Content-Type", "font/ttf")
			case ".png":
				rw.Header().Set("Content-Type", "image/png")
			case ".webp":
				rw.Header().Set("Content-Type", "image/webp")
			}
			_, _ = rw.Write(b)
		default:
			http.NotFound(rw, r)
		}
	})
}

// ---------------------------------------------------------------- kaldırma

func runUninstall(o options) {
	// Program Files'taki kopyadan çalışıyorsa önce geçici klasöre kopyalanıp oradan devam eder;
	// böylece program klasörü tamamen silinebilir.
	if !o.temp {
		self, err := os.Executable()
		if err == nil {
			if b, err := os.ReadFile(self); err == nil {
				tmp := filepath.Join(os.TempDir(), "MelCapitalKaldir-"+randHex(4)+".exe")
				if os.WriteFile(tmp, b, 0o755) == nil && startDetached(tmp, append([]string{"--gecici"}, o.passArgs()...)...) == nil {
					return
				}
			}
		}
	}
	if !o.silent && !askYesNo(T("Mel Capital bu bilgisayardan kaldırılsın mı?", "Remove Mel Capital from this computer?"), false) {
		scheduleSelfDelete()
		return
	}
	wipe := o.wipe
	if !o.silent {
		wipe = askYesNo(T("Verilerin de silinsin mi?\n\n\"Belgeler\\Mel Capital\" klasöründeki profillerin, veri dosyaların ve bütün yedeklerin Geri Dönüşüm Kutusu'na taşınır.\n\n\"Hayır\" dersen verilerin olduğu yerde kalır; Mel Capital'i yeniden kurarsan kaldığın yerden devam edersin.",
			"Delete your data too?\n\nYour profiles, data files and all backups in \"Documents\\Mel Capital\" are moved to the Recycle Bin.\n\nIf you choose \"No\", your data stays where it is; if you reinstall Mel Capital you continue where you left off."), true)
	}
	closeRunningApp()
	if err := runElevated("kaldir"); err != nil {
		writeResult(o.result, err)
		if !o.silent {
			messageBox(T("Mel Capital kaldırılamadı.\n\n", "Mel Capital could not be removed.\n\n")+err.Error(), true)
		}
		scheduleSelfDelete()
		return
	}
	_ = os.Remove(filepath.Join(desktopDir(), appName+".lnk"))
	cleanupLegacy()
	time.Sleep(500 * time.Millisecond)
	_ = os.RemoveAll(stateDir()) // eski uygulamanın pencere profili, fotoğraf önbelleği, kurulum penceresi
	msg := T("Mel Capital kaldırıldı.\n\nVerilerin \"Belgeler\\Mel Capital\" klasöründe duruyor.",
		"Mel Capital has been removed.\n\nYour data is still in the \"Documents\\Mel Capital\" folder.")
	var wipeErr error
	if wipe {
		if o.silent {
			wipeErr = os.RemoveAll(dataDir())
		} else {
			wipeErr = recycle(dataDir())
		}
		if wipeErr != nil {
			msg = T("Mel Capital kaldırıldı, ama veriler Geri Dönüşüm Kutusu'na taşınamadı:\n", "Mel Capital has been removed, but your data could not be moved to the Recycle Bin:\n") +
				wipeErr.Error() + T("\n\nVerilerin \"Belgeler\\Mel Capital\" klasöründe duruyor.", "\n\nYour data is still in the \"Documents\\Mel Capital\" folder.")
		} else {
			msg = T("Mel Capital kaldırıldı.\n\nVerilerin Geri Dönüşüm Kutusu'na taşındı; gerekirse oradan geri alabilirsin.",
				"Mel Capital has been removed.\n\nYour data was moved to the Recycle Bin; you can restore it from there if needed.")
		}
	}
	writeResult(o.result, wipeErr)
	if !o.silent {
		messageBox(msg, false)
	}
	scheduleSelfDelete()
}
