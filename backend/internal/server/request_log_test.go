package server

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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
