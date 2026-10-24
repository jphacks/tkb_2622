package evaluation

import (
	"math"
	"strings"
	"testing"
	"time"

	"focuspocket/macos-native/analysis"
	"focuspocket/macos-native/model"
)

var evaluationEpoch = time.Date(2026, time.October, 24, 0, 0, 0, 0, time.UTC)

func evaluationTime(seconds int) time.Time {
	return evaluationEpoch.Add(time.Duration(seconds) * time.Second)
}

func evaluationSession(rules ...Rule) Session {
	return Session{
		ID: "session-1",
		TaskSnapshot: TaskSnapshot{
			ID:           "task-1",
			Name:         "Sample task",
			Mode:         "NORMAL",
			RulesVersion: "rules-v1",
			Rules:        rules,
		},
		Pauses: []TimeRange{},
	}
}

func evaluationInterval(start, end int, appID, domain, quality string) model.Interval {
	return model.Interval{
		StartAt:           evaluationTime(start),
		EndAt:             evaluationTime(end),
		AppID:             stringPointer(appID),
		BrowserDomain:     optionalString(domain),
		IdleOverThreshold: falseIdleValues(),
		Quality:           quality,
		Reasons:           []string{"fixture"},
	}
}

func evaluationAnalysis(start, end int, intervals ...model.Interval) model.Analysis {
	return model.Analysis{
		SchemaVersion: model.SchemaVersion,
		StartAt:       evaluationTime(start),
		EndAt:         evaluationTime(end),
		Intervals:     intervals,
	}
}

func falseIdleValues() map[string]*bool {
	falseValue := func() *bool {
		value := false
		return &value
	}
	return map[string]*bool{
		"60":  falseValue(),
		"180": falseValue(),
		"300": falseValue(),
	}
}

func stringPointer(value string) *string {
	return &value
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return stringPointer(value)
}

func requireNear(t *testing.T, got, want float64) {
	t.Helper()
	if math.Abs(got-want) > 1e-8 {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestValidateSessionRejectsInvalidRulesAndSnapshots(t *testing.T) {
	valid := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	cases := []struct {
		name    string
		session Session
		want    string
	}{
		{"empty session id", func() Session { value := valid; value.ID = " "; return value }(), "session id"},
		{"empty task id", func() Session { value := valid; value.TaskSnapshot.ID = ""; return value }(), "task_snapshot.id"},
		{"invalid mode", func() Session { value := valid; value.TaskSnapshot.Mode = "FOCUS"; return value }(), "mode"},
		{"invalid class", evaluationSession(Rule{AppID: "com.example.editor", Class: "OTHER"}), "class"},
		{"browser domain required", evaluationSession(Rule{AppID: "com.google.Chrome", Class: RuleTask}), "domain is required"},
		{"duplicate rule", evaluationSession(
			Rule{AppID: "com.example.editor", Class: RuleTask},
			Rule{AppID: "com.example.editor", Class: RuleTask},
		), "duplicated or conflicting"},
		{"conflicting browser rules", evaluationSession(
			Rule{AppID: "com.google.Chrome", Domain: "Example.com.", Class: RuleTask},
			Rule{AppID: "com.google.Chrome", Domain: "example.com", Class: RuleDistraction},
		), "duplicated or conflicting"},
		{"domain on non-browser", evaluationSession(
			Rule{AppID: "com.example.editor", Domain: "example.com", Class: RuleTask},
		), "only supported for Chrome and Safari"},
		{"invalid domain", evaluationSession(Rule{AppID: "com.example.editor", Domain: "https://example.com/a", Class: RuleTask}), "hostname"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			err := ValidateSession(testCase.session)
			if err == nil || !strings.Contains(err.Error(), testCase.want) {
				t.Fatalf("ValidateSession() error = %v, want substring %q", err, testCase.want)
			}
		})
	}
}

func TestValidateSessionAcceptsDistinctBrowserHosts(t *testing.T) {
	session := evaluationSession(
		Rule{AppID: "com.google.Chrome", Domain: "Example.com.", Class: RuleTask},
		Rule{AppID: "com.google.Chrome", Domain: "other.example", Class: RuleDistraction},
	)
	if err := ValidateSession(session); err != nil {
		t.Fatalf("ValidateSession() error = %v", err)
	}
}

func TestEvaluateAggregatesThirtyMinuteExample(t *testing.T) {
	session := evaluationSession(
		Rule{AppID: "com.example.editor", Class: RuleTask},
		Rule{AppID: "com.example.docs", Class: RuleRelatedTransition},
		Rule{AppID: "com.example.video", Class: RuleDistraction},
	)
	observed := evaluationAnalysis(0, 1800,
		evaluationInterval(0, 1200, "com.example.editor", "", qualitySampleBasedEstimate),
		evaluationInterval(1200, 1500, "com.example.docs", "", qualitySampleBasedEstimate),
		evaluationInterval(1500, 1680, "com.example.video", "", qualitySampleBasedEstimate),
	)
	evidence := []EvidenceInterval{{
		StartAt: evaluationTime(1740),
		EndAt:   evaluationTime(1800),
		Kind:    EvidenceLock,
		Source:  "fixture-lock-feed",
	}}

	result, err := EvaluateWithEvidence(session, observed, evidence)
	if err != nil {
		t.Fatalf("EvaluateWithEvidence() error = %v", err)
	}
	if result.Totals != (Totals{T: 1200, R: 300, D: 180, U: 60, I: 60}) {
		t.Fatalf("totals = %+v", result.Totals)
	}
	if result.WorkSeconds != 1500 || result.KnownSeconds != 1680 || result.ElapsedSeconds != 1800 {
		t.Fatalf("unexpected duration metrics: %+v", result)
	}
	requireNear(t, *result.B, 100*1500.0/1680.0)
	requireNear(t, *result.Q, 1740.0/1800.0)
	requireNear(t, *result.WorkRate, 1500.0/1800.0)
	if result.EvaluatorVersion != EvaluatorVersion || result.Session.TaskSnapshot.RulesVersion != "rules-v1" {
		t.Fatalf("result did not preserve the evaluator and rules versions: %+v", result)
	}
}

func TestDistractionThresholdIsInclusiveAndRetrospective(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.video", Class: RuleDistraction})

	short := model.Analysis{
		SchemaVersion: model.SchemaVersion,
		StartAt:       evaluationEpoch,
		EndAt:         evaluationEpoch.Add(9999 * time.Millisecond),
		Intervals: []model.Interval{{
			StartAt:           evaluationEpoch,
			EndAt:             evaluationEpoch.Add(9999 * time.Millisecond),
			AppID:             stringPointer("com.example.video"),
			IdleOverThreshold: falseIdleValues(),
			Quality:           qualitySampleBasedEstimate,
		}},
	}
	shortResult, err := Evaluate(session, short)
	if err != nil {
		t.Fatalf("Evaluate(short) error = %v", err)
	}
	requireNear(t, shortResult.Totals.U, 9.999)
	if shortResult.Totals.D != 0 {
		t.Fatalf("short distraction streak classified D: %+v", shortResult.Totals)
	}

	exact := model.Analysis{
		SchemaVersion: model.SchemaVersion,
		StartAt:       evaluationEpoch,
		EndAt:         evaluationEpoch.Add(10 * time.Second),
		Intervals: []model.Interval{{
			StartAt:           evaluationEpoch,
			EndAt:             evaluationEpoch.Add(10 * time.Second),
			AppID:             stringPointer("com.example.video"),
			IdleOverThreshold: falseIdleValues(),
			Quality:           qualitySampleBasedEstimate,
		}},
	}
	exactResult, err := Evaluate(session, exact)
	if err != nil {
		t.Fatalf("Evaluate(exact) error = %v", err)
	}
	if exactResult.Totals.D != 10 || exactResult.Totals.U != 0 {
		t.Fatalf("10-second streak was not promoted to D: %+v", exactResult.Totals)
	}
}

func TestGapAndPauseBreakDistractionContinuity(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.video", Class: RuleDistraction})
	observed := model.Analysis{
		SchemaVersion: model.SchemaVersion,
		StartAt:       evaluationTime(0),
		EndAt:         evaluationTime(11),
		Intervals: []model.Interval{
			evaluationInterval(0, 5, "com.example.video", "", qualitySampleBasedEstimate),
			evaluationInterval(6, 11, "com.example.video", "", qualitySampleBasedEstimate),
		},
	}
	result, err := Evaluate(session, observed)
	if err != nil {
		t.Fatalf("Evaluate(gap) error = %v", err)
	}
	if result.Totals.D != 0 || result.Totals.U != 11 {
		t.Fatalf("distraction bridged an analysis gap: %+v", result.Totals)
	}

	session.Pauses = []TimeRange{{StartAt: evaluationTime(5), EndAt: evaluationTime(6)}}
	observed.Intervals[1].StartAt = evaluationTime(6)
	observed.Intervals[1].EndAt = evaluationTime(11)
	result, err = Evaluate(session, observed)
	if err != nil {
		t.Fatalf("Evaluate(pause) error = %v", err)
	}
	if result.Totals.D != 0 || result.Totals.U != 10 || result.Totals.I != 0 {
		t.Fatalf("distraction bridged a pause: %+v", result.Totals)
	}
	if result.SessionSeconds != 11 || result.PausedSeconds != 1 || result.ElapsedSeconds != 10 {
		t.Fatalf("pause was not removed from active elapsed time: %+v", result)
	}
}

func TestIdleThresholdUnknownOrTrueStaysUnknown(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	unknown := evaluationInterval(0, 10, "com.example.editor", "", qualitySampleBasedEstimate)
	unknown.IdleOverThreshold = nil
	result, err := Evaluate(session, evaluationAnalysis(0, 10, unknown))
	if err != nil {
		t.Fatalf("Evaluate(nil idle values) error = %v", err)
	}
	if result.Totals.U != 10 || result.Totals.T != 0 {
		t.Fatalf("nil idle threshold was classified: %+v", result.Totals)
	}

	idle := evaluationInterval(0, 10, "com.example.editor", "", qualitySampleBasedEstimate)
	trueValue := true
	idle.IdleOverThreshold["60"] = &trueValue
	result, err = Evaluate(session, evaluationAnalysis(0, 10, idle))
	if err != nil {
		t.Fatalf("Evaluate(true idle value) error = %v", err)
	}
	if result.Totals.U != 10 || result.Totals.T != 0 {
		t.Fatalf("true idle threshold was classified: %+v", result.Totals)
	}
}

func TestBrowserRulesRequireExactDomainAndMissingContextIsUnknown(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.google.Chrome", Domain: "example.com", Class: RuleTask})
	missing := evaluationInterval(0, 10, "com.google.Chrome", "", qualitySampleBasedEstimate)
	subdomain := evaluationInterval(10, 20, "com.google.Chrome", "docs.example.com", qualitySampleBasedEstimate)
	exact := evaluationInterval(20, 30, "com.google.Chrome", "EXAMPLE.COM.", qualitySampleBasedEstimate)
	result, err := Evaluate(session, evaluationAnalysis(0, 30, missing, subdomain, exact))
	if err != nil {
		t.Fatalf("Evaluate(browser) error = %v", err)
	}
	if result.Totals.U != 20 || result.Totals.T != 10 {
		t.Fatalf("browser domain matching was not exact: %+v", result.Totals)
	}
}

func TestQualityAndGapsStayUnknownAndOverlapsAreRejected(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	nonEstimate := evaluationInterval(2, 8, "com.example.editor", "", "point_observation")
	result, err := Evaluate(session, evaluationAnalysis(0, 10, nonEstimate))
	if err != nil {
		t.Fatalf("Evaluate(non-estimate) error = %v", err)
	}
	if result.Totals.U != 10 {
		t.Fatalf("non-estimate quality or gaps were counted as known: %+v", result.Totals)
	}

	first := evaluationInterval(0, 7, "com.example.editor", "", qualitySampleBasedEstimate)
	second := evaluationInterval(6, 10, "com.example.editor", "", qualitySampleBasedEstimate)
	_, err = Evaluate(session, evaluationAnalysis(0, 10, first, second))
	if err == nil || !strings.Contains(err.Error(), "overlap") {
		t.Fatalf("overlapping intervals should fail, got %v", err)
	}
}

func TestZeroDurationHasNullableRates(t *testing.T) {
	session := evaluationSession()
	at := evaluationTime(0)
	result, err := Evaluate(session, model.Analysis{SchemaVersion: model.SchemaVersion, StartAt: at, EndAt: at})
	if err != nil {
		t.Fatalf("Evaluate(zero duration) error = %v", err)
	}
	if result.ElapsedSeconds != 0 || result.Totals != (Totals{}) || len(result.Segments) != 0 {
		t.Fatalf("unexpected zero-duration result: %+v", result)
	}
	if result.B != nil || result.Q != nil || result.WorkRate != nil {
		t.Fatalf("zero denominators must produce nullable metrics: %+v", result)
	}
}

func TestEvidenceCreatesInactiveTwentyFiveMinuteIdleExampleAndIsDeepCopied(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	observed := evaluationAnalysis(0, 1800,
		evaluationInterval(0, 1800, "com.example.editor", "", qualitySampleBasedEstimate),
	)
	evidence := []EvidenceInterval{{
		StartAt: evaluationTime(300),
		EndAt:   evaluationTime(1800),
		Kind:    EvidenceSleep,
		Source:  "fixture-lock-feed",
		Reasons: []string{"confirmed_by_fixture"},
	}}
	result, err := EvaluateWithEvidence(session, observed, evidence)
	if err != nil {
		t.Fatalf("EvaluateWithEvidence() error = %v", err)
	}
	if result.Totals.I != 1500 || result.Totals.T != 300 || result.Totals.U != 0 {
		t.Fatalf("5-minute task + 25-minute inactive totals = %+v", result.Totals)
	}
	if len(result.Evidence) != 1 || result.Evidence[0].Source != "fixture-lock-feed" {
		t.Fatalf("evidence was not preserved in the result: %+v", result.Evidence)
	}
	requireNear(t, *result.B, 100)
	requireNear(t, *result.Q, 1)
	requireNear(t, *result.WorkRate, 300.0/1800.0)

	session.TaskSnapshot.Rules[0].Class = RuleDistraction
	session.Pauses = append(session.Pauses, TimeRange{StartAt: evaluationTime(0), EndAt: evaluationTime(1)})
	evidence[0].Reasons[0] = "mutated"
	if result.Session.TaskSnapshot.Rules[0].Class != RuleTask || len(result.Session.Pauses) != 0 ||
		result.Evidence[0].Reasons[0] != "confirmed_by_fixture" {
		t.Fatal("result retained mutable slices from input")
	}
}

func TestEvidenceRequiresKindAndSource(t *testing.T) {
	session := evaluationSession()
	observed := evaluationAnalysis(0, 10)
	for _, evidence := range []EvidenceInterval{
		{StartAt: evaluationTime(0), EndAt: evaluationTime(1), Kind: "IDLE", Source: "fixture"},
		{StartAt: evaluationTime(0), EndAt: evaluationTime(1), Kind: EvidenceLock},
	} {
		if _, err := EvaluateWithEvidence(session, observed, []EvidenceInterval{evidence}); err == nil {
			t.Fatalf("invalid evidence accepted: %+v", evidence)
		}
	}
}

func TestPauseOverridesObservedClassification(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	session.Pauses = []TimeRange{{StartAt: evaluationTime(3), EndAt: evaluationTime(7)}}
	result, err := Evaluate(session, evaluationAnalysis(0, 10,
		evaluationInterval(0, 10, "com.example.editor", "", qualitySampleBasedEstimate),
	))
	if err != nil {
		t.Fatalf("Evaluate(pause) error = %v", err)
	}
	if result.Totals.T != 6 || result.Totals.I != 0 {
		t.Fatalf("pause must be excluded from class totals: %+v", result.Totals)
	}
	if result.SessionSeconds != 10 || result.PausedSeconds != 4 || result.ElapsedSeconds != 6 {
		t.Fatalf("pause duration metrics = %+v", result)
	}
	for _, segment := range result.Segments {
		if segment.StartAt.Before(evaluationTime(7)) && segment.EndAt.After(evaluationTime(3)) {
			t.Fatalf("pause leaked into segments: %+v", segment)
		}
	}
}

func TestModeUsesOnlyItsIdleThreshold(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	interval := evaluationInterval(0, 10, "com.example.editor", "", qualitySampleBasedEstimate)
	trueValue := true
	interval.IdleOverThreshold["180"] = &trueValue
	normal, err := Evaluate(session, evaluationAnalysis(0, 10, interval))
	if err != nil {
		t.Fatalf("Evaluate(NORMAL) error = %v", err)
	}
	if normal.Totals.T != 10 {
		t.Fatalf("NORMAL should use the 60-second threshold: %+v", normal.Totals)
	}

	session.TaskSnapshot.Mode = "READING"
	readingInterval := evaluationInterval(0, 10, "com.example.editor", "", qualitySampleBasedEstimate)
	readingInterval.IdleOverThreshold["180"] = nil
	reading, err := Evaluate(session, evaluationAnalysis(0, 10, readingInterval))
	if err != nil {
		t.Fatalf("Evaluate(READING) error = %v", err)
	}
	if reading.Totals.U != 10 {
		t.Fatalf("READING should use the 180-second threshold: %+v", reading.Totals)
	}
}

func TestValidateSessionRejectsInvalidPauseAndAnalysisSchema(t *testing.T) {
	session := evaluationSession()
	session.Pauses = []TimeRange{{StartAt: evaluationTime(1), EndAt: evaluationTime(1)}}
	if err := ValidateSession(session); err == nil || !strings.Contains(err.Error(), "pause 0") {
		t.Fatalf("invalid pause range was accepted: %v", err)
	}

	session = evaluationSession()
	observed := evaluationAnalysis(0, 10)
	observed.SchemaVersion = "unsupported"
	if _, err := Evaluate(session, observed); err == nil || !strings.Contains(err.Error(), "schema_version") {
		t.Fatalf("unsupported analysis schema was accepted: %v", err)
	}
}

func TestFullyPausedSessionHasZeroActiveMetrics(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask})
	session.Pauses = []TimeRange{{StartAt: evaluationTime(0), EndAt: evaluationTime(10)}}
	result, err := Evaluate(session, evaluationAnalysis(0, 10,
		evaluationInterval(0, 10, "com.example.editor", "", qualitySampleBasedEstimate),
	))
	if err != nil {
		t.Fatalf("Evaluate(fully paused) error = %v", err)
	}
	if result.SessionSeconds != 10 || result.PausedSeconds != 10 || result.ElapsedSeconds != 0 || result.Totals != (Totals{}) {
		t.Fatalf("unexpected fully paused result: %+v", result)
	}
	if result.B != nil || result.Q != nil || result.WorkRate != nil {
		t.Fatalf("fully paused session must have nullable rates: %+v", result)
	}
}

func TestDifferentAppsDoNotMergeSegmentsOrDistractionStreaks(t *testing.T) {
	taskSession := evaluationSession(
		Rule{AppID: "com.example.editor", Class: RuleTask},
		Rule{AppID: "com.example.docs", Class: RuleTask},
	)
	taskResult, err := Evaluate(taskSession, evaluationAnalysis(0, 10,
		evaluationInterval(0, 5, "com.example.editor", "", qualitySampleBasedEstimate),
		evaluationInterval(5, 10, "com.example.docs", "", qualitySampleBasedEstimate),
	))
	if err != nil {
		t.Fatalf("Evaluate(task context) error = %v", err)
	}
	if len(taskResult.Segments) != 2 || taskResult.Segments[0].AppID == nil || taskResult.Segments[1].AppID == nil ||
		*taskResult.Segments[0].AppID != "com.example.editor" || *taskResult.Segments[1].AppID != "com.example.docs" {
		t.Fatalf("segments lost their app context: %+v", taskResult.Segments)
	}

	distractionSession := evaluationSession(
		Rule{AppID: "com.example.video", Class: RuleDistraction},
		Rule{AppID: "com.example.game", Class: RuleDistraction},
	)
	distractionResult, err := Evaluate(distractionSession, evaluationAnalysis(0, 10,
		evaluationInterval(0, 5, "com.example.video", "", qualitySampleBasedEstimate),
		evaluationInterval(5, 10, "com.example.game", "", qualitySampleBasedEstimate),
	))
	if err != nil {
		t.Fatalf("Evaluate(distraction context) error = %v", err)
	}
	if distractionResult.Totals.D != 0 || distractionResult.Totals.U != 10 {
		t.Fatalf("different apps combined into a distraction streak: %+v", distractionResult.Totals)
	}
}

func TestEvidenceClippingPausePriorityAndOverlap(t *testing.T) {
	session := evaluationSession()
	session.Pauses = []TimeRange{{StartAt: evaluationTime(4), EndAt: evaluationTime(6)}}
	evidence := []EvidenceInterval{
		{StartAt: evaluationTime(-10), EndAt: evaluationTime(20), Kind: EvidenceSleep, Source: "fixture"},
		{StartAt: evaluationTime(2), EndAt: evaluationTime(8), Kind: EvidenceLock, Source: "fixture"},
		{StartAt: evaluationTime(30), EndAt: evaluationTime(40), Kind: EvidenceLock, Source: "outside"},
	}
	result, err := EvaluateWithEvidence(session, evaluationAnalysis(0, 10), evidence)
	if err != nil {
		t.Fatal(err)
	}
	if result.Totals.I != 8 || result.ElapsedSeconds != 8 || result.PausedSeconds != 2 || result.Q == nil || *result.Q != 1 {
		t.Fatalf("pause or overlapping evidence counted twice: %+v", result)
	}
	if len(result.Evidence) != 2 || !result.Evidence[0].StartAt.Equal(evaluationTime(0)) || !result.Evidence[0].EndAt.Equal(evaluationTime(10)) || len(result.InputEvidence) != 3 {
		t.Fatalf("applied and input evidence not separated: %+v", result)
	}
}

func TestRepeatedShortDistractionsRemainUnknownAndReduceCoverage(t *testing.T) {
	session := evaluationSession(Rule{AppID: "com.example.editor", Class: RuleTask}, Rule{AppID: "com.example.video", Class: RuleDistraction})
	intervals := []model.Interval{}
	for start := 0; start < 30; start += 6 {
		intervals = append(intervals, evaluationInterval(start, start+5, "com.example.video", "", qualitySampleBasedEstimate), evaluationInterval(start+5, start+6, "com.example.editor", "", qualitySampleBasedEstimate))
	}
	result, err := Evaluate(session, evaluationAnalysis(0, 30, intervals...))
	if err != nil {
		t.Fatal(err)
	}
	if result.Totals.D != 0 || result.Totals.U != 25 || result.WorkSeconds != 5 {
		t.Fatalf("short visits inflated known/work seconds: %+v", result)
	}
	requireNear(t, *result.B, 100)
	requireNear(t, *result.Q, 1.0/6)
	requireNear(t, *result.WorkRate, 1.0/6)
	unknown, err := Evaluate(evaluationSession(), evaluationAnalysis(0, 10))
	if err != nil {
		t.Fatal(err)
	}
	if unknown.B != nil || unknown.Q == nil || *unknown.Q != 0 || unknown.WorkRate == nil || *unknown.WorkRate != 0 {
		t.Fatalf("all unknown metrics not held: %+v", unknown)
	}
}

func TestDistractionPersistsAcrossInputResetsInSameContext(t *testing.T) {
	capture := model.Capture{SchemaVersion: model.SchemaVersion, Source: "macos-native", StartAt: evaluationTime(0), EndAt: evaluationTime(22), PollSeconds: 1}
	appID, browser, domain := "com.google.Chrome", "Chrome", "example.com"
	for second := 1; second <= 21; second++ {
		at := evaluationTime(second)
		idle := float64((second - 1) % 9)
		capture.Snapshots = append(capture.Snapshots, model.Snapshot{SchemaVersion: model.SchemaVersion, Source: "macos-native", SampleStartedAt: at.Add(-time.Millisecond * 100), ObservedAt: at, ReceivedAt: at.Add(time.Millisecond * 10), IdleObservedAt: at, IdleSeconds: &idle, AppID: &appID, BrowserName: &browser, BrowserDomain: &domain, BrowserStatus: "ok"})
	}
	session := evaluationSession(Rule{AppID: appID, Domain: domain, Class: RuleDistraction})
	result, err := Evaluate(session, analysis.Analyze(capture))
	if err != nil {
		t.Fatal(err)
	}
	if result.Totals.D != 20 || result.Totals.U != 2 || result.B == nil || *result.B != 0 {
		t.Fatalf("input resets broke continuous context: %+v", result)
	}
	for _, fail := range []struct {
		name  string
		alter func(*model.Capture)
	}{
		{"failure", func(c *model.Capture) {
			c.Errors = []model.Failure{{ReceivedAt: evaluationTime(11), Reason: "fixture_failure"}}
		}},
		{"domain change", func(c *model.Capture) { other := "other.example"; c.Snapshots[10].BrowserDomain = &other }},
		{"missing idle", func(c *model.Capture) { c.Snapshots[10].IdleSeconds = nil }},
		{"stale gap", func(c *model.Capture) { c.Snapshots = append(c.Snapshots[:8:8], c.Snapshots[12:]...) }},
	} {
		t.Run(fail.name, func(t *testing.T) {
			copyCapture := capture
			copyCapture.Snapshots = append([]model.Snapshot{}, capture.Snapshots...)
			fail.alter(&copyCapture)
			changed, err := Evaluate(session, analysis.Analyze(copyCapture))
			if err != nil {
				t.Fatal(err)
			}
			if changed.Totals.D >= 20 || changed.Totals.U <= 2 {
				t.Fatalf("uncertainty bridged: %+v", changed)
			}
		})
	}
}
