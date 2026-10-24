package session

type Task struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	PlannedSeconds int    `json:"plannedSeconds"`
	MinimumSeconds int    `json:"minimumSeconds"`
}

type WorkSession struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Status         string `json:"status"`
	Task           Task   `json:"task"`
	ElapsedSeconds int    `json:"elapsedSeconds"`
	Evaluation     string `json:"evaluation"`
}

type Capability struct {
	Allowed bool   `json:"allowed"`
	Reason  string `json:"reason"`
}

type Failure struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
}

type Classification struct {
	Name     string `json:"name"`
	Category string `json:"category"`
}

type Settings struct {
	Tasks           []Task           `json:"tasks"`
	SelectedTaskID  string           `json:"selectedTaskId"`
	Classifications []Classification `json:"classifications"`
}

type Result struct {
	SessionID         string `json:"sessionId"`
	Name              string `json:"name"`
	Status            string `json:"status"`
	ElapsedSeconds    int    `json:"elapsedSeconds"`
	WorkSeconds       int    `json:"workSeconds"`
	DistractedSeconds int    `json:"distractedSeconds"`
	UncertainSeconds  int    `json:"uncertainSeconds"`
	EarnedSeconds     int    `json:"earnedSeconds"`
	UsedSeconds       int    `json:"usedSeconds"`
	DiscardedSeconds  int    `json:"discardedSeconds"`
}

type Snapshot struct {
	Revision             int                   `json:"revision"`
	Platform             string                `json:"platform"`
	Mode                 string                `json:"mode"`
	UpdatedAt            string                `json:"updatedAt"`
	Session              *WorkSession          `json:"session"`
	BalanceSeconds       *int                  `json:"balanceSeconds"`
	Sync                 string                `json:"sync"`
	Permission           string                `json:"permission"`
	Online               bool                  `json:"online"`
	RestrictionDesired   string                `json:"restrictionDesired"`
	RestrictionConfirmed bool                  `json:"restrictionConfirmed"`
	Settings             Settings              `json:"settings"`
	History              []Result              `json:"history"`
	Result               *Result               `json:"result"`
	Actions              map[string]Capability `json:"actions"`
	Failure              *Failure              `json:"failure"`
}

type Scenario struct {
	ID             string `json:"id"`
	Label          string `json:"label"`
	Status         string `json:"status"`
	ElapsedSeconds int    `json:"elapsedSeconds"`
	Evaluation     string `json:"evaluation"`
	Sync           string `json:"sync"`
	Permission     string `json:"permission"`
	Online         bool   `json:"online"`
	BalanceSeconds *int   `json:"balanceSeconds"`
}

type FixtureSet struct {
	Task            Task             `json:"task"`
	Tasks           []Task           `json:"tasks"`
	Classifications []Classification `json:"classifications"`
	Scenarios       []Scenario       `json:"scenarios"`
}

type Command struct {
	Action         string         `json:"action"`
	Name           string         `json:"name"`
	ScenarioID     string         `json:"scenarioId"`
	Task           Task           `json:"task"`
	Classification Classification `json:"classification"`
	Settings       Settings       `json:"settings"`
}
