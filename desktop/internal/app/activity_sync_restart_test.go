package app

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
	"github.com/jphacks/tkb_2622/desktop/internal/monitor"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
)

func TestPrepareActivitySyncAfterRestartUsesSavedSessionCapture(t *testing.T) {
	for _, status := range []string{"ABORTED", "FINALIZED"} {
		t.Run(status, func(t *testing.T) {
			app, endedAt, capturePath := restoredTerminalActivityApp(t, status)
			before, err := os.ReadFile(capturePath)
			if err != nil {
				t.Fatal(err)
			}

			if err := app.prepareActivitySync(endedAt, true); err != nil {
				t.Fatalf("cannot prepare saved activity after restarting: %v", err)
			}
			queued, _, err := app.store.LoadActivitySyncState()
			if err != nil {
				t.Fatal(err)
			}
			if !queued.ProducedThrough.Equal(endedAt) || len(queued.Items) == 0 {
				t.Fatalf("saved activity was not queued through the terminal boundary: %+v", queued)
			}
			if err := app.prepareActivitySync(endedAt, true); err != nil {
				t.Fatalf("retrying preparation failed: %v", err)
			}
			retried, _, err := app.store.LoadActivitySyncState()
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(queued, retried) {
				t.Fatal("retrying preparation duplicated or changed queued activity")
			}
			after, err := os.ReadFile(capturePath)
			if err != nil || !bytes.Equal(before, after) {
				t.Fatalf("upload preparation changed the original capture: %v", err)
			}
		})
	}
}

func TestRetryAbortAfterRestartUsesSavedSessionCapture(t *testing.T) {
	app, endedAt, _ := restoredTerminalActivityApp(t, "ABORTED")
	sessionID := app.snapshot().Session.ID
	queued, _, err := app.store.LoadActivitySyncState()
	if err != nil {
		t.Fatal(err)
	}
	queued.Items = []activitySyncItem{{Kind: "abort", Operation: &pendingSessionOperation{
		Kind: "abort", ID: "abort-operation", ExpectedVersion: 1, OccurredAt: endedAt,
	}}}
	if err := app.store.SaveActivitySyncState(queued); err != nil {
		t.Fatal(err)
	}
	methods := make(chan string, 8)
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		method := filepath.Base(request.URL.Path)
		methods <- method
		response.Header().Set("Content-Type", "application/json")
		switch method {
		case "GetCurrentSession":
			fmt.Fprintf(response, `{"session":{"id":%q,"deviceId":"pc-1","taskId":"task-1","status":"SESSION_STATUS_RUNNING","version":"3"}}`, sessionID)
		case "AbortSession":
			var body struct {
				Remaining []cloud.ActivitySegment `json:"remainingSegments"`
			}
			if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
				t.Errorf("decode abort request: %v", err)
			}
			if len(body.Remaining) == 0 {
				t.Error("abort request did not include saved remaining activity")
			}
			fmt.Fprintf(response, `{"session":{"id":%q,"status":"SESSION_STATUS_ABORTED","version":"4"},"balance":{"sessionId":%q}}`, sessionID, sessionID)
		case "GetSession":
			fmt.Fprintf(response, `{"session":{"id":%q,"status":"SESSION_STATUS_ABORTED","version":"4"},"reward":{"status":"REWARD_STATUS_GRANTED"}}`, sessionID)
		default:
			t.Errorf("unexpected RPC while retrying abort: %s", method)
			http.Error(response, "unexpected RPC", http.StatusNotFound)
		}
	}))
	defer server.Close()
	app.cloudClient, err = cloud.NewClient(cloud.Config{
		APIBaseURL: server.URL, SupabaseURL: server.URL, SupabasePublishableKey: "test-key",
	})
	if err != nil {
		t.Fatal(err)
	}

	if err := app.flushActivitySyncLocked(context.Background(), cloud.AuthSession{AccessToken: "test-token"}); err != nil {
		t.Fatalf("retrying an abort after restart failed: %v", err)
	}
	var called []string
	for len(methods) > 0 {
		called = append(called, <-methods)
	}
	if !reflect.DeepEqual(called, []string{"GetCurrentSession", "AbortSession", "GetSession"}) {
		t.Fatalf("abort retry used unexpected RPCs: %v", called)
	}
	remaining, _, err := app.store.LoadActivitySyncState()
	if err != nil {
		t.Fatal(err)
	}
	if len(remaining.Items) != 0 || app.snapshot().Sync != "synced" {
		t.Fatal("successful retry did not clear the pending operation")
	}
}

func TestPrepareActivitySyncAfterRestartPreservesOutboxWhenCaptureIsUnreadable(t *testing.T) {
	for _, failure := range []string{"missing", "invalid-json", "different-session"} {
		t.Run(failure, func(t *testing.T) {
			app, endedAt, capturePath := restoredTerminalActivityApp(t, "ABORTED")
			before, _, err := app.store.LoadActivitySyncState()
			if err != nil {
				t.Fatal(err)
			}
			expected := "session capture could not be opened"
			switch failure {
			case "missing":
				err = os.Remove(capturePath)
			case "invalid-json":
				err = os.WriteFile(capturePath, []byte("invalid json\n"), 0o600)
				expected = "session capture record is invalid"
			case "different-session":
				err = os.WriteFile(capturePath, []byte("{\"kind\":\"started\",\"sessionId\":\"other-session\"}\n"), 0o600)
				expected = "session capture contains a different session id"
			}
			if err != nil {
				t.Fatal(err)
			}

			err = app.prepareActivitySync(endedAt, true)
			if err == nil || !strings.Contains(err.Error(), expected) {
				t.Fatalf("invalid capture was not reported: %v", err)
			}
			after, _, err := app.store.LoadActivitySyncState()
			if err != nil || !reflect.DeepEqual(before, after) {
				t.Fatalf("failed capture read changed the pending activity: %v", err)
			}
		})
	}
}

func restoredTerminalActivityApp(t *testing.T, status string) (*App, time.Time, string) {
	t.Helper()
	start := time.Date(2026, time.October, 25, 10, 0, 0, 0, time.UTC)
	end := start.Add(time.Minute)
	sessionID := "01234567-89ab-4cde-8123-456789abcdef"
	store := &stateStore{path: filepath.Join(t.TempDir(), "desktop-state.json")}
	capturePath := filepath.Join(filepath.Dir(store.path), "sessions", sessionID+".jsonl")
	if err := os.MkdirAll(filepath.Dir(capturePath), 0o700); err != nil {
		t.Fatal(err)
	}
	terminalKind := "finished"
	if status == "ABORTED" {
		terminalKind = "aborted"
	}
	var capture bytes.Buffer
	for _, record := range []monitor.Record{
		{Kind: "started", SessionID: sessionID, RecordedAt: start},
		{Kind: terminalKind, SessionID: sessionID, RecordedAt: end},
	} {
		if err := json.NewEncoder(&capture).Encode(record); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(capturePath, capture.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	engine := session.New("macos", start)
	engine.SetMode("local-monitor", start)
	engine.SetLocalStorageReady(true, start)
	snapshot := engine.Snapshot()
	snapshot.Session = &session.WorkSession{
		ID: sessionID, Name: "Test session", Status: status, ServerVersion: 1,
		Task: session.Task{ID: "task-1", Name: "Test task", Mode: "NORMAL"},
	}
	snapshot.Monitor = session.MonitorStatus{State: "ready"}
	if err := store.Save(snapshot); err != nil {
		t.Fatal(err)
	}
	saved, _, err := store.Load()
	if err != nil || !engine.Restore(saved, end) {
		t.Fatalf("restore saved terminal session: %v", err)
	}
	if err := store.SaveActivitySyncState(newActivitySyncState(sessionID, start, 0)); err != nil {
		t.Fatal(err)
	}
	return &App{engine: engine, recorder: monitor.New(""), store: store, stateLoaded: true}, end, capturePath
}
