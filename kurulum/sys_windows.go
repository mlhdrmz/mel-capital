//go:build windows

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	shell32                      = syscall.NewLazyDLL("shell32.dll")
	ole32                        = syscall.NewLazyDLL("ole32.dll")
	user32                       = syscall.NewLazyDLL("user32.dll")
	kernel32                     = syscall.NewLazyDLL("kernel32.dll")
	procSHGetKnownFolderPath     = shell32.NewProc("SHGetKnownFolderPath")
	procShellExecuteExW          = shell32.NewProc("ShellExecuteExW")
	procCoTaskMemFree            = ole32.NewProc("CoTaskMemFree")
	procMessageBoxW              = user32.NewProc("MessageBoxW")
	procEnumWindows              = user32.NewProc("EnumWindows")
	procGetWindowTextW           = user32.NewProc("GetWindowTextW")
	procGetClassNameW            = user32.NewProc("GetClassNameW")
	procIsWindowVisible          = user32.NewProc("IsWindowVisible")
	procPostMessageW             = user32.NewProc("PostMessageW")
	procGetSystemMetrics         = user32.NewProc("GetSystemMetrics")
	procGetWindowThreadProcessId = user32.NewProc("GetWindowThreadProcessId")
	procWaitForSingleObject      = kernel32.NewProc("WaitForSingleObject")
	procCloseHandle              = kernel32.NewProc("CloseHandle")
	procOpenProcess              = kernel32.NewProc("OpenProcess")
	procQueryFullProcessImageW   = kernel32.NewProc("QueryFullProcessImageNameW")
	procGetUserDefaultUILanguage = kernel32.NewProc("GetUserDefaultUILanguage")
)

type guid struct {
	Data1        uint32
	Data2, Data3 uint16
	Data4        [8]byte
}

var (
	folderDocuments      = guid{0xFDD39AD0, 0x238F, 0x46AF, [8]byte{0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7}}
	folderDesktop        = guid{0xB4BFCC3A, 0xDB2C, 0x424C, [8]byte{0xB0, 0x29, 0x7F, 0xE9, 0x9A, 0x87, 0xC6, 0x41}}
	folderPrograms       = guid{0xA77F5D77, 0x2E2B, 0x44C3, [8]byte{0xA6, 0xA2, 0xAB, 0xA6, 0x01, 0x05, 0x4A, 0x51}}
	folderCommonPrograms = guid{0x0139D44E, 0x6AFE, 0x49F2, [8]byte{0x86, 0x90, 0x3D, 0xAF, 0xCA, 0xE6, 0xFF, 0xB8}}
	folderLocalApp       = guid{0xF1B32785, 0x6FBA, 0x4FCF, [8]byte{0x9D, 0x55, 0x7B, 0x8E, 0x7F, 0x15, 0x70, 0x91}}
	folderProgramFiles   = guid{0x905E63B6, 0xC1BF, 0x494E, [8]byte{0xB2, 0x9C, 0x65, 0xB7, 0x32, 0xD3, 0xD2, 0x1A}}
)

const createNoWindow = 0x08000000

func knownFolder(id *guid, fallback string) string {
	var p *uint16
	r, _, _ := procSHGetKnownFolderPath.Call(uintptr(unsafe.Pointer(id)), 0, 0, uintptr(unsafe.Pointer(&p)))
	if r != 0 || p == nil {
		return fallback
	}
	defer procCoTaskMemFree.Call(uintptr(unsafe.Pointer(p)))
	n := 0
	for ptr := unsafe.Pointer(p); *(*uint16)(ptr) != 0; n++ {
		ptr = unsafe.Pointer(uintptr(ptr) + 2)
	}
	return syscall.UTF16ToString(unsafe.Slice(p, n))
}

func programFilesDir() string {
	return knownFolder(&folderProgramFiles, os.Getenv("ProgramFiles"))
}
func localAppDataDir() string { return knownFolder(&folderLocalApp, os.Getenv("LOCALAPPDATA")) }
func documentsDir() string {
	return knownFolder(&folderDocuments, filepath.Join(os.Getenv("USERPROFILE"), "Documents"))
}
func desktopDir() string {
	return knownFolder(&folderDesktop, filepath.Join(os.Getenv("USERPROFILE"), "Desktop"))
}
func userProgramsDir() string   { return knownFolder(&folderPrograms, "") }
func commonProgramsDir() string { return knownFolder(&folderCommonPrograms, "") }

// Windows'un arayüz dili Türkçe mi?
func uiLanguageTurkish() bool {
	id, _, _ := procGetUserDefaultUILanguage.Call()
	return id&0x3FF == 0x1F // LANG_TURKISH
}

func hidden(cmd *exec.Cmd) *exec.Cmd {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
	return cmd
}

func powershell(script string, env ...string) error {
	cmd := hidden(exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script))
	cmd.Env = append(os.Environ(), env...)
	return cmd.Run()
}

// ---------------------------------------------------------------- uygulamayı kapatma

const flutterWindowClass = "FLUTTER_RUNNER_WIN32_WINDOW"

type appWindow struct {
	h   uintptr
	pid uint32
}

var (
	flutterMu    sync.Mutex
	flutterFound []appWindow
	flutterEnum  = syscall.NewCallback(func(h, _ uintptr) uintptr {
		var cls [128]uint16
		procGetClassNameW.Call(h, uintptr(unsafe.Pointer(&cls[0])), 128)
		if syscall.UTF16ToString(cls[:]) != flutterWindowClass {
			return 1
		}
		var pid uint32
		procGetWindowThreadProcessId.Call(h, uintptr(unsafe.Pointer(&pid)))
		flutterFound = append(flutterFound, appWindow{h, pid})
		return 1
	})
)

func processPath(pid uint32) string {
	h, _, _ := procOpenProcess.Call(0x1000, 0, uintptr(pid)) // PROCESS_QUERY_LIMITED_INFORMATION
	if h == 0 {
		return ""
	}
	defer procCloseHandle.Call(h)
	buf := make([]uint16, 1024)
	n := uint32(len(buf))
	if r, _, _ := procQueryFullProcessImageW.Call(h, 0, uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&n))); r == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}

// closeFlutterApp, açık Mel Capital pencerelerine kapan der (uygulama bekleyen kaydını bitirip
// kapanır) ve süreçlerin bitmesini en çok timeout kadar bekler. Pencere bulduysa true döner.
func closeFlutterApp(timeout time.Duration) bool {
	flutterMu.Lock()
	flutterFound = nil
	procEnumWindows.Call(flutterEnum, 0)
	wins := append([]appWindow(nil), flutterFound...)
	flutterMu.Unlock()
	dir := strings.ToLower(installDir()) + `\`
	var pids []uint32
	for _, w := range wins {
		p := strings.ToLower(processPath(w.pid))
		base := filepath.Base(p)
		if !strings.HasPrefix(p, dir) && base != "mel capital.exe" && base != "melcapital.exe" {
			continue
		}
		procPostMessageW.Call(w.h, 0x0010, 0, 0) // WM_CLOSE
		pids = append(pids, w.pid)
	}
	deadline := time.Now().Add(timeout)
	for _, pid := range pids {
		h, _, _ := procOpenProcess.Call(0x00100000, 0, uintptr(pid)) // SYNCHRONIZE
		if h == 0 {
			continue
		}
		ms := time.Until(deadline).Milliseconds()
		if ms < 0 {
			ms = 0
		}
		procWaitForSingleObject.Call(h, uintptr(ms))
		procCloseHandle.Call(h)
	}
	return len(pids) > 0
}

// Hâlâ açık kalan Mel Capital süreçlerini sonlandırır.
func killApp() {
	for _, name := range []string{appExeName, builtExeName} {
		_ = hidden(exec.Command("taskkill.exe", "/F", "/IM", name)).Run()
	}
}

// Eski uygulamanın yerel sunucusunu tutan süreci kapatır (dosya adı farklı bir eski kopya olabilir).
func killLegacyPort() {
	_ = hidden(exec.Command("taskkill.exe", "/F", "/IM", appExeName)).Run()
	if waitPortFree(legacyPort, 1200*time.Millisecond) {
		return
	}
	_ = powershell(fmt.Sprintf(`Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort %d -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }`, legacyPort))
}

// Eski uygulamanın kendi tarayıcı profilindeki pencerelerini kapatır (kurulum penceresi ayrı profilde).
func closeLegacyWindows() {
	_ = powershell(`Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($env:MC_PROF) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`,
		"MC_PROF="+filepath.Join(stateDir(), "Pencere"))
	time.Sleep(600 * time.Millisecond)
}

// ---------------------------------------------------------------- kısayol ve Windows kaydı

func makeShortcut(lnk, target string) {
	if lnk == "" || filepath.Dir(lnk) == "." {
		return
	}
	_ = powershell(`$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:MC_LNK);$s.TargetPath=$env:MC_TARGET;$s.WorkingDirectory=$env:MC_WD;$s.IconLocation=$env:MC_TARGET+',0';$s.Description='Mel Capital';$s.Save()`,
		"MC_LNK="+lnk, "MC_TARGET="+target, "MC_WD="+filepath.Dir(target))
}

func registerUninstall(strs map[string]string, dwords map[string]uint32) error {
	keys := make([]string, 0, len(strs))
	for k := range strs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if out, err := hidden(exec.Command("reg.exe", "add", regKey, "/v", k, "/t", "REG_SZ", "/d", strs[k], "/f")).CombinedOutput(); err != nil {
			return fmt.Errorf(T("Windows kaydı yazılamadı (%s): %v %s", "Could not write to the Windows registry (%s): %v %s"), k, err, strings.TrimSpace(string(out)))
		}
	}
	for k, v := range dwords {
		_ = hidden(exec.Command("reg.exe", "add", regKey, "/v", k, "/t", "REG_DWORD", "/d", fmt.Sprint(v), "/f")).Run()
	}
	return nil
}

func unregisterUninstall() { _ = hidden(exec.Command("reg.exe", "delete", regKey, "/f")).Run() }

// ---------------------------------------------------------------- yönetici olarak çalıştırma

type shellExecuteInfo struct {
	cbSize         uint32
	fMask          uint32
	hwnd           uintptr
	lpVerb         *uint16
	lpFile         *uint16
	lpParameters   *uint16
	lpDirectory    *uint16
	nShow          int32
	hInstApp       uintptr
	lpIDList       uintptr
	lpClass        *uint16
	hkeyClass      uintptr
	dwHotKey       uint32
	hIconOrMonitor uintptr
	hProcess       uintptr
}

// Kendini "--yonetici <op>" ile yönetici olarak başlatır, bitmesini bekler, sonucu okur.
func runElevated(op string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	f, err := os.CreateTemp("", "melcapital-sonuc-*.txt")
	if err != nil {
		return err
	}
	res := f.Name()
	f.Close()
	defer os.Remove(res)

	verb, _ := syscall.UTF16PtrFromString("runas")
	file, _ := syscall.UTF16PtrFromString(self)
	params, _ := syscall.UTF16PtrFromString(fmt.Sprintf(`--yonetici %s "%s" --dil %s`, op, res, lang))
	dir, _ := syscall.UTF16PtrFromString(os.TempDir())
	info := shellExecuteInfo{fMask: 0x00000040 | 0x00000100, lpVerb: verb, lpFile: file, lpParameters: params, lpDirectory: dir, nShow: 0}
	if hs := windowsTitled(windowTitle()); len(hs) > 0 {
		info.hwnd = hs[0] // izin penceresi kurulum penceresinin önünde açılsın
	}
	info.cbSize = uint32(unsafe.Sizeof(info))
	r, _, e := procShellExecuteExW.Call(uintptr(unsafe.Pointer(&info)))
	if r == 0 {
		if errno, ok := e.(syscall.Errno); ok && errno == 1223 {
			return errors.New(T("Windows izni verilmedi. Program Files'a yazmak için izin penceresinde \"Evet\"e basman gerekiyor.",
				"Windows permission was not given. To write to Program Files, click \"Yes\" in the permission window."))
		}
		return fmt.Errorf(T("yönetici izni alınamadı: %v", "could not get administrator permission: %v"), e)
	}
	if info.hProcess != 0 {
		procWaitForSingleObject.Call(info.hProcess, 0xFFFFFFFF)
		procCloseHandle.Call(info.hProcess)
	}
	b, _ := os.ReadFile(res)
	msg := strings.TrimSpace(string(b))
	if msg == "ok" {
		return nil
	}
	if msg == "" {
		msg = T("yönetici adımı tamamlanamadı", "the administrator step did not finish")
	}
	return errors.New(msg)
}

// ---------------------------------------------------------------- pencereler

func browserPath() string {
	pf86, pf, local := os.Getenv("ProgramFiles(x86)"), os.Getenv("ProgramFiles"), os.Getenv("LOCALAPPDATA")
	for _, c := range []string{
		filepath.Join(pf86, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(pf, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(local, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(pf, `Google\Chrome\Application\chrome.exe`),
		filepath.Join(pf86, `Google\Chrome\Application\chrome.exe`),
		filepath.Join(local, `Google\Chrome\Application\chrome.exe`),
	} {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c
		}
	}
	return ""
}

func openWizardWindow(url string) bool {
	b := browserPath()
	if b == "" {
		return false
	}
	sw, _, _ := procGetSystemMetrics.Call(0)
	sh, _, _ := procGetSystemMetrics.Call(1)
	w, h := 880, 600
	x, y := (int(sw)-w)/2, (int(sh)-h)/2
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	prof := filepath.Join(stateDir(), "Kurulum")
	_ = os.MkdirAll(prof, 0o755)
	args := []string{"--app=" + url, "--user-data-dir=" + prof, "--no-first-run", "--no-default-browser-check",
		"--disable-features=Translate", "--lang=" + lang, fmt.Sprintf("--window-size=%d,%d", w, h), fmt.Sprintf("--window-position=%d,%d", x, y),
		"--hide-crash-restore-bubble", "--disable-session-crashed-bubble"}
	return exec.Command(b, args...).Start() == nil
}

var (
	winMu    sync.Mutex
	winFound []uintptr
	winTitle string
	winEnum  = syscall.NewCallback(func(h, _ uintptr) uintptr {
		if v, _, _ := procIsWindowVisible.Call(h); v == 0 {
			return 1
		}
		var cls [128]uint16
		procGetClassNameW.Call(h, uintptr(unsafe.Pointer(&cls[0])), 128)
		if syscall.UTF16ToString(cls[:]) != "Chrome_WidgetWin_1" {
			return 1
		}
		var t [256]uint16
		procGetWindowTextW.Call(h, uintptr(unsafe.Pointer(&t[0])), 256)
		if syscall.UTF16ToString(t[:]) == winTitle {
			winFound = append(winFound, h)
		}
		return 1
	})
)

func windowsTitled(title string) []uintptr {
	winMu.Lock()
	defer winMu.Unlock()
	winFound, winTitle = nil, title
	procEnumWindows.Call(winEnum, 0)
	return append([]uintptr(nil), winFound...)
}

func closeWindowTitled(title string) {
	for _, h := range windowsTitled(title) {
		procPostMessageW.Call(h, 0x0010, 0, 0) // WM_CLOSE
	}
}

// Kurulu uygulamayı normal kullanıcı olarak açar (bu program zaten yönetici değil).
func launchInstalledApp() {
	cmd := exec.Command(installedExe())
	cmd.Dir = installDir()
	_ = cmd.Start()
}

func startDetached(exe string, args ...string) error {
	cmd := exec.Command(exe, args...)
	cmd.Dir = os.TempDir()
	return cmd.Start()
}

// Geçici kopyayı kapandıktan birkaç saniye sonra sildirir.
func scheduleSelfDelete() {
	self, err := os.Executable()
	if err != nil || !strings.HasPrefix(strings.ToLower(self), strings.ToLower(os.TempDir())) {
		return
	}
	cmd := hidden(exec.Command("cmd.exe", "/c", "ping -n 4 127.0.0.1 >nul & del /f /q \""+self+"\""))
	cmd.Dir = os.TempDir()
	_ = cmd.Start()
}

func recycle(dir string) error {
	if _, err := os.Stat(dir); err != nil {
		return nil
	}
	return powershell(`Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($env:MC_DIR,'OnlyErrorDialogs','SendToRecycleBin')`, "MC_DIR="+dir)
}

// ---------------------------------------------------------------- mesaj kutuları

func msgBox(text string, flags uintptr) int {
	t, _ := syscall.UTF16PtrFromString(text)
	c, _ := syscall.UTF16PtrFromString(appName)
	r, _, _ := procMessageBoxW.Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(c)), flags|0x00010000) // MB_SETFOREGROUND
	return int(r)
}

func messageBox(text string, isErr bool) {
	if isErr {
		msgBox(text, 0x10)
		return
	}
	msgBox(text, 0x40)
}

// Evet → true. defNo: varsayılan düğme "Hayır" olsun.
func askYesNo(text string, defNo bool) bool {
	flags := uintptr(0x04 | 0x20) // MB_YESNO | MB_ICONQUESTION
	if defNo {
		flags = 0x04 | 0x30 | 0x100 // uyarı simgesi, varsayılan Hayır
	}
	return msgBox(text, flags) == 6 // IDYES
}
