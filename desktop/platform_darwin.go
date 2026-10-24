//go:build darwin

package main

/*
#cgo LDFLAGS: -framework AppKit
#include <stdlib.h>
#include "platform_darwin_tray.h"
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"unsafe"

	"github.com/jphacks/tkb_2622/desktop/internal/app"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

var trayStateMu sync.RWMutex
var trayContext context.Context
var trayHost *app.Host
var trayStateReady bool

type popoverCapability struct {
	Allowed bool   `json:"allowed"`
	Reason  string `json:"reason"`
}

type popoverState struct {
	Status          string            `json:"status"`
	StatusLabel     string            `json:"statusLabel"`
	TaskDescription string            `json:"taskDescription"`
	Elapsed         string            `json:"elapsed"`
	TimerHint       string            `json:"timerHint"`
	Balance         string            `json:"balance"`
	Detail          string            `json:"detail"`
	HasTask         bool              `json:"hasTask"`
	HasResult       bool              `json:"hasResult"`
	Start           popoverCapability `json:"start"`
	Pause           popoverCapability `json:"pause"`
	Resume          popoverCapability `json:"resume"`
	Finish          popoverCapability `json:"finish"`
	Abort           popoverCapability `json:"abort"`
	Retry           popoverCapability `json:"retry"`
}

func configurePlatform(configuration *options.App, host *app.Host) {
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
		trayStateMu.Lock()
		trayContext = ctx
		trayHost = host
		trayStateReady = false
		trayStateMu.Unlock()
		wailsruntime.EventsOn(ctx, app.StateEvent, func(...interface{}) {
			updateNativePopover(host.CurrentSnapshot())
		})
		wailsruntime.EventsOn(ctx, app.StartupStateReadyEvent, func(...interface{}) {
			trayStateMu.Lock()
			trayStateReady = true
			trayStateMu.Unlock()
			updateNativePopover(host.CurrentSnapshot())
		})
		C.FocusLinkInstallStatusItem()
		updateNativePopover(host.CurrentSnapshot())
	}
}

func currentTrayHost() (*app.Host, context.Context) {
	trayStateMu.RLock()
	defer trayStateMu.RUnlock()
	return trayHost, trayContext
}

func updateNativePopover(snapshot session.Snapshot) {
	state := makePopoverState(snapshot)
	trayStateMu.RLock()
	ready := trayStateReady
	trayStateMu.RUnlock()
	if !ready {
		for _, action := range []*popoverCapability{&state.Start, &state.Pause, &state.Resume, &state.Finish, &state.Abort, &state.Retry} {
			action.Allowed = false
			action.Reason = "起動時の状態を確認しています。"
		}
		if state.Detail == "" {
			state.Detail = "状態を確認しています…"
		}
	}
	data, err := json.Marshal(state)
	if err != nil {
		return
	}
	cData := C.CString(string(data))
	defer C.free(unsafe.Pointer(cData))
	C.FocusLinkUpdatePopover(cData)
}

func makePopoverState(snapshot session.Snapshot) popoverState {
	view := popoverState{Status: "idle", StatusLabel: "作業開始前", Elapsed: "0:00:00"}
	view.Start = capability(snapshot, "start")
	view.Pause = capability(snapshot, "pause")
	view.Resume = capability(snapshot, "resume")
	view.Finish = capability(snapshot, "finish")
	view.Abort = capability(snapshot, "abort")
	view.Retry = capability(snapshot, "retry")

	var task *session.Task
	if snapshot.Session != nil && (snapshot.Session.Status == "RUNNING" || snapshot.Session.Status == "PAUSED") {
		task = &snapshot.Session.Task
	} else {
		for i := range snapshot.Settings.Tasks {
			if snapshot.Settings.Tasks[i].ID == snapshot.Settings.SelectedTaskID {
				task = &snapshot.Settings.Tasks[i]
				break
			}
		}
	}
	if task != nil {
		view.HasTask = true
		view.TaskDescription = task.Name
		if task.PlannedSeconds > 0 {
			view.TaskDescription += " ・ 予定 " + formatPopoverDuration(task.PlannedSeconds)
		}
	} else {
		view.TaskDescription = "タスクがありません。設定から追加してください。"
	}

	sessionState := snapshot.Session
	if sessionState != nil {
		switch sessionState.Status {
		case "RUNNING":
			view.Status = "running"
			view.StatusLabel = "作業中"
			view.Elapsed = formatPopoverClock(sessionState.ElapsedSeconds)
			remaining := sessionState.Task.MinimumSeconds - sessionState.ElapsedSeconds
			if remaining > 0 {
				view.TimerHint = "終了まであと " + formatPopoverDuration(remaining)
			} else {
				view.TimerHint = "終了できます"
			}
		case "PAUSED":
			view.Status = "paused"
			view.StatusLabel = "一時停止中"
			view.Elapsed = formatPopoverClock(sessionState.ElapsedSeconds)
			view.TimerHint = "作業を再開すると計測を続けます"
		case "COMPLETED_LOCAL", "ABORTED_LOCAL":
			view.Status = "pending"
			if sessionState.Status == "ABORTED_LOCAL" {
				view.StatusLabel = "中止・同期待ち"
			} else {
				view.StatusLabel = "終了・同期待ち"
			}
			view.Elapsed = formatPopoverClock(sessionState.ElapsedSeconds)
			view.TimerHint = "記録の同期が終わるまで結果は確定しません"
		}
		if sessionState.Name != "" {
			view.TaskDescription = sessionState.Name
		} else if sessionState.Task.Name != "" {
			view.TaskDescription = sessionState.Task.Name
		}
	}

	if snapshot.BalanceSeconds != nil {
		if sessionState != nil && sessionState.TrackingOnly {
			view.Balance = "このセッションの報酬残高　" + formatPopoverDuration(*snapshot.BalanceSeconds)
		} else if snapshot.Account.Status == "signedIn" {
			view.Balance = "確定残高　" + formatPopoverDuration(*snapshot.BalanceSeconds)
		}
	}
	if snapshot.Result != nil && sessionState != nil && snapshot.Result.SessionID == sessionState.ID && (sessionState.Status == "FINALIZED" || sessionState.Status == "ABORTED") {
		view.HasResult = true
		if sessionState.Status == "ABORTED" {
			view.StatusLabel = "中止済み"
		} else {
			view.StatusLabel = "作業終了"
		}
		view.TaskDescription = sessionState.Name
		if view.TaskDescription == "" {
			view.TaskDescription = sessionState.Task.Name
		}
		view.Detail = "作業結果を確認できます。"
	}

	switch {
	case view.HasResult:
	case snapshot.Failure != nil && snapshot.Failure.Message != "":
		view.Detail = snapshot.Failure.Message
	case snapshot.CloudOperationPending:
		view.Detail = "サーバーへの作業状態を同期しています。"
	case snapshot.Sync == "failed":
		view.Detail = "同期に失敗しました。未送信の記録はこのMacに保存されています。"
	case snapshot.Sync == "pending":
		view.Detail = "作業記録をサーバーへ同期しています。"
	case snapshot.CloudSession != nil && snapshot.CloudSession.Message != "":
		view.Detail = snapshot.CloudSession.Message
	case sessionState != nil && sessionState.TrackingOnly:
		view.Detail = "このセッションは記録専用です。iPhoneの利用制限は適用しません。"
	case sessionState != nil && snapshot.Mode == "local-monitor" && sessionState.ServerVersion == 0:
		view.Detail = "記録はこのMacに保存されます。報酬の確定とiPhone利用枠は未接続です。"
	}
	return view
}

func capability(snapshot session.Snapshot, action string) popoverCapability {
	value := snapshot.Actions[action]
	return popoverCapability{Allowed: value.Allowed, Reason: value.Reason}
}

func formatPopoverDuration(seconds int) string {
	if seconds < 0 {
		seconds = 0
	}
	if seconds < 60 {
		return fmt.Sprintf("%d秒", seconds)
	}
	minutes := seconds / 60
	if minutes >= 60 {
		return fmt.Sprintf("%d時間%d分", minutes/60, minutes%60)
	}
	return fmt.Sprintf("%d分", minutes)
}

func formatPopoverClock(seconds int) string {
	if seconds < 0 {
		seconds = 0
	}
	return fmt.Sprintf("%d:%02d:%02d", seconds/3600, (seconds/60)%60, seconds%60)
}

//export FocusLinkShowPopover
func FocusLinkShowPopover() {
	host, _ := currentTrayHost()
	if host != nil {
		updateNativePopover(host.CurrentSnapshot())
	}
	C.FocusLinkPresentPopover()
}

//export FocusLinkPopoverAction
func FocusLinkPopoverAction(cAction *C.char, cName *C.char) {
	host, _ := currentTrayHost()
	trayStateMu.RLock()
	ready := trayStateReady
	trayStateMu.RUnlock()
	if host == nil || !ready || cAction == nil {
		return
	}
	action := C.GoString(cAction)
	if action != "start" && action != "pause" && action != "resume" && action != "finish" && action != "abort" && action != "retry" {
		return
	}
	name := ""
	if cName != nil {
		name = C.GoString(cName)
	}
	C.FocusLinkSetPopoverBusy(1)
	go func() {
		before := host.CurrentSnapshot()
		updated := host.API.Execute(session.Command{Action: action, Name: name})
		updateNativePopover(updated)
		C.FocusLinkSetPopoverBusy(0)
		if (action == "finish" || action == "abort" || action == "retry") && isCompletedResult(before, updated) {
			_, ctx := currentTrayHost()
			if ctx != nil {
				C.FocusLinkClosePopover()
				wailsruntime.Show(ctx)
				wailsruntime.WindowShow(ctx)
				wailsruntime.EventsEmit(ctx, "desktop:show-feedback", updated.Result)
			}
		}
	}()
}

func isCompletedResult(before, updated session.Snapshot) bool {
	if updated.Session == nil || updated.Result == nil {
		return false
	}
	if before.Session != nil && before.Session.ID != updated.Session.ID {
		return false
	}
	return (updated.Session.Status == "FINALIZED" || updated.Session.Status == "ABORTED") && updated.Result.SessionID == updated.Session.ID
}

//export FocusLinkOpenPage
func FocusLinkOpenPage(cPage *C.char) {
	host, ctx := currentTrayHost()
	if host == nil || ctx == nil || cPage == nil {
		return
	}
	page := C.GoString(cPage)
	if page != "session" && page != "history" && page != "settings" && page != "feedback" {
		return
	}
	if page == "feedback" {
		state := host.CurrentSnapshot()
		if state.Result == nil {
			return
		}
	}
	C.FocusLinkClosePopover()
	wailsruntime.Show(ctx)
	wailsruntime.WindowShow(ctx)
	if page == "feedback" {
		wailsruntime.EventsEmit(ctx, "desktop:show-feedback", host.CurrentSnapshot().Result)
	} else {
		wailsruntime.EventsEmit(ctx, "desktop:open-page", page)
	}
}

//export FocusLinkQuit
func FocusLinkQuit() {
	_, ctx := currentTrayHost()
	if ctx == nil {
		return
	}
	wailsruntime.Quit(ctx)
}
