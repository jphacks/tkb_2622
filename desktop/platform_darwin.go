package main

/*
#cgo LDFLAGS: -framework AppKit
#include "platform_darwin_tray.h"
*/
import "C"

import (
	"context"
	"sync"

	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

var trayContextMu sync.RWMutex
var trayContext context.Context

func configurePlatform(configuration *options.App) {
	configuration.Mac = &mac.Options{TitleBar: mac.TitleBarDefault()}
	configuration.HideWindowOnClose = true
	applicationMenu := menu.NewMenu()
	applicationMenu.Append(menu.AppMenu())
	applicationMenu.Append(menu.EditMenu())
	configuration.Menu = applicationMenu

	startup := configuration.OnStartup
	configuration.OnStartup = func(ctx context.Context) {
		if startup != nil {
			startup(ctx)
		}
		trayContextMu.Lock()
		trayContext = ctx
		trayContextMu.Unlock()
		C.FocusLinkInstallStatusItem()
	}
}

//export FocusLinkShowWindow
func FocusLinkShowWindow() {
	trayContextMu.RLock()
	ctx := trayContext
	trayContextMu.RUnlock()
	if ctx == nil {
		return
	}
	wailsruntime.Show(ctx)
	wailsruntime.WindowShow(ctx)
}

//export FocusLinkQuit
func FocusLinkQuit() {
	trayContextMu.RLock()
	ctx := trayContext
	trayContextMu.RUnlock()
	if ctx == nil {
		return
	}
	wailsruntime.Quit(ctx)
}
