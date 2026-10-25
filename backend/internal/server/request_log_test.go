package server

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRequestLoggerRecordsOperationAndStatusWithoutCredentials(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&output, nil))
	handler := requestLogger(logger, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unauthenticated", http.StatusUnauthorized)
	}))
	request := httptest.NewRequest(http.MethodPost, "/identity.v1.IdentityService/EnsureUser", nil)
	request.Header.Set("Authorization", "Bearer do-not-log-this")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected handler status %d, got %d", http.StatusUnauthorized, response.Code)
	}
	logLine := output.String()
	for _, expected := range []string{`"method":"POST"`, `"path":"/identity.v1.IdentityService/EnsureUser"`, `"status":401`} {
		if !strings.Contains(logLine, expected) {
			t.Errorf("request log is missing %s: %s", expected, logLine)
		}
	}
	if strings.Contains(logLine, "do-not-log-this") {
		t.Fatalf("request log contains an authorization credential: %s", logLine)
	}
}

func TestRequestLoggerRecordsRequestStartBeforeHandlerFinishes(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&output, nil))
	entered := make(chan struct{})
	finish := make(chan struct{})
	done := make(chan struct{})
	handler := requestLogger(logger, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		<-finish
		w.WriteHeader(http.StatusOK)
	}))
	request := httptest.NewRequest(http.MethodPost, "/identity.v1.IdentityService/EnsureUser", nil)
	request.Header.Set("Authorization", "Bearer must-not-be-logged")
	response := httptest.NewRecorder()
	go func() {
		handler.ServeHTTP(response, request)
		close(done)
	}()

	select {
	case <-entered:
	case <-time.After(time.Second):
		close(finish)
		t.Fatal("handler was not entered")
	}
	startLog := output.String()
	if !strings.Contains(startLog, `"msg":"HTTP request started"`) ||
		!strings.Contains(startLog, `"path":"/identity.v1.IdentityService/EnsureUser"`) {
		close(finish)
		<-done
		t.Fatalf("request start was not logged before handler completion: %s", startLog)
	}
	if strings.Contains(startLog, "must-not-be-logged") {
		close(finish)
		<-done
		t.Fatalf("request start log contains authorization credentials: %s", startLog)
	}

	close(finish)
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("handler did not finish")
	}
	if response.Code != http.StatusOK {
		t.Fatalf("expected handler status %d, got %d", http.StatusOK, response.Code)
	}
}
