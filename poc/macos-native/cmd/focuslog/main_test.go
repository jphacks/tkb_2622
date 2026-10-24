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
