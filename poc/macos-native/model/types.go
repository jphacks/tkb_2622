// Package model は取得元やUIに依存しない観測と分析の形式を定義する。
package model

import "time"

const SchemaVersion = "1"

type Snapshot struct {
	SchemaVersion   string     `json:"schema_version"`
	Source          string     `json:"source"`
	SampleStartedAt time.Time  `json:"sample_started_at"`
	ObservedAt      time.Time  `json:"observed_at"`
	ReceivedAt      time.Time  `json:"received_at"`
	IdleObservedAt  time.Time  `json:"idle_observed_at"`
	AppID           *string    `json:"app_id"`
	AppName         *string    `json:"app_name"`
	IdleSeconds     *float64   `json:"idle_seconds"`
	BrowserName     *string    `json:"browser_name"`
	BrowserDomain   *string    `json:"browser_domain"`
	TabID           *string    `json:"tab_id"`
	BrowserStatus   string     `json:"browser_status"`
	Audible         *bool      `json:"audible"`
	LockState       *bool      `json:"lock_state"`
	SleepState      *bool      `json:"sleep_state"`
	PowerEvent      *string    `json:"power_event,omitempty"`
	PowerObservedAt *time.Time `json:"power_observed_at,omitempty"`
	Reasons         []string   `json:"reasons"`
}

type Capture struct {
	SchemaVersion string     `json:"schema_version"`
	Source        string     `json:"source"`
	StartAt       time.Time  `json:"start_at"`
	EndAt         time.Time  `json:"end_at"`
	PollSeconds   float64    `json:"poll_seconds"`
	Snapshots     []Snapshot `json:"snapshots"`
	Errors        []Failure  `json:"errors"`
}

type Failure struct {
	ReceivedAt time.Time `json:"received_at"`
	Reason     string    `json:"reason"`
}

type Event struct {
	SchemaVersion string    `json:"schema_version"`
	Source        string    `json:"source"`
	StartAt       time.Time `json:"start_at"`
	EndAt         time.Time `json:"end_at"`
	ObservedAt    time.Time `json:"observed_at"`
	ReceivedAt    time.Time `json:"received_at"`
	AppID         *string   `json:"app_id"`
	AppName       *string   `json:"app_name"`
	BrowserName   *string   `json:"browser_name"`
	BrowserDomain *string   `json:"browser_domain"`
	TabID         *string   `json:"tab_id"`
	IdleSeconds   *float64  `json:"idle_seconds"`
	AFKStatus     *string   `json:"afk_status"`
	Quality       string    `json:"quality"`
	Reasons       []string  `json:"reasons"`
}

type Interval struct {
	StartAt           time.Time        `json:"start_at"`
	EndAt             time.Time        `json:"end_at"`
	AppID             *string          `json:"app_id"`
	AppName           *string          `json:"app_name"`
	BrowserDomain     *string          `json:"browser_domain"`
	IdleOverThreshold map[string]*bool `json:"idle_over_threshold"`
	Quality           string           `json:"quality"`
	Reasons           []string         `json:"reasons"`
}

type Application struct {
	AppID                     string  `json:"app_id"`
	AppName                   *string `json:"app_name"`
	EstimatedFrontmostSeconds float64 `json:"estimated_frontmost_seconds"`
}

type Report struct {
	ElapsedSeconds         float64        `json:"elapsed_seconds"`
	SampledSeconds         float64        `json:"sampled_seconds"`
	UnknownSeconds         float64        `json:"unknown_seconds"`
	SnapshotCount          int            `json:"snapshot_count"`
	InvalidSnapshotCount   int            `json:"invalid_snapshot_count"`
	DuplicateSnapshotCount int            `json:"duplicate_snapshot_count"`
	LastSuccessAt          *time.Time     `json:"last_success_at"`
	Applications           []Application  `json:"applications"`
	Domains                []string       `json:"domains"`
	BrowserStates          map[string]int `json:"browser_states"`
	IdleThresholdSeconds   []int          `json:"idle_threshold_seconds"`
	Reasons                []string       `json:"reasons"`
}

type Analysis struct {
	SchemaVersion string     `json:"schema_version"`
	StartAt       time.Time  `json:"start_at"`
	EndAt         time.Time  `json:"end_at"`
	Events        []Event    `json:"events"`
	Intervals     []Interval `json:"intervals"`
	Report        Report     `json:"report"`
}
