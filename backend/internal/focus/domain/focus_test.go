package domain

import (
	"errors"
	"testing"
	"time"
)

var t0 = time.Date(2026, 10, 24, 9, 0, 0, 0, time.UTC)

func seg(fromSec, toSec int, class string) Segment {
	return Segment{Start: t0.Add(time.Duration(fromSec) * time.Second), End: t0.Add(time.Duration(toSec) * time.Second), Classification: class}
}

func newSession(minimum int64) Session {
	return NewSession("s", "u", "d", Task{ID: "t", Settings: TaskSettings{Name: "n", Category: "STUDY", Mode: "NORMAL", PlannedSeconds: 3600, MinimumSeconds: minimum}}, t0)
}

func TestApplyTotalsAndScores(t *testing.T) {
	s := newSession(0)
	if err := s.Apply([]Segment{seg(0, 60, "TASK"), seg(60, 90, "RELATED_TRANSITION"), seg(90, 120, "DISTRACTION"), seg(120, 150, "UNKNOWN")}, t0.Add(10*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if s.Totals.Work() != 90_000 || s.Totals.Active() != 150_000 {
		t.Fatalf("totals = %+v", s.Totals)
	}
	focus, quality, rate := s.Totals.Scores()
	if *focus != 75 || *quality != 0.8 || *rate != 0.6 {
		t.Fatalf("scores = %v %v %v", *focus, *quality, *rate)
	}
	if f, q, r := (Totals{}).Scores(); f != nil || q != nil || r != nil {
		t.Fatal("zero totals must have nil scores")
	}
}

func TestApplyRejectsOverlapAndExcess(t *testing.T) {
	s := newSession(0)
	if err := s.Apply([]Segment{seg(0, 60, "TASK")}, t0.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := s.Apply([]Segment{seg(30, 90, "TASK")}, t0.Add(time.Hour)); !errors.Is(err, ErrOverlap) {
		t.Fatalf("overlap err = %v", err)
	}
	// Server has only seen 1 minute of running time; 10 minutes of activity exceeds it plus grace.
	if err := s.Apply([]Segment{seg(60, 660, "TASK")}, t0.Add(time.Minute)); !errors.Is(err, ErrTooMuch) {
		t.Fatalf("excess err = %v", err)
	}
	if s.Totals.Active() != 60_000 {
		t.Fatal("failed apply must not change totals")
	}
}

func TestPauseNeedsAllRecords(t *testing.T) {
	s := newSession(0)
	s.AcceptedSeq = 2
	if err := s.Pause(t0.Add(time.Minute), 3, t0.Add(time.Minute)); !errors.Is(err, ErrMissing) {
		t.Fatalf("err = %v", err)
	}
	if err := s.Pause(t0.Add(time.Minute), 2, t0.Add(time.Minute)); err != nil || s.Status != Paused || s.Version != 2 {
		t.Fatalf("pause: %v %+v", err, s)
	}
	// Segments may not cover the paused span before resume time.
	_ = s.Resume(t0.Add(2 * time.Minute))
	if err := s.Apply([]Segment{seg(30, 90, "TASK")}, t0.Add(3*time.Minute)); !errors.Is(err, ErrOverlap) {
		t.Fatalf("segment before pause point err = %v", err)
	}
}

func TestFinishNeedsMinimumButAbortDoesNot(t *testing.T) {
	s := newSession(120)
	now := t0.Add(time.Hour)
	if err := s.End(false, now, 0, []Segment{seg(0, 60, "TASK")}, now); !errors.Is(err, ErrMinimum) {
		t.Fatalf("finish err = %v", err)
	}
	s = newSession(120)
	if err := s.End(true, now, 5, []Segment{seg(0, 60, "TASK")}, now); err != nil || s.Status != Aborted {
		t.Fatalf("abort: %v %s", err, s.Status)
	}
	if err := s.End(true, now, 0, nil, now); !errors.Is(err, ErrState) {
		t.Fatalf("second end err = %v", err)
	}
	s = newSession(60)
	if err := s.End(false, now, 0, []Segment{seg(0, 60, "TASK")}, now); err != nil || s.Status != Finalized {
		t.Fatalf("finish: %v %s", err, s.Status)
	}
}

func TestTaskSettingsRanges(t *testing.T) {
	ok := TaskSettings{Name: "Report", Category: "DOCUMENT_WRITING", Mode: "READING", PlannedSeconds: 1800, MinimumSeconds: 900}
	if ok.Validate() != nil {
		t.Fatal("valid settings rejected")
	}
	for _, bad := range []TaskSettings{
		{Name: " ", Category: "STUDY", Mode: "NORMAL", PlannedSeconds: 60},
		{Name: "a", Category: "UNSPECIFIED", Mode: "NORMAL", PlannedSeconds: 60},
		{Name: "a", Category: "STUDY", Mode: "NORMAL", PlannedSeconds: 59},
		{Name: "a", Category: "STUDY", Mode: "NORMAL", PlannedSeconds: 600, MinimumSeconds: 601},
	} {
		if bad.Validate() == nil {
			t.Errorf("accepted %+v", bad)
		}
	}
}
