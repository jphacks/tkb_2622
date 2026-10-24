package session

import (
	"reflect"
	"testing"
	"time"
)

func TestEngineSaveSettingsIsAtomic(t *testing.T) {
	now := time.Date(2026, time.October, 24, 9, 0, 0, 0, time.UTC)
	engine := New("macos", now)
	draft := Settings{
		Tasks:           []Task{{ID: "writing", Name: "論文執筆", PlannedSeconds: 7200, MinimumSeconds: 3600}},
		SelectedTaskID:  "writing",
		Classifications: []Classification{{Name: "Notion", Category: "work"}},
	}
	saved := engine.Execute(Command{Action: "saveSettings", Settings: draft}, now)
	if saved.Failure != nil || saved.Settings.SelectedTaskID != "writing" || len(saved.Settings.Tasks) != 1 || len(saved.Settings.Classifications) != 1 {
		t.Fatalf("設定の保存結果 = %#v", saved)
	}

	invalid := draft
	invalid.Tasks = append(invalid.Tasks, draft.Tasks[0])
	rejected := engine.Execute(Command{Action: "saveSettings", Settings: invalid}, now)
	if rejected.Failure == nil || rejected.Failure.Code != "invalid_input" {
		t.Fatalf("重複IDを含む設定が拒否されない: %#v", rejected.Failure)
	}
	if !reflect.DeepEqual(rejected.Settings, saved.Settings) {
		t.Fatalf("無効な設定の一部が反映された: %#v", rejected.Settings)
	}
}

func TestEngineFinishHonorsMinimumTime(t *testing.T) {
	start := time.Date(2026, time.October, 24, 10, 0, 0, 0, time.UTC)
	engine := New("macos", start)

	state := engine.Execute(Command{Action: "start"}, start)
	if state.Session == nil || state.Session.Status != "RUNNING" {
		t.Fatalf("開始後の状態 = %#v、RUNNINGを期待", state.Session)
	}
	if state.Actions["finish"].Allowed {
		t.Fatal("開始直後に終了が許可されている")
	}

	state = engine.Execute(Command{Action: "finish"}, start.Add(3599*time.Second))
	if state.Session == nil || state.Session.Status != "RUNNING" {
		t.Fatalf("最小時間未達で終了状態へ進んだ: %#v", state.Session)
	}
	if state.Session.ElapsedSeconds != 3599 || state.Actions["finish"].Allowed {
		t.Fatalf("59分59秒時点の状態 = %#v、終了不可を期待", state.Session)
	}
	if state.Failure == nil || state.Failure.Code != "invalid_state" {
		t.Fatalf("最小時間未達時の失敗 = %#v、invalid_stateを期待", state.Failure)
	}

	state = engine.Execute(Command{Action: "finish"}, start.Add(3600*time.Second))
	if state.Session == nil || state.Session.Status != "FINALIZED" {
		t.Fatalf("最小時間到達後の状態 = %#v、FINALIZEDを期待", state.Session)
	}
	if state.Result == nil || state.Result.ElapsedSeconds != 3600 {
		t.Fatalf("終了結果 = %#v、3600秒を期待", state.Result)
	}
}

func TestEnginePauseStopsElapsedTimeAndRetryAllowsResume(t *testing.T) {
	start := time.Date(2026, time.October, 24, 11, 0, 0, 0, time.UTC)
	engine := New("macos", start)

	engine.Execute(Command{Action: "start"}, start)
	paused := engine.Execute(Command{Action: "pause"}, start.Add(10*time.Second))
	if paused.Session == nil || paused.Session.Status != "PAUSED" || paused.Session.ElapsedSeconds != 10 {
		t.Fatalf("一時停止後の状態 = %#v、10秒でPAUSEDを期待", paused.Session)
	}
	if paused.Actions["resume"].Allowed {
		t.Fatal("評価・同期完了前に再開が許可されている")
	}
	if engine.Tick(start.Add(2 * time.Minute)) {
		t.Fatal("一時停止中のTickが状態を変更した")
	}
	paused = engine.Snapshot()
	if paused.Session == nil || paused.Session.ElapsedSeconds != 10 {
		t.Fatalf("一時停止中に経過秒数が増えた: %#v", paused.Session)
	}

	retried := engine.Execute(Command{Action: "retry"}, start.Add(2*time.Minute))
	if retried.Session == nil || retried.Session.Evaluation != "complete" || retried.Sync != "synced" {
		t.Fatalf("再試行後の状態 = %#v、評価完了・同期済みを期待", retried)
	}
	if !retried.Actions["resume"].Allowed {
		t.Fatal("評価・同期完了後も再開できない")
	}

	resumed := engine.Execute(Command{Action: "resume"}, start.Add(2*time.Minute))
	if resumed.Session == nil || resumed.Session.Status != "RUNNING" {
		t.Fatalf("再開後の状態 = %#v、RUNNINGを期待", resumed.Session)
	}
	engine.Tick(start.Add(2*time.Minute + 5*time.Second))
	resumed = engine.Snapshot()
	if resumed.Session == nil || resumed.Session.ElapsedSeconds != 15 {
		t.Fatalf("再開後の経過秒数 = %#v、15秒を期待", resumed.Session)
	}
}

func TestEngineSuppressesDuplicateStartAndPause(t *testing.T) {
	start := time.Date(2026, time.October, 24, 12, 0, 0, 0, time.UTC)
	engine := New("macos", start)

	first := engine.Execute(Command{Action: "start"}, start)
	sessionID := first.Session.ID
	second := engine.Execute(Command{Action: "start"}, start.Add(time.Second))
	if second.Session == nil || second.Session.ID != sessionID {
		t.Fatalf("連続開始でセッションが置き換わった: %#v", second.Session)
	}
	if second.Failure == nil || second.Failure.Code != "invalid_state" {
		t.Fatalf("連続開始の失敗 = %#v、invalid_stateを期待", second.Failure)
	}

	paused := engine.Execute(Command{Action: "pause"}, start.Add(2*time.Second))
	duplicate := engine.Execute(Command{Action: "pause"}, start.Add(3*time.Second))
	if duplicate.Session == nil || duplicate.Session.Status != "PAUSED" || duplicate.Session.ElapsedSeconds != paused.Session.ElapsedSeconds {
		t.Fatalf("連続一時停止で状態が変わった: %#v", duplicate.Session)
	}
	if duplicate.Failure == nil || duplicate.Failure.Code != "invalid_state" {
		t.Fatalf("連続一時停止の失敗 = %#v、invalid_stateを期待", duplicate.Failure)
	}
}

func TestEngineOfflineFinishAndAbortWaitForRetry(t *testing.T) {
	tests := []struct {
		name       string
		action     string
		wantLocal  string
		wantServer string
	}{
		{name: "finish", action: "finish", wantLocal: "COMPLETED_LOCAL", wantServer: "FINALIZED"},
		{name: "abort", action: "abort", wantLocal: "ABORTED_LOCAL", wantServer: "ABORTED"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			start := time.Date(2026, time.October, 24, 13, 0, 0, 0, time.UTC)
			engine := New("macos", start)
			engine.Execute(Command{Action: "start"}, start)
			engine.Execute(Command{Action: "connection"}, start.Add(time.Second))
			if test.action == "finish" {
				engine.Tick(start.Add(time.Hour))
			}

			local := engine.Execute(Command{Action: test.action}, start.Add(time.Hour))
			if local.Session == nil || local.Session.Status != test.wantLocal {
				t.Fatalf("オフライン操作後の状態 = %#v、%sを期待", local.Session, test.wantLocal)
			}
			if local.Sync != "pending" || local.Result != nil {
				t.Fatalf("再同期前に確定状態を表示した: sync=%q result=%#v", local.Sync, local.Result)
			}
			if local.RestrictionDesired != "restricted" {
				t.Fatalf("再同期前に制限解除を示した: %q", local.RestrictionDesired)
			}

			synced := engine.Execute(Command{Action: "retry"}, start.Add(61*time.Second))
			if synced.Session == nil || synced.Session.Status != test.wantServer || synced.Sync != "synced" {
				t.Fatalf("再試行後の状態 = %#v, sync=%q", synced.Session, synced.Sync)
			}
			if synced.Result == nil || synced.Result.Status != test.wantServer || synced.RestrictionDesired != "unrestricted" {
				t.Fatalf("再試行後に確定結果・解除状態が反映されない: result=%#v restriction=%q", synced.Result, synced.RestrictionDesired)
			}
		})
	}
}

func TestEngineFinishingPendingPauseSyncsAndDiscardsBalance(t *testing.T) {
	start := time.Date(2026, time.October, 24, 14, 0, 0, 0, time.UTC)
	engine := New("macos", start)

	paused := engine.Execute(Command{Action: "scenario", ScenarioID: "pausing"}, start)
	if paused.Session == nil || paused.Session.Status != "PAUSED" || paused.Sync != "pending" || paused.BalanceSeconds == nil || *paused.BalanceSeconds != 120 {
		t.Fatalf("停止・同期待ちシナリオ = %#v", paused)
	}

	finished := engine.Execute(Command{Action: "finish"}, start)
	if finished.Session == nil || finished.Session.Status != "FINALIZED" {
		t.Fatalf("オンライン終了後のセッション = %#v、FINALIZEDを期待", finished.Session)
	}
	if finished.Sync != "synced" || finished.BalanceSeconds == nil || *finished.BalanceSeconds != 0 {
		t.Fatalf("オンライン終了後の同期・残高 = sync:%q balance:%v、synced/0を期待", finished.Sync, finished.BalanceSeconds)
	}
	if finished.Result == nil || finished.Result.DiscardedSeconds != 120 {
		t.Fatalf("終了結果 = %#v、破棄120秒を期待", finished.Result)
	}
}

func TestEngineRequiresPermissionAndNetworkToStart(t *testing.T) {
	tests := []struct {
		name    string
		prepare func(*Engine, time.Time) Snapshot
	}{
		{
			name: "permission denied",
			prepare: func(engine *Engine, now time.Time) Snapshot {
				return engine.Execute(Command{Action: "scenario", ScenarioID: "denied"}, now)
			},
		},
		{
			name: "offline",
			prepare: func(engine *Engine, now time.Time) Snapshot {
				return engine.Execute(Command{Action: "connection"}, now)
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			now := time.Date(2026, time.October, 24, 15, 0, 0, 0, time.UTC)
			engine := New("macos", now)
			prepared := test.prepare(engine, now)
			if prepared.Actions["start"].Allowed {
				t.Fatal("権限拒否またはオフライン状態で開始が許可されている")
			}

			state := engine.Execute(Command{Action: "start"}, now)
			if state.Session != nil || state.Failure == nil || state.Failure.Code != "invalid_state" {
				t.Fatalf("開始拒否後の状態 = %#v、セッションなしとinvalid_stateを期待", state)
			}
		})
	}
}

func TestEngineStartNameLengthBoundary(t *testing.T) {
	now := time.Date(2026, time.October, 24, 16, 0, 0, 0, time.UTC)
	makeName := func(length int) string {
		runes := make([]rune, length)
		for index := range runes {
			runes[index] = 'あ'
		}
		return string(runes)
	}

	accepted := New("macos", now).Execute(Command{Action: "start", Name: makeName(80)}, now)
	if accepted.Session == nil || len([]rune(accepted.Session.Name)) != 80 {
		t.Fatalf("80文字の作業名が受理されない: %#v", accepted)
	}

	rejected := New("macos", now).Execute(Command{Action: "start", Name: makeName(81)}, now)
	if rejected.Session != nil || rejected.Failure == nil || rejected.Failure.Code != "invalid_input" {
		t.Fatalf("81文字の作業名が拒否されない: %#v", rejected)
	}
}
