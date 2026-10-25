package session

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/jphacks/tkb_2622/desktop/fixtures"
)

// Engineは表示確認用のデモとローカル計測を管理し，クラウドの業務状態を確定しない．
type Engine struct {
	state             Snapshot
	fixtures          FixtureSet
	lastTick          time.Time
	sequence          int
	localStorageReady bool
}

func New(platform string, now time.Time) *Engine {
	var data FixtureSet
	if err := json.Unmarshal(fixtures.Scenarios, &data); err != nil {
		panic(err)
	}
	e := &Engine{fixtures: data, lastTick: now, localStorageReady: true}
	e.state = Snapshot{Platform: platform, Mode: "demo", Settings: Settings{
		Tasks: data.Tasks, SelectedTaskID: data.Task.ID, Classifications: data.Classifications,
	}, History: []Result{}, Monitor: MonitorStatus{State: "demo"}}
	e.applyScenario("ready")
	e.touch(now)
	return e
}

func terminal(status string) bool {
	return status == "FINALIZED" || status == "ABORTED"
}

func (e *Engine) Snapshot() Snapshot {
	e.updateActions()
	// 呼び出し元による変更と，イベント送信中の状態更新を分離する．
	data, _ := json.Marshal(e.state)
	var copy Snapshot
	_ = json.Unmarshal(data, &copy)
	return copy
}

func (e *Engine) SetMode(mode string, now time.Time) {
	e.state.Mode = mode
	e.touch(now)
}

func (e *Engine) SetLocalStorageReady(ready bool, now time.Time) {
	if e.localStorageReady == ready {
		return
	}
	e.localStorageReady = ready
	if ready && e.state.Failure != nil && e.state.Failure.Code == "local_storage" {
		e.state.Failure = nil
	}
	e.touch(now)
}

func (e *Engine) SetAccount(account AccountState, now time.Time) {
	e.state.Account = account
	if account.Status != "signedIn" {
		e.state.BalanceSeconds = nil
	}
	e.touch(now)
}

func (e *Engine) SetTasks(tasks []Task, selectedTaskID string, now time.Time) bool {
	settings := e.state.Settings
	settings.Tasks = append([]Task(nil), tasks...)
	settings.SelectedTaskID = selectedTaskID
	selectedExists := false
	for _, task := range settings.Tasks {
		if task.ID == settings.SelectedTaskID {
			selectedExists = true
			break
		}
	}
	if !selectedExists {
		settings.SelectedTaskID = ""
		if len(settings.Tasks) > 0 {
			settings.SelectedTaskID = settings.Tasks[0].ID
		}
	}
	normalized, valid := normalizeSettings(settings)
	if !valid {
		return false
	}
	e.state.Settings = normalized
	e.touch(now)
	return true
}

func (e *Engine) Restore(snapshot Snapshot, now time.Time) bool {
	if snapshot.Platform != e.state.Platform {
		return false
	}
	data, err := json.Marshal(snapshot)
	if err != nil {
		return false
	}
	var restored Snapshot
	if err := json.Unmarshal(data, &restored); err != nil {
		return false
	}
	if _, valid := normalizeSettings(restored.Settings); !valid {
		return false
	}
	if restored.Session != nil && restored.Session.Status == "RUNNING" {
		restored.Session.Status = "PAUSED"
		restored.Session.Evaluation = "pending"
		if restored.Mode == "local-monitor" {
			restored.Monitor.State = "paused"
		}
	}
	e.state = restored
	e.lastTick = now
	e.touch(now)
	e.updateActions()
	return true
}

func (e *Engine) SetMonitor(status MonitorStatus, now time.Time) {
	e.state.Monitor = status
	if status.State == "running" && status.Message == "" && e.state.Failure != nil && e.state.Failure.Code == "monitor_sample" {
		e.state.Failure = nil
	}
	e.touch(now)
}

func (e *Engine) SetServerSession(id string, task Task, version int64, now time.Time) bool {
	if e.state.Session == nil || e.state.Session.ID != id || version < 0 {
		return false
	}
	e.state.Session.ServerVersion = version
	if task.ID != "" {
		e.state.Session.Task = task
	}
	if e.state.Session.Name == "" {
		e.state.Session.Name = task.Name
	}
	e.touch(now)
	return true
}

func (e *Engine) SetServerVersion(id string, version int64, now time.Time) bool {
	if e.state.Session == nil || e.state.Session.ID != id || version < 0 {
		return false
	}
	e.state.Session.ServerVersion = version
	e.touch(now)
	return true
}

func (e *Engine) SetTrackingOnly(id string, trackingOnly bool, now time.Time) bool {
	if e.state.Session == nil || e.state.Session.ID != id {
		return false
	}
	e.state.Session.TrackingOnly = trackingOnly
	e.touch(now)
	return true
}

func (e *Engine) SetCloudBalance(id string, seconds int, now time.Time) bool {
	if seconds < 0 {
		return false
	}
	if e.state.Session == nil || e.state.Session.ID != id {
		if e.state.CloudSession == nil || e.state.CloudSession.ID != id {
			return false
		}
	}
	e.state.BalanceSeconds = &seconds
	e.touch(now)
	return true
}

func (e *Engine) ClearCloudBalance(now time.Time) {
	e.state.BalanceSeconds = nil
	e.touch(now)
}

func (e *Engine) SetSyncStatus(status string, now time.Time) {
	if status != "synced" && status != "pending" && status != "failed" {
		return
	}
	e.state.Sync = status
	if status == "synced" && e.state.Failure != nil && e.state.Failure.Code == "cloud_activity_sync" {
		e.state.Failure = nil
	}
	e.touch(now)
}

func (e *Engine) SetCloudOperationPending(pending bool, now time.Time) {
	e.state.CloudOperationPending = pending
	if pending && e.state.Result != nil && e.state.Session != nil && e.state.Result.SessionID == e.state.Session.ID &&
		(e.state.Session.Status == "FINALIZED" || e.state.Session.Status == "ABORTED") && e.state.Result.RewardStatus == "" {
		// 報酬結果はAPI応答が返るまで確定表示しない。
		e.state.Result.RewardStatus = "queued"
	}
	e.touch(now)
}

func (e *Engine) SetResultReward(id string, reward RewardSummary, now time.Time) bool {
	if reward.EarnedSeconds < 0 || reward.SpentSeconds < 0 || reward.DiscardedSeconds < 0 {
		return false
	}
	updated := false
	if e.state.Result != nil && e.state.Result.SessionID == id {
		applyRewardSummary(e.state.Result, reward)
		updated = true
	}
	for index := range e.state.History {
		if e.state.History[index].SessionID == id {
			applyRewardSummary(&e.state.History[index], reward)
			updated = true
		}
	}
	if updated {
		if e.state.Session != nil && e.state.Session.ID == id {
			e.state.Session.Evaluation = "complete"
		}
		e.touch(now)
	}
	return updated
}

func applyRewardSummary(result *Result, reward RewardSummary) {
	result.EarnedSeconds = reward.EarnedSeconds
	result.UsedSeconds = reward.SpentSeconds
	result.DiscardedSeconds = reward.DiscardedSeconds
	result.RewardStatus = reward.Status
	result.RewardReason = reward.Reason
	result.RewardPolicyVersion = reward.PolicyVersion
	result.RewardGrantStopped = reward.GrantStopped
}

func (e *Engine) SetCloudSession(current *CloudSession, now time.Time) {
	if current == nil {
		e.state.CloudSession = nil
	} else {
		copy := *current
		e.state.CloudSession = &copy
	}
	e.touch(now)
}

func (e *Engine) SetIPhoneRestrictionState(state *IPhoneRestrictionState, failure string, now time.Time) {
	if state == nil {
		e.state.IPhoneRestriction = nil
	} else {
		copy := *state
		e.state.IPhoneRestriction = &copy
	}
	e.state.IPhoneRestrictionError = failure
	e.touch(now)
}

// SetCloudHistory merges the server's authoritative session summaries with
// local-only history entries that have not been uploaded to the server.
func (e *Engine) SetCloudHistory(history []Result, now time.Time) {
	merged := append([]Result(nil), history...)
	known := make(map[string]int, len(history))
	for index, item := range history {
		known[item.SessionID] = index
	}
	for _, item := range e.state.History {
		if index, exists := known[item.SessionID]; exists {
			if len(merged[index].ActivityDetails) == 0 && len(item.ActivityDetails) > 0 {
				merged[index].ActivityDetails = append([]ActivityDetail(nil), item.ActivityDetails...)
			}
			continue
		}
		merged = append(merged, item)
	}
	sort.SliceStable(merged, func(i, j int) bool {
		if merged[i].StartedAt == "" {
			return false
		}
		if merged[j].StartedAt == "" {
			return true
		}
		return merged[i].StartedAt > merged[j].StartedAt
	})
	e.state.History = merged
	e.state.HistoryError = ""
	e.touch(now)
}

func (e *Engine) SetHistoryError(message string, now time.Time) {
	e.state.HistoryError = message
	e.touch(now)
}

func (e *Engine) SetFailure(code, message string, retryable bool, now time.Time) {
	e.fail(code, message, retryable)
	e.touch(now)
}

func (e *Engine) ApplyLocalEvaluation(result Result, now time.Time) bool {
	if e.state.Mode != "local-monitor" || e.state.Session == nil || e.state.Session.ID != result.SessionID || result.EvaluatorVersion == "" {
		return false
	}
	e.state.Session.Evaluation = "complete"
	e.state.Result = &result
	for index := range e.state.History {
		if e.state.History[index].SessionID == result.SessionID {
			e.state.History[index] = result
			e.touch(now)
			return true
		}
	}
	e.state.History = append([]Result{result}, e.state.History...)
	e.touch(now)
	return true
}

func (e *Engine) FailLocalEvaluation(sessionID string, now time.Time) {
	if e.state.Mode != "local-monitor" || e.state.Session == nil || e.state.Session.ID != sessionID {
		return
	}
	e.state.Session.Evaluation = "failed"
	e.fail("local_evaluation", "ローカルの5分類評価に失敗しました。設定と保存済み観測データを確認してください。", false)
	e.touch(now)
}

func (e *Engine) PauseForShutdown(now time.Time) {
	if e.state.Session == nil || e.state.Session.Status != "RUNNING" {
		return
	}
	e.state.Session.Status = "PAUSED"
	e.state.Session.Evaluation = "pending"
	if e.state.Mode == "local-monitor" && e.state.Monitor.State == "running" {
		e.state.Monitor.State = "paused"
	}
	e.lastTick = now
	e.touch(now)
}

func (e *Engine) Tick(now time.Time) bool {
	if e.state.Session == nil || e.state.Session.Status != "RUNNING" {
		e.lastTick = now
		return false
	}
	seconds := int(now.Sub(e.lastTick).Seconds())
	if seconds <= 0 {
		return false
	}
	e.state.Session.ElapsedSeconds += seconds
	e.lastTick = e.lastTick.Add(time.Duration(seconds) * time.Second)
	e.touch(now)
	return true
}

func normalizeSettings(input Settings) (Settings, bool) {
	settings := Settings{
		SelectedTaskID:  strings.TrimSpace(input.SelectedTaskID),
		Tasks:           make([]Task, len(input.Tasks)),
		Classifications: make([]Classification, len(input.Classifications)),
	}
	taskIDs := make(map[string]struct{}, len(input.Tasks))
	selectedTaskExists := false
	for index, task := range input.Tasks {
		task.ID = strings.TrimSpace(task.ID)
		task.Name = strings.TrimSpace(task.Name)
		if task.ID == "" || task.Name == "" || len([]rune(task.Name)) > 80 || task.MinimumSeconds < 1 || task.MinimumSeconds > 86400 || task.PlannedSeconds < task.MinimumSeconds || task.PlannedSeconds > 86400 {
			return Settings{}, false
		}
		if _, exists := taskIDs[task.ID]; exists {
			return Settings{}, false
		}
		taskIDs[task.ID] = struct{}{}
		selectedTaskExists = selectedTaskExists || task.ID == settings.SelectedTaskID
		settings.Tasks[index] = task
	}
	if len(settings.Tasks) == 0 {
		if settings.SelectedTaskID != "" {
			return Settings{}, false
		}
	} else if !selectedTaskExists {
		return Settings{}, false
	}
	classificationNames := make(map[string]struct{}, len(input.Classifications))
	classificationTargets := make(map[string]struct{}, len(input.Classifications))
	for index, classification := range input.Classifications {
		classification.Name = strings.TrimSpace(classification.Name)
		classification.AppID = strings.TrimSpace(classification.AppID)
		classification.Domain = strings.TrimSpace(classification.Domain)
		if classification.Name == "" || len([]rune(classification.Name)) > 200 || len(classification.AppID) > 256 || len(classification.Domain) > 253 ||
			(classification.Category != "work" && classification.Category != "related" && classification.Category != "distraction" && classification.Category != "uncertain") ||
			(classification.Domain != "" && !browserAppID(classification.AppID)) ||
			(classification.AppID != "" && browserAppID(classification.AppID) && classification.Domain == "") {
			return Settings{}, false
		}
		if _, exists := classificationNames[classification.Name]; exists {
			return Settings{}, false
		}
		classificationNames[classification.Name] = struct{}{}
		if classification.AppID != "" {
			target := strings.ToLower(classification.AppID) + "|" + strings.ToLower(classification.Domain)
			if _, exists := classificationTargets[target]; exists {
				return Settings{}, false
			}
			classificationTargets[target] = struct{}{}
		}
		settings.Classifications[index] = classification
	}
	return settings, true
}

func (e *Engine) Execute(command Command, now time.Time) Snapshot {
	return e.ExecuteWithSessionID(command, "", now)
}

func (e *Engine) ExecuteWithSessionID(command Command, requestedSessionID string, now time.Time) Snapshot {
	e.Tick(now)
	e.state.Failure = nil
	e.updateActions()
	if capability, exists := e.state.Actions[command.Action]; exists && !capability.Allowed {
		e.fail("invalid_state", capability.Reason, false)
		e.touch(now)
		return e.Snapshot()
	}
	switch command.Action {
	case "scenario":
		if !e.applyScenario(command.ScenarioID) {
			e.fail("invalid_input", "存在しないデモシナリオです。", false)
		}
	case "start":
		if len([]rune(strings.TrimSpace(command.Name))) > 80 {
			e.fail("invalid_input", "作業名は80文字以内で入力してください。", false)
			break
		}
		e.sequence++
		var task Task
		for _, candidate := range e.state.Settings.Tasks {
			if candidate.ID == e.state.Settings.SelectedTaskID {
				task = candidate
			}
		}
		sessionID := requestedSessionID
		if sessionID == "" {
			sessionID = fmt.Sprintf("demo-%d-%d", now.UnixNano(), e.sequence)
		}
		e.state.Session = &WorkSession{
			ID: sessionID, Name: strings.TrimSpace(command.Name), Status: "RUNNING", Task: task,
			Classifications: append([]Classification(nil), e.state.Settings.Classifications...),
			RulesVersion:    "desktop-classifications-v1", Evaluation: "pending",
		}
		if e.state.Session.Name == "" {
			e.state.Session.Name = task.Name
		}
		e.state.Result = nil
		e.state.BalanceSeconds = nil
		if e.state.Mode == "demo" {
			e.state.RestrictionDesired = "restricted"
		}
	case "pause":
		e.state.Session.Status = "PAUSED"
		e.state.Session.Evaluation = "pending"
		e.state.Sync = "pending"
	case "retry":
		e.state.Online = true
		e.state.Sync = "synced"
		if s := e.state.Session; s != nil {
			switch s.Status {
			case "COMPLETED_LOCAL":
				s.Status = "FINALIZED"
				e.complete()
			case "ABORTED_LOCAL":
				s.Status = "ABORTED"
				e.complete()
			default:
				s.Evaluation = "complete"
			}
		}
	case "resume":
		e.state.Session.Status = "RUNNING"
		e.state.Session.Evaluation = "pending"
		if e.state.Mode == "demo" {
			e.state.RestrictionDesired = "restricted"
		}
	case "finish", "abort":
		s := e.state.Session
		if command.Action == "abort" {
			s.Status = "ABORTED"
		} else {
			s.Status = "FINALIZED"
		}
		if !e.state.Online && e.state.Mode != "local-monitor" {
			if command.Action == "abort" {
				s.Status = "ABORTED_LOCAL"
			} else {
				s.Status = "COMPLETED_LOCAL"
			}
			e.state.Sync = "pending"
		} else {
			e.complete()
		}
	case "connection":
		e.state.Online = !e.state.Online
	case "saveSettings":
		settings, valid := normalizeSettings(command.Settings)
		if !valid {
			e.fail("invalid_input", "設定内容を確認してください。", false)
			break
		}
		e.state.Settings = settings
	case "saveTask":
		task := command.Task
		task.Name = strings.TrimSpace(task.Name)
		if task.Name == "" || len([]rune(task.Name)) > 80 || task.MinimumSeconds < 1 || task.MinimumSeconds > 86400 || task.PlannedSeconds < task.MinimumSeconds || task.PlannedSeconds > 86400 {
			e.fail("invalid_input", "タスク名は1〜80文字、最小時間は1〜86400秒、予定時間は最小時間以上・86400秒以下で入力してください。", false)
			break
		}
		if task.ID == "" {
			e.sequence++
			task.ID = fmt.Sprintf("task-%d-%d", now.UnixNano(), e.sequence)
		}
		found := false
		for i, existing := range e.state.Settings.Tasks {
			if existing.ID == task.ID {
				e.state.Settings.Tasks[i] = task
				found = true
			}
		}
		if !found {
			e.state.Settings.Tasks = append(e.state.Settings.Tasks, task)
		}
		e.state.Settings.SelectedTaskID = task.ID
	case "classification":
		value := command.Classification
		value.Name = strings.TrimSpace(value.Name)
		if value.Name == "" || len([]rune(value.Name)) > 200 || (value.Category != "work" && value.Category != "distraction" && value.Category != "uncertain") {
			e.fail("invalid_input", "分類の名前と種別を確認してください。", false)
			break
		}
		found := false
		for i, item := range e.state.Settings.Classifications {
			if item.Name == value.Name {
				e.state.Settings.Classifications[i] = value
				found = true
			}
		}
		if !found {
			e.state.Settings.Classifications = append(e.state.Settings.Classifications, value)
		}
	default:
		e.fail("unsupported", "この操作はまだ対応していません。", false)
	}
	if command.Action == "start" || command.Action == "resume" || command.Action == "pause" || command.Action == "finish" || command.Action == "abort" || command.Action == "scenario" {
		e.lastTick = now
	}
	e.touch(now)
	return e.Snapshot()
}

func (e *Engine) complete() {
	s := e.state.Session
	if e.state.Mode == "local-monitor" {
		s.Evaluation = "pending"
		e.state.Sync = "pending"
		e.state.RestrictionDesired = "unknown"
	} else {
		s.Evaluation = "complete"
		e.state.Sync = "synced"
		e.state.RestrictionDesired = "unrestricted"
	}
	discarded := 0
	if e.state.BalanceSeconds != nil {
		discarded = *e.state.BalanceSeconds
	}
	zero := 0
	e.state.BalanceSeconds = &zero
	// 活動分類未接続のため全時間を保留とし，作業時間や報酬を推定しない．
	result := Result{SessionID: s.ID, Name: s.Name, Status: s.Status, ElapsedSeconds: s.ElapsedSeconds, UncertainSeconds: s.ElapsedSeconds, DiscardedSeconds: discarded}
	e.state.Result = &result
	for _, previous := range e.state.History {
		if previous.SessionID == s.ID {
			return
		}
	}
	e.state.History = append([]Result{result}, e.state.History...)
}

func (e *Engine) applyScenario(id string) bool {
	for _, scenario := range e.fixtures.Scenarios {
		if scenario.ID != id {
			continue
		}
		e.state.Session = nil
		e.state.Result = nil
		e.state.BalanceSeconds = scenario.BalanceSeconds
		e.state.Sync, e.state.Permission, e.state.Online = scenario.Sync, scenario.Permission, scenario.Online
		e.state.RestrictionDesired, e.state.RestrictionConfirmed = "unknown", false
		if scenario.Status != "" {
			e.sequence++
			e.state.Session = &WorkSession{ID: fmt.Sprintf("fixture-%s-%d", id, e.sequence), Name: e.fixtures.Task.Name, Task: e.fixtures.Task, Status: scenario.Status, ElapsedSeconds: scenario.ElapsedSeconds, Evaluation: scenario.Evaluation}
			e.state.RestrictionDesired = "restricted"
			if terminal(scenario.Status) {
				e.complete()
			}
		}
		if scenario.ID == "failure" {
			e.fail("unavailable", "デモ：記録の送信に失敗しました。再試行できます。", true)
		}
		return true
	}
	return false
}

func (e *Engine) updateActions() {
	s := e.state.Session
	active := s != nil && (s.Status == "RUNNING" || s.Status == "PAUSED")
	available := s == nil || terminal(s.Status)
	cloudManaged := s != nil && s.ServerVersion > 0
	cloudOperationPending := e.state.CloudOperationPending
	cloudRecovery := e.state.CloudSession != nil
	monitorReady := e.state.Mode != "local-monitor" || e.state.Monitor.State == "ready" || e.state.Monitor.State == "finished" || e.state.Monitor.State == "aborted"
	monitorCanResume := e.state.Mode != "local-monitor" || e.state.Monitor.State == "paused" || e.state.Monitor.State == "ready"
	storageReady := e.state.Mode != "local-monitor" || e.localStorageReady
	rules := map[string]bool{
		"start":  available && monitorReady && storageReady && !cloudRecovery && !cloudOperationPending && e.state.Account.Status != "error" && (e.state.Mode == "local-monitor" || e.state.Online) && e.state.Permission != "denied",
		"pause":  active && s.Status == "RUNNING" && !cloudOperationPending,
		"resume": active && s.Status == "PAUSED" && monitorCanResume && storageReady && e.state.Permission != "denied" && !cloudOperationPending && (cloudManaged || e.state.Mode == "local-monitor" || e.state.Online && e.state.Sync == "synced" && s.Evaluation == "complete"),
		"finish": active && s.ElapsedSeconds >= s.Task.MinimumSeconds && !cloudOperationPending,
		"abort":  active && !cloudOperationPending && (e.state.CloudSession == nil || e.state.CloudSession.ID != s.ID || e.state.CloudSession.OwnedByThisDevice),
		"retry":  e.state.Mode != "local-monitor" && e.state.Sync != "synced",
	}
	if !active && cloudRecovery {
		rules["abort"] = e.state.CloudSession.OwnedByThisDevice
	}
	e.state.Actions = map[string]Capability{}
	for action, allowed := range rules {
		reason := ""
		if !allowed {
			reason = "現在の状態では操作できません。"
		}
		e.state.Actions[action] = Capability{Allowed: allowed, Reason: reason}
	}
	if !rules["start"] && !e.state.Online {
		e.state.Actions["start"] = Capability{Reason: "開始にはオンライン接続が必要です。"}
	}
	if !rules["start"] && e.state.Mode == "local-monitor" && !monitorReady {
		reason := e.state.Monitor.Message
		if reason == "" {
			reason = "macOS計測ヘルパーを利用できません。アプリ用ビルド手順を確認してください。"
		}
		e.state.Actions["start"] = Capability{Reason: reason}
	}
	if !rules["start"] && e.state.Mode == "local-monitor" && !storageReady {
		e.state.Actions["start"] = Capability{Reason: "作業状態を保存できません。保存先の権限を確認してください。"}
	}
	if !rules["start"] && cloudRecovery {
		e.state.Actions["start"] = Capability{Reason: "サーバーに未終了の作業があります。状態を確認してから開始してください。"}
	}
	if !rules["start"] && e.state.Account.Status == "error" {
		e.state.Actions["start"] = Capability{Reason: "ログイン状態を確認できません。設定から再接続してください。"}
	}
	if cloudOperationPending && active {
		message := "サーバーへの作業状態の同期が終わるまでお待ちください。"
		for _, action := range []string{"pause", "resume", "finish", "abort"} {
			e.state.Actions[action] = Capability{Reason: message}
		}
	}
	if active && s.Status == "PAUSED" && e.state.Mode == "local-monitor" && !storageReady {
		e.state.Actions["resume"] = Capability{Reason: "作業状態を保存できないため再開できません。保存先の権限を確認してください。"}
	}
	if active && s.Status == "PAUSED" && e.state.Mode == "local-monitor" && !monitorCanResume {
		reason := e.state.Monitor.Message
		if reason == "" {
			reason = "macOS計測ヘルパーを利用できません。アプリ用ビルド手順を確認してください。"
		}
		e.state.Actions["resume"] = Capability{Reason: reason}
	}
	if !rules["start"] && e.state.Permission == "denied" {
		e.state.Actions["start"] = Capability{Reason: "計測権限が拒否されています。設定を確認してください。"}
	}
	if active && !rules["finish"] && !cloudOperationPending {
		e.state.Actions["finish"] = Capability{Reason: "最小作業時間に達していません。"}
	}
}

func (e *Engine) touch(now time.Time) {
	e.state.Revision++
	e.state.UpdatedAt = now.UTC().Format(time.RFC3339)
}
func (e *Engine) fail(code, message string, retryable bool) {
	e.state.Failure = &Failure{Code: code, Message: message, Retryable: retryable}
}

func browserAppID(appID string) bool {
	switch strings.ToLower(appID) {
	case "com.google.chrome", "com.apple.safari":
		return true
	default:
		return false
	}
}
