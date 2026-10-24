package cloud

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestUploadActivityBatchSendsOnlyClassifiedSegmentsAndStableIdentity(t *testing.T) {
	var requests []map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/focus.v1.FocusService/UploadActivityBatch" {
			t.Errorf("unexpected RPC path: %s", request.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(request.Body).Decode(&payload); err != nil {
			t.Errorf("decode request: %v", err)
		}
		requests = append(requests, payload)
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"receipt":{"batchId":"batch-1","seq":"1","status":"BATCH_STATUS_ACCEPTED","acceptedThroughSeq":"1","earnedSeconds":"3"},"balance":{"sessionId":"session-1","balanceSeconds":"4","version":"2","evaluatedThroughSeq":"1"}}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIBaseURL: server.URL, SupabaseURL: server.URL, SupabasePublishableKey: "test-key",
	})
	if err != nil {
		t.Fatalf("create client: %v", err)
	}
	batch := ActivityBatch{
		SessionID: "session-1", BatchID: "batch-1", Seq: 1,
		EvaluatorVersion: "evaluator-v1", RulesVersion: "rules-v1",
		Segments: []ActivitySegment{{
			StartTime:      time.Date(2026, time.October, 24, 10, 0, 0, 0, time.UTC),
			EndTime:        time.Date(2026, time.October, 24, 10, 0, 1, 0, time.UTC),
			Classification: "ACTIVITY_CLASS_TASK",
		}},
	}

	for range 2 {
		receipt, balance, err := client.UploadActivityBatch(context.Background(), AuthSession{AccessToken: "access"}, batch)
		if err != nil {
			t.Fatalf("upload activity batch: %v", err)
		}
		if receipt.BatchID != batch.BatchID || receipt.Seq != batch.Seq || receipt.Status != "ACCEPTED" || balance.BalanceSeconds != 4 {
			t.Fatalf("unexpected upload response: receipt=%#v balance=%#v", receipt, balance)
		}
	}
	if len(requests) != 2 {
		t.Fatalf("request count = %d, want 2", len(requests))
	}
	for _, payload := range requests {
		if payload["batchId"] != "batch-1" || payload["seq"] != "1" {
			t.Fatalf("retry changed its batch identity: %#v", payload)
		}
		segments, ok := payload["segments"].([]any)
		if !ok || len(segments) != 1 {
			t.Fatalf("classified segments missing: %#v", payload["segments"])
		}
		segment, ok := segments[0].(map[string]any)
		if !ok || segment["classification"] != "ACTIVITY_CLASS_TASK" {
			t.Fatalf("unexpected segment payload: %#v", segments[0])
		}
		for _, forbidden := range []string{"appId", "appName", "domain", "url", "title", "https://example.test", "private title"} {
			if _, exists := segment[forbidden]; exists {
				t.Fatalf("raw activity field %q was sent: %#v", forbidden, segment)
			}
			encoded, _ := json.Marshal(payload)
			if strings.Contains(string(encoded), forbidden) && (strings.Contains(forbidden, "://") || forbidden == "private title") {
				t.Fatalf("raw URL or title leaked in activity payload: %s", encoded)
			}
		}
	}
}

func TestGetCurrentSessionReadsTrackingOnlyMode(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"session":{"id":"session-1","deviceId":"pc-1","taskId":"task-1","taskSnapshot":{"name":"Writing","category":"TASK_CATEGORY_STUDY","mode":"FOCUS_MODE_NORMAL","plannedSeconds":3600,"minimumSeconds":60},"status":"SESSION_STATUS_RUNNING","version":"1","trackingOnly":true,"acceptedThroughSeq":"2","startedAt":"2026-10-24T10:00:00Z"}}`))
	}))
	defer server.Close()
	client, err := NewClient(Config{
		APIBaseURL: server.URL, SupabaseURL: server.URL, SupabasePublishableKey: "test-key",
	})
	if err != nil {
		t.Fatalf("create client: %v", err)
	}
	current, err := client.GetCurrentSession(context.Background(), AuthSession{AccessToken: "access"})
	if err != nil {
		t.Fatalf("get current session: %v", err)
	}
	if current == nil || !current.TrackingOnly || current.AcceptedThroughSeq != 2 {
		t.Fatalf("tracking-only mode was not restored: %#v", current)
	}
}

func TestGetBalanceReadsSessionScopedRewardBalance(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/reward.v1.RewardService/GetBalance" {
			t.Errorf("unexpected RPC path: %s", request.URL.Path)
		}
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"balance":{"sessionId":"session-1","balanceSeconds":"42","version":"3","evaluatedThroughSeq":"5"}}`))
	}))
	defer server.Close()
	client, err := NewClient(Config{
		APIBaseURL: server.URL, SupabaseURL: server.URL, SupabasePublishableKey: "test-key",
	})
	if err != nil {
		t.Fatalf("create client: %v", err)
	}
	balance, err := client.GetBalance(context.Background(), AuthSession{AccessToken: "access"})
	if err != nil {
		t.Fatalf("get balance: %v", err)
	}
	if balance.SessionID != "session-1" || balance.BalanceSeconds != 42 || balance.EvaluatedThroughSeq != 5 {
		t.Fatalf("unexpected reward balance: %#v", balance)
	}
}
