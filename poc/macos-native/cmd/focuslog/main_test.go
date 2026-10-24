package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestReplayPrivateFilesAndNoOverwrite(t *testing.T) {
	out := filepath.Join(t.TempDir(), "replay")
	if err := run([]string{"replay", "--input", "../../testdata/sample.json", "--out", out}); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"capture.json", "events.json", "analysis.json"} {
		path := filepath.Join(out, name)
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !json.Valid(data) {
			t.Errorf("invalid JSON %s", name)
		}
		info, _ := os.Stat(path)
		if info.Mode().Perm() != 0600 {
			t.Errorf("permissions %s: %v", name, info.Mode())
		}
	}
	info, _ := os.Stat(out)
	if info.Mode().Perm() != 0700 {
		t.Errorf("directory permission %v", info.Mode())
	}
	if err := run([]string{"replay", "--input", "../../testdata/sample.json", "--out", out}); err == nil {
		t.Fatal("overwrote existing directory")
	}
}
func TestRejectUnknownSensitiveFields(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "private.json")
	fixture := `{"schema_version":"1","source":"macos-native","start_at":"2026-10-24T00:00:00Z","end_at":"2026-10-24T00:01:00Z","url":"https://private.example/path"}`
	if err := os.WriteFile(path, []byte(fixture), 0600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"replay", "--input", path}); err == nil {
		t.Fatal("accepted unknown sensitive field")
	}
}
func TestRecordTotalFailureSavesEvidence(t *testing.T) {
	root := t.TempDir()
	helper := "/usr/bin/false"
	out := filepath.Join(root, "result")
	if err := run([]string{"record", "--helper", helper, "--duration", "250ms", "--poll", "50ms", "--out", out}); err == nil {
		t.Fatal("total failure reported as success")
	}
	data, err := os.ReadFile(filepath.Join(out, "capture.json"))
	if err != nil {
		t.Fatal(err)
	}
	var capture map[string]any
	if err = json.Unmarshal(data, &capture); err != nil {
		t.Fatal(err)
	}
	if len(capture["errors"].([]any)) == 0 {
		t.Fatal("no failure evidence")
	}
}
func TestInvalidArguments(t *testing.T) {
	for _, args := range [][]string{{}, {"unknown"}, {"replay", "--poll", "0s"}, {"record", "--duration", "-1s"}, {"replay", "--allow-sensitive"}, {"check", "unexpected"}} {
		if err := run(args); err == nil {
			t.Errorf("accepted %v", args)
		}
	}
}

func TestReplaySessionEvaluation(t *testing.T) {
	out := filepath.Join(t.TempDir(), "evaluated")
	if err := run([]string{"replay", "--input", "../../testdata/sample.json", "--session", "../../testdata/session.json", "--out", out}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(out, "evaluation.json"))
	if err != nil {
		t.Fatal(err)
	}
	var result struct {
		WorkSeconds float64            `json:"work_seconds"`
		Totals      map[string]float64 `json:"totals"`
		B           *float64           `json:"b"`
		Q           *float64           `json:"q"`
		Session     struct {
			ID string `json:"id"`
		} `json:"session"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	if result.WorkSeconds != 3 || result.Totals["T"] != 2 || result.Totals["R"] != 1 || result.Totals["D"] != 0 || result.Totals["U"] != 9 || result.B == nil || *result.B != 100 || result.Q == nil || *result.Q != .25 || result.Session.ID != "fixture-programming-session" {
		t.Fatalf("unexpected result: %+v", result)
	}
	info, err := os.Stat(filepath.Join(out, "evaluation.json"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatal("evaluation not private")
	}
}

func TestInvalidSessionRejectedBeforeCapture(t *testing.T) {
	root := t.TempDir()
	config := filepath.Join(root, "session.json")
	if err := os.WriteFile(config, []byte(`{"id":"invalid"}`), 0600); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(root, "result")
	if err := run([]string{"record", "--helper", "/usr/bin/false", "--session", config, "--out", out}); err == nil {
		t.Fatal("accepted invalid session")
	}
	if _, err := os.Stat(out); !os.IsNotExist(err) {
		t.Fatal("capture attempted despite invalid session")
	}
}

func TestSessionRejectsUnknownFieldsAndTrailingData(t *testing.T) {
	data, err := os.ReadFile("../../testdata/session.json")
	if err != nil {
		t.Fatal(err)
	}
	for _, invalid := range []string{string(data) + " {}", `{"url":"https://private.example/path"}`} {
		config := filepath.Join(t.TempDir(), "session.json")
		if err := os.WriteFile(config, []byte(invalid), 0600); err != nil {
			t.Fatal(err)
		}
		if err := run([]string{"replay", "--input", "../../testdata/sample.json", "--session", config}); err == nil {
			t.Fatal("accepted invalid JSON session")
		}
	}
}
