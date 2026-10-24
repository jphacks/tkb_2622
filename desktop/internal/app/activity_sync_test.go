package app

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
	"github.com/jphacks/tkb_2622/desktop/internal/evaluation"
	"github.com/jphacks/tkb_2622/desktop/internal/monitor"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
)

func TestFinishMonitoringAppendsTerminalRecord(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", home)
	configDirectory, err := os.UserConfigDir()
	if err != nil {
		t.Fatalf("user config directory: %v", err)
	}
	sessionID := "0123456789abcdef0123456789abcdef"
	sessionDirectory := filepath.Join(configDirectory, "Focus Link", "sessions")
	if err := os.MkdirAll(sessionDirectory, 0o700); err != nil {
		t.Fatalf("create session directory: %v", err)
	}
	start := time.Date(2026, time.October, 24, 9, 0, 0, 0, time.UTC)
	file, err := os.Create(filepath.Join(sessionDirectory, sessionID+".jsonl"))
	if err != nil {
		t.Fatalf("create session log: %v", err)
	}
	if err := json.NewEncoder(file).Encode(monitor.Record{Kind: "started", SessionID: sessionID, RecordedAt: start}); err != nil {
		_ = file.Close()
		t.Fatalf("write start record: %v", err)
	}
	if err := file.Close(); err != nil {
		t.Fatalf("close session log: %v", err)
	}

	recorder := monitor.New("")
	if err := recorder.RestoreSession(sessionID, monitor.Status{State: "paused"}); err != nil {
		t.Fatalf("restore recorder: %v", err)
	}
	engine := session.New("macos", start)
	engine.SetMode("local-monitor", start)
	engine.SetMonitor(session.MonitorStatus{State: "ready"}, start)
	engine.SetLocalStorageReady(true, start)
	if state := engine.ExecuteWithSessionID(session.Command{Action: "start"}, sessionID, start); state.Session == nil {
		t.Fatal("could not prepare local work session")
	}
	app := &App{engine: engine, recorder: recorder}
	app.finishMonitoring("aborted", start.Add(time.Minute))

	records, err := recorder.ReadRecords()
	if err != nil {
		t.Fatalf("read session log: %v", err)
	}
	if len(records) < 2 || records[len(records)-1].Kind != "aborted" {
		t.Fatalf("termination record was not persisted: %#v", records)
	}
}

func TestClearStaleTerminalEvaluationFailureKeepsActiveFailures(t *testing.T) {
	terminal := session.Snapshot{
		Session: &session.WorkSession{Status: "ABORTED"},
		Failure: &session.Failure{Code: "local_evaluation", Message: "old result failure"},
	}
	clearStaleTerminalEvaluationFailure(&terminal)
	if terminal.Failure != nil {
		t.Fatalf("terminal result failure remains as a global banner: %#v", terminal.Failure)
	}

	active := session.Snapshot{
		Session: &session.WorkSession{Status: "PAUSED"},
		Failure: &session.Failure{Code: "local_evaluation", Message: "active failure"},
	}
	clearStaleTerminalEvaluationFailure(&active)
	if active.Failure == nil {
		t.Fatal("active-session failure was cleared")
	}
}

func TestPrepareAbortOutboxKeepsUnacceptedSegmentsOutOfRewardBatches(t *testing.T) {
	start := time.Date(2026, time.October, 24, 10, 0, 0, 0, time.UTC)
	queuedSegment := cloud.ActivitySegment{
		StartTime: start.Add(10 * time.Second), EndTime: start.Add(20 * time.Second),
		Classification: "ACTIVITY_CLASS_TASK",
	}
	tailSegment := evaluation.ActivitySegment{
		StartTime: start.Add(20 * time.Second), EndTime: start.Add(30 * time.Second),
		Classification: "ACTIVITY_CLASS_DISTRACTION",
	}
	state := activitySyncState{
		SessionID: "session-1", NextSequence: 3, AcceptedThroughSeq: 1,
		ProducedThrough: start.Add(20 * time.Second),
		Items: []activitySyncItem{
			{Kind: "batch", Batch: &cloud.ActivityBatch{
				SessionID: "session-1", BatchID: "batch-2", Seq: 2,
				Segments: []cloud.ActivitySegment{queuedSegment},
			}},
			{Kind: "abort", Operation: &pendingSessionOperation{
				Kind: "abort", ID: "abort-1", ExpectedVersion: 2,
				OccurredAt: start.Add(30 * time.Second), LastSequence: 2,
			}},
		},
	}
	remote := cloud.Session{ID: "session-1", Status: "RUNNING", Version: 3, AcceptedThroughSeq: 1}

	prepared, err := prepareAbortOutbox(state, remote, []evaluation.ActivitySegment{tailSegment})
	if err != nil {
		t.Fatalf("Abort送信待ち状態の準備に失敗: %v", err)
	}
	if err := validateActivitySyncState(prepared); err != nil {
		t.Fatalf("準備後outboxが不正: %v", err)
	}
	if prepared.AcceptedThroughSeq != 1 || len(prepared.Items) != 1 || prepared.Items[0].Kind != "abort" {
		t.Fatalf("未確定batchが送信キューに残っている: %#v", prepared)
	}
	op := prepared.Items[0].Operation
	if !op.RemainingPrepared || op.LastSequence != 1 || op.ExpectedVersion != 3 {
		t.Fatalf("Abortの確定seq/versionが不正: %#v", op)
	}
	if len(op.Remaining) != 2 || op.Remaining[0].StartTime != queuedSegment.StartTime ||
		op.Remaining[0].EndTime != queuedSegment.EndTime || op.Remaining[0].Classification != queuedSegment.Classification ||
		op.Remaining[1].StartTime != tailSegment.StartTime || op.Remaining[1].EndTime != tailSegment.EndTime {
		t.Fatalf("未確定batchと末尾がRemainingへ正しく集約されていない: %#v", op.Remaining)
	}
}

func TestPrepareAbortOutboxExcludesBatchAlreadyAcceptedByServer(t *testing.T) {
	start := time.Date(2026, time.October, 24, 11, 0, 0, 0, time.UTC)
	queuedSegment := cloud.ActivitySegment{
		StartTime: start.Add(10 * time.Second), EndTime: start.Add(20 * time.Second),
		Classification: "ACTIVITY_CLASS_TASK",
	}
	tailSegment := evaluation.ActivitySegment{
		StartTime: start.Add(20 * time.Second), EndTime: start.Add(30 * time.Second),
		Classification: "ACTIVITY_CLASS_UNKNOWN",
	}
	state := activitySyncState{
		SessionID: "session-2", NextSequence: 3, AcceptedThroughSeq: 1,
		ProducedThrough: start.Add(20 * time.Second),
		Items: []activitySyncItem{
			{Kind: "batch", Batch: &cloud.ActivityBatch{
				SessionID: "session-2", BatchID: "batch-2", Seq: 2,
				Segments: []cloud.ActivitySegment{queuedSegment},
			}},
			{Kind: "abort", Operation: &pendingSessionOperation{
				Kind: "abort", ID: "abort-2", OccurredAt: start.Add(30 * time.Second), LastSequence: 2,
			}},
		},
	}
	remote := cloud.Session{ID: "session-2", Status: "RUNNING", Version: 5, AcceptedThroughSeq: 2}

	prepared, err := prepareAbortOutbox(state, remote, []evaluation.ActivitySegment{tailSegment})
	if err != nil {
		t.Fatalf("サーバー確定済みbatchの照合に失敗: %v", err)
	}
	op := prepared.Items[0].Operation
	if prepared.AcceptedThroughSeq != 2 || op.LastSequence != 2 {
		t.Fatalf("サーバー確定済みseqが反映されない: accepted=%d operation=%#v", prepared.AcceptedThroughSeq, op)
	}
	if len(op.Remaining) != 1 || op.Remaining[0].StartTime != tailSegment.StartTime || op.Remaining[0].Classification != tailSegment.Classification {
		t.Fatalf("サーバー確定済み区間をAbort Remainingへ再送している: %#v", op.Remaining)
	}
}

func TestPrepareAbortOutboxRejectsUnverifiableAcceptedSequence(t *testing.T) {
	start := time.Date(2026, time.October, 24, 12, 0, 0, 0, time.UTC)
	state := activitySyncState{
		SessionID: "session-3", NextSequence: 2, AcceptedThroughSeq: 1,
		ProducedThrough: start,
		Items: []activitySyncItem{{Kind: "abort", Operation: &pendingSessionOperation{
			Kind: "abort", ID: "abort-3", OccurredAt: start.Add(time.Second), LastSequence: 1,
		}}},
	}
	remote := cloud.Session{ID: "session-3", Status: "RUNNING", Version: 1, AcceptedThroughSeq: 2}
	if _, err := prepareAbortOutbox(state, remote, nil); err == nil {
		t.Fatal("local outboxにないサーバーseqを照合できた扱いにした")
	}
}
