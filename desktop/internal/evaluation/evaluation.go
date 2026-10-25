// Package evaluation adapts saved desktop observations to the shared offline evaluator.
package evaluation

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"focuspocket/macos-native/analysis"
	poc "focuspocket/macos-native/evaluation"
	"focuspocket/macos-native/model"

	"github.com/jphacks/tkb_2622/desktop/internal/monitor"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
)

const pollSeconds = 1

func Evaluate(records []monitor.Record, workSession session.WorkSession) (session.Result, error) {
	result, _, _, err := EvaluateDetailed(records, workSession, time.Time{})
	return result, err
}

type ActivitySegment struct {
	StartTime      time.Time
	EndTime        time.Time
	Classification string
	Reasons        []string
}

// EvaluateDetailed は確定済み記録またはクラウド送信用の一時区間を評価する。
func EvaluateDetailed(records []monitor.Record, workSession session.WorkSession, through time.Time) (session.Result, []ActivitySegment, string, error) {
	if !through.IsZero() && !hasTerminalRecord(records) {
		records = append(append([]monitor.Record(nil), records...), monitor.Record{
			Kind: "finished", SessionID: workSession.ID, RecordedAt: through,
		})
	}
	capture, pauses, evidence, err := makeCapture(records)
	if err != nil {
		return session.Result{}, nil, "", err
	}
	rules := make([]poc.Rule, 0, len(workSession.Classifications))
	for _, classification := range workSession.Classifications {
		if classification.AppID == "" || classification.Category == "uncertain" {
			continue
		}
		class := ""
		switch classification.Category {
		case "work":
			class = poc.RuleTask
		case "related":
			class = poc.RuleRelatedTransition
		case "distraction":
			class = poc.RuleDistraction
		default:
			return session.Result{}, nil, "", fmt.Errorf("unsupported classification category %q", classification.Category)
		}
		rules = append(rules, poc.Rule{AppID: classification.AppID, Domain: classification.Domain, Class: class})
	}
	mode := workSession.Task.Mode
	if mode == "" {
		mode = "NORMAL"
	}
	rulesVersion := workSession.RulesVersion
	if rulesVersion == "" {
		rulesVersion = "desktop-classifications-v1"
	}
	offlineSession := poc.Session{
		ID: workSession.ID,
		TaskSnapshot: poc.TaskSnapshot{
			ID: workSession.Task.ID, Name: workSession.Task.Name, Mode: mode,
			RulesVersion: rulesVersion, Rules: rules,
		},
		Pauses: pauses,
	}
	if err := poc.ValidateSession(offlineSession); err != nil {
		return session.Result{}, nil, "", fmt.Errorf("saved classification rules are invalid: %w", err)
	}
	observed := analysis.Analyze(capture)
	evaluated, err := poc.EvaluateWithEvidence(offlineSession, observed, evidence)
	if err != nil {
		return session.Result{}, nil, "", fmt.Errorf("activity evaluation failed: %w", err)
	}
	totals := roundTotals(evaluated.Totals, evaluated.ElapsedSeconds)
	result := session.Result{
		SessionID: workSession.ID, Name: workSession.Name, Status: workSession.Status,
		ElapsedSeconds: totals.elapsed, TaskSeconds: totals.task, RelatedSeconds: totals.related,
		WorkSeconds: totals.task + totals.related, DistractedSeconds: totals.distraction,
		UncertainSeconds: totals.unknown, InactiveSeconds: totals.inactive,
		EvaluatorVersion: evaluated.EvaluatorVersion,
		B100:             evaluated.B, Q: evaluated.Q, WorkRate: evaluated.WorkRate,
	}
	appNames := localAppNames(records)
	segments := make([]ActivitySegment, 0, len(evaluated.Segments))
	result.ActivityDetails = make([]session.ActivityDetail, 0, len(evaluated.Segments))
	for _, segment := range evaluated.Segments {
		classification, err := activityClass(segment.Class)
		if err != nil {
			return session.Result{}, nil, "", err
		}
		appID := strings.TrimSpace(stringValue(segment.AppID))
		appName := appNames[appID]
		domain := stringValue(segment.BrowserDomain)
		durationSeconds := int(math.Round(segment.EndAt.Sub(segment.StartAt).Seconds()))
		if durationSeconds < 0 {
			durationSeconds = 0
		}
		reasons := append([]string(nil), segment.Reasons...)
		segments = append(segments, ActivitySegment{
			StartTime: segment.StartAt, EndTime: segment.EndAt,
			Classification: classification, Reasons: reasons,
		})
		result.ActivityDetails = append(result.ActivityDetails, session.ActivityDetail{
			AppName: appName, Domain: domain, StartTime: segment.StartAt, EndTime: segment.EndAt,
			DurationSeconds: durationSeconds, Classification: classification, Reasons: reasons,
		})
	}
	return result, segments, evaluated.EvaluatorVersion, nil
}

func localAppNames(records []monitor.Record) map[string]string {
	appNames := make(map[string]string)
	for _, record := range records {
		if record.Observation == nil {
			continue
		}
		appID := strings.TrimSpace(stringValue(record.Observation.AppID))
		appName := strings.TrimSpace(stringValue(record.Observation.AppName))
		if appID != "" && appName != "" {
			appNames[appID] = appName
		}
	}
	return appNames
}

func stringValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func hasTerminalRecord(records []monitor.Record) bool {
	for _, record := range records {
		if record.Kind == "finished" || record.Kind == "aborted" {
			return true
		}
	}
	return false
}

func activityClass(class string) (string, error) {
	switch class {
	case poc.ClassTask:
		return "ACTIVITY_CLASS_TASK", nil
	case poc.ClassRelatedTransition:
		return "ACTIVITY_CLASS_RELATED_TRANSITION", nil
	case poc.ClassDistraction:
		return "ACTIVITY_CLASS_DISTRACTION", nil
	case poc.ClassUnknown:
		return "ACTIVITY_CLASS_UNKNOWN", nil
	case poc.ClassInactive:
		return "ACTIVITY_CLASS_IDLE", nil
	default:
		return "", fmt.Errorf("unsupported evaluated activity class %q", class)
	}
}

func makeCapture(records []monitor.Record) (model.Capture, []poc.TimeRange, []poc.EvidenceInterval, error) {
	capture := model.Capture{
		SchemaVersion: model.SchemaVersion, Source: "macos-native", PollSeconds: pollSeconds,
		Snapshots: []model.Snapshot{}, Errors: []model.Failure{},
	}
	var startAt, endAt time.Time
	var pauseStart *time.Time
	pauses := []poc.TimeRange{}
	for _, record := range records {
		switch record.Kind {
		case "started":
			if startAt.IsZero() {
				startAt = record.RecordedAt
			}
		case "sample":
			if record.Observation == nil {
				return model.Capture{}, nil, nil, errors.New("sample record has no observation")
			}
			capture.Snapshots = append(capture.Snapshots, toSnapshot(*record.Observation))
		case "sample_error":
			capture.Errors = append(capture.Errors, model.Failure{ReceivedAt: record.RecordedAt, Reason: "native_sample_failed"})
		case "paused":
			if pauseStart == nil {
				value := record.RecordedAt
				pauseStart = &value
			}
		case "resumed":
			if pauseStart != nil {
				if record.RecordedAt.After(*pauseStart) {
					pauses = append(pauses, poc.TimeRange{StartAt: *pauseStart, EndAt: record.RecordedAt})
				}
				pauseStart = nil
			}
		case "finished", "aborted":
			endAt = record.RecordedAt
			if pauseStart != nil {
				if endAt.After(*pauseStart) {
					pauses = append(pauses, poc.TimeRange{StartAt: *pauseStart, EndAt: endAt})
				}
				pauseStart = nil
			}
		}
	}
	if startAt.IsZero() || endAt.IsZero() || !endAt.After(startAt) {
		return model.Capture{}, nil, nil, errors.New("session capture has no valid start and finish range")
	}
	capture.StartAt = startAt
	capture.EndAt = endAt
	evidence := buildEvidence(capture.Snapshots, startAt, endAt)
	return capture, pauses, evidence, nil
}

func toSnapshot(observation monitor.Observation) model.Snapshot {
	return model.Snapshot{
		SchemaVersion: observation.SchemaVersion, Source: observation.Source,
		SampleStartedAt: observation.SampleStartedAt, ObservedAt: observation.ObservedAt,
		ReceivedAt: observation.ReceivedAt, IdleObservedAt: observation.IdleObservedAt,
		AppID: observation.AppID, AppName: observation.AppName, IdleSeconds: observation.IdleSeconds,
		BrowserName: observation.BrowserName, BrowserDomain: observation.BrowserDomain,
		BrowserStatus: observation.BrowserStatus, Audible: observation.Audible,
		LockState: observation.LockState, SleepState: observation.SleepState,
		PowerEvent: observation.PowerEvent, PowerObservedAt: observation.PowerObservedAt,
		Reasons: append([]string(nil), observation.Reasons...),
	}
}

func buildEvidence(snapshots []model.Snapshot, startAt, endAt time.Time) []poc.EvidenceInterval {
	evidence := []poc.EvidenceInterval{}
	for _, snapshot := range snapshots {
		observedAt := snapshot.ObservedAt
		if observedAt.IsZero() {
			continue
		}
		evidenceEnd := observedAt.Add(time.Duration(pollSeconds) * time.Second)
		if evidenceEnd.After(endAt) {
			evidenceEnd = endAt
		}
		if observedAt.Before(startAt) {
			observedAt = startAt
		}
		if !evidenceEnd.After(observedAt) {
			continue
		}
		if snapshot.LockState != nil && *snapshot.LockState {
			evidence = append(evidence, poc.EvidenceInterval{
				StartAt: observedAt, EndAt: evidenceEnd, Kind: poc.EvidenceLock,
				Source: "macos-native-lock-state",
			})
		}
		if snapshot.SleepState != nil && *snapshot.SleepState {
			evidence = append(evidence, poc.EvidenceInterval{
				StartAt: observedAt, EndAt: evidenceEnd, Kind: poc.EvidenceSleep,
				Source: "macos-native-sleep-state",
			})
		}
	}
	return evidence
}

type roundedTotals struct {
	task, related, distraction, unknown, inactive, elapsed int
}

func roundTotals(totals poc.Totals, elapsed float64) roundedTotals {
	values := []float64{totals.T, totals.R, totals.D, totals.U, totals.I}
	seconds := make([]int, len(values))
	fractions := make([]float64, len(values))
	sum := 0
	for index, value := range values {
		seconds[index] = int(math.Floor(value))
		fractions[index] = value - float64(seconds[index])
		sum += seconds[index]
	}
	target := int(math.Round(elapsed))
	order := []int{0, 1, 2, 3, 4}
	if remaining := target - sum; remaining > 0 {
		sort.SliceStable(order, func(i, j int) bool { return fractions[order[i]] > fractions[order[j]] })
		for index := 0; index < remaining; index++ {
			seconds[order[index%len(order)]]++
		}
	} else if remaining < 0 {
		sort.SliceStable(order, func(i, j int) bool { return fractions[order[i]] < fractions[order[j]] })
		for index := 0; index < -remaining; index++ {
			candidate := order[index%len(order)]
			if seconds[candidate] > 0 {
				seconds[candidate]--
			}
		}
	}
	return roundedTotals{
		task: seconds[0], related: seconds[1], distraction: seconds[2],
		unknown: seconds[3], inactive: seconds[4], elapsed: target,
	}
}
