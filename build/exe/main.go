// TailCraft single-file launcher stub: extracts embedded scripts next to the EXE and runs the WPF GUI hidden-console.
package main

import (
	"embed"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"unsafe"
)

//go:embed payload
var payload embed.FS

func msgbox(title, text string) {
	u32 := syscall.NewLazyDLL("user32.dll")
	t, _ := syscall.UTF16PtrFromString(text)
	c, _ := syscall.UTF16PtrFromString(title)
	u32.NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(t)), uintptr(unsafe.Pointer(c)), 0x10)
}

func main() {
	exe, err := os.Executable()
	if err != nil {
		msgbox("TailCraft", err.Error())
		return
	}
	root := filepath.Dir(exe)
	app := filepath.Join(root, "app")

	// 항상 최신 스크립트로 덮어씀 (server/, runtime/, config.json 은 root 에 있어 영향 없음)
	err = fs.WalkDir(payload, "payload", func(p string, d fs.DirEntry, e error) error {
		if e != nil {
			return e
		}
		rel, _ := filepath.Rel("payload", p)
		dst := filepath.Join(app, rel)
		if d.IsDir() {
			return os.MkdirAll(dst, 0o755)
		}
		b, e := payload.ReadFile(p)
		if e != nil {
			return e
		}
		return os.WriteFile(dst, b, 0o644)
	})
	if err != nil {
		msgbox("TailCraft", "파일을 풀 수 없습니다 / Cannot extract files:\n"+err.Error()+"\n\n"+app)
		return
	}

	// 라이선스 파일은 EXE 옆에 항상 존재하도록 복사
	if lic, e := payload.ReadFile("payload/LICENSE.txt"); e == nil {
		_ = os.WriteFile(filepath.Join(root, "LICENSE.txt"), lic, 0o644)
	}

	ps := filepath.Join(os.Getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
	if _, e := os.Stat(ps); e != nil {
		ps = "powershell.exe"
	}
	cmd := exec.Command(ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", filepath.Join(app, "launcher.ps1"), "-Root", root)
	cmd.Dir = root
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000} // CREATE_NO_WINDOW
	if err := cmd.Start(); err != nil {
		msgbox("TailCraft", "PowerShell 을 실행할 수 없습니다 / Cannot start PowerShell:\n"+err.Error())
		return
	}
	_ = cmd.Wait()
}
