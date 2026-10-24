package app

import (
	"context"
	"runtime"
	"sync"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/monitor"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

const StateEvent = "desktop:state"

type App struct {
	mu          sync.Mutex
	engine      *session.Engine
	recorder    *monitor.Recorder
	store       *stateStore
	stateLoaded bool
	ctx         context.Context
}

// ライフサイクル関数をバインド対象から分け，画面に公開する操作を限定する．
type Host struct {
	API    *App
	cancel context.CancelFunc
}

func New() *Host {
	now := time.Now()
	platform := "unsupported"
	if runtime.GOOS == "darwin" {
		platform = "macos"
	}
	if runtime.GOOS == "windows" {
		platform = "windows"
	}
	engine := session.New(platform, now)
	app := &App{engine: engine}
	if platform == "macos" {
		engine.SetMode("local-monitor", now)
		app.recorder = monitor.New(monitor.ResolveHelper())
		engine.SetMonitor(toSessionMonitor(app.recorder.Status()), now)
		store, storeErr := newStateStore()
		if storeErr != nil {
			engine.SetLocalStorageReady(false, now)
			engine.SetFailure("local_storage_unavailable", "作業状態の保存先を準備できませんでした。保存先の権限を確認してください。", true, now)
		} else {
			app.store = store
			snapshot, exists, loadErr := store.Load()
			if loadErr != nil {
				engine.SetLocalStorageReady(false, now)
				engine.SetFailure("local_state_read", "前回の作業状態を読み込めませんでした。", true, now)
			} else {
				app.stateLoaded = true
				if exists {
					snapshot.Mode = "local-monitor"
					if snapshot.Monitor.State == "" {
						if snapshot.Session != nil && (snapshot.Session.Status == "RUNNING" || snapshot.Session.Status == "PAUSED") {
							snapshot.Monitor.State = "paused"
						} else {
							snapshot.Monitor = toSessionMonitor(app.recorder.Status())
						}
					}
					if !engine.Restore(snapshot, now) {
						app.stateLoaded = false
						engine.SetLocalStorageReady(false, now)
						engine.SetFailure("local_state_invalid", "前回の作業状態を復元できませんでした。保存ファイルを確認してください。", false, now)
					} else if app.recorder.Status().State == "unavailable" {
						monitorStatus := engine.Snapshot().Monitor
						monitorStatus.State = "unavailable"
						monitorStatus.Message = app.recorder.Status().Message
						engine.SetMonitor(monitorStatus, now)
					}
				}
			}
		}
	}
	return &Host{API: app}
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
				a.tick(loop, now)
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
	h.API.shutdown()
}

func (a *App) tick(ctx context.Context, now time.Time) {
	a.mu.Lock()
	changed := a.engine.Tick(now)
	state := a.engine.Snapshot()
	if state.Mode == "local-monitor" && state.Session != nil && state.Session.Status == "RUNNING" {
		if a.recorder == nil {
			a.engine.SetFailure("monitor_unavailable", "macOS計測ヘルパーを利用できません。", false, now)
		} else {
			status, err := a.recorder.Sample(ctx)
			a.engine.SetMonitor(toSessionMonitor(status), now)
			if err != nil {
				a.engine.SetFailure("monitor_sample", status.Message, true, now)
			}
		}
		changed = true
	}
	if changed {
		a.persistLocked(now)
	}
	state = a.engine.Snapshot()
	a.mu.Unlock()
	if changed && a.ctx != nil {
		wailsruntime.EventsEmit(a.ctx, StateEvent, state)
	}
}

func (a *App) shutdown() {
	now := time.Now()
	a.mu.Lock()
	state := a.engine.Snapshot()
	if state.Mode == "local-monitor" && state.Session != nil && state.Session.Status == "RUNNING" {
		if a.recorder != nil {
			status, err := a.recorder.Pause()
			a.engine.SetMonitor(toSessionMonitor(status), now)
			if err != nil {
				a.engine.SetFailure("monitor_pause", status.Message, true, now)
			}
		}
		a.engine.PauseForShutdown(now)
	}
	a.persistLocked(now)
	a.mu.Unlock()
}

func (a *App) GetStartupState() session.Snapshot {
	a.mu.Lock()
	defer a.mu.Unlock()
	now := time.Now()
	if a.engine.Tick(now) {
		a.persistLocked(now)
	}
	return a.engine.Snapshot()
}

func (a *App) Execute(command session.Command) session.Snapshot {
	now := time.Now()
	a.mu.Lock()
	before := a.engine.Snapshot()
	sessionID := ""
	if before.Mode == "local-monitor" && command.Action == "start" {
		generatedSessionID, err := monitor.NewSessionID()
		if err != nil {
			a.engine.SetFailure("session_id", "ローカル作業IDを作成できませんでした。", false, now)
			state := a.engine.Snapshot()
			a.mu.Unlock()
			return state
		}
		sessionID = generatedSessionID
	}
	state := a.engine.ExecuteWithSessionID(command, sessionID, now)
	if state.Failure == nil && state.Mode == "local-monitor" {
		switch command.Action {
		case "start":
			a.startMonitoring(state, before, now)
		case "pause":
			a.pauseMonitoring(now)
		case "resume":
			a.resumeMonitoring(state, before, now)
		case "finish":
			a.finishMonitoring("finished", now)
		case "abort":
			a.finishMonitoring("aborted", now)
		}
	}
	a.persistLocked(now)
	state = a.engine.Snapshot()
	a.mu.Unlock()
	if a.ctx != nil {
		wailsruntime.EventsEmit(a.ctx, StateEvent, state)
	}
	return state
}

func (a *App) startMonitoring(state, before session.Snapshot, now time.Time) {
	if a.recorder == nil || state.Session == nil {
		a.engine.Restore(before, now)
		a.engine.SetFailure("monitor_unavailable", "macOS計測ヘルパーを利用できません。", false, now)
		return
	}
	status, err := a.recorder.Start(a.context(), state.Session.ID)
	if err != nil && status.State == "running" {
		if aborted, finishErr := a.recorder.Finish("aborted"); finishErr == nil {
			aborted.Message = status.Message
			status = aborted
		}
	}
	a.engine.SetMonitor(toSessionMonitor(status), now)
	if err != nil {
		a.engine.Restore(before, now)
		a.engine.SetMonitor(toSessionMonitor(status), now)
		a.engine.SetFailure("monitor_start", status.Message, true, now)
	}
}

func (a *App) pauseMonitoring(now time.Time) {
	if a.recorder == nil {
		return
	}
	status, err := a.recorder.Pause()
	a.engine.SetMonitor(toSessionMonitor(status), now)
	if err != nil {
		a.engine.SetFailure("monitor_pause", status.Message, true, now)
	}
}

func (a *App) resumeMonitoring(state, before session.Snapshot, now time.Time) {
	if a.recorder == nil || state.Session == nil {
		a.engine.Restore(before, now)
		a.engine.SetFailure("monitor_unavailable", "macOS計測ヘルパーを利用できません。", false, now)
		return
	}
	status, err := a.recorder.Resume(a.context(), state.Session.ID, toMonitorStatus(state.Monitor))
	if err != nil {
		if paused, pauseErr := a.recorder.Pause(); pauseErr == nil {
			status = paused
		}
	}
	a.engine.SetMonitor(toSessionMonitor(status), now)
	if err != nil {
		a.engine.Restore(before, now)
		a.engine.SetMonitor(toSessionMonitor(status), now)
		a.engine.SetFailure("monitor_resume", status.Message, true, now)
	}
}

func (a *App) finishMonitoring(outcome string, now time.Time) {
	if a.recorder == nil {
		return
	}
	status, err := a.recorder.Finish(outcome)
	a.engine.SetMonitor(toSessionMonitor(status), now)
	if err != nil {
		a.engine.SetFailure("monitor_finish", status.Message, true, now)
	}
}

func (a *App) persistLocked(now time.Time) {
	if a.store == nil || !a.stateLoaded {
		a.engine.SetLocalStorageReady(false, now)
		a.engine.SetFailure("local_storage_unavailable", "作業状態を読み込み・保存できません。保存先の権限と状態ファイルを確認してください。", false, now)
		return
	}
	if err := a.store.Save(a.engine.Snapshot()); err != nil {
		a.engine.SetLocalStorageReady(false, now)
		a.engine.SetFailure("local_storage", "作業状態をこのMacに保存できませんでした。保存先の空き容量と権限を確認してください。", true, now)
	} else {
		a.engine.SetLocalStorageReady(true, now)
	}
}

func (a *App) context() context.Context {
	if a.ctx != nil {
		return a.ctx
	}
	return context.Background()
}

func toMonitorStatus(status session.MonitorStatus) monitor.Status {
	return monitor.Status{
		State: status.State, AppName: status.AppName, BrowserName: status.BrowserName,
		Domain: status.Domain, LastSample: status.LastSample, SampleCount: status.SampleCount,
		Message: status.Message,
	}
}

func toSessionMonitor(status monitor.Status) session.MonitorStatus {
	return session.MonitorStatus{
		State: status.State, AppName: status.AppName, BrowserName: status.BrowserName,
		Domain: status.Domain, LastSample: status.LastSample, SampleCount: status.SampleCount,
		Message: status.Message,
	}
}
