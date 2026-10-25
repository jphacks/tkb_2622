package session

type Task struct {
	ID                  string `json:"id"`
	Name                string `json:"name"`
	Category            string `json:"category"`
	Mode                string `json:"mode"`
	PlannedSeconds      int    `json:"plannedSeconds"`
	MinimumSeconds      int    `json:"minimumSeconds"`
	Version             int64  `json:"version"`
	PendingOperationID  string `json:"pendingOperationId,omitempty"`
	PendingSettingsHash string `json:"pendingSettingsHash,omitempty"`
}

type WorkSession struct {
	ID              string           `json:"id"`
	Name            string           `json:"name"`
	Status          string           `json:"status"`
	Task            Task             `json:"task"`
	ServerVersion   int64            `json:"serverVersion,omitempty"`
	TrackingOnly    bool             `json:"trackingOnly,omitempty"`
	Classifications []Classification `json:"classifications,omitempty"`
	RulesVersion    string           `json:"rulesVersion,omitempty"`
	ElapsedSeconds  int              `json:"elapsedSeconds"`
	Evaluation      string           `json:"evaluation"`
}

type CloudSession struct {
	ID                string `json:"id"`
	TaskID            string `json:"taskId"`
	Name              string `json:"name"`
	Status            string `json:"status"`
	Version           int64  `json:"version"`
	OwnedByThisDevice bool   `json:"ownedByThisDevice"`
	TrackingOnly      bool   `json:"trackingOnly"`
	Message           string `json:"message"`
}

type IPhoneRestrictionState struct {
	SessionID        string `json:"sessionId"`
	DeviceID         string `json:"deviceId"`
	ControlRevision  int64  `json:"controlRevision"`
	DesiredMode      string `json:"desiredMode"`
	AppliedRevision  int64  `json:"appliedRevision"`
	ShieldStatus     string `json:"shieldStatus"`
	PermissionStatus string `json:"permissionStatus"`
	LastAppliedAt    string `json:"lastAppliedAt,omitempty"`
	LastReportedAt   string `json:"lastReportedAt,omitempty"`
	FailureReason    string `json:"failureReason,omitempty"`
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

type MonitorStatus struct {
	State       string `json:"state"`
	AppID       string `json:"appId"`
	AppName     string `json:"appName"`
	BrowserName string `json:"browserName"`
	Domain      string `json:"domain"`
	LastSample  string `json:"lastSample"`
	SampleCount int    `json:"sampleCount"`
	Message     string `json:"message"`
}

type Classification struct {
	Name     string `json:"name"`
	AppID    string `json:"appId,omitempty"`
	Domain   string `json:"domain,omitempty"`
	Category string `json:"category"`
}

type Settings struct {
	Tasks           []Task           `json:"tasks"`
	SelectedTaskID  string           `json:"selectedTaskId"`
	Classifications []Classification `json:"classifications"`
}

type Result struct {
	SessionID           string   `json:"sessionId"`
	Name                string   `json:"name"`
	Status              string   `json:"status"`
	StartedAt           string   `json:"startedAt,omitempty"`
	EndedAt             string   `json:"endedAt,omitempty"`
	ElapsedSeconds      int      `json:"elapsedSeconds"`
	TaskSeconds         int      `json:"taskSeconds"`
	RelatedSeconds      int      `json:"relatedSeconds"`
	WorkSeconds         int      `json:"workSeconds"`
	DistractedSeconds   int      `json:"distractedSeconds"`
	UncertainSeconds    int      `json:"uncertainSeconds"`
	InactiveSeconds     int      `json:"inactiveSeconds"`
	EvaluatorVersion    string   `json:"evaluatorVersion,omitempty"`
	B100                *float64 `json:"b100,omitempty"`
	Q                   *float64 `json:"q,omitempty"`
	WorkRate            *float64 `json:"workRate,omitempty"`
	EarnedSeconds       int      `json:"earnedSeconds"`
	UsedSeconds         int      `json:"usedSeconds"`
	DiscardedSeconds    int      `json:"discardedSeconds"`
	RewardStatus        string   `json:"rewardStatus,omitempty"`
	RewardReason        string   `json:"rewardReason,omitempty"`
	RewardPolicyVersion int32    `json:"rewardPolicyVersion,omitempty"`
	RewardGrantStopped  bool     `json:"rewardGrantStopped,omitempty"`
}

type RewardSummary struct {
	EarnedSeconds    int
	SpentSeconds     int
	DiscardedSeconds int
	Status           string
	Reason           string
	PolicyVersion    int32
	GrantStopped     bool
}

type Snapshot struct {
	Revision               int                     `json:"revision"`
	Platform               string                  `json:"platform"`
	Mode                   string                  `json:"mode"`
	UpdatedAt              string                  `json:"updatedAt"`
	Session                *WorkSession            `json:"session"`
	CloudSession           *CloudSession           `json:"cloudSession,omitempty"`
	IPhoneRestriction      *IPhoneRestrictionState `json:"iPhoneRestriction,omitempty"`
	IPhoneRestrictionError string                  `json:"iPhoneRestrictionError,omitempty"`
	CloudOperationPending  bool                    `json:"cloudOperationPending,omitempty"`
	BalanceSeconds         *int                    `json:"balanceSeconds"`
	Sync                   string                  `json:"sync"`
	Permission             string                  `json:"permission"`
	Online                 bool                    `json:"online"`
	Monitor                MonitorStatus           `json:"monitor"`
	RestrictionDesired     string                  `json:"restrictionDesired"`
	RestrictionConfirmed   bool                    `json:"restrictionConfirmed"`
	Settings               Settings                `json:"settings"`
	History                []Result                `json:"history"`
	HistoryError           string                  `json:"historyError,omitempty"`
	Result                 *Result                 `json:"result"`
	Actions                map[string]Capability   `json:"actions"`
	Failure                *Failure                `json:"failure"`
	Account                AccountState            `json:"account"`
}

type AccountState struct {
	Status           string `json:"status"`
	Email            string `json:"email"`
	DeviceRegistered bool   `json:"deviceRegistered"`
	Message          string `json:"message"`
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
