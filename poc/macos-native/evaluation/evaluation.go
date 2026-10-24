// Package evaluation は観測区間を明示ルールに基づく5分類へ変換する。
package evaluation

import (
	"fmt"
	"net"
	"sort"
	"strings"
	"time"

	"focuspocket/macos-native/model"
)

const (
	// EvaluatorVersion は評価規則の固定バージョンを示す。
	EvaluatorVersion = "five-class-v2"

	ClassTask              = "T"
	ClassRelatedTransition = "R"
	ClassDistraction       = "D"
	ClassUnknown           = "U"
	ClassInactive          = "I"

	RuleTask              = "TASK"
	RuleRelatedTransition = "RELATED_TRANSITION"
	RuleDistraction       = "DISTRACTION"

	EvidenceLock  = "LOCK"
	EvidenceSleep = "SLEEP"

	qualitySampleBasedEstimate = "sample_based_estimate"
)

var modeIdleThresholdKey = map[string]string{
	"NORMAL":  "60",
	"READING": "180",
	"VIDEO":   "300",
}

type Session struct {
	ID           string       `json:"id"`
	TaskSnapshot TaskSnapshot `json:"task_snapshot"`
	Pauses       []TimeRange  `json:"pauses"`
}

type TaskSnapshot struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Mode         string `json:"mode"`
	RulesVersion string `json:"rules_version"`
	Rules        []Rule `json:"rules"`
}

type Rule struct {
	AppID  string `json:"app_id"`
	Domain string `json:"domain,omitempty"`
	Class  string `json:"class"`
}

type TimeRange struct {
	StartAt time.Time `json:"start_at"`
	EndAt   time.Time `json:"end_at"`
}

type EvidenceInterval struct {
	StartAt time.Time `json:"start_at"`
	EndAt   time.Time `json:"end_at"`
	Kind    string    `json:"kind"`
	Source  string    `json:"source"`
	Reasons []string  `json:"reasons,omitempty"`
}

type Segment struct {
	StartAt       time.Time `json:"start_at"`
	EndAt         time.Time `json:"end_at"`
	Class         string    `json:"class"`
	AppID         *string   `json:"app_id,omitempty"`
	BrowserDomain *string   `json:"browser_domain,omitempty"`
	Reasons       []string  `json:"reasons"`
}

type Totals struct {
	T float64 `json:"T"`
	R float64 `json:"R"`
	D float64 `json:"D"`
	U float64 `json:"U"`
	I float64 `json:"I"`
}

type Result struct {
	SchemaVersion    string             `json:"schema_version"`
	EvaluatorVersion string             `json:"evaluator_version"`
	Session          Session            `json:"session"`
	Evidence         []EvidenceInterval `json:"evidence"`
	InputEvidence    []EvidenceInterval `json:"input_evidence"`
	StartAt          time.Time          `json:"start_at"`
	EndAt            time.Time          `json:"end_at"`
	Segments         []Segment          `json:"segments"`
	Totals           Totals             `json:"totals"`
	SessionSeconds   float64            `json:"session_seconds"`
	PausedSeconds    float64            `json:"paused_seconds"`
	ElapsedSeconds   float64            `json:"elapsed_seconds"`
	KnownSeconds     float64            `json:"known_seconds"`
	WorkSeconds      float64            `json:"work_seconds"`
	B                *float64           `json:"b"`
	Q                *float64           `json:"q"`
	WorkRate         *float64           `json:"work_rate"`
}

type normalizedRule struct {
	appID  string
	domain string
	class  string
}

type clippedEvidence struct {
	startAt time.Time
	endAt   time.Time
	kind    string
	source  string
	reasons []string
}

type classifiedAtom struct {
	segment     Segment
	key         string
	distraction bool
	paused      bool
}

// ValidateSession はセッションと分類ルールの整合性を検証する。
func ValidateSession(session Session) error {
	_, err := prepareRules(session)
	return err
}

// Evaluate は分析結果を5分類へ変換する。確定したLOCK/SLEEP証拠は追加しない。
func Evaluate(session Session, observed model.Analysis) (Result, error) {
	return EvaluateWithEvidence(session, observed, nil)
}

// EvaluateWithEvidence は明示されたLOCK/SLEEP証拠を含めて5分類を計算する。
func EvaluateWithEvidence(session Session, observed model.Analysis, evidence []EvidenceInterval) (Result, error) {
	rules, err := prepareRules(session)
	if err != nil {
		return Result{}, err
	}
	if observed.SchemaVersion != model.SchemaVersion {
		return Result{}, fmt.Errorf("unsupported analysis schema_version %q", observed.SchemaVersion)
	}
	if observed.StartAt.IsZero() || observed.EndAt.IsZero() || observed.EndAt.Before(observed.StartAt) {
		return Result{}, fmt.Errorf("analysis range is invalid")
	}

	intervals, err := prepareIntervals(observed)
	if err != nil {
		return Result{}, err
	}
	pauses, err := preparePauses(session.Pauses, observed.StartAt, observed.EndAt)
	if err != nil {
		return Result{}, err
	}
	clipped, err := prepareEvidence(evidence, observed.StartAt, observed.EndAt)
	if err != nil {
		return Result{}, err
	}

	boundaries := makeBoundaries(observed.StartAt, observed.EndAt, intervals, pauses, clipped)
	atoms := make([]classifiedAtom, 0, len(boundaries)-1)
	intervalIndex := 0
	for index := 0; index+1 < len(boundaries); index++ {
		startAt, endAt := boundaries[index], boundaries[index+1]
		for intervalIndex < len(intervals) && !startAt.Before(intervals[intervalIndex].EndAt) {
			intervalIndex++
		}
		var source *model.Interval
		if intervalIndex < len(intervals) {
			interval := &intervals[intervalIndex]
			if !startAt.Before(interval.StartAt) && !endAt.After(interval.EndAt) {
				source = interval
			}
		}

		paused := containsRange(pauses, startAt)
		activeEvidence := evidenceAt(clipped, startAt)
		atoms = append(atoms, classifyAtom(startAt, endAt, source, paused, activeEvidence, rules, session.TaskSnapshot.Mode))
	}

	resolveDistractionRuns(atoms)
	segments := coalesce(atoms)
	totals, err := aggregateSegments(segments)
	if err != nil {
		return Result{}, err
	}
	sessionSeconds := observed.EndAt.Sub(observed.StartAt).Seconds()
	pausedSeconds := rangesSeconds(pauses)
	elapsed := sessionSeconds - pausedSeconds
	known := totals.T + totals.R + totals.D
	work := totals.T + totals.R
	coverage := known + totals.I

	result := Result{
		SchemaVersion:    model.SchemaVersion,
		EvaluatorVersion: EvaluatorVersion,
		Session:          cloneSession(session),
		Evidence:         appliedEvidence(clipped),
		InputEvidence:    cloneEvidence(evidence),
		StartAt:          observed.StartAt,
		EndAt:            observed.EndAt,
		Segments:         segments,
		Totals:           totals,
		SessionSeconds:   sessionSeconds,
		PausedSeconds:    pausedSeconds,
		ElapsedSeconds:   elapsed,
		KnownSeconds:     known,
		WorkSeconds:      work,
	}
	if known > 0 {
		value := 100 * work / known
		result.B = &value
	}
	if elapsed > 0 {
		q := coverage / elapsed
		workRate := work / elapsed
		result.Q = &q
		result.WorkRate = &workRate
	}
	return result, nil
}

func prepareRules(session Session) ([]normalizedRule, error) {
	if strings.TrimSpace(session.ID) == "" {
		return nil, fmt.Errorf("session id is empty")
	}
	snapshot := session.TaskSnapshot
	if strings.TrimSpace(snapshot.ID) == "" {
		return nil, fmt.Errorf("task_snapshot.id is empty")
	}
	if strings.TrimSpace(snapshot.Name) == "" {
		return nil, fmt.Errorf("task_snapshot.name is empty")
	}
	if strings.TrimSpace(snapshot.RulesVersion) == "" {
		return nil, fmt.Errorf("task_snapshot.rules_version is empty")
	}
	switch snapshot.Mode {
	case "NORMAL", "READING", "VIDEO":
	default:
		return nil, fmt.Errorf("unsupported task_snapshot.mode %q", snapshot.Mode)
	}
	if err := validatePauseRanges(session.Pauses); err != nil {
		return nil, err
	}

	rules := make([]normalizedRule, 0, len(snapshot.Rules))
	for index, rule := range snapshot.Rules {
		if strings.TrimSpace(rule.AppID) == "" || strings.TrimSpace(rule.AppID) != rule.AppID {
			return nil, fmt.Errorf("rules[%d].app_id is empty or has surrounding whitespace", index)
		}
		switch rule.Class {
		case RuleTask, RuleRelatedTransition, RuleDistraction:
		default:
			return nil, fmt.Errorf("rules[%d].class %q is invalid", index, rule.Class)
		}

		domain := ""
		if rule.Domain != "" {
			var err error
			domain, err = normalizeHost(rule.Domain)
			if err != nil {
				return nil, fmt.Errorf("rules[%d].domain: %w", index, err)
			}
		}
		if domain != "" && !isBrowserAppID(rule.AppID) {
			return nil, fmt.Errorf("rules[%d].domain is only supported for Chrome and Safari app ids", index)
		}
		if isBrowserAppID(rule.AppID) && domain == "" {
			return nil, fmt.Errorf("rules[%d].domain is required for browser app %q", index, rule.AppID)
		}
		candidate := normalizedRule{appID: rule.AppID, domain: domain, class: rule.Class}
		for _, prior := range rules {
			if prior.appID != candidate.appID {
				continue
			}
			if prior.domain == candidate.domain {
				return nil, fmt.Errorf("rules for app_id %q and domain %q are duplicated or conflicting", candidate.appID, candidate.domain)
			}
			if prior.domain == "" || candidate.domain == "" {
				return nil, fmt.Errorf("rules for app_id %q overlap between wildcard and domain scope", candidate.appID)
			}
		}
		rules = append(rules, candidate)
	}
	return rules, nil
}

func prepareIntervals(observed model.Analysis) ([]model.Interval, error) {
	intervals := append([]model.Interval(nil), observed.Intervals...)
	sort.Slice(intervals, func(i, j int) bool {
		if intervals[i].StartAt.Equal(intervals[j].StartAt) {
			return intervals[i].EndAt.Before(intervals[j].EndAt)
		}
		return intervals[i].StartAt.Before(intervals[j].StartAt)
	})
	for index, interval := range intervals {
		if interval.StartAt.IsZero() || interval.EndAt.IsZero() || !interval.EndAt.After(interval.StartAt) {
			return nil, fmt.Errorf("analysis interval %d has an invalid range", index)
		}
		if interval.StartAt.Before(observed.StartAt) || interval.EndAt.After(observed.EndAt) {
			return nil, fmt.Errorf("analysis interval %d is outside the analysis range", index)
		}
		if index > 0 && interval.StartAt.Before(intervals[index-1].EndAt) {
			return nil, fmt.Errorf("analysis intervals %d and %d overlap", index-1, index)
		}
	}
	return intervals, nil
}

func validatePauseRanges(input []TimeRange) error {
	for index, interval := range input {
		if interval.StartAt.IsZero() || interval.EndAt.IsZero() || !interval.EndAt.After(interval.StartAt) {
			return fmt.Errorf("pause %d has an invalid range", index)
		}
	}
	return nil
}

func preparePauses(input []TimeRange, startAt, endAt time.Time) ([]TimeRange, error) {
	if err := validatePauseRanges(input); err != nil {
		return nil, err
	}
	ranges := make([]TimeRange, 0, len(input))
	for _, interval := range input {
		if !interval.EndAt.After(startAt) || !interval.StartAt.Before(endAt) {
			continue
		}
		if interval.StartAt.Before(startAt) {
			interval.StartAt = startAt
		}
		if interval.EndAt.After(endAt) {
			interval.EndAt = endAt
		}
		ranges = append(ranges, interval)
	}
	sort.Slice(ranges, func(i, j int) bool { return ranges[i].StartAt.Before(ranges[j].StartAt) })
	merged := make([]TimeRange, 0, len(ranges))
	for _, interval := range ranges {
		if len(merged) == 0 || interval.StartAt.After(merged[len(merged)-1].EndAt) {
			merged = append(merged, interval)
			continue
		}
		if interval.EndAt.After(merged[len(merged)-1].EndAt) {
			merged[len(merged)-1].EndAt = interval.EndAt
		}
	}
	return merged, nil
}

func prepareEvidence(input []EvidenceInterval, startAt, endAt time.Time) ([]clippedEvidence, error) {
	prepared := make([]clippedEvidence, 0, len(input))
	for index, interval := range input {
		if interval.StartAt.IsZero() || interval.EndAt.IsZero() || !interval.EndAt.After(interval.StartAt) {
			return nil, fmt.Errorf("evidence[%d] has an invalid range", index)
		}
		if interval.Kind != EvidenceLock && interval.Kind != EvidenceSleep {
			return nil, fmt.Errorf("evidence[%d].kind must be LOCK or SLEEP", index)
		}
		if strings.TrimSpace(interval.Source) == "" || strings.TrimSpace(interval.Source) != interval.Source {
			return nil, fmt.Errorf("evidence[%d].source is empty or has surrounding whitespace", index)
		}
		if !interval.EndAt.After(startAt) || !interval.StartAt.Before(endAt) {
			continue
		}
		if interval.StartAt.Before(startAt) {
			interval.StartAt = startAt
		}
		if interval.EndAt.After(endAt) {
			interval.EndAt = endAt
		}
		prepared = append(prepared, clippedEvidence{
			startAt: interval.StartAt,
			endAt:   interval.EndAt,
			kind:    interval.Kind,
			source:  interval.Source,
			reasons: uniqueSorted(interval.Reasons),
		})
	}
	sort.Slice(prepared, func(i, j int) bool { return prepared[i].startAt.Before(prepared[j].startAt) })
	return prepared, nil
}

func makeBoundaries(startAt, endAt time.Time, intervals []model.Interval, pauses []TimeRange, evidence []clippedEvidence) []time.Time {
	boundaries := []time.Time{startAt, endAt}
	for _, interval := range intervals {
		boundaries = append(boundaries, interval.StartAt, interval.EndAt)
	}
	for _, interval := range pauses {
		boundaries = append(boundaries, interval.StartAt, interval.EndAt)
	}
	for _, interval := range evidence {
		boundaries = append(boundaries, interval.startAt, interval.endAt)
	}
	sort.Slice(boundaries, func(i, j int) bool { return boundaries[i].Before(boundaries[j]) })
	unique := boundaries[:0]
	for _, boundary := range boundaries {
		if len(unique) == 0 || !boundary.Equal(unique[len(unique)-1]) {
			unique = append(unique, boundary)
		}
	}
	return unique
}

func classifyAtom(startAt, endAt time.Time, interval *model.Interval, paused bool, evidence []clippedEvidence, rules []normalizedRule, mode string) classifiedAtom {
	atom := classifiedAtom{
		segment: Segment{
			StartAt: startAt,
			EndAt:   endAt,
			Class:   ClassUnknown,
			Reasons: []string{},
		},
	}
	if interval != nil {
		atom.segment.Reasons = append(atom.segment.Reasons, interval.Reasons...)
		atom.segment.AppID = cloneStringPointer(interval.AppID)
		atom.segment.BrowserDomain = cloneStringPointer(interval.BrowserDomain)
	}
	if paused {
		atom.paused = true
		return atom
	}
	for _, item := range evidence {
		if !startAt.Before(item.startAt) && startAt.Before(item.endAt) {
			atom.segment.Class = ClassInactive
			atom.segment.Reasons = append(atom.segment.Reasons, "confirmed_"+strings.ToLower(item.kind)+":"+item.source)
			atom.segment.Reasons = append(atom.segment.Reasons, item.reasons...)
		}
	}
	if atom.segment.Class == ClassInactive {
		atom.segment.Reasons = uniqueSorted(atom.segment.Reasons)
		return atom
	}
	if interval == nil {
		atom.segment.Reasons = uniqueSorted(append(atom.segment.Reasons, "analysis_interval_gap"))
		return atom
	}

	class, key, reasons := classifyInterval(*interval, rules, mode)
	atom.segment.Class = class
	atom.segment.Reasons = uniqueSorted(append(atom.segment.Reasons, reasons...))
	atom.key = key
	atom.distraction = class == ClassDistraction
	return atom
}

func classifyInterval(interval model.Interval, rules []normalizedRule, mode string) (string, string, []string) {
	reasons := []string{}
	if interval.Quality != qualitySampleBasedEstimate {
		reasons = append(reasons, "quality_not_sample_based_estimate")
		return ClassUnknown, "", reasons
	}
	if interval.AppID == nil || strings.TrimSpace(*interval.AppID) == "" {
		reasons = append(reasons, "missing_app_id")
		return ClassUnknown, "", reasons
	}

	appID := *interval.AppID
	browser := isBrowserAppID(appID)
	domain := ""
	if interval.BrowserDomain != nil {
		if *interval.BrowserDomain != "" {
			normalized, err := normalizeHost(*interval.BrowserDomain)
			if err != nil {
				reasons = append(reasons, "invalid_browser_domain")
				return ClassUnknown, "", reasons
			}
			domain = normalized
		}
	}
	if browser && domain == "" {
		reasons = append(reasons, "missing_browser_domain")
		return ClassUnknown, "", reasons
	}
	if !browser && domain != "" {
		reasons = append(reasons, "unexpected_browser_domain")
		return ClassUnknown, "", reasons
	}

	threshold := modeIdleThresholdKey[mode]
	value, exists := interval.IdleOverThreshold[threshold]
	if !exists || value == nil {
		return ClassUnknown, "", []string{"idle_over_threshold_" + threshold + "_unknown"}
	}
	if *value {
		return ClassUnknown, "", []string{"idle_over_threshold_" + threshold + "_true"}
	}

	for _, rule := range rules {
		if rule.appID != appID {
			continue
		}
		if rule.domain != "" && rule.domain != domain {
			continue
		}
		reasons = append(reasons, "matched_rule_"+rule.class)
		switch rule.class {
		case RuleTask:
			return ClassTask, appID + ":" + domain, reasons
		case RuleRelatedTransition:
			return ClassRelatedTransition, appID + ":" + domain, reasons
		case RuleDistraction:
			return ClassDistraction, appID + ":" + domain, reasons
		}
	}
	return ClassUnknown, "", append(reasons, "no_matching_rule")
}

func resolveDistractionRuns(atoms []classifiedAtom) {
	run := make([]int, 0)
	runKey := ""
	flush := func() {
		if len(run) == 0 {
			return
		}
		duration := atoms[run[len(run)-1]].segment.EndAt.Sub(atoms[run[0]].segment.StartAt)
		reason := "distraction_streak_under_10_seconds"
		class := ClassUnknown
		if duration >= 10*time.Second {
			reason = "distraction_streak_at_least_10_seconds"
			class = ClassDistraction
		}
		for _, index := range run {
			atoms[index].segment.Class = class
			atoms[index].segment.Reasons = uniqueSorted(append(atoms[index].segment.Reasons, reason))
		}
		run = run[:0]
		runKey = ""
	}

	for index := range atoms {
		atom := &atoms[index]
		if !atom.distraction {
			flush()
			continue
		}
		if len(run) > 0 {
			prior := atoms[run[len(run)-1]].segment
			if atom.key != runKey || !prior.EndAt.Equal(atom.segment.StartAt) {
				flush()
			}
		}
		if len(run) == 0 {
			runKey = atom.key
		}
		run = append(run, index)
	}
	flush()
}

func coalesce(atoms []classifiedAtom) []Segment {
	segments := make([]Segment, 0, len(atoms))
	for _, atom := range atoms {
		if atom.paused {
			continue
		}
		segment := atom.segment
		if len(segments) > 0 {
			prior := &segments[len(segments)-1]
			if prior.EndAt.Equal(segment.StartAt) && prior.Class == segment.Class &&
				sameStrings(prior.Reasons, segment.Reasons) &&
				sameStringPointers(prior.AppID, segment.AppID) &&
				sameStringPointers(prior.BrowserDomain, segment.BrowserDomain) {
				prior.EndAt = segment.EndAt
				continue
			}
		}
		segment.Reasons = append([]string{}, segment.Reasons...)
		segments = append(segments, segment)
	}
	return segments
}

func aggregateSegments(segments []Segment) (Totals, error) {
	var totals Totals
	for index, segment := range segments {
		if !segment.EndAt.After(segment.StartAt) {
			return Totals{}, fmt.Errorf("segment %d has an invalid range", index)
		}
		seconds := segment.EndAt.Sub(segment.StartAt).Seconds()
		switch segment.Class {
		case ClassTask:
			totals.T += seconds
		case ClassRelatedTransition:
			totals.R += seconds
		case ClassDistraction:
			totals.D += seconds
		case ClassUnknown:
			totals.U += seconds
		case ClassInactive:
			totals.I += seconds
		default:
			return Totals{}, fmt.Errorf("segment %d has unknown class %q", index, segment.Class)
		}
	}
	return totals, nil
}

func containsRange(ranges []TimeRange, at time.Time) bool {
	for _, interval := range ranges {
		if at.Before(interval.StartAt) {
			return false
		}
		if at.Before(interval.EndAt) {
			return true
		}
	}
	return false
}

func evidenceAt(evidence []clippedEvidence, at time.Time) []clippedEvidence {
	active := make([]clippedEvidence, 0)
	for _, interval := range evidence {
		if at.Before(interval.startAt) {
			break
		}
		if at.Before(interval.endAt) {
			active = append(active, interval)
		}
	}
	return active
}

func isBrowserAppID(appID string) bool {
	switch strings.ToLower(appID) {
	case "com.google.chrome", "com.apple.safari":
		return true
	default:
		return false
	}
}

func normalizeHost(value string) (string, error) {
	if value == "" || strings.TrimSpace(value) != value || strings.ContainsAny(value, "/?#@") {
		return "", fmt.Errorf("must be a hostname")
	}
	if ip := net.ParseIP(value); ip != nil {
		return ip.String(), nil
	}
	if strings.Contains(value, ":") {
		return "", fmt.Errorf("must be a hostname without a port")
	}
	host := strings.TrimSuffix(strings.ToLower(value), ".")
	if host == "" || len(host) > 253 {
		return "", fmt.Errorf("hostname has an invalid length")
	}
	for _, label := range strings.Split(host, ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return "", fmt.Errorf("hostname has an invalid label")
		}
		for _, character := range label {
			if !(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '-' {
				return "", fmt.Errorf("hostname contains an invalid character")
			}
		}
	}
	return host, nil
}

func uniqueSorted(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			seen[value] = struct{}{}
		}
	}
	result := make([]string, 0, len(seen))
	for value := range seen {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}

func rangesSeconds(ranges []TimeRange) float64 {
	total := 0.0
	for _, interval := range ranges {
		total += interval.EndAt.Sub(interval.StartAt).Seconds()
	}
	return total
}

func cloneStringPointer(value *string) *string {
	if value == nil {
		return nil
	}
	clone := *value
	return &clone
}

func sameStringPointers(first, second *string) bool {
	if first == nil || second == nil {
		return first == nil && second == nil
	}
	return *first == *second
}

func sameStrings(first, second []string) bool {
	if len(first) != len(second) {
		return false
	}
	for index := range first {
		if first[index] != second[index] {
			return false
		}
	}
	return true
}

func cloneSession(session Session) Session {
	clone := session
	clone.Pauses = append([]TimeRange{}, session.Pauses...)
	clone.TaskSnapshot.Rules = append([]Rule{}, session.TaskSnapshot.Rules...)
	return clone
}

func cloneEvidence(evidence []EvidenceInterval) []EvidenceInterval {
	clone := make([]EvidenceInterval, len(evidence))
	for index, item := range evidence {
		clone[index] = item
		clone[index].Reasons = append([]string{}, item.Reasons...)
	}
	return clone
}

// 入力根拠と適用範囲を分け，セッション外の時刻を分類済みと誤解させない。
func appliedEvidence(input []clippedEvidence) []EvidenceInterval {
	result := make([]EvidenceInterval, 0, len(input))
	for _, item := range input {
		result = append(result, EvidenceInterval{StartAt: item.startAt, EndAt: item.endAt, Kind: item.kind, Source: item.source, Reasons: append([]string{}, item.reasons...)})
	}
	return result
}
