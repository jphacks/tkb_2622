package app

import (
	"context"
	"runtime"
	"sync"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/session"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

const StateEvent = "desktop:state"

type App struct {
	mu     sync.Mutex
	engine *session.Engine
	ctx    context.Context
}

// ライフサイクル関数をバインド対象から分け，画面に公開する操作を限定する．
type Host struct {
	API    *App
	cancel context.CancelFunc
}

func New() *Host {
	platform := "unsupported"
	if runtime.GOOS == "darwin" {
		platform = "macos"
	}
	if runtime.GOOS == "windows" {
		platform = "windows"
	}
	return &Host{API: &App{engine: session.New(platform, time.Now())}}
}

func (h *Host) Startup(ctx context.Context) { h.API.ctx = ctx }

func (h *Host) DomReady(ctx context.Context) {
	a := h.API
	if h.cancel != nil {
		h.cancel()
	}
	loop, cancel := context.WithCancel(ctx)
	h.cancel = cancel
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case now := <-ticker.C:
				a.mu.Lock()
				changed := a.engine.Tick(now)
				state := a.engine.Snapshot()
				a.mu.Unlock()
				if changed {
					wailsruntime.EventsEmit(ctx, StateEvent, state)
				}
			case <-loop.Done():
				return
			}
		}
	}()
}

func (h *Host) Shutdown(context.Context) {
	if h.cancel != nil {
		h.cancel()
	}
}

func (a *App) GetStartupState() session.Snapshot {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.engine.Tick(time.Now())
	return a.engine.Snapshot()
}

func (a *App) Execute(command session.Command) session.Snapshot {
	a.mu.Lock()
	state := a.engine.Execute(command, time.Now())
	a.mu.Unlock()
	if a.ctx != nil {
		wailsruntime.EventsEmit(a.ctx, StateEvent, state)
	}
	return state
}
