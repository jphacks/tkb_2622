package session

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/jphacks/tkb_2622/desktop/fixtures"
)

// Engineは表示・結合確認用のデモであり，クラウドの業務状態を確定しない．
type Engine struct {
	state    Snapshot
	fixtures FixtureSet
	lastTick time.Time
	sequence int
}

func New(platform string, now time.Time) *Engine {
	var data FixtureSet
	if err := json.Unmarshal(fixtures.Scenarios, &data); err != nil {
		panic(err)
	}
	e := &Engine{fixtures: data, lastTick: now}
	e.state = Snapshot{Platform: platform, Mode: "demo", Settings: Settings{
		Tasks: data.Tasks, SelectedTaskID: data.Task.ID, Classifications: data.Classifications,
	}, History: []Result{}}
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
	if len(settings.Tasks) == 0 || !selectedTaskExists {
		return Settings{}, false
	}
	classificationNames := make(map[string]struct{}, len(input.Classifications))
	for index, classification := range input.Classifications {
		classification.Name = strings.TrimSpace(classification.Name)
		if classification.Name == "" || len([]rune(classification.Name)) > 200 || (classification.Category != "work" && classification.Category != "distraction" && classification.Category != "uncertain") {
			return Settings{}, false
		}
		if _, exists := classificationNames[classification.Name]; exists {
			return Settings{}, false
		}
		classificationNames[classification.Name] = struct{}{}
		settings.Classifications[index] = classification
	}
	return settings, true
}

func (e *Engine) Execute(command Command, now time.Time) Snapshot {
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
		e.state.Session = &WorkSession{ID: fmt.Sprintf("demo-%d-%d", now.UnixNano(), e.sequence), Name: strings.TrimSpace(command.Name), Status: "RUNNING", Task: task, Evaluation: "pending"}
		if e.state.Session.Name == "" {
			e.state.Session.Name = task.Name
		}
		e.state.Result = nil
		e.state.BalanceSeconds = nil
		e.state.RestrictionDesired = "restricted"
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
		e.state.RestrictionDesired = "restricted"
	case "finish", "abort":
		s := e.state.Session
		if command.Action == "abort" {
			s.Status = "ABORTED"
		} else {
			s.Status = "FINALIZED"
		}
		if !e.state.Online {
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
	s.Evaluation = "complete"
	e.state.Sync = "synced"
	e.state.RestrictionDesired = "unrestricted"
	discarded := 0
	if e.state.BalanceSeconds != nil { discarded = *e.state.BalanceSeconds }
	zero := 0
	e.state.BalanceSeconds = &zero
	// 計測未接続のため全時間を保留とし，作業時間や報酬を推定しない．
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
	rules := map[string]bool{
		"start":  available && e.state.Online && e.state.Permission != "denied",
		"pause":  active && s.Status == "RUNNING",
		"resume": active && s.Status == "PAUSED" && e.state.Online && e.state.Sync == "synced" && s.Evaluation == "complete" && e.state.Permission != "denied",
		"finish": active && s.ElapsedSeconds >= s.Task.MinimumSeconds,
		"abort":  active,
		"retry":  e.state.Sync != "synced",
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
	if !rules["start"] && e.state.Permission == "denied" {
		e.state.Actions["start"] = Capability{Reason: "計測権限が拒否されています。設定を確認してください。"}
	}
	if active && !rules["finish"] {
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
