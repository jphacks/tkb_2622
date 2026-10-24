package app

import (
	"context"
	"errors"
	"reflect"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
	offlineevaluation "github.com/jphacks/tkb_2622/desktop/internal/evaluation"
	"github.com/jphacks/tkb_2622/desktop/internal/monitor"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

const (
	StateEvent                 = "desktop:state"
	classificationCaptureDelay = 5 * time.Second
)

type App struct {
	mu                 sync.Mutex
	startMu            sync.Mutex
	engine             *session.Engine
	recorder           *monitor.Recorder
	store              *stateStore
	stateLoaded        bool
	ctx                context.Context
	cloudMu            sync.Mutex
	cloudClient        *cloud.Client
	cloudConfigError   error
	credentials        *credentialStore
	credentialStoreErr error
	authSession        cloud.AuthSession
	pendingEmail       string
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
	client, clientErr := cloud.NewClient(cloud.ConfigFromEnv())
	credentials, credentialErr := newCredentialStore()
	app := &App{
		engine: engine, cloudClient: client, cloudConfigError: clientErr,
		credentials: credentials, credentialStoreErr: credentialErr,
	}
	app.setAccountStatus(session.AccountState{Status: "unconfigured", Message: "Connect APIとSupabase Authの接続先を設定してください。"}, now)
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
					clearStaleTerminalEvaluationFailure(&snapshot)
					currentMonitor := toSessionMonitor(app.recorder.Status())
					if snapshot.Session != nil && (snapshot.Session.Status == "RUNNING" || snapshot.Session.Status == "PAUSED") {
						currentMonitor.State = "paused"
						currentMonitor.AppID = snapshot.Monitor.AppID
						currentMonitor.AppName = snapshot.Monitor.AppName
						currentMonitor.BrowserName = snapshot.Monitor.BrowserName
						currentMonitor.Domain = snapshot.Monitor.Domain
						currentMonitor.LastSample = snapshot.Monitor.LastSample
						currentMonitor.SampleCount = snapshot.Monitor.SampleCount
					} else {
						currentMonitor = toSessionMonitor(app.recorder.Status())
					}
					snapshot.Monitor = currentMonitor
					if !engine.Restore(snapshot, now) {
						app.stateLoaded = false
						engine.SetLocalStorageReady(false, now)
						engine.SetFailure("local_state_invalid", "前回の作業状態を復元できませんでした。保存ファイルを確認してください。", false, now)
					} else if snapshot.Session != nil && (snapshot.Session.Status == "RUNNING" || snapshot.Session.Status == "PAUSED") {
						if err := app.recorder.RestoreSession(snapshot.Session.ID, toMonitorStatus(currentMonitor)); err != nil {
							monitorStatus := currentMonitor
							monitorStatus.State = "error"
							monitorStatus.Message = "前回のローカル計測記録を復元できませんでした。"
							engine.SetMonitor(monitorStatus, now)
							engine.SetFailure("local_capture_restore", monitorStatus.Message, true, now)
						}
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

func clearStaleTerminalEvaluationFailure(snapshot *session.Snapshot) {
	if snapshot == nil || snapshot.Session == nil || snapshot.Failure == nil || snapshot.Failure.Code != "local_evaluation" {
		return
	}
	switch snapshot.Session.Status {
	case "FINALIZED", "ABORTED", "COMPLETED_LOCAL", "ABORTED_LOCAL":
		snapshot.Failure = nil
	}
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
	go func() {
		a.syncActivity(loop)
		ticker := time.NewTicker(activityBatchInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				a.syncActivity(loop)
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
	queuePause := false
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
		queuePause = state.Session.ServerVersion > 0
		if queuePause {
			a.engine.SetCloudOperationPending(true, now)
			a.engine.SetSyncStatus("pending", now)
		}
	}
	a.persistLocked(now)
	a.mu.Unlock()
	if queuePause {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := a.queueAndPrepareCloudOperation("pause", time.Now()); err == nil {
			_ = a.flushActivitySync(ctx)
		} else {
			a.markActivitySyncPending()
		}
	}
}

func (a *App) GetStartupState() session.Snapshot {
	ctx, cancel := context.WithTimeout(a.context(), 15*time.Second)
	defer cancel()
	a.syncCloud(ctx)
	a.mu.Lock()
	defer a.mu.Unlock()
	now := time.Now()
	if a.engine.Tick(now) {
		a.persistLocked(now)
	}
	return a.engine.Snapshot()
}

func (a *App) GetClassificationCandidates() ([]monitor.ClassificationCandidate, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	state := a.engine.Snapshot()
	if state.Session == nil {
		return []monitor.ClassificationCandidate{}, nil
	}
	return monitor.ReadClassificationCandidates(state.Session.ID)
}

func (a *App) CaptureCurrentClassificationCandidate() (monitor.ClassificationCandidate, error) {
	ctx := a.context()
	a.mu.Lock()
	state := a.engine.Snapshot()
	if state.Session != nil && (state.Session.Status == "RUNNING" || state.Session.Status == "PAUSED") {
		a.mu.Unlock()
		return monitor.ClassificationCandidate{}, errors.New("cannot read a candidate during an active work session")
	}
	if a.recorder == nil {
		a.mu.Unlock()
		return monitor.ClassificationCandidate{}, errors.New("native collector is unavailable")
	}
	a.mu.Unlock()

	timer := time.NewTimer(classificationCaptureDelay)
	defer timer.Stop()
	select {
	case <-timer.C:
	case <-ctx.Done():
		return monitor.ClassificationCandidate{}, ctx.Err()
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	state = a.engine.Snapshot()
	if state.Session != nil && (state.Session.Status == "RUNNING" || state.Session.Status == "PAUSED") {
		return monitor.ClassificationCandidate{}, errors.New("cannot read a candidate during an active work session")
	}
	return a.recorder.CaptureCurrentCandidate(ctx)
}

func (a *App) Execute(command session.Command) session.Snapshot {
	if command.Action == "abortCloudSession" {
		return a.abortCloudSessionFromUI()
	}
	if command.Action == "start" {
		return a.startSession(command)
	}
	if command.Action == "abort" {
		a.mu.Lock()
		current := a.engine.Snapshot()
		shouldConfirm := current.Mode == "local-monitor" && current.Actions["abort"].Allowed
		a.mu.Unlock()
		if shouldConfirm {
			confirmed, err := a.confirmAbort()
			if err != nil {
				a.mu.Lock()
				now := time.Now()
				a.engine.SetFailure("abort_confirmation", "中止の確認を表示できませんでした。もう一度お試しください。", true, now)
				state := a.engine.Snapshot()
				a.mu.Unlock()
				return state
			}
			if !confirmed {
				return current
			}
		}
	}
	if command.Action == "saveSettings" {
		return a.saveTaskSettings(command)
	}
	if command.Action == "abort" {
		if state := a.abortServerSessionIfNeeded(); state != nil {
			return *state
		}
	}
	now := time.Now()
	a.mu.Lock()
	before := a.engine.Snapshot()
	state := a.engine.Execute(command, now)
	if state.Failure == nil && state.Mode == "local-monitor" {
		switch command.Action {
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
	cloudOperation := before.Session != nil && before.Session.ServerVersion > 0 && state.Session != nil && state.Session.ID == before.Session.ID &&
		state.Session.Status != before.Session.Status &&
		(command.Action == "pause" || command.Action == "resume" || command.Action == "finish" || command.Action == "abort")
	if cloudOperation {
		a.engine.SetCloudOperationPending(true, now)
		a.engine.SetSyncStatus("pending", now)
	}
	a.persistLocked(now)
	state = a.engine.Snapshot()
	a.mu.Unlock()
	if cloudOperation {
		ctx, cancel := context.WithTimeout(a.context(), 20*time.Second)
		defer cancel()
		if err := a.queueAndPrepareCloudOperation(command.Action, time.Now()); err != nil {
			a.markActivitySyncPending()
		} else if err := a.flushActivitySync(ctx); err != nil {
			a.markActivitySyncPending()
		}
		state = a.snapshot()
	}
	if a.ctx != nil {
		wailsruntime.EventsEmit(a.ctx, StateEvent, state)
	}
	return state
}

func (a *App) startSession(command session.Command) session.Snapshot {
	a.startMu.Lock()
	defer a.startMu.Unlock()
	if len([]rune(strings.TrimSpace(command.Name))) > 80 {
		return a.failAction("invalid_input", "作業名は80文字以内で入力してください。", false)
	}

	now := time.Now()
	a.mu.Lock()
	before := a.engine.Snapshot()
	if !before.Actions["start"].Allowed {
		state := a.engine.Execute(command, now)
		a.persistLocked(now)
		state = a.engine.Snapshot()
		a.mu.Unlock()
		a.emitState(state)
		return state
	}
	selected := session.Task{}
	for _, task := range before.Settings.Tasks {
		if task.ID == before.Settings.SelectedTaskID {
			selected = task
			break
		}
	}
	useCloud := before.Mode == "local-monitor" && before.Account.Status == "signedIn"
	if useCloud && (selected.ID == "" || selected.Version < 1) {
		a.engine.SetFailure("task_unavailable", "開始するタスクをサーバーから再読み込みしてください。", true, now)
		state := a.engine.Snapshot()
		a.mu.Unlock()
		a.emitState(state)
		return state
	}
	a.mu.Unlock()

	var cloudSession *cloud.Session
	sessionID := ""
	if useCloud {
		started, err := a.startCloudSession(selected)
		if err != nil {
			a.refreshCurrentCloudSession()
			return a.failAction("session_start", "サーバーで作業を開始できませんでした: "+err.Error(), true)
		}
		cloudSession = &started
		sessionID = started.ID
	} else {
		generated, err := monitor.NewSessionID()
		if err != nil {
			return a.failAction("session_id", "ローカル作業IDを作成できませんでした。", false)
		}
		sessionID = generated
	}

	now = time.Now()
	a.mu.Lock()
	current := a.engine.Snapshot()
	selectedStillCurrent := current.Settings.SelectedTaskID == selected.ID && reflect.DeepEqual(current.Settings.Classifications, before.Settings.Classifications)
	if useCloud {
		selectedStillCurrent = selectedStillCurrent && current.Account.Status == "signedIn"
		found := false
		for _, task := range current.Settings.Tasks {
			if task.ID == selected.ID {
				selectedStillCurrent = selectedStillCurrent && task.Version == selected.Version
				found = true
				break
			}
		}
		selectedStillCurrent = selectedStillCurrent && found
	}
	if !current.Actions["start"].Allowed || !selectedStillCurrent {
		a.mu.Unlock()
		if cloudSession != nil {
			if err := a.abortCloudSession(*cloudSession); err != nil {
				return a.failOrphanedCloudStart(*cloudSession, err)
			}
		}
		return a.failAction("session_start_state_changed", "開始中に状態が変わりました。状態を確認してから再度お試しください。", true)
	}
	state := a.engine.ExecuteWithSessionID(command, sessionID, now)
	var startErr error
	if state.Failure == nil && state.Mode == "local-monitor" {
		if cloudSession != nil {
			task := selected
			task.Name = cloudSession.TaskSettings.Name
			task.Category = cloudSession.TaskSettings.Category
			task.Mode = cloudSession.TaskSettings.Mode
			task.PlannedSeconds = int(cloudSession.TaskSettings.PlannedSeconds)
			task.MinimumSeconds = int(cloudSession.TaskSettings.MinimumSeconds)
			a.engine.SetServerSession(cloudSession.ID, task, cloudSession.Version, now)
			a.engine.SetCloudBalance(cloudSession.ID, int(cloudSession.Balance.BalanceSeconds), now)
			state = a.engine.Snapshot()
		}
		startErr = a.startMonitoring(state, before, now)
	} else if state.Failure != nil && cloudSession != nil {
		startErr = errors.New(state.Failure.Message)
	}
	a.persistLocked(now)
	state = a.engine.Snapshot()
	a.mu.Unlock()
	if cloudSession != nil && startErr == nil {
		if err := a.ensureActivitySyncState(cloudSession.ID, cloudSession.AcceptedThroughSeq); err != nil {
			if a.recorder != nil {
				status, _ := a.recorder.Finish("aborted")
				a.mu.Lock()
				a.engine.Restore(before, time.Now())
				a.engine.SetMonitor(toSessionMonitor(status), time.Now())
				a.engine.SetFailure("activity_outbox", "サーバー作業を記録するローカル送信待ちを作成できませんでした。", true, time.Now())
				a.persistLocked(time.Now())
				state = a.engine.Snapshot()
				a.mu.Unlock()
			}
			startErr = err
		} else {
			a.mu.Lock()
			a.engine.SetTrackingOnly(cloudSession.ID, cloudSession.TrackingOnly, time.Now())
			a.persistLocked(time.Now())
			state = a.engine.Snapshot()
			a.mu.Unlock()
		}
	}
	if startErr != nil && cloudSession != nil {
		if err := a.abortCloudSession(*cloudSession); err != nil {
			return a.failOrphanedCloudStart(*cloudSession, err)
		}
	}
	a.emitState(state)
	return state
}

func (a *App) startMonitoring(state, before session.Snapshot, now time.Time) error {
	if a.recorder == nil || state.Session == nil {
		a.engine.Restore(before, now)
		a.engine.SetFailure("monitor_unavailable", "macOS計測ヘルパーを利用できません。", false, now)
		return errors.New("macOS計測ヘルパーを利用できません")
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
		return err
	}
	return nil
}

func (a *App) failAction(code, message string, retryable bool) session.Snapshot {
	a.mu.Lock()
	now := time.Now()
	a.engine.SetFailure(code, message, retryable, now)
	a.persistLocked(now)
	state := a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
	return state
}

func (a *App) failOrphanedCloudStart(started cloud.Session, cause error) session.Snapshot {
	a.mu.Lock()
	now := time.Now()
	a.engine.SetCloudSession(&session.CloudSession{
		ID: started.ID, TaskID: started.TaskID, Name: started.TaskSettings.Name,
		Status: started.Status, Version: started.Version,
		TrackingOnly:      started.TrackingOnly,
		OwnedByThisDevice: true,
		Message:           "このMacで計測を開始できず、サーバー側セッションも中止できませんでした。設定から再接続してください。",
	}, now)
	a.engine.SetFailure("session_compensation", "ローカル計測を開始できませんでした。サーバー側の中止にも失敗しました: "+cause.Error(), true, now)
	a.persistLocked(now)
	state := a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
	return state
}

func (a *App) emitState(state session.Snapshot) {
	if a.ctx != nil {
		wailsruntime.EventsEmit(a.ctx, StateEvent, state)
	}
}

func (a *App) confirmAbort() (bool, error) {
	result, err := wailsruntime.MessageDialog(a.context(), wailsruntime.MessageDialogOptions{
		Type:          wailsruntime.QuestionDialog,
		Title:         "作業を中止しますか？",
		Message:       "作業を中止します。未使用の報酬は破棄され、報酬は付与されません。",
		Buttons:       []string{"中止する", "作業に戻る"},
		DefaultButton: "作業に戻る",
		CancelButton:  "作業に戻る",
	})
	return result == "中止する", err
}

func (a *App) abortCloudSessionFromUI() session.Snapshot {
	state := a.snapshot()
	if state.CloudSession == nil || !state.CloudSession.OwnedByThisDevice || state.Session != nil && state.Session.ID == state.CloudSession.ID {
		return a.failAction("cloud_abort_unavailable", "このサーバーセッションはこの操作から中止できません。", false)
	}
	confirmed, err := a.confirmAbort()
	if err != nil {
		return a.failAction("abort_confirmation", "中止の確認を表示できませんでした。もう一度お試しください。", true)
	}
	if !confirmed {
		return state
	}
	current := cloud.Session{
		ID: state.CloudSession.ID, TaskID: state.CloudSession.TaskID,
		Status: state.CloudSession.Status, Version: state.CloudSession.Version,
	}
	if err := a.abortCloudSession(current); err != nil {
		a.refreshCurrentCloudSession()
		return a.failAction("session_abort", "サーバー上の作業を中止できませんでした: "+err.Error(), true)
	}
	a.mu.Lock()
	latest := a.engine.Snapshot()
	if latest.CloudSession != nil && latest.CloudSession.ID == current.ID {
		a.engine.SetCloudSession(nil, time.Now())
		a.persistLocked(time.Now())
	}
	state = a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
	return state
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
	state := a.engine.Snapshot()
	if state.Session == nil {
		return
	}
	if err != nil {
		a.engine.FailLocalEvaluation(state.Session.ID, now)
		a.engine.SetFailure("monitor_finish", status.Message, true, now)
		return
	}
	records, err := a.recorder.ReadRecords()
	if err != nil {
		a.engine.FailLocalEvaluation(state.Session.ID, now)
		return
	}
	result, err := offlineevaluation.Evaluate(records, *state.Session)
	if err != nil {
		a.engine.FailLocalEvaluation(state.Session.ID, now)
		return
	}
	a.engine.ApplyLocalEvaluation(result, now)
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
		State: status.State, AppID: status.AppID, AppName: status.AppName, BrowserName: status.BrowserName,
		Domain: status.Domain, LastSample: status.LastSample, SampleCount: status.SampleCount,
		Message: status.Message,
	}
}

func toSessionMonitor(status monitor.Status) session.MonitorStatus {
	return session.MonitorStatus{
		State: status.State, AppID: status.AppID, AppName: status.AppName, BrowserName: status.BrowserName,
		Domain: status.Domain, LastSample: status.LastSample, SampleCount: status.SampleCount,
		Message: status.Message,
	}
}
