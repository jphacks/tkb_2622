package collector

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"focuspocket/macos-native/model"
)

func helperFixture(t *testing.T, script string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "helper")
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+script), 0700); err != nil {
		t.Fatal(err)
	}
	return path
}
func TestSnapshot(t *testing.T) {
	root := t.TempDir()
	fixture := filepath.Join(root, "snapshot.json")
	snapshot := model.Snapshot{SchemaVersion: "1", Source: "macos-native", ObservedAt: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), SampleStartedAt: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), BrowserStatus: "not_applicable"}
	data, _ := json.Marshal(snapshot)
	if err := os.WriteFile(fixture, data, 0600); err != nil {
		t.Fatal(err)
	}
	path := helperFixture(t, "exec /bin/cat '"+fixture+"'\n")
	native, err := New(path, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	actual, err := native.Snapshot(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if actual.ReceivedAt.IsZero() || actual.Source != "macos-native" {
		t.Fatalf("%+v", actual)
	}
}
func TestInvalidHelperOutput(t *testing.T) {
	for _, script := range []string{"printf 'not-json'\n", "printf '{\"schema_version\":\"1\",\"source\":\"macos-native\",\"url\":\"private\"}'\n", "printf '{} {}'\n", "exit 2\n"} {
		t.Run(script, func(t *testing.T) {
			native, _ := New(helperFixture(t, script), time.Second)
			_, err := native.Snapshot(context.Background())
			if err == nil || strings.Contains(err.Error(), "private") {
				t.Fatalf("invalid helper output: %v", err)
			}
		})
	}
}
func TestTimeout(t *testing.T) {
	native, _ := New(helperFixture(t, "exec /bin/sleep 2\n"), 20*time.Millisecond)
	_, err := native.Snapshot(context.Background())
	if err == nil || !strings.Contains(err.Error(), "timeout_or_cancelled") {
		t.Fatalf("timeout not detected: %v", err)
	}
}
func TestHelperValidation(t *testing.T) {
	if _, err := New(filepath.Join(t.TempDir(), "missing"), time.Second); err == nil {
		t.Fatal("missing helper accepted")
	}
	if _, err := New("/bin/sh", 0); err == nil {
		t.Fatal("invalid timeout accepted")
	}
}
