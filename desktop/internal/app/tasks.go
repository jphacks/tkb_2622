package app

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

func taskSettingsHash(task session.Task) (string, error) {
	settings := cloud.TaskSettings{
		Name: task.Name, Category: task.Category, Mode: task.Mode,
		PlannedSeconds: int64(task.PlannedSeconds), MinimumSeconds: int64(task.MinimumSeconds),
	}
	data, err := json.Marshal(settings)
	if err != nil {
		return "", err
	}
	hash := sha256.Sum256(data)
	return fmt.Sprintf("%x", hash[:]), nil
}

func (a *App) prepareTaskWrites(settings *session.Settings, previous []session.Task) error {
	previousByID := make(map[string]session.Task, len(previous))
	for _, task := range previous {
		previousByID[task.ID] = task
	}
	for index, task := range settings.Tasks {
		hash, err := taskSettingsHash(task)
		if err != nil {
			return errors.New("タスク設定を保存用に準備できませんでした")
		}
		prior, exists := previousByID[task.ID]
		isNew := !exists || task.Version == 0
		if task.PendingOperationID != "" && task.PendingSettingsHash == hash {
			settings.Tasks[index].PendingSettingsHash = hash
			continue
		}
		changed := isNew
		if exists && !isNew {
			previousHash, hashErr := taskSettingsHash(prior)
			if hashErr != nil {
				return errors.New("保存済みタスク設定を確認できませんでした")
			}
			changed = previousHash != hash
		}
		if !changed {
			settings.Tasks[index].PendingOperationID = ""
			settings.Tasks[index].PendingSettingsHash = ""
			continue
		}
		operationID, err := newUUID()
		if err != nil {
			return errors.New("タスク保存用のIDを作成できませんでした")
		}
		settings.Tasks[index].PendingOperationID = operationID
		settings.Tasks[index].PendingSettingsHash = hash
	}
	return nil
}

func (a *App) syncPendingTasks(ctx context.Context, current cloud.AuthSession, tasks []session.Task) ([]session.Task, map[string]string, error) {
	updated := append([]session.Task(nil), tasks...)
	ids := make(map[string]string)
	for index, task := range updated {
		if task.PendingOperationID == "" {
			continue
		}
		hash, err := taskSettingsHash(task)
		if err != nil || hash != task.PendingSettingsHash {
			return nil, nil, errors.New("保存待ちタスクが変更されています。設定を保存し直してください")
		}
		settings := cloud.TaskSettings{
			Name: task.Name, Category: task.Category, Mode: task.Mode,
			PlannedSeconds: int64(task.PlannedSeconds), MinimumSeconds: int64(task.MinimumSeconds),
		}
		var saved cloud.Task
		if task.Version > 0 {
			saved, err = a.cloudClient.UpdateTask(ctx, current, task.ID, task.Version, task.PendingOperationID, settings)
		} else {
			saved, err = a.cloudClient.CreateTask(ctx, current, task.PendingOperationID, settings)
		}
		if err != nil {
			return nil, nil, fmt.Errorf("「%s」を保存できませんでした: %w", task.Name, err)
		}
		if saved.ID == "" || saved.Version < 1 {
			return nil, nil, errors.New("APIから保存済みタスクの識別情報が返りませんでした")
		}
		ids[task.ID] = saved.ID
		updated[index] = session.Task{
			ID: saved.ID, Name: saved.Settings.Name, Category: saved.Settings.Category, Mode: saved.Settings.Mode,
			PlannedSeconds: int(saved.Settings.PlannedSeconds), MinimumSeconds: int(saved.Settings.MinimumSeconds), Version: saved.Version,
		}
	}
	return updated, ids, nil
}

func (a *App) saveTaskSettings(command session.Command) session.Snapshot {
	now := time.Now()
	a.mu.Lock()
	before := a.engine.Snapshot()
	if before.Account.Status != "signedIn" || a.cloudClient == nil || a.credentials == nil {
		state := a.engine.Execute(command, now)
		a.persistLocked(now)
		state = a.engine.Snapshot()
		ctx := a.ctx
		a.mu.Unlock()
		if ctx != nil {
			wailsruntime.EventsEmit(ctx, StateEvent, state)
		}
		return state
	}
	if err := a.prepareTaskWrites(&command.Settings, before.Settings.Tasks); err != nil {
		a.engine.SetFailure("task_prepare", err.Error(), false, now)
		state := a.engine.Snapshot()
		a.mu.Unlock()
		return state
	}
	state := a.engine.Execute(command, now)
	if state.Failure != nil {
		a.mu.Unlock()
		return state
	}
	a.persistLocked(now)
	a.mu.Unlock()

	a.cloudMu.Lock()
	ctx, cancel := context.WithTimeout(a.context(), 30*time.Second)
	current, err := a.activeCloudSession(ctx)
	var tasks []session.Task
	var ids map[string]string
	if err == nil {
		tasks, ids, err = a.syncPendingTasks(ctx, current, command.Settings.Tasks)
	}
	cancel()
	a.cloudMu.Unlock()

	a.mu.Lock()
	if err != nil {
		a.engine.SetFailure("task_save", err.Error(), true, time.Now())
	} else {
		selectedID := command.Settings.SelectedTaskID
		if savedID, ok := ids[selectedID]; ok {
			selectedID = savedID
		}
		command.Settings.Tasks = tasks
		command.Settings.SelectedTaskID = selectedID
		if !a.engine.SetTasks(tasks, selectedID, time.Now()) {
			a.engine.SetFailure("task_response", "APIから保存したタスク設定を画面へ反映できませんでした。", true, time.Now())
		}
	}
	a.persistLocked(time.Now())
	state = a.engine.Snapshot()
	ctxForEvents := a.ctx
	a.mu.Unlock()
	if ctxForEvents != nil {
		wailsruntime.EventsEmit(ctxForEvents, StateEvent, state)
	}
	return state
}

func (a *App) activeCloudSession(ctx context.Context) (cloud.AuthSession, error) {
	current := a.authSession
	if current.AccessToken == "" {
		loaded, found, err := a.credentials.Load()
		if err != nil || !found {
			return cloud.AuthSession{}, errors.New("ログイン状態を取得できません。再ログインしてください")
		}
		current = loaded
	}
	updated, err := a.refreshSessionIfNeeded(ctx, current)
	if err != nil {
		return cloud.AuthSession{}, fmt.Errorf("ログイン状態を更新できませんでした: %w", err)
	}
	a.authSession = updated
	return updated, nil
}
