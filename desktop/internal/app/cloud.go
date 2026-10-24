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
	if err := a.cloudClient.RegisterPCDevice(ctx, *current, platform, name); err != nil {
		return fmt.Errorf("このPCを登録できませんでした: %w", err)
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
	a.setAccountStatus(session.AccountState{Status: "signedOut", Message: message}, time.Now())
	return a.snapshot()
}

func (a *App) snapshot() session.Snapshot {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.engine.Snapshot()
}
