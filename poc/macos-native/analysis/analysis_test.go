package analysis

import (
	"reflect"
	"strings"
	"testing"
	"time"

	"focuspocket/macos-native/model"
)

var testEpoch = time.Date(2026, time.October, 24, 0, 0, 0, 0, time.FixedZone("test", 9*60*60))

func testTime(seconds int) time.Time {
	return testEpoch.Add(time.Duration(seconds) * time.Second)
}

func testSnapshot(seconds int, appID, browserName, status, domain string) model.Snapshot {
	observedAt := testTime(seconds)
	return model.Snapshot{
		SchemaVersion:   "1",
		Source:          "macos-native",
		SampleStartedAt: observedAt.Add(-100 * time.Millisecond),
		ObservedAt:      observedAt,
		ReceivedAt:      observedAt.Add(200 * time.Millisecond),
		IdleObservedAt:  observedAt,
		AppID:           stringPointer(appID),
		AppName:         stringPointer("Editor"),
		BrowserName:     optionalString(browserName),
		BrowserDomain:   optionalString(domain),
		BrowserStatus:   status,
		TabID:           optionalString("tab-1"),
	}
}

func testCapture(start, end int, snapshots ...model.Snapshot) model.Capture {
	return model.Capture{
		SchemaVersion: "1",
		Source:        "macos-native",
		StartAt:       testTime(start),
		EndAt:         testTime(end),
		PollSeconds:   10,
		Snapshots:     snapshots,
	}
}

func optionalString(value string) *string {
	if value == "" {
		return nil
	}
	return stringPointer(value)
}

func TestAnalyzeCoversHalfOpenCaptureAndKeepsUnobservedEdgesUnknown(t *testing.T) {
	capture := testCapture(0, 30,
		testSnapshot(20, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(10, "com.example.editor", "", "not_applicable", ""),
	)
	analysis := Analyze(capture)

	if len(analysis.Intervals) != 3 {
		t.Fatalf("expected three contiguous intervals, got %#v", analysis.Intervals)
	}
	want := []struct {
		start, end int
		quality    string
	}{
		{0, 10, qualityUnknown},
		{10, 20, qualitySampleEstimate},
		{20, 30, qualityUnknown},
	}
	for index, interval := range analysis.Intervals {
		if !interval.StartAt.Equal(testTime(want[index].start)) || !interval.EndAt.Equal(testTime(want[index].end)) || interval.Quality != want[index].quality {
			t.Errorf("interval %d = (%v, %v, %q), want (%d, %d, %q)", index, interval.StartAt, interval.EndAt, interval.Quality, want[index].start, want[index].end, want[index].quality)
		}
	}
	if analysis.Report.ElapsedSeconds != 30 || analysis.Report.SampledSeconds != 10 || analysis.Report.UnknownSeconds != 20 {
		t.Errorf("unexpected duration report: %#v", analysis.Report)
	}
	if len(analysis.Report.Applications) != 1 || analysis.Report.Applications[0].EstimatedFrontmostSeconds != 10 {
		t.Errorf("unexpected application summary: %#v", analysis.Report.Applications)
	}
	if len(analysis.Events) != 2 || !analysis.Events[0].ObservedAt.Equal(testTime(10)) {
		t.Errorf("events are not sorted by observation time: %#v", analysis.Events)
	}
	for _, event := range analysis.Events {
		if !event.StartAt.Equal(event.ObservedAt) || !event.EndAt.Equal(event.ObservedAt) || event.AFKStatus != nil || event.Source != "macos-native" {
			t.Errorf("event was not normalized as a source-only point observation: %#v", event)
		}
	}
	assertCoverage(t, analysis)
}

func TestAnalyzeDeduplicatesAndMarksSimultaneousConflictUnknown(t *testing.T) {
	first := testSnapshot(10, "com.example.editor", "", "not_applicable", "")
	conflictA := testSnapshot(20, "com.example.editor", "", "not_applicable", "")
	conflictB := testSnapshot(20, "com.example.browser", "", "not_applicable", "")
	capture := testCapture(0, 30, conflictB, first, first, conflictA)
	analysis := Analyze(capture)
	if analysis.Report.DuplicateSnapshotCount != 1 {
		t.Errorf("duplicate count = %d, want 1", analysis.Report.DuplicateSnapshotCount)
	}
	if len(analysis.Events) != 3 || !analysis.Events[0].ObservedAt.Equal(testTime(10)) {
		t.Errorf("unexpected deduplicated/sorted events: %#v", analysis.Events)
	}
	interval := intervalAt(t, analysis, 10, 20)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "simultaneous_timestamp_conflict") {
		t.Errorf("conflicting same-time observations must invalidate their adjacent interval: %#v", interval)
	}
	if !reflect.DeepEqual(analysis, Analyze(capture)) {
		t.Error("conflict handling is not deterministic")
	}
	assertCoverage(t, analysis)
}

func TestAnalyzeKeepsStaleGapsAndLongProcessingUnknown(t *testing.T) {
	stale := testCapture(0, 20,
		testSnapshot(0, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(7, "com.example.editor", "", "not_applicable", ""),
	)
	stale.PollSeconds = 2
	staleResult := Analyze(stale)
	interval := intervalAt(t, staleResult, 0, 7)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "stale_observation_gap") {
		t.Errorf("stale observations were inferred as continuous: %#v", interval)
	}

	longProcessing := testCapture(0, 20,
		testSnapshot(0, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(10, "com.example.editor", "", "not_applicable", ""),
	)
	longProcessing.Snapshots[0].SampleStartedAt = testTime(-31)
	processingResult := Analyze(longProcessing)
	interval = intervalAt(t, processingResult, 0, 10)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "sample_processing_too_long") {
		t.Errorf("long observation processing was not marked unknown: %#v", interval)
	}
	assertCoverage(t, staleResult)
	assertCoverage(t, processingResult)
}

func TestAnalyzeInvalidFutureTimestampsPreventInference(t *testing.T) {
	observedAfterReceive := testCapture(0, 20,
		testSnapshot(10, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(20, "com.example.editor", "", "not_applicable", ""),
	)
	observedAfterReceive.Snapshots[0].ReceivedAt = testTime(9)
	result := Analyze(observedAfterReceive)
	interval := intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "observed_after_received") {
		t.Errorf("future observation was accepted: %#v", interval)
	}

	idleAfterReceive := testCapture(0, 20,
		testSnapshot(10, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(20, "com.example.editor", "", "not_applicable", ""),
	)
	idleAfterReceive.Snapshots[0].IdleSeconds = floatPointer(5)
	idleAfterReceive.Snapshots[0].IdleObservedAt = testTime(11)
	idleAfterReceive.Snapshots[0].ReceivedAt = testTime(10)
	result = Analyze(idleAfterReceive)
	interval = intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "idle_observed_after_received") {
		t.Errorf("future idle timestamp was accepted: %#v", interval)
	}
	assertCoverage(t, result)
}

func TestSanitizeIsIdempotentAndReducesOnlyValidHTTPSHost(t *testing.T) {
	valid := testSnapshot(10, "com.google.Chrome", "Chrome", "success", "HTTPS://Example.COM/path?private=1#frag")
	valid.LockState = nil
	valid.SleepState = nil
	unknownBrowser := testSnapshot(11, "com.example.mystery", "Mystery", "success", "private.example/path")
	invalidURL := testSnapshot(12, "com.apple.Safari", "Safari", "success", "file:///private/path")
	capture := testCapture(0, 20, valid, unknownBrowser, invalidURL)
	first := Sanitize(capture)
	second := Sanitize(first)
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("sanitize is not idempotent:\nfirst: %#v\nsecond: %#v", first, second)
	}
	if first.Source != "macos-native" || first.SchemaVersion != model.SchemaVersion {
		t.Errorf("capture source/schema was not fixed: %#v", first)
	}
	if got := *first.Snapshots[0].BrowserDomain; got != "example.com" {
		t.Errorf("domain = %q, want host-only example.com", got)
	}
	if first.Snapshots[0].BrowserStatus != "ok" {
		t.Errorf("native success status was not normalized: %q", first.Snapshots[0].BrowserStatus)
	}
	if first.Snapshots[0].LockState != nil || first.Snapshots[0].SleepState != nil {
		t.Error("unavailable lock/sleep signals must remain nil")
	}
	if first.Snapshots[1].BrowserDomain != nil || first.Snapshots[1].TabID != nil || first.Snapshots[1].BrowserStatus != "unknown" {
		t.Errorf("unknown browser metadata was not removed: %#v", first.Snapshots[1])
	}
	if first.Snapshots[2].BrowserDomain != nil || first.Snapshots[2].BrowserStatus != "unknown" {
		t.Errorf("non-http URL was not removed: %#v", first.Snapshots[2])
	}
	encoded := snapshotKey(first.Snapshots[0])
	if strings.Contains(encoded, "/path") || strings.Contains(encoded, "private=1") || strings.Contains(encoded, "#frag") {
		t.Errorf("raw URL details remained after sanitizing: %s", encoded)
	}
}

func TestAnalyzeSplitsAllIdleThresholdBoundaries(t *testing.T) {
	seconds := []int{50, 75, 170, 190, 290, 310}
	snapshots := make([]model.Snapshot, 0, len(seconds))
	for _, second := range seconds {
		snapshot := testSnapshot(second, "com.example.editor", "", "not_applicable", "")
		snapshot.IdleSeconds = floatPointer(float64(second))
		snapshots = append(snapshots, snapshot)
	}
	result := Analyze(testCapture(50, 310, snapshots...))
	for _, threshold := range []int{60, 180, 300} {
		if !hasBoundary(result.Intervals, threshold) {
			t.Errorf("missing idle threshold boundary at %d seconds", threshold)
		}
	}
	checkIdleValues(t, intervalAt(t, result, 60, 75), true, false, false)
	checkIdleValues(t, intervalAt(t, result, 180, 190), true, true, false)
	checkIdleValues(t, intervalAt(t, result, 300, 310), true, true, true)
	assertCoverage(t, result)
}

func TestAnalyzeLeavesIdleUnknownAfterInputResumption(t *testing.T) {
	first := testSnapshot(100, "com.example.editor", "", "not_applicable", "")
	first.IdleSeconds = floatPointer(70)
	second := testSnapshot(110, "com.example.editor", "", "not_applicable", "")
	second.IdleSeconds = floatPointer(5)
	result := Analyze(testCapture(100, 110, first, second))
	interval := intervalAt(t, result, 100, 110)
	for _, threshold := range idleThresholds {
		if interval.IdleOverThreshold[thresholdKey(threshold)] != nil {
			t.Errorf("idle threshold %d was guessed after input resumption: %#v", threshold, interval.IdleOverThreshold)
		}
	}
	if !contains(interval.Reasons, "idle_continuity_unknown") {
		t.Errorf("missing idle continuity reason: %#v", interval.Reasons)
	}
}

func TestAnalyzeRequiresMatchingBrowserStateAndExcludesUnknownDomains(t *testing.T) {
	first := testSnapshot(10, "com.google.Chrome", "Chrome", "success", "https://one.example/path")
	second := testSnapshot(20, "com.google.Chrome", "Chrome", "success", "https://two.example/path")
	result := Analyze(testCapture(10, 20, first, second))
	interval := intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || interval.BrowserDomain != nil || len(result.Report.Domains) != 2 {
		t.Errorf("changed browser domain was included in a sampled interval: %#v, domains=%v", interval, result.Report.Domains)
	}

	first = testSnapshot(10, "com.google.Chrome", "Chrome", "success", "https://one.example/path")
	second = testSnapshot(20, "com.google.Chrome", "Chrome", "timeout", "https://one.example/path")
	result = Analyze(testCapture(10, 20, first, second))
	interval = intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || interval.BrowserDomain != nil || len(result.Report.Domains) != 1 {
		t.Errorf("non-ok browser state was accepted: %#v, domains=%v", interval, result.Report.Domains)
	}

	first = testSnapshot(10, "com.google.Chrome", "Chrome", "success", "https://one.example/path")
	second = testSnapshot(20, "com.google.Chrome", "Chrome", "success", "https://one.example/path")
	result = Analyze(testCapture(10, 20, first, second))
	if len(result.Report.Domains) != 1 || result.Report.Domains[0] != "one.example" || result.Report.BrowserStates["ok"] != 2 {
		t.Errorf("matching successful browser observations were not summarized: %#v", result.Report)
	}
}

func TestAnalyzeFailuresAndPowerTransitionsInvalidateCrossedIntervals(t *testing.T) {
	capture := testCapture(10, 20,
		testSnapshot(10, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(20, "com.example.editor", "", "not_applicable", ""),
	)
	capture.Errors = []model.Failure{{ReceivedAt: testTime(15), Reason: "collector_timeout"}}
	result := Analyze(capture)
	interval := intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "capture_error_crossed_interval") {
		t.Errorf("failure timestamp was crossed by a sampled interval: %#v", interval)
	}

	capture = testCapture(10, 20,
		testSnapshot(10, "com.example.editor", "", "not_applicable", ""),
		testSnapshot(20, "com.example.editor", "", "not_applicable", ""),
	)
	capture.Snapshots[0].PowerEvent = stringPointer("sleep")
	powerAt := testTime(15)
	capture.Snapshots[0].PowerObservedAt = &powerAt
	result = Analyze(capture)
	interval = intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || !contains(interval.Reasons, "power_transition_crossed_interval") {
		t.Errorf("power transition was crossed by a sampled interval: %#v", interval)
	}
}

func TestAnalyzeDoesNotInferDomainsAcrossForegroundAppChange(t *testing.T) {
	first := testSnapshot(10, "com.google.Chrome", "Chrome", "success", "https://example.com/path")
	second := testSnapshot(20, "com.example.editor", "", "not_applicable", "")
	result := Analyze(testCapture(10, 20, first, second))
	interval := intervalAt(t, result, 10, 20)
	if interval.Quality != qualityUnknown || interval.BrowserDomain != nil || len(result.Report.Domains) != 1 {
		t.Errorf("domain was retained across a foreground-app change: %#v, domains=%v", interval, result.Report.Domains)
	}
}

func TestAnalyzeKeepsUnavailableAudioAFKLockAndSleepUnknown(t *testing.T) {
	snapshot := testSnapshot(10, "com.example.editor", "", "not_applicable", "")
	snapshot.Audible = nil
	snapshot.LockState = nil
	snapshot.SleepState = nil
	result := Analyze(testCapture(10, 20, snapshot))
	if result.Events[0].AFKStatus != nil {
		t.Errorf("AFK was inferred from an idle reading: %#v", result.Events[0])
	}
	cleaned := Sanitize(testCapture(10, 20, snapshot)).Snapshots[0]
	if cleaned.LockState != nil || cleaned.SleepState != nil || cleaned.Audible != nil {
		t.Errorf("unavailable signals were filled in: %#v", cleaned)
	}
}

func TestAnalyzeReportsEntireRangeUnknownWithoutObservations(t *testing.T) {
	result := Analyze(testCapture(0, 15))
	if len(result.Intervals) != 1 || result.Intervals[0].Quality != qualityUnknown || result.Report.UnknownSeconds != 15 {
		t.Fatalf("empty capture must remain fully unknown: %#v", result)
	}
	assertCoverage(t, result)
}

func intervalAt(t *testing.T, result model.Analysis, start, end int) model.Interval {
	t.Helper()
	for _, interval := range result.Intervals {
		if interval.StartAt.Equal(testTime(start)) && interval.EndAt.Equal(testTime(end)) {
			return interval
		}
	}
	t.Fatalf("no interval [%d, %d) found: %#v", start, end, result.Intervals)
	return model.Interval{}
}

func assertCoverage(t *testing.T, result model.Analysis) {
	t.Helper()
	if len(result.Intervals) == 0 {
		return
	}
	if !result.Intervals[0].StartAt.Equal(result.StartAt) || !result.Intervals[len(result.Intervals)-1].EndAt.Equal(result.EndAt) {
		t.Fatalf("intervals do not cover capture edges: %#v", result.Intervals)
	}
	duration := 0.0
	for index, interval := range result.Intervals {
		if !interval.EndAt.After(interval.StartAt) {
			t.Fatalf("interval %d is not a positive half-open interval: %#v", index, interval)
		}
		if index > 0 && !result.Intervals[index-1].EndAt.Equal(interval.StartAt) {
			t.Fatalf("intervals have a gap or overlap at %v", interval.StartAt)
		}
		duration += interval.EndAt.Sub(interval.StartAt).Seconds()
	}
	if duration != result.Report.ElapsedSeconds {
		t.Errorf("interval sum %v does not equal elapsed %v", duration, result.Report.ElapsedSeconds)
	}
	if result.Report.SampledSeconds > result.Report.ElapsedSeconds {
		t.Errorf("sampled seconds exceed elapsed: %#v", result.Report)
	}
	if result.Report.SampledSeconds+result.Report.UnknownSeconds != result.Report.ElapsedSeconds {
		t.Errorf("sampled and unknown seconds do not sum to elapsed: %#v", result.Report)
	}
	for _, application := range result.Report.Applications {
		if application.EstimatedFrontmostSeconds > result.Report.ElapsedSeconds {
			t.Errorf("application estimate exceeds elapsed: %#v", application)
		}
	}
}

func checkIdleValues(t *testing.T, interval model.Interval, over60, over180, over300 bool) {
	t.Helper()
	for threshold, expected := range map[int]bool{60: over60, 180: over180, 300: over300} {
		value := interval.IdleOverThreshold[thresholdKey(threshold)]
		if value == nil || *value != expected {
			t.Errorf("idle threshold %d = %v, want %v in interval [%v, %v)", threshold, value, expected, interval.StartAt, interval.EndAt)
		}
	}
}

func hasBoundary(intervals []model.Interval, seconds int) bool {
	for _, interval := range intervals {
		if interval.StartAt.Equal(testTime(seconds)) || interval.EndAt.Equal(testTime(seconds)) {
			return true
		}
	}
	return false
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func floatPointer(value float64) *float64 { return &value }

func TestBrowserIdentityAndMissingContextStayUnknown(t *testing.T) {
	for _, tc := range []struct{ name, app, browser, status, domain string }{
		{"mismatched app", "com.microsoft.VSCode", "Chrome", "ok", "example.com"},
		{"mismatched browser", "com.google.Chrome", "Safari", "ok", "example.com"},
		{"permission denied", "com.google.Chrome", "Chrome", "permission_denied", ""},
		{"foreground race", "com.google.Chrome", "Chrome", "foreground_changed", ""},
		{"domain missing", "com.google.Chrome", "Chrome", "ok", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := testCapture(0, 10, testSnapshot(0, tc.app, tc.browser, tc.status, tc.domain), testSnapshot(10, tc.app, tc.browser, tc.status, tc.domain))
			a := Analyze(c)
			if a.Report.SampledSeconds != 0 || a.Report.UnknownSeconds != 10 {
				t.Fatalf("unconfirmed browser accepted: %+v", a.Report)
			}
			if tc.name == "mismatched app" && len(a.Report.Domains) != 0 {
				t.Fatalf("domain attached to unrelated app: %v", a.Report.Domains)
			}
		})
	}
}
func TestRejectForeignSourceAndPreserveInput(t *testing.T) {
	c := testCapture(0, 10, testSnapshot(0, "com.example.editor", "", "not_applicable", ""), testSnapshot(10, "com.example.editor", "", "not_applicable", ""))
	c.Errors = []model.Failure{{ReceivedAt: testTime(9), Reason: "later"}, {ReceivedAt: testTime(1), Reason: "earlier"}}
	before := snapshotKey(c.Snapshots[0])
	beforeError := c.Errors[0]
	_ = Sanitize(c)
	if snapshotKey(c.Snapshots[0]) != before || c.Errors[0] != beforeError {
		t.Fatal("Sanitize mutated caller input")
	}
	c.Errors = nil
	c.Snapshots[0].Source = "another-collector"
	a := Analyze(c)
	if a.Report.SampledSeconds != 0 || a.Report.InvalidSnapshotCount == 0 {
		t.Fatal("foreign snapshot relabeled as native")
	}
	c.Source = "another-collector"
	a = Analyze(c)
	if a.Report.UnknownSeconds != 10 {
		t.Fatal("foreign capture accepted")
	}
}
func TestIdleMeasurementMustBeInsideSample(t *testing.T) {
	c := testCapture(0, 10, testSnapshot(0, "com.example.editor", "", "not_applicable", ""), testSnapshot(10, "com.example.editor", "", "not_applicable", ""))
	value := 60.0
	for i := range c.Snapshots {
		c.Snapshots[i].IdleSeconds = &value
		c.Snapshots[i].IdleObservedAt = c.Snapshots[i].ObservedAt.Add(100 * time.Millisecond)
	}
	a := Analyze(c)
	if a.Report.SampledSeconds != 0 || a.Report.InvalidSnapshotCount != 2 {
		t.Fatalf("invalid idle timestamp accepted: %+v", a.Report)
	}
}
func TestPointObservationHasNoFabricatedDuration(t *testing.T) {
	c := testCapture(0, 10, testSnapshot(5, "com.google.Chrome", "Chrome", "ok", "github.com"))
	a := Analyze(c)
	if a.Report.SampledSeconds != 0 || len(a.Report.Applications) != 1 || a.Report.Applications[0].EstimatedFrontmostSeconds != 0 || len(a.Report.Domains) != 1 {
		t.Fatalf("single point lost or extended: %+v", a.Report)
	}
}

func TestOutsideCaptureDoesNotRefreshLastSuccess(t *testing.T) {
	c := testCapture(0, 10, testSnapshot(5, "com.example.editor", "", "not_applicable", ""), testSnapshot(15, "com.example.editor", "", "not_applicable", ""))
	a := Analyze(c)
	if a.Report.LastSuccessAt == nil || !a.Report.LastSuccessAt.Equal(testTime(5).Add(200*time.Millisecond)) {
		t.Fatalf("outside observation refreshed session: %+v", a.Report)
	}
	if a.Report.InvalidSnapshotCount != 1 {
		t.Fatal("outside observation not flagged")
	}
}
func TestFailureAtIntervalStartIsUnknown(t *testing.T) {
	c := testCapture(10, 20, testSnapshot(10, "com.example.editor", "", "not_applicable", ""), testSnapshot(20, "com.example.editor", "", "not_applicable", ""))
	c.Errors = []model.Failure{{ReceivedAt: testTime(10), Reason: "fixture_failure"}}
	a := Analyze(c)
	if a.Report.SampledSeconds != 0 || a.Report.UnknownSeconds != 10 {
		t.Fatal("failure boundary accepted as continuous observation")
	}
}
