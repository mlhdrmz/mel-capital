//go:build !windows

package main

// Windows dışı derleme yalnızca test içindir: Windows klasörleri MC_HOME altında taklit edilir,
// yönetici izni MC_IZIN=hayir ile "reddedildi" sayılır, mesaj kutularının cevabı MC_CEVAP'tan okunur.

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

func home() string {
	if h := os.Getenv("MC_HOME"); h != "" {
		return h
	}
	h, _ := os.UserHomeDir()
	return h
}

func programFilesDir() string   { return filepath.Join(home(), "ProgramFiles") }
func localAppDataDir() string   { return filepath.Join(home(), "AppData") }
func documentsDir() string      { return filepath.Join(home(), "Documents") }
func desktopDir() string        { return filepath.Join(home(), "Desktop") }
func userProgramsDir() string   { return filepath.Join(home(), "StartMenu") }
func commonProgramsDir() string { return filepath.Join(home(), "StartMenuAll") }

func uiLanguageTurkish() bool { return os.Getenv("MC_WINDOWS_DILI") != "en" }

func closeFlutterApp(time.Duration) bool { return false }
func killApp()                           {}
func killLegacyPort()                    {}
func closeLegacyWindows()                { fmt.Println("eski uygulama pencereleri kapatıldı") }

func makeShortcut(lnk, target string) {
	_ = os.MkdirAll(filepath.Dir(lnk), 0o755)
	_ = os.WriteFile(lnk, []byte(target), 0o644)
}

func regPath() string { return filepath.Join(home(), "registry", "MelCapital.json") }

func registerUninstall(strs map[string]string, dwords map[string]uint32) error {
	_ = os.MkdirAll(filepath.Dir(regPath()), 0o755)
	b, _ := json.Marshal(map[string]any{"str": strs, "dword": dwords})
	return os.WriteFile(regPath(), b, 0o644)
}
func unregisterUninstall() { _ = os.Remove(regPath()) }

func runElevated(op string) error {
	if os.Getenv("MC_IZIN") == "hayir" {
		return errors.New(T("Windows izni verilmedi.", "Windows permission was not given."))
	}
	self, _ := os.Executable()
	res := filepath.Join(os.TempDir(), "mc-sonuc-"+randHex(4))
	defer os.Remove(res)
	_ = exec.Command(self, "--yonetici", op, res, "--dil", lang).Run()
	b, _ := os.ReadFile(res)
	if strings.TrimSpace(string(b)) == "ok" {
		return nil
	}
	return errors.New(strings.TrimSpace(string(b)))
}

func openWizardWindow(url string) bool {
	fmt.Println("pencere:", url)
	_ = os.WriteFile(filepath.Join(os.TempDir(), "mc-kurulum-url"), []byte(url), 0o644)
	return os.Getenv("MC_TARAYICI_YOK") == ""
}

func closeWindowTitled(title string) { fmt.Println("pencere kapandı:", title) }

var launched sync.Once

func launchInstalledApp() {
	launched.Do(func() { fmt.Println("uygulama açıldı:", installedExe()) })
}

func startDetached(exe string, args ...string) error {
	if os.Getenv("MC_GECICI_YOK") != "" {
		return errors.New("test")
	}
	return exec.Command(exe, args...).Start()
}

func scheduleSelfDelete() {}

func recycle(dir string) error {
	dst := filepath.Join(home(), "CopKutusu", filepath.Base(dir))
	_ = os.MkdirAll(filepath.Dir(dst), 0o755)
	return os.Rename(dir, dst)
}

var answers []string

func nextAnswer() string {
	if answers == nil {
		answers = strings.Split(os.Getenv("MC_CEVAP"), ",")
	}
	if len(answers) == 0 {
		return ""
	}
	a := answers[0]
	answers = answers[1:]
	return a
}

func messageBox(text string, isErr bool) { fmt.Println("MESAJ:", strings.ReplaceAll(text, "\n", " ")) }
func askYesNo(text string, defNo bool) bool {
	a := nextAnswer()
	fmt.Println("SORU:", strings.ReplaceAll(text, "\n", " "), "→", a)
	return a == "evet"
}
