package app

import (
	"context"
	"testing"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/session"
)

func TestDemoModeTickDoesNotRequireLocalStorage(t *testing.T) {
	start := time.Date(2026, time.October, 25, 9, 0, 0, 0, time.UTC)
	engine := session.New("windows", start)
	if state := engine.Execute(session.Command{Action: "start"}, start); state.Session == nil || state.Session.Status != "RUNNING" {
		t.Fatal("could not start demo work session")
	}
	app := &App{engine: engine}
	app.tick(context.Background(), start.Add(2*time.Second))

	state := engine.Snapshot()
	if state.Failure != nil {
		t.Fatalf("demo mode reported failure: %s %s", state.Failure.Code, state.Failure.Message)
	}
	if !state.Actions["pause"].Allowed {
		t.Fatalf("pause is not allowed in demo mode: %s", state.Actions["pause"].Reason)
	}
}
