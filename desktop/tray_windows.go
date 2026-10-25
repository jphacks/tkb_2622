package main

import (
	"context"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"

	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

// Windowsのタスクトレイ（通知領域）にアイコンを置き，ウィンドウの表示・画面の切り替え・終了を行う．
// Wails v2にはトレイの機能がないため，専用のスレッドでShell_NotifyIconとメッセージループを動かす．

const (
	trayCallbackMessage = 0x8000 + 1 // WM_APP + 1
	trayIconID          = 1
	// Wailsがbuild/windows/icon.icoを埋め込むリソースID（winc.AppIconID）
	appIconResourceID = 3

	wmNull      = 0x0000
	wmDestroy   = 0x0002
	wmClose     = 0x0010
	wmLButtonUp = 0x0202
	wmRButtonUp = 0x0205

	nimAdd      = 0x0
	nimDelete   = 0x2
	nifMessage  = 0x1
	nifIcon     = 0x2
	nifTip      = 0x4
	mfString    = 0x0
	mfSeparator = 0x800

	tpmRightButton = 0x0002
	tpmBottomAlign = 0x0020
	tpmNoNotify    = 0x0080
	tpmReturnCmd   = 0x0100

	imageIcon      = 1
	smCxSmIcon     = 49
	smCySmIcon     = 50
	idiApplication = 32512
)

const (
	menuOpenSession = iota + 1
	menuOpenHistory
	menuOpenSettings
	menuQuit
)

var (
	user32                     = syscall.NewLazyDLL("user32.dll")
	shell32                    = syscall.NewLazyDLL("shell32.dll")
	kernel32                   = syscall.NewLazyDLL("kernel32.dll")
	procAppendMenuW            = user32.NewProc("AppendMenuW")
	procCreatePopupMenu        = user32.NewProc("CreatePopupMenu")
	procCreateWindowExW        = user32.NewProc("CreateWindowExW")
	procDefWindowProcW         = user32.NewProc("DefWindowProcW")
	procDestroyMenu            = user32.NewProc("DestroyMenu")
	procDestroyWindow          = user32.NewProc("DestroyWindow")
	procDispatchMessageW       = user32.NewProc("DispatchMessageW")
	procGetCursorPos           = user32.NewProc("GetCursorPos")
	procGetMessageW            = user32.NewProc("GetMessageW")
	procGetSystemMetrics       = user32.NewProc("GetSystemMetrics")
	procLoadIconW              = user32.NewProc("LoadIconW")
	procLoadImageW             = user32.NewProc("LoadImageW")
	procPostMessageW           = user32.NewProc("PostMessageW")
	procPostQuitMessage        = user32.NewProc("PostQuitMessage")
	procRegisterClassExW       = user32.NewProc("RegisterClassExW")
	procRegisterWindowMessageW = user32.NewProc("RegisterWindowMessageW")
	procSetForegroundWindow    = user32.NewProc("SetForegroundWindow")
	procTrackPopupMenu         = user32.NewProc("TrackPopupMenu")
	procTranslateMessage       = user32.NewProc("TranslateMessage")
	procShellNotifyIconW       = shell32.NewProc("Shell_NotifyIconW")
	procGetModuleHandleW       = kernel32.NewProc("GetModuleHandleW")
)

type notifyIconData struct {
	CbSize           uint32
	HWnd             uintptr
	UID              uint32
	UFlags           uint32
	UCallbackMessage uint32
	HIcon            uintptr
	SzTip            [128]uint16
	DwState          uint32
	DwStateMask      uint32
	SzInfo           [256]uint16
	UVersion         uint32
	SzInfoTitle      [64]uint16
	DwInfoFlags      uint32
	GuidItem         [16]byte
	HBalloonIcon     uintptr
}

type wndClassEx struct {
	CbSize        uint32
	Style         uint32
	LpfnWndProc   uintptr
	CbClsExtra    int32
	CbWndExtra    int32
	HInstance     uintptr
	HIcon         uintptr
	HCursor       uintptr
	HbrBackground uintptr
	LpszMenuName  *uint16
	LpszClassName *uint16
	HIconSm       uintptr
}

type point struct{ X, Y int32 }

type msg struct {
	HWnd     uintptr
	Message  uint32
	WParam   uintptr
	LParam   uintptr
	Time     uint32
	Pt       point
	LPrivate uint32
}

var (
	trayMu                sync.Mutex
	trayContext           context.Context
	trayWindow            uintptr
	trayIcon              uintptr
	trayStopped           chan struct{}
	taskbarCreatedMessage uintptr
	trayWindowProcPointer = syscall.NewCallback(trayWindowProc)
)

func startTray(ctx context.Context) {
	trayMu.Lock()
	defer trayMu.Unlock()
	if trayWindow != 0 {
		return
	}
	trayContext = ctx
	ready := make(chan uintptr)
	stopped := make(chan struct{})
	trayStopped = stopped
	go func() {
		// ウィンドウとメッセージループは作成したスレッドから動かせないため固定する．
		runtime.LockOSThread()
		defer close(stopped)
		hwnd := createTrayWindow()
		ready <- hwnd
		if hwnd == 0 {
			return
		}
		var message msg
		for {
			result, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
			if int32(result) <= 0 {
				return
			}
			procTranslateMessage.Call(uintptr(unsafe.Pointer(&message)))
			procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
		}
	}()
	trayWindow = <-ready
}

func stopTray() {
	trayMu.Lock()
	hwnd, stopped := trayWindow, trayStopped
	trayWindow = 0
	trayMu.Unlock()
	if hwnd == 0 {
		return
	}
	procPostMessageW.Call(hwnd, wmClose, 0, 0)
	// 終了後にアイコンが通知領域へ残らないよう，削除を少しだけ待つ．
	select {
	case <-stopped:
	case <-time.After(time.Second):
	}
}

func createTrayWindow() uintptr {
	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("FocusLinkTrayWindow")
	windowClass := wndClassEx{LpfnWndProc: trayWindowProcPointer, HInstance: instance, LpszClassName: className}
	windowClass.CbSize = uint32(unsafe.Sizeof(windowClass))
	if atom, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&windowClass))); atom == 0 {
		return 0
	}
	taskbarCreated, _ := syscall.UTF16PtrFromString("TaskbarCreated")
	taskbarCreatedMessage, _, _ = procRegisterWindowMessageW.Call(uintptr(unsafe.Pointer(taskbarCreated)))

	// 表示しない通常ウィンドウにする（メッセージ専用ウィンドウは前面化できず，メニューが閉じなくなる）．
	hwnd, _, _ := procCreateWindowExW.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(className)), 0, 0, 0, 0, 0, 0, 0, instance, 0)
	if hwnd == 0 {
		return 0
	}
	width, _, _ := procGetSystemMetrics.Call(smCxSmIcon)
	height, _, _ := procGetSystemMetrics.Call(smCySmIcon)
	trayIcon, _, _ = procLoadImageW.Call(instance, appIconResourceID, imageIcon, width, height, 0)
	if trayIcon == 0 {
		trayIcon, _, _ = procLoadIconW.Call(0, idiApplication)
	}
	addTrayIcon(hwnd)
	return hwnd
}

func trayIconData(hwnd uintptr) notifyIconData {
	data := notifyIconData{HWnd: hwnd, UID: trayIconID, UFlags: nifMessage | nifIcon | nifTip, UCallbackMessage: trayCallbackMessage, HIcon: trayIcon}
	data.CbSize = uint32(unsafe.Sizeof(data))
	tip, _ := syscall.UTF16FromString("Focus Link")
	copy(data.SzTip[:len(data.SzTip)-1], tip)
	return data
}

func addTrayIcon(hwnd uintptr) {
	data := trayIconData(hwnd)
	procShellNotifyIconW.Call(nimAdd, uintptr(unsafe.Pointer(&data)))
}

func deleteTrayIcon(hwnd uintptr) {
	data := trayIconData(hwnd)
	procShellNotifyIconW.Call(nimDelete, uintptr(unsafe.Pointer(&data)))
}

func trayWindowProc(hwnd, message, wParam, lParam uintptr) uintptr {
	switch {
	case message == trayCallbackMessage:
		switch lParam & 0xffff {
		case wmLButtonUp:
			// 閉じる前の画面（設定など）ではなく，作業を開始・操作できる作業画面から始める．
			showMainWindow("session")
		case wmRButtonUp:
			showTrayMenu(hwnd)
		}
		return 0
	case taskbarCreatedMessage != 0 && message == taskbarCreatedMessage:
		// エクスプローラーが再起動すると通知領域が作り直されるため，アイコンを登録し直す．
		addTrayIcon(hwnd)
		return 0
	case message == wmClose:
		procDestroyWindow.Call(hwnd)
		return 0
	case message == wmDestroy:
		deleteTrayIcon(hwnd)
		procPostQuitMessage.Call(0)
		return 0
	}
	result, _, _ := procDefWindowProcW.Call(hwnd, message, wParam, lParam)
	return result
}

func showTrayMenu(hwnd uintptr) {
	menu, _, _ := procCreatePopupMenu.Call()
	if menu == 0 {
		return
	}
	defer procDestroyMenu.Call(menu)
	appendTrayMenuItem(menu, menuOpenSession, "作業画面を開く")
	appendTrayMenuItem(menu, menuOpenHistory, "これまでの記録")
	appendTrayMenuItem(menu, menuOpenSettings, "設定")
	procAppendMenuW.Call(menu, mfSeparator, 0, 0)
	appendTrayMenuItem(menu, menuQuit, "終了")

	var cursor point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&cursor)))
	// 前面化しないと，メニューの外をクリックしてもメニューが閉じない．
	procSetForegroundWindow.Call(hwnd)
	command, _, _ := procTrackPopupMenu.Call(menu, tpmRightButton|tpmBottomAlign|tpmReturnCmd|tpmNoNotify, uintptr(cursor.X), uintptr(cursor.Y), 0, hwnd, 0)
	procPostMessageW.Call(hwnd, wmNull, 0, 0)

	switch command {
	case menuOpenSession:
		showMainWindow("session")
	case menuOpenHistory:
		showMainWindow("history")
	case menuOpenSettings:
		showMainWindow("settings")
	case menuQuit:
		quitFromTray()
	}
}

func appendTrayMenuItem(menu uintptr, id uintptr, label string) {
	text, _ := syscall.UTF16PtrFromString(label)
	procAppendMenuW.Call(menu, mfString, id, uintptr(unsafe.Pointer(text)))
}

// showMainWindow はウィンドウを表示し，pageの画面へ切り替える．
func showMainWindow(page string) {
	trayMu.Lock()
	ctx := trayContext
	trayMu.Unlock()
	if ctx == nil {
		return
	}
	// トレイのスレッドを止めないよう，Wailsのウィンドウ操作は別のgoroutineで行う．
	go func() {
		wailsruntime.WindowUnminimise(ctx)
		wailsruntime.WindowShow(ctx)
		wailsruntime.EventsEmit(ctx, "desktop:open-page", page)
	}()
}

func quitFromTray() {
	trayMu.Lock()
	ctx := trayContext
	trayMu.Unlock()
	if ctx == nil {
		return
	}
	go wailsruntime.Quit(ctx)
}
