package app

import (
	"context"
	"errors"
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

func (a *App) setAccountStatus(state session.AccountState, now time.Time) {
	a.mu.Lock()
	a.engine.SetAccount(state, now)
	if a.stateLoaded {
		a.persistLocked(now)
	}
	snapshot := a.engine.Snapshot()
	ctx := a.ctx
	a.mu.Unlock()
	if ctx != nil {
		wailsruntime.EventsEmit(ctx, StateEvent, snapshot)
	}
}

func (a *App) syncCloud(ctx context.Context) {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	if a.cloudClient == nil {
		message := "FOCUS_LINK_API_BASE_URL、FOCUS_LINK_SUPABASE_URL、FOCUS_LINK_SUPABASE_PUBLISHABLE_KEYを設定してください。"
		if a.cloudConfigError != nil && !strings.Contains(a.cloudConfigError.Error(), "URL is not configured") && !strings.Contains(a.cloudConfigError.Error(), "publishable key is not configured") {
			message = "接続設定を確認してください: " + a.cloudConfigError.Error()
		}
		a.setAccountStatus(session.AccountState{Status: "unconfigured", Message: message}, time.Now())
		return
	}
	if a.credentials == nil {
		message := "OSの資格情報ストアを利用できません。"
		if a.credentialStoreErr != nil {
			message += " " + a.credentialStoreErr.Error()
		}
		a.setAccountStatus(session.AccountState{Status: "storageUnavailable", Message: message}, time.Now())
		return
	}
	current, found, err := a.credentials.Load()
	if err != nil {
		a.setAccountStatus(session.AccountState{Status: "storageUnavailable", Message: "保存済みのログイン情報を読み取れません。OSの資格情報ストアを確認してください。"}, time.Now())
		return
	}
	if !found {
		a.authSession = cloud.AuthSession{}
		a.setIPhoneRestrictionState(nil, nil)
		status := session.AccountState{Status: "signedOut"}
		if a.pendingEmail != "" {
			status.Status = "otpPending"
			status.Email = a.pendingEmail
		}
		a.setAccountStatus(status, time.Now())
		return
	}
	updated, err := a.refreshSessionIfNeeded(ctx, current)
	if err != nil {
		a.setAccountStatus(session.AccountState{Status: "error", Email: current.Email, Message: err.Error()}, time.Now())
		return
	}
	if err := a.bootstrapSession(ctx, &updated); err != nil {
		a.authSession = updated
		a.setAccountStatus(session.AccountState{Status: "error", Email: updated.Email, Message: err.Error()}, time.Now())
		return
	}
	a.authSession = updated
	a.pendingEmail = ""
	a.setAccountStatus(session.AccountState{Status: "signedIn", Email: updated.Email, DeviceRegistered: true}, time.Now())
}

func (a *App) refreshSessionIfNeeded(ctx context.Context, current cloud.AuthSession) (cloud.AuthSession, error) {
	if time.Until(current.ExpiresAt) > 2*time.Minute {
		return current, nil
	}
	updated, err := a.cloudClient.RefreshSession(ctx, current)
	if err != nil {
		return cloud.AuthSession{}, err
	}
	if err := a.credentials.Save(updated); err != nil {
		return cloud.AuthSession{}, errors.New("更新したログイン情報をOSの資格情報ストアへ保存できませんでした")
	}
	return updated, nil
}

func (a *App) bootstrapSession(ctx context.Context, current *cloud.AuthSession) error {
	if current.EnsureOperationID == "" {
		id, err := newUUID()
		if err != nil {
			return errors.New("ユーザー確認用のIDを作成できませんでした")
		}
		current.EnsureOperationID = id
	}
	if current.RegistrationID == "" {
		id, err := newUUID()
		if err != nil {
			return errors.New("端末登録用のIDを作成できませんでした")
		}
		current.RegistrationID = id
	}
	if current.RegisterOperationID == "" {
		id, err := newUUID()
		if err != nil {
			return errors.New("端末登録操作のIDを作成できませんでした")
		}
		current.RegisterOperationID = id
	}
	if err := a.credentials.Save(*current); err != nil {
		return errors.New("ログイン情報をOSの資格情報ストアへ保存できませんでした")
	}
	if err := a.cloudClient.EnsureUser(ctx, *current); err != nil {
		return fmt.Errorf("業務ユーザーを確認できませんでした: %w", err)
	}
	name, platform := desktopDevice()
	if platform == "" {
		return errors.New("このOSではPC端末登録を利用できません")
	}
	deviceID, err := a.cloudClient.RegisterPCDevice(ctx, *current, platform, name)
	if err != nil {
		return fmt.Errorf("このPCを登録できませんでした: %w", err)
	}
	current.PCDeviceID = deviceID
	if err := a.credentials.Save(*current); err != nil {
		return errors.New("PC端末IDをOSの資格情報ストアへ保存できませんでした")
	}
	state := a.snapshot()
	updatedTasks, ids, err := a.syncPendingTasks(ctx, *current, state.Settings.Tasks)
	if err != nil {
		return err
	}
	selectedID := state.Settings.SelectedTaskID
	if savedID, ok := ids[selectedID]; ok {
		selectedID = savedID
	}
	a.mu.Lock()
	if len(ids) > 0 {
		if !a.engine.SetTasks(updatedTasks, selectedID, time.Now()) {
			a.mu.Unlock()
			return errors.New("保存待ちタスクを画面用に読み込めませんでした")
		}
		a.persistLocked(time.Now())
	}
	a.mu.Unlock()
	tasks, err := a.cloudClient.ListTasks(ctx, *current)
	if err != nil {
		return fmt.Errorf("タスク設定を取得できませんでした: %w", err)
	}
	converted := make([]session.Task, 0, len(tasks))
	for _, task := range tasks {
		converted = append(converted, session.Task{
			ID: task.ID, Name: task.Settings.Name, Category: task.Settings.Category, Mode: task.Settings.Mode,
			PlannedSeconds: int(task.Settings.PlannedSeconds), MinimumSeconds: int(task.Settings.MinimumSeconds), Version: task.Version,
		})
	}
	a.mu.Lock()
	selectedID = a.engine.Snapshot().Settings.SelectedTaskID
	if !a.engine.SetTasks(converted, selectedID, time.Now()) {
		a.mu.Unlock()
		return errors.New("APIから取得したタスク設定を画面用に読み込めませんでした")
	}
	a.persistLocked(time.Now())
	a.mu.Unlock()
	if err := a.flushActivitySyncLocked(ctx, *current); err != nil {
		a.markActivitySyncPending(err)
	}
	currentSession, err := a.cloudClient.GetCurrentSession(ctx, *current)
	if err != nil {
		return fmt.Errorf("未終了の作業を確認できませんでした: %w", err)
	}
	local := a.snapshot()
	if currentSession != nil && local.Session != nil && local.Session.ID == currentSession.ID && local.Session.ServerVersion > 0 {
		if err := a.ensureActivitySyncStateLocked(currentSession.ID, currentSession.AcceptedThroughSeq); err != nil {
			a.markActivitySyncPending(err)
		} else if currentSession.Status == "RUNNING" && local.Session.Status == "PAUSED" {
			pausedAt := time.Now()
			if err := a.queueCloudOperationLocked("pause", pausedAt, nil); err != nil {
				a.markActivitySyncPending(err)
			} else if err := a.prepareActivitySyncLocked(pausedAt, true); err != nil {
				a.markActivitySyncPending(err)
			} else {
				if err := a.flushActivitySyncLocked(ctx, *current); err != nil {
					a.markActivitySyncPending(err)
				}
			}
			currentSession, err = a.cloudClient.GetCurrentSession(ctx, *current)
			if err != nil {
				return fmt.Errorf("復元した作業状態を確認できませんでした: %w", err)
			}
		}
	}
	var balance *cloud.Balance
	if currentSession != nil {
		currentBalance, err := a.cloudClient.GetBalance(ctx, *current)
		if err != nil {
			return fmt.Errorf("作業中の報酬残高を取得できませんでした: %w", err)
		}
		if currentBalance.SessionID != currentSession.ID {
			return errors.New("APIの報酬残高が現在のセッションと一致しません")
		}
		balance = &currentBalance
	}
	a.reconcileCloudSession(currentSession, current.PCDeviceID)
	if balance != nil {
		a.applyCloudBalance(balance.SessionID, *balance)
	}
	_ = a.refreshCloudHistory(ctx, *current)
	a.fetchIPhoneRestrictionState(ctx, *current)
	return nil
}

func (a *App) refreshCloudHistory(ctx context.Context, auth cloud.AuthSession) error {
	entries, err := a.cloudClient.ListSessionHistory(ctx, auth)
	if err != nil {
		a.mu.Lock()
		a.engine.SetHistoryError("作業履歴を更新できませんでした。接続を確認して「更新」を押してください。", time.Now())
		a.persistLocked(time.Now())
		snapshot := a.engine.Snapshot()
		ctxApp := a.ctx
		a.mu.Unlock()
		if ctxApp != nil {
			wailsruntime.EventsEmit(ctxApp, StateEvent, snapshot)
		}
		return err
	}
	history := make([]session.Result, 0, len(entries))
	for _, entry := range entries {
		work := entry.Session.Durations.WorkMillis / 1000
		related := entry.Session.Durations.RelatedTransitionMillis / 1000
		distracted := entry.Session.Durations.DistractionMillis / 1000
		unknown := entry.Session.Durations.UnknownMillis / 1000
		inactive := entry.Session.Durations.IdleMillis / 1000
		result := session.Result{
			SessionID: entry.Session.ID, Name: entry.Session.TaskSettings.Name,
			Status: entry.Session.Status, StartedAt: entry.Session.StartedAt.Format(time.RFC3339Nano),
			ElapsedSeconds: int(entry.Session.Durations.ActiveMillis / 1000),
			TaskSeconds:    int(entry.Session.Durations.TaskMillis / 1000), RelatedSeconds: int(related),
			WorkSeconds: int(work), DistractedSeconds: int(distracted), UncertainSeconds: int(unknown),
			InactiveSeconds: int(inactive), EarnedSeconds: int(entry.Reward.EarnedSeconds),
			UsedSeconds: int(entry.Reward.SpentSeconds), DiscardedSeconds: int(entry.Reward.DiscardedSeconds),
			RewardStatus: entry.Reward.Status, RewardReason: entry.Reward.Reason,
			RewardPolicyVersion: entry.Reward.PolicyVersion, RewardGrantStopped: entry.Reward.GrantStopped,
			B100: entry.Session.FocusScore, Q: entry.Session.Quality, WorkRate: entry.Session.WorkRate,
		}
		if !entry.Session.EndedAt.IsZero() {
			result.EndedAt = entry.Session.EndedAt.Format(time.RFC3339Nano)
		}
		history = append(history, result)
	}
	a.mu.Lock()
	a.engine.SetCloudHistory(history, time.Now())
	a.persistLocked(time.Now())
	snapshot := a.engine.Snapshot()
	ctxApp := a.ctx
	a.mu.Unlock()
	if ctxApp != nil {
		wailsruntime.EventsEmit(ctxApp, StateEvent, snapshot)
	}
	return nil
}

func (a *App) fetchIPhoneRestrictionState(ctx context.Context, auth cloud.AuthSession) {
	state, err := a.cloudClient.GetRestrictionState(ctx, auth)
	if err != nil {
		a.setIPhoneRestrictionState(nil, err)
		return
	}
	lastAppliedAt, lastReportedAt := "", ""
	if state.LastAppliedAt != nil {
		lastAppliedAt = state.LastAppliedAt.UTC().Format(time.RFC3339Nano)
	}
	if state.LastReportedAt != nil {
		lastReportedAt = state.LastReportedAt.UTC().Format(time.RFC3339Nano)
	}
	a.setIPhoneRestrictionState(&session.IPhoneRestrictionState{
		SessionID: state.SessionID, DeviceID: state.DeviceID,
		ControlRevision: state.ControlRevision, DesiredMode: state.DesiredMode,
		AppliedRevision: state.AppliedRevision, ShieldStatus: state.ShieldStatus,
		PermissionStatus: state.PermissionStatus, LastAppliedAt: lastAppliedAt,
		LastReportedAt: lastReportedAt, FailureReason: state.FailureReason,
	}, nil)
}

func (a *App) setIPhoneRestrictionState(state *session.IPhoneRestrictionState, err error) {
	a.mu.Lock()
	if err != nil {
		state = a.engine.Snapshot().IPhoneRestriction
	}
	message := ""
	if err != nil {
		message = "iPhoneの適用状態を取得できません。"
	}
	a.engine.SetIPhoneRestrictionState(state, message, time.Now())
	snapshot, ctx := a.engine.Snapshot(), a.ctx
	a.mu.Unlock()
	if ctx != nil {
		wailsruntime.EventsEmit(ctx, StateEvent, snapshot)
	}
}

func (a *App) syncIPhoneRestrictionState(ctx context.Context) {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	if a.cloudClient == nil || a.credentials == nil {
		return
	}
	auth, found, err := a.credentials.Load()
	if err != nil {
		a.setIPhoneRestrictionState(nil, err)
		return
	}
	if !found {
		a.setIPhoneRestrictionState(nil, nil)
		return
	}
	updated, err := a.refreshSessionIfNeeded(ctx, auth)
	if err != nil {
		a.setIPhoneRestrictionState(nil, err)
		return
	}
	a.authSession = updated
	a.fetchIPhoneRestrictionState(ctx, updated)
}

func (a *App) reconcileCloudSession(current *cloud.Session, localDeviceID string) {
	now := time.Now()
	a.mu.Lock()
	state := a.engine.Snapshot()
	local := state.Session
	if current == nil {
		a.engine.SetCloudSession(nil, now)
		a.engine.ClearCloudBalance(now)
	} else {
		task := session.Task{
			ID: current.TaskID, Name: current.TaskSettings.Name, Category: current.TaskSettings.Category,
			Mode: current.TaskSettings.Mode, PlannedSeconds: int(current.TaskSettings.PlannedSeconds),
			MinimumSeconds: int(current.TaskSettings.MinimumSeconds),
		}
		for _, configured := range state.Settings.Tasks {
			if configured.ID == current.TaskID {
				task.Version = configured.Version
				break
			}
		}
		remote := &session.CloudSession{
			ID: current.ID, TaskID: current.TaskID, Name: current.TaskSettings.Name,
			Status: current.Status, Version: current.Version,
			TrackingOnly:      current.TrackingOnly,
			Message:           "サーバーに未終了の作業があります。このMacの記録と照合できるまで新しい作業を開始できません。",
			OwnedByThisDevice: current.DeviceID == localDeviceID,
		}
		if current.TrackingOnly {
			remote.Message = "この作業はiPhone制限なしの記録専用セッションです。"
		}
		if !remote.OwnedByThisDevice {
			if current.TrackingOnly {
				remote.Message = "別のPCで開始されたiPhone制限なしの記録専用セッションです。開始したPCで再開または中止してください。"
			} else {
				remote.Message = "別のPCで開始された未終了の作業があります。開始したPCで再開または中止してください。"
			}
		}
		if task.Name == "" {
			task.Name = current.TaskID
			remote.Name = current.TaskID
		}
		if remote.OwnedByThisDevice && local != nil && local.ID == current.ID {
			a.engine.SetServerSession(current.ID, task, current.Version, now)
			a.engine.SetTrackingOnly(current.ID, current.TrackingOnly, now)
			if local.Status == current.Status {
				a.engine.SetCloudSession(nil, now)
			} else {
				remote.Message = "サーバーの状態とこのMacの計測状態が一致しません。"
				if remote.OwnedByThisDevice {
					remote.Message += "中止以外の操作は次のAPI連携後に利用できます。"
				}
				a.engine.SetCloudSession(remote, now)
			}
		} else {
			a.engine.SetCloudSession(remote, now)
		}
	}
	a.persistLocked(now)
	snapshot := a.engine.Snapshot()
	ctx := a.ctx
	a.mu.Unlock()
	if ctx != nil {
		wailsruntime.EventsEmit(ctx, StateEvent, snapshot)
	}
}

func (a *App) startCloudSession(task session.Task) (cloud.Session, error) {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	ctx, cancel := context.WithTimeout(a.context(), 20*time.Second)
	defer cancel()
	auth, err := a.currentCloudAuthLocked(ctx)
	if err != nil {
		return cloud.Session{}, err
	}
	operationID, err := newUUID()
	if err != nil {
		return cloud.Session{}, errors.New("開始操作のIDを作成できませんでした")
	}
	return a.cloudClient.StartSession(ctx, auth, operationID, cloud.Task{
		ID: task.ID, Version: task.Version,
	})
}

func (a *App) abortCloudSession(current cloud.Session) error {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	ctx, cancel := context.WithTimeout(a.context(), 20*time.Second)
	defer cancel()
	auth, err := a.currentCloudAuthLocked(ctx)
	if err != nil {
		return err
	}
	remote, err := a.cloudClient.GetCurrentSession(ctx, auth)
	if err != nil {
		return err
	}
	if remote == nil || remote.ID != current.ID {
		return errors.New("サーバー上の未終了セッションを確認できません")
	}
	operationID, err := newUUID()
	if err != nil {
		return errors.New("中止操作のIDを作成できませんでした")
	}
	_, err = a.cloudClient.AbortSessionWithActivity(ctx, auth, operationID, current.ID, remote.Version, time.Now(), remote.AcceptedThroughSeq, nil)
	return err
}

func (a *App) currentCloudAuthLocked(ctx context.Context) (cloud.AuthSession, error) {
	if a.cloudClient == nil {
		return cloud.AuthSession{}, errors.New("API接続先が設定されていません")
	}
	if a.credentials == nil {
		return cloud.AuthSession{}, errors.New("OSの資格情報ストアを利用できません")
	}
	current := a.authSession
	if current.AccessToken == "" {
		var found bool
		var err error
		current, found, err = a.credentials.Load()
		if err != nil {
			return cloud.AuthSession{}, errors.New("保存済みのログイン情報を読み取れません")
		}
		if !found {
			return cloud.AuthSession{}, errors.New("ログイン情報がありません。設定からログインしてください")
		}
	}
	updated, err := a.refreshSessionIfNeeded(ctx, current)
	if err != nil {
		return cloud.AuthSession{}, err
	}
	a.authSession = updated
	return updated, nil
}

func (a *App) refreshCurrentCloudSession() {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	ctx, cancel := context.WithTimeout(a.context(), 20*time.Second)
	defer cancel()
	auth, err := a.currentCloudAuthLocked(ctx)
	if err == nil {
		var current *cloud.Session
		current, err = a.cloudClient.GetCurrentSession(ctx, auth)
		if err == nil {
			a.reconcileCloudSession(current, auth.PCDeviceID)
			return
		}
	}
	a.setAccountStatus(session.AccountState{Status: "error", Email: auth.Email, Message: "サーバー上の作業状態を確認できませんでした: " + err.Error()}, time.Now())
}

func (a *App) abortServerSessionIfNeeded() *session.Snapshot {
	a.mu.Lock()
	state := a.engine.Snapshot()
	if !state.Actions["abort"].Allowed {
		a.mu.Unlock()
		return nil
	}
	if state.Session != nil && state.Session.ServerVersion > 0 {
		a.mu.Unlock()
		return nil
	}
	if state.CloudSession != nil && (!state.CloudSession.OwnedByThisDevice || state.Session != nil && state.Session.ID != state.CloudSession.ID) {
		a.mu.Unlock()
		return nil
	}
	var current cloud.Session
	if state.CloudSession != nil && state.CloudSession.OwnedByThisDevice {
		current = cloud.Session{ID: state.CloudSession.ID, TaskID: state.CloudSession.TaskID, Status: state.CloudSession.Status, Version: state.CloudSession.Version}
		if state.Session != nil && state.Session.ID == state.CloudSession.ID && state.Session.ServerVersion > current.Version {
			current.Version = state.Session.ServerVersion
		}
	} else if state.Session != nil && state.Session.ServerVersion > 0 {
		task := state.Session.Task
		current = cloud.Session{ID: state.Session.ID, TaskID: task.ID, Status: state.Session.Status, Version: state.Session.ServerVersion}
	} else {
		a.mu.Unlock()
		return nil
	}
	localActive := state.Session != nil && (state.Session.Status == "RUNNING" || state.Session.Status == "PAUSED")
	a.mu.Unlock()

	if err := a.abortCloudSession(current); err != nil {
		a.refreshCurrentCloudSession()
		failed := a.failAction("session_abort", "サーバー上の作業を中止できませんでした: "+err.Error(), true)
		return &failed
	}

	a.mu.Lock()
	a.engine.SetCloudSession(nil, time.Now())
	if !localActive {
		a.persistLocked(time.Now())
		state = a.engine.Snapshot()
		a.mu.Unlock()
		a.emitState(state)
		return &state
	}
	a.persistLocked(time.Now())
	a.mu.Unlock()
	return nil
}

func desktopDevice() (string, string) {
	name, err := os.Hostname()
	if err != nil || strings.TrimSpace(name) == "" {
		name = "Focus Link PC"
	}
	if len([]rune(name)) > 100 {
		name = string([]rune(name)[:100])
	}
	switch runtime.GOOS {
	case "darwin":
		return name, "MACOS"
	case "windows":
		return name, "WINDOWS"
	default:
		return name, ""
	}
}

func (a *App) RequestEmailOTP(email string) session.Snapshot {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	ctx, cancel := context.WithTimeout(a.context(), 15*time.Second)
	defer cancel()
	if a.cloudClient == nil {
		a.setAccountStatus(session.AccountState{Status: "unconfigured", Message: "接続先の設定が不足しています。"}, time.Now())
		return a.snapshot()
	}
	if a.credentials == nil {
		a.setAccountStatus(session.AccountState{Status: "storageUnavailable", Message: "OSの資格情報ストアを利用できません。"}, time.Now())
		return a.snapshot()
	}
	if err := a.cloudClient.RequestEmailOTP(ctx, email); err != nil {
		a.setAccountStatus(session.AccountState{Status: "signedOut", Message: err.Error()}, time.Now())
		return a.snapshot()
	}
	a.pendingEmail = strings.TrimSpace(email)
	a.setAccountStatus(session.AccountState{Status: "otpPending", Email: a.pendingEmail, Message: "確認コードをメールで送信しました。"}, time.Now())
	return a.snapshot()
}

func (a *App) VerifyEmailOTP(email, code string) session.Snapshot {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	ctx, cancel := context.WithTimeout(a.context(), 30*time.Second)
	defer cancel()
	if a.cloudClient == nil {
		a.setAccountStatus(session.AccountState{Status: "unconfigured", Message: "API設定が不足しています。"}, time.Now())
		return a.snapshot()
	}
	if a.credentials == nil {
		a.setAccountStatus(session.AccountState{Status: "storageUnavailable", Message: "OSの資格情報ストアを利用できません。"}, time.Now())
		return a.snapshot()
	}
	current, err := a.cloudClient.VerifyEmailOTP(ctx, email, code)
	if err != nil {
		a.setAccountStatus(session.AccountState{Status: "otpPending", Email: strings.TrimSpace(email), Message: err.Error()}, time.Now())
		return a.snapshot()
	}
	current.EnsureOperationID, err = newUUID()
	if err == nil {
		current.RegistrationID, err = newUUID()
	}
	if err == nil {
		current.RegisterOperationID, err = newUUID()
	}
	if err != nil {
		a.setAccountStatus(session.AccountState{Status: "otpPending", Email: current.Email, Message: "ログイン情報の準備に失敗しました。もう一度お試しください。"}, time.Now())
		return a.snapshot()
	}
	if err := a.credentials.Save(current); err != nil {
		a.setAccountStatus(session.AccountState{Status: "otpPending", Email: current.Email, Message: "ログイン情報をOSの資格情報ストアへ保存できませんでした。"}, time.Now())
		return a.snapshot()
	}
	if err := a.bootstrapSession(ctx, &current); err != nil {
		a.authSession = current
		a.setAccountStatus(session.AccountState{Status: "error", Email: current.Email, Message: err.Error()}, time.Now())
		return a.snapshot()
	}
	a.authSession = current
	a.pendingEmail = ""
	a.setAccountStatus(session.AccountState{Status: "signedIn", Email: current.Email, DeviceRegistered: true}, time.Now())
	return a.snapshot()
}

func (a *App) SignOut() session.Snapshot {
	state := a.snapshot()
	if state.CloudSession != nil && state.CloudSession.OwnedByThisDevice || state.Session != nil && state.Session.ServerVersion > 0 && (state.Session.Status == "RUNNING" || state.Session.Status == "PAUSED") {
		return a.failAction("active_cloud_session", "サーバー上の作業を中止してからログアウトしてください。", false)
	}
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	message := ""
	if a.cloudClient != nil && a.authSession.AccessToken != "" {
		ctx, cancel := context.WithTimeout(a.context(), 10*time.Second)
		if err := a.cloudClient.SignOut(ctx, a.authSession); err != nil {
			message = "サーバーからログアウトを確認できませんでした。保存済みログイン情報は削除します。"
		}
		cancel()
	}
	if a.credentials != nil {
		if err := a.credentials.Delete(); err != nil {
			a.setAccountStatus(session.AccountState{Status: "error", Email: a.authSession.Email, Message: "OSの資格情報ストアからログイン情報を削除できませんでした。ログイン状態は保持されています。"}, time.Now())
			return a.snapshot()
		}
	}
	a.authSession = cloud.AuthSession{}
	a.pendingEmail = ""
	a.setIPhoneRestrictionState(nil, nil)
	a.setAccountStatus(session.AccountState{Status: "signedOut", Message: message}, time.Now())
	return a.snapshot()
}

func (a *App) snapshot() session.Snapshot {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.engine.Snapshot()
}
