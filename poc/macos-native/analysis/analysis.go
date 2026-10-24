// Package analysis は macOS の観測を、推定と不明が区別された分析結果へ変換する。
package analysis

import (
	"encoding/json"
	"math"
	"net"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"focuspocket/macos-native/model"
)

const (
	qualityPointObservation = "point_observation"
	qualitySampleEstimate   = "sample_based_estimate"
	qualityUnknown          = "unknown"
)

var idleThresholds = []int{60, 180, 300}

// Sanitize は元の取得元を保持し、入力を変更せず時刻と保存項目を正規化する。
func Sanitize(c model.Capture) model.Capture {
	c.Snapshots = append([]model.Snapshot{}, c.Snapshots...)
	c.Errors = append([]model.Failure{}, c.Errors...)
	c.StartAt = utc(c.StartAt)
	c.EndAt = utc(c.EndAt)
	if !finite(c.PollSeconds) || c.PollSeconds <= 0 {
		c.PollSeconds = 0
	}

	for i := range c.Snapshots {
		snapshot := &c.Snapshots[i]
		snapshot.SampleStartedAt = utc(snapshot.SampleStartedAt)
		snapshot.ObservedAt = utc(snapshot.ObservedAt)
		snapshot.ReceivedAt = utc(snapshot.ReceivedAt)
		snapshot.IdleObservedAt = utc(snapshot.IdleObservedAt)
		if snapshot.PowerObservedAt != nil {
			powerAt := utc(*snapshot.PowerObservedAt)
			snapshot.PowerObservedAt = &powerAt
		}

		snapshot.AppID = cleanString(snapshot.AppID, 256)
		snapshot.AppName = cleanString(snapshot.AppName, 256)
		snapshot.BrowserName = cleanString(snapshot.BrowserName, 128)
		snapshot.TabID = cleanString(snapshot.TabID, 256)
		snapshot.PowerEvent = cleanString(snapshot.PowerEvent, 64)
		snapshot.Reasons = uniqueSorted(snapshot.Reasons)
		snapshot.BrowserStatus = normalizeBrowserStatus(snapshot.BrowserStatus)

		if snapshot.IdleSeconds != nil && (!finite(*snapshot.IdleSeconds) || *snapshot.IdleSeconds < 0 || *snapshot.IdleSeconds >= float64(math.MaxInt64)/float64(time.Second)) {
			snapshot.IdleSeconds = nil
			snapshot.Reasons = uniqueSorted(append(snapshot.Reasons, "invalid_idle_seconds"))
		}

		if snapshot.BrowserStatus == "ok" {
			if !knownBrowser(snapshot.BrowserName, snapshot.AppID) {
				snapshot.BrowserStatus = "unknown"
				snapshot.BrowserDomain = nil
				snapshot.TabID = nil
				snapshot.Reasons = uniqueSorted(append(snapshot.Reasons, "unknown_browser"))
			} else if snapshot.BrowserDomain != nil {
				if host, ok := sanitizeHost(*snapshot.BrowserDomain); ok {
					snapshot.BrowserDomain = stringPointer(host)
				} else {
					snapshot.BrowserStatus = "unknown"
					snapshot.BrowserDomain = nil
					snapshot.TabID = nil
					snapshot.Reasons = uniqueSorted(append(snapshot.Reasons, "invalid_browser_domain"))
				}
			}
		} else {
			snapshot.BrowserDomain = nil
			snapshot.TabID = nil
		}
	}

	for i := range c.Errors {
		c.Errors[i].ReceivedAt = utc(c.Errors[i].ReceivedAt)
		c.Errors[i].Reason = strings.TrimSpace(c.Errors[i].Reason)
		if c.Errors[i].Reason == "" {
			c.Errors[i].Reason = "capture_error"
		}
	}
	sort.Slice(c.Errors, func(i, j int) bool {
		if c.Errors[i].ReceivedAt.Equal(c.Errors[j].ReceivedAt) {
			return c.Errors[i].Reason < c.Errors[j].Reason
		}
		return c.Errors[i].ReceivedAt.Before(c.Errors[j].ReceivedAt)
	})
	return c
}

// Analyze は観測点から半開区間を作り、未観測範囲を unknown のまま保持する。
func Analyze(c model.Capture) model.Analysis {
	rawSnapshotCount := len(c.Snapshots)
	c = Sanitize(c)
	result := model.Analysis{
		SchemaVersion: model.SchemaVersion,
		StartAt:       c.StartAt,
		EndAt:         c.EndAt,
		Events:        []model.Event{},
		Intervals:     []model.Interval{},
	}
	result.Report = model.Report{
		SnapshotCount:        rawSnapshotCount,
		BrowserStates:        map[string]int{},
		IdleThresholdSeconds: append([]int(nil), idleThresholds...),
		Applications:         []model.Application{},
		Domains:              []string{},
		Reasons:              []string{},
	}

	if c.StartAt.IsZero() || c.EndAt.IsZero() || !c.EndAt.After(c.StartAt) {
		result.Report.Reasons = []string{"invalid_capture_range"}
		return result
	}
	result.Report.ElapsedSeconds = c.EndAt.Sub(c.StartAt).Seconds()
	if c.SchemaVersion != model.SchemaVersion || c.Source != "macos-native" {
		result.Report.Reasons = []string{"unsupported_capture_schema_or_source"}
		appendUnknown(&result.Intervals, c.StartAt, c.EndAt, "unsupported_capture_schema_or_source")
		result.Report.UnknownSeconds = result.Report.ElapsedSeconds
		return result
	}

	maxGap, pollValid := maximumGap(c.PollSeconds)
	preparedSnapshots, duplicateCount := prepareSnapshots(c, maxGap, pollValid)
	result.Report.DuplicateSnapshotCount = duplicateCount

	preparedByTimestamp := make(map[int64][]preparedSnapshot)
	globalUnknown := false
	globalReasons := []string{}
	for _, prepared := range preparedSnapshots {
		result.Events = append(result.Events, eventFromSnapshot(prepared))
		if !prepared.valid {
			result.Report.InvalidSnapshotCount++
		}
		result.Report.Reasons = append(result.Report.Reasons, prepared.reasons...)
		result.Report.Reasons = append(result.Report.Reasons, prepared.snapshot.Reasons...)
		if prepared.snapshot.BrowserStatus != "" {
			result.Report.BrowserStates[prepared.snapshot.BrowserStatus]++
		}
		if prepared.valid && (result.Report.LastSuccessAt == nil || prepared.snapshot.ReceivedAt.After(*result.Report.LastSuccessAt)) {
			receivedAt := prepared.snapshot.ReceivedAt
			result.Report.LastSuccessAt = &receivedAt
		}

		observedAt := prepared.snapshot.ObservedAt
		if observedAt.IsZero() {
			globalUnknown = true
			globalReasons = append(globalReasons, "invalid_snapshot_unlocated")
			continue
		}
		if observedAt.Before(c.StartAt) || observedAt.After(c.EndAt) {
			continue
		}
		preparedByTimestamp[observedAt.UnixNano()] = append(preparedByTimestamp[observedAt.UnixNano()], prepared)
	}

	eventsAreOrdered(result.Events)
	nodes := make([]observationNode, 0, len(preparedByTimestamp))
	for timestamp, entries := range preparedByTimestamp {
		node := combineAtTimestamp(time.Unix(0, timestamp).UTC(), entries)
		result.Report.InvalidSnapshotCount += node.additionalInvalidCount
		result.Report.Reasons = append(result.Report.Reasons, node.reasons...)
		nodes = append(nodes, node)
	}
	sort.Slice(nodes, func(i, j int) bool { return nodes[i].at.Before(nodes[j].at) })

	failures := validFailures(c.Errors)
	for _, failure := range c.Errors {
		if failure.ReceivedAt.IsZero() {
			globalUnknown = true
			globalReasons = append(globalReasons, "failure_timestamp_unknown")
		}
		if failure.Reason != "" {
			result.Report.Reasons = append(result.Report.Reasons, failure.Reason)
		}
	}
	if len(c.Errors) > 0 {
		result.Report.Reasons = append(result.Report.Reasons, "capture_error_recorded")
	}

	if globalUnknown {
		appendUnknown(&result.Intervals, c.StartAt, c.EndAt, globalReasons...)
	} else if len(nodes) == 0 {
		appendUnknown(&result.Intervals, c.StartAt, c.EndAt, "no_observations")
	} else {
		if nodes[0].at.After(c.StartAt) {
			appendUnknown(&result.Intervals, c.StartAt, nodes[0].at, "unknown_before_first_observation")
		}
		for i := 0; i+1 < len(nodes); i++ {
			left, right := nodes[i], nodes[i+1]
			reasons := pairUnknownReasons(left, right, maxGap, pollValid, failures)
			if len(reasons) > 0 {
				appendUnknown(&result.Intervals, left.at, right.at, reasons...)
				continue
			}
			for _, interval := range sampleIntervals(left, right) {
				result.Intervals = append(result.Intervals, interval)
			}
		}
		lastAt := nodes[len(nodes)-1].at
		if lastAt.Before(c.EndAt) {
			appendUnknown(&result.Intervals, lastAt, c.EndAt, "unknown_after_last_observation")
		}
	}

	hasIdleReading := false
	for _, prepared := range preparedSnapshots {
		if prepared.snapshot.IdleSeconds != nil {
			hasIdleReading = true
			break
		}
	}
	if hasIdleReading {
		result.Report.Reasons = append(result.Report.Reasons, "idle_seconds_may_include_synthetic_or_remote_input")
	}
	for _, interval := range result.Intervals {
		result.Report.Reasons = append(result.Report.Reasons, interval.Reasons...)
	}
	result.Report.Reasons = uniqueSorted(result.Report.Reasons)
	result.Report.SampledSeconds, result.Report.UnknownSeconds = summarizeIntervals(&result, result.Report.ElapsedSeconds)
	if result.Report.UnknownSeconds > 0 {
		result.Report.Reasons = uniqueSorted(append(result.Report.Reasons, "coverage_contains_unknown_time"))
	}
	return result
}

type preparedSnapshot struct {
	snapshot model.Snapshot
	valid    bool
	reasons  []string
	key      string
	stateKey string
}

type observationNode struct {
	at                     time.Time
	snapshot               model.Snapshot
	valid                  bool
	conflict               bool
	additionalInvalidCount int
	reasons                []string
}

func prepareSnapshots(c model.Capture, maxGap time.Duration, pollValid bool) ([]preparedSnapshot, int) {
	prepared := make([]preparedSnapshot, 0, len(c.Snapshots))
	seen := make(map[string]struct{}, len(c.Snapshots))
	duplicates := 0
	for _, snapshot := range c.Snapshots {
		item := preparedSnapshot{
			snapshot: snapshot,
			valid:    true,
		}
		item.reasons = validateSnapshot(snapshot, maxGap, pollValid)
		if snapshot.ObservedAt.Before(c.StartAt) || snapshot.ObservedAt.After(c.EndAt) {
			item.reasons = append(item.reasons, "snapshot_outside_capture")
		}
		item.valid = len(item.reasons) == 0
		item.key = snapshotKey(snapshot)
		item.stateKey = observationStateKey(snapshot)
		if _, exists := seen[item.key]; exists {
			duplicates++
			continue
		}
		seen[item.key] = struct{}{}
		prepared = append(prepared, item)
	}
	sort.Slice(prepared, func(i, j int) bool {
		if prepared[i].snapshot.ObservedAt.Equal(prepared[j].snapshot.ObservedAt) {
			if prepared[i].stateKey == prepared[j].stateKey {
				return prepared[i].key < prepared[j].key
			}
			return prepared[i].stateKey < prepared[j].stateKey
		}
		return prepared[i].snapshot.ObservedAt.Before(prepared[j].snapshot.ObservedAt)
	})
	return prepared, duplicates
}

func validateSnapshot(snapshot model.Snapshot, maxGap time.Duration, pollValid bool) []string {
	reasons := []string{}
	if snapshot.SchemaVersion != model.SchemaVersion || snapshot.Source != "macos-native" {
		reasons = append(reasons, "unsupported_snapshot_schema_or_source")
	}
	if snapshot.BrowserStatus == "foreground_changed" {
		reasons = append(reasons, "foreground_changed_during_sample")
	}
	if snapshot.SampleStartedAt.IsZero() || snapshot.ObservedAt.IsZero() || snapshot.ReceivedAt.IsZero() {
		reasons = append(reasons, "invalid_snapshot_time")
	}
	if !snapshot.SampleStartedAt.IsZero() && !snapshot.ObservedAt.IsZero() {
		if snapshot.ObservedAt.Before(snapshot.SampleStartedAt) {
			reasons = append(reasons, "observation_before_sample_start")
		} else if snapshot.ObservedAt.Sub(snapshot.SampleStartedAt) > maxGap || snapshot.ObservedAt.Sub(snapshot.SampleStartedAt) > 30*time.Second {
			reasons = append(reasons, "sample_processing_too_long")
		}
	}
	if !snapshot.ObservedAt.IsZero() && !snapshot.ReceivedAt.IsZero() && snapshot.ObservedAt.After(snapshot.ReceivedAt) {
		reasons = append(reasons, "observed_after_received")
	}
	if !snapshot.IdleObservedAt.IsZero() && !snapshot.ReceivedAt.IsZero() && snapshot.IdleObservedAt.After(snapshot.ReceivedAt) {
		reasons = append(reasons, "idle_observed_after_received")
	}
	if snapshot.IdleSeconds != nil && (snapshot.IdleObservedAt.IsZero() || snapshot.IdleObservedAt.Before(snapshot.SampleStartedAt) || snapshot.IdleObservedAt.After(snapshot.ObservedAt)) {
		reasons = append(reasons, "idle_measurement_outside_sample")
	}
	if snapshot.AppID == nil || strings.TrimSpace(*snapshot.AppID) == "" {
		reasons = append(reasons, "frontmost_app_unavailable")
	}
	if !pollValid {
		reasons = append(reasons, "invalid_poll_seconds")
	}
	return uniqueSorted(reasons)
}

func combineAtTimestamp(at time.Time, entries []preparedSnapshot) observationNode {
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].stateKey == entries[j].stateKey {
			return entries[i].key < entries[j].key
		}
		return entries[i].stateKey < entries[j].stateKey
	})
	node := observationNode{at: at, snapshot: entries[0].snapshot, valid: true}
	firstState := entries[0].stateKey
	for _, entry := range entries {
		node.valid = node.valid && entry.valid
		node.reasons = append(node.reasons, entry.reasons...)
		if entry.stateKey != firstState {
			node.conflict = true
			node.valid = false
			node.reasons = append(node.reasons, "simultaneous_timestamp_conflict")
		}
	}
	if node.conflict {
		for _, entry := range entries {
			if entry.valid {
				node.additionalInvalidCount++
			}
		}
	}
	node.reasons = uniqueSorted(node.reasons)
	return node
}

func pairUnknownReasons(left, right observationNode, maxGap time.Duration, pollValid bool, failures []model.Failure) []string {
	reasons := []string{}
	gap := right.at.Sub(left.at)
	if gap <= 0 {
		reasons = append(reasons, "nonpositive_observation_gap")
	}
	if gap > maxGap || gap > 30*time.Second {
		reasons = append(reasons, "stale_observation_gap")
	}
	if !pollValid {
		reasons = append(reasons, "invalid_poll_seconds")
	}
	if !left.valid || !right.valid {
		reasons = append(reasons, "invalid_observation")
		reasons = append(reasons, left.reasons...)
		reasons = append(reasons, right.reasons...)
	}
	if left.conflict || right.conflict {
		reasons = append(reasons, "simultaneous_timestamp_conflict")
	}
	if left.snapshot.AppID == nil || right.snapshot.AppID == nil || !sameString(left.snapshot.AppID, right.snapshot.AppID) {
		reasons = append(reasons, "foreground_app_changed_or_unknown")
	}
	if !sameString(left.snapshot.BrowserDomain, right.snapshot.BrowserDomain) || left.snapshot.BrowserStatus != right.snapshot.BrowserStatus {
		reasons = append(reasons, "browser_state_changed_or_unknown")
	}
	for _, point := range []model.Snapshot{left.snapshot, right.snapshot} {
		browserExpected := knownBrowser(nil, point.AppID) || point.BrowserName != nil || point.BrowserStatus != "not_applicable"
		if browserExpected && (point.BrowserStatus != "ok" || point.BrowserDomain == nil || !knownBrowser(point.BrowserName, point.AppID)) {
			reasons = append(reasons, "browser_context_unavailable")
		}
	}
	if (left.snapshot.BrowserDomain != nil && left.snapshot.BrowserStatus != "ok") || (right.snapshot.BrowserDomain != nil && right.snapshot.BrowserStatus != "ok") {
		reasons = append(reasons, "browser_status_not_ok")
	}
	for _, failure := range failures {
		if !failure.ReceivedAt.Before(left.at) && failure.ReceivedAt.Before(right.at) {
			reasons = append(reasons, "capture_error_crossed_interval")
			if failure.Reason != "" {
				reasons = append(reasons, failure.Reason)
			}
		}
	}
	if hasPowerTransition(left.snapshot, left.at, right.at) || hasPowerTransition(right.snapshot, left.at, right.at) {
		reasons = append(reasons, "power_transition_crossed_interval")
	}
	return uniqueSorted(reasons)
}

func sampleIntervals(left, right observationNode) []model.Interval {
	start, end := left.at, right.at
	reasons := []string{qualitySampleEstimate}
	origin, idleKnown, idleReason := continuousIdleOrigin(left.snapshot, right.snapshot)
	if idleReason != "" {
		reasons = append(reasons, idleReason)
	}
	boundaries := []time.Time{start, end}
	if idleKnown {
		for _, threshold := range idleThresholds {
			boundary := origin.Add(time.Duration(threshold) * time.Second)
			if boundary.After(start) && boundary.Before(end) {
				boundaries = append(boundaries, boundary)
			}
		}
	}
	sort.Slice(boundaries, func(i, j int) bool { return boundaries[i].Before(boundaries[j]) })

	intervals := make([]model.Interval, 0, len(boundaries)-1)
	for i := 0; i+1 < len(boundaries); i++ {
		segmentStart, segmentEnd := boundaries[i], boundaries[i+1]
		if !segmentEnd.After(segmentStart) {
			continue
		}
		idleValues := unknownIdleThresholds()
		segmentReasons := append([]string{}, reasons...)
		if idleKnown {
			midpoint := segmentStart.Add(segmentEnd.Sub(segmentStart) / 2)
			idleValues = classifyIdleAt(midpoint, origin)
		} else {
			idleValues = boundedIdleThresholds(left.snapshot, right.snapshot, segmentEnd)
			for _, value := range idleValues {
				if value != nil {
					segmentReasons = append(segmentReasons, "idle_threshold_bounded_by_elapsed_time")
					break
				}
			}
		}
		intervals = append(intervals, model.Interval{
			StartAt:           segmentStart,
			EndAt:             segmentEnd,
			AppID:             cloneString(left.snapshot.AppID),
			AppName:           cloneString(left.snapshot.AppName),
			BrowserDomain:     cloneString(left.snapshot.BrowserDomain),
			IdleOverThreshold: idleValues,
			Quality:           qualitySampleEstimate,
			Reasons:           uniqueSorted(segmentReasons),
		})
	}
	return intervals
}

// 入力でidle値がリセットされても，左観測から増え得る最大値が猶予未満なら
// 区間全体の閾値未到達を確認できる。入力時刻の復元や欠測の補完はしない。
func boundedIdleThresholds(left, right model.Snapshot, end time.Time) map[string]*bool {
	values := unknownIdleThresholds()
	if left.IdleSeconds == nil || right.IdleSeconds == nil ||
		!finite(*left.IdleSeconds) || !finite(*right.IdleSeconds) ||
		*left.IdleSeconds < 0 || *right.IdleSeconds < 0 ||
		left.SampleStartedAt.IsZero() || left.IdleObservedAt.IsZero() || right.IdleObservedAt.IsZero() ||
		left.SampleStartedAt.After(left.IdleObservedAt) ||
		left.IdleObservedAt.After(left.ObservedAt) ||
		right.IdleObservedAt.Before(left.IdleObservedAt) || right.IdleObservedAt.After(end) ||
		end.Before(left.ObservedAt) {
		return values
	}
	// idleの値はIdleObservedAtの記録より前に読むため，取得開始を起点にする。
	// native時刻のミリ秒精度と数値丸めも安全側へ含める。
	measurementEarliest := left.SampleStartedAt.Add(-time.Millisecond)
	rightUpper := math.Nextafter(*left.IdleSeconds+right.IdleObservedAt.Sub(measurementEarliest).Seconds(), math.Inf(1))
	upper := math.Nextafter(*left.IdleSeconds+end.Sub(measurementEarliest).Seconds(), math.Inf(1))
	if !finite(upper) || !finite(rightUpper) || *right.IdleSeconds > rightUpper {
		return values
	}
	for _, threshold := range idleThresholds {
		if upper < float64(threshold) {
			value := false
			values[thresholdKey(threshold)] = &value
		}
	}
	return values
}

func continuousIdleOrigin(left, right model.Snapshot) (time.Time, bool, string) {
	if left.IdleSeconds == nil || right.IdleSeconds == nil {
		return time.Time{}, false, ""
	}
	if *left.IdleSeconds <= 0 || *right.IdleSeconds <= 0 || *right.IdleSeconds < *left.IdleSeconds {
		return time.Time{}, false, "idle_continuity_unknown"
	}
	if left.IdleObservedAt.IsZero() || right.IdleObservedAt.IsZero() {
		return time.Time{}, false, "idle_continuity_unknown"
	}
	leftOrigin := left.IdleObservedAt.Add(-time.Duration(*left.IdleSeconds * float64(time.Second)))
	rightOrigin := right.IdleObservedAt.Add(-time.Duration(*right.IdleSeconds * float64(time.Second)))
	gap := right.ObservedAt.Sub(left.ObservedAt)
	tolerance := time.Second
	if candidate := gap / 4; candidate > tolerance {
		tolerance = candidate
	}
	if tolerance > 5*time.Second {
		tolerance = 5 * time.Second
	}
	if absDuration(rightOrigin.Sub(leftOrigin)) > tolerance {
		return time.Time{}, false, "idle_continuity_unknown"
	}
	idleElapsed := right.IdleObservedAt.Sub(left.IdleObservedAt)
	idleSecondsElapsed := time.Duration((*right.IdleSeconds - *left.IdleSeconds) * float64(time.Second))
	if absDuration(idleElapsed-idleSecondsElapsed) > tolerance {
		return time.Time{}, false, "idle_continuity_unknown"
	}
	origin := leftOrigin.Add(rightOrigin.Sub(leftOrigin) / 2)
	return origin, true, ""
}

func appendUnknown(intervals *[]model.Interval, start, end time.Time, reasons ...string) {
	if !end.After(start) {
		return
	}
	*intervals = append(*intervals, model.Interval{
		StartAt:           start,
		EndAt:             end,
		IdleOverThreshold: unknownIdleThresholds(),
		Quality:           qualityUnknown,
		Reasons:           uniqueSorted(reasons),
	})
}

func summarizeIntervals(result *model.Analysis, elapsed float64) (float64, float64) {
	applications := map[string]*model.Application{}
	domains := map[string]struct{}{}
	sampledSeconds := 0.0
	// 単発観測も一覧へ残すが、未観測の継続時間は加算しない。
	for _, event := range result.Events {
		if event.Quality != qualityPointObservation {
			continue
		}
		if event.AppID != nil {
			applications[*event.AppID] = &model.Application{AppID: *event.AppID, AppName: cloneString(event.AppName)}
		}
		if event.BrowserDomain != nil {
			domains[*event.BrowserDomain] = struct{}{}
		}
	}
	for _, interval := range result.Intervals {
		seconds := interval.EndAt.Sub(interval.StartAt).Seconds()
		if interval.Quality != qualitySampleEstimate {
			continue
		}
		sampledSeconds += seconds
		if interval.AppID != nil {
			application, exists := applications[*interval.AppID]
			if !exists {
				application = &model.Application{AppID: *interval.AppID, AppName: cloneString(interval.AppName)}
				applications[*interval.AppID] = application
			}
			application.EstimatedFrontmostSeconds += seconds
		}
		if interval.BrowserDomain != nil {
			domains[*interval.BrowserDomain] = struct{}{}
		}
	}
	if sampledSeconds > elapsed {
		sampledSeconds = elapsed
	}
	unknownSeconds := elapsed - sampledSeconds
	if unknownSeconds < 0 && unknownSeconds > -1e-9 {
		unknownSeconds = 0
	}

	for _, application := range applications {
		result.Report.Applications = append(result.Report.Applications, *application)
	}
	sort.Slice(result.Report.Applications, func(i, j int) bool {
		return result.Report.Applications[i].AppID < result.Report.Applications[j].AppID
	})
	for domain := range domains {
		result.Report.Domains = append(result.Report.Domains, domain)
	}
	sort.Strings(result.Report.Domains)
	return sampledSeconds, unknownSeconds
}

func eventFromSnapshot(prepared preparedSnapshot) model.Event {
	snapshot := prepared.snapshot
	reasons := append([]string(nil), snapshot.Reasons...)
	reasons = append(reasons, prepared.reasons...)
	quality := qualityPointObservation
	if !prepared.valid {
		quality = qualityUnknown
	}
	return model.Event{
		SchemaVersion: model.SchemaVersion,
		Source:        snapshot.Source,
		StartAt:       snapshot.ObservedAt,
		EndAt:         snapshot.ObservedAt,
		ObservedAt:    snapshot.ObservedAt,
		ReceivedAt:    snapshot.ReceivedAt,
		AppID:         cloneString(snapshot.AppID),
		AppName:       cloneString(snapshot.AppName),
		BrowserName:   cloneString(snapshot.BrowserName),
		BrowserDomain: cloneString(snapshot.BrowserDomain),
		TabID:         cloneString(snapshot.TabID),
		IdleSeconds:   cloneFloat(snapshot.IdleSeconds),
		AFKStatus:     nil,
		Quality:       quality,
		Reasons:       uniqueSorted(reasons),
	}
}

func eventsAreOrdered(events []model.Event) {
	sort.Slice(events, func(i, j int) bool {
		if events[i].ObservedAt.Equal(events[j].ObservedAt) {
			if events[i].ReceivedAt.Equal(events[j].ReceivedAt) {
				return eventKey(events[i]) < eventKey(events[j])
			}
			return events[i].ReceivedAt.Before(events[j].ReceivedAt)
		}
		return events[i].ObservedAt.Before(events[j].ObservedAt)
	})
}

func eventKey(event model.Event) string {
	encoded, _ := json.Marshal(event)
	return string(encoded)
}

func snapshotKey(snapshot model.Snapshot) string {
	encoded, _ := json.Marshal(snapshot)
	return string(encoded)
}

func observationStateKey(snapshot model.Snapshot) string {
	state := struct {
		AppID           *string    `json:"app_id"`
		AppName         *string    `json:"app_name"`
		IdleObservedAt  time.Time  `json:"idle_observed_at"`
		IdleSeconds     *float64   `json:"idle_seconds"`
		BrowserName     *string    `json:"browser_name"`
		BrowserDomain   *string    `json:"browser_domain"`
		TabID           *string    `json:"tab_id"`
		BrowserStatus   string     `json:"browser_status"`
		Audible         *bool      `json:"audible"`
		LockState       *bool      `json:"lock_state"`
		SleepState      *bool      `json:"sleep_state"`
		PowerEvent      *string    `json:"power_event"`
		PowerObservedAt *time.Time `json:"power_observed_at"`
	}{
		AppID:           snapshot.AppID,
		AppName:         snapshot.AppName,
		IdleObservedAt:  snapshot.IdleObservedAt,
		IdleSeconds:     snapshot.IdleSeconds,
		BrowserName:     snapshot.BrowserName,
		BrowserDomain:   snapshot.BrowserDomain,
		TabID:           snapshot.TabID,
		BrowserStatus:   snapshot.BrowserStatus,
		Audible:         snapshot.Audible,
		LockState:       snapshot.LockState,
		SleepState:      snapshot.SleepState,
		PowerEvent:      snapshot.PowerEvent,
		PowerObservedAt: snapshot.PowerObservedAt,
	}
	encoded, _ := json.Marshal(state)
	return string(encoded)
}

func validFailures(failures []model.Failure) []model.Failure {
	valid := make([]model.Failure, 0, len(failures))
	for _, failure := range failures {
		if !failure.ReceivedAt.IsZero() {
			valid = append(valid, failure)
		}
	}
	return valid
}

func hasPowerTransition(snapshot model.Snapshot, start, end time.Time) bool {
	if snapshot.PowerEvent == nil || strings.TrimSpace(*snapshot.PowerEvent) == "" {
		return false
	}
	transitionAt := snapshot.ObservedAt
	if snapshot.PowerObservedAt != nil {
		transitionAt = *snapshot.PowerObservedAt
	}
	return !transitionAt.Before(start) && !transitionAt.After(end)
}

func maximumGap(pollSeconds float64) (time.Duration, bool) {
	if !finite(pollSeconds) || pollSeconds <= 0 {
		return 3 * time.Second, false
	}
	if pollSeconds >= 10 {
		return 30 * time.Second, true
	}
	gapSeconds := 3 * pollSeconds
	if gapSeconds < 3 {
		gapSeconds = 3
	}
	return time.Duration(gapSeconds * float64(time.Second)), true
}

func normalizeBrowserStatus(status string) string {
	status = strings.ToLower(strings.TrimSpace(status))
	if status == "success" {
		return "ok"
	}
	switch status {
	case "ok", "not_applicable", "permission_denied", "timeout", "no_window", "unknown_error", "unsupported", "foreground_changed", "unknown":
		return status
	default:
		return "unknown"
	}
}

func knownBrowser(name, appID *string) bool {
	if appID == nil {
		return false
	}
	expected := ""
	switch strings.ToLower(strings.TrimSpace(*appID)) {
	case "com.google.chrome":
		expected = "chrome"
	case "com.apple.safari":
		expected = "safari"
	default:
		return false
	}
	return name == nil || strings.ToLower(strings.TrimSpace(*name)) == expected
}

func sanitizeHost(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", false
	}
	host := ""
	if strings.Contains(value, "://") {
		parsed, err := url.Parse(value)
		if err != nil || parsed.User != nil || parsed.Opaque != "" || parsed.Host == "" {
			return "", false
		}
		scheme := strings.ToLower(parsed.Scheme)
		if scheme != "http" && scheme != "https" {
			return "", false
		}
		host = parsed.Hostname()
	} else {
		if strings.ContainsAny(value, "/?#@") || strings.Contains(value, ":") {
			return "", false
		}
		host = value
	}
	host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	if ip := net.ParseIP(host); ip != nil {
		return ip.String(), true
	}
	if host == "" || len(host) > 253 {
		return "", false
	}
	for _, label := range strings.Split(host, ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return "", false
		}
		for _, character := range label {
			if !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '-' {
				return "", false
			}
		}
	}
	return host, true
}

func classifyIdleAt(at, origin time.Time) map[string]*bool {
	values := make(map[string]*bool, len(idleThresholds))
	for _, threshold := range idleThresholds {
		idle := !at.Before(origin.Add(time.Duration(threshold) * time.Second))
		values[thresholdKey(threshold)] = boolPointer(idle)
	}
	return values
}

func unknownIdleThresholds() map[string]*bool {
	values := make(map[string]*bool, len(idleThresholds))
	for _, threshold := range idleThresholds {
		values[thresholdKey(threshold)] = nil
	}
	return values
}

func thresholdKey(threshold int) string {
	return strconv.Itoa(threshold)
}

func utc(value time.Time) time.Time {
	if value.IsZero() {
		return value
	}
	return value.UTC()
}

func cleanString(value *string, maxLength int) *string {
	if value == nil {
		return nil
	}
	cleaned := strings.ToValidUTF8(strings.TrimSpace(*value), "�")
	if cleaned == "" {
		return nil
	}
	characters := []rune(cleaned)
	if len(characters) > maxLength {
		cleaned = string(characters[:maxLength])
	}
	return &cleaned
}

func uniqueSorted(values []string) []string {
	set := make(map[string]struct{}, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			set[value] = struct{}{}
		}
	}
	result := make([]string, 0, len(set))
	for value := range set {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}

func cloneString(value *string) *string {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}

func cloneFloat(value *float64) *float64 {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}

func stringPointer(value string) *string { return &value }
func boolPointer(value bool) *bool       { return &value }

func sameString(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func absDuration(value time.Duration) time.Duration {
	if value < 0 {
		return -value
	}
	return value
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}
