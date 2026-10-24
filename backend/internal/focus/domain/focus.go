// Package domain holds the focus rules: task settings, session state transitions and activity totals.
package domain

import (
	"errors"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	ErrInvalid  = errors.New("invalid input")
	ErrState    = errors.New("session state does not allow this operation")
	ErrOverlap  = errors.New("activity segments overlap or go backwards")
	ErrMinimum  = errors.New("minimum duration not reached")
	ErrMissing  = errors.New("earlier activity batches have not been accepted yet")
	ErrTooMuch  = errors.New("reported activity exceeds server-observed running time")
	categories  = map[string]bool{"PROGRAMMING": true, "DOCUMENT_WRITING": true, "READING": true, "DESIGN": true, "STUDY": true, "OTHER": true}
	modes       = map[string]bool{"NORMAL": true, "READING": true, "VIDEO": true}
	classes     = map[string]bool{"TASK": true, "RELATED_TRANSITION": true, "DISTRACTION": true, "UNKNOWN": true, "IDLE": true}
	maxSegments = 1000
)

// ActivityGrace tolerates clock and network delay when capping reported activity by server-observed time.
const ActivityGrace = 2 * time.Minute

type TaskSettings struct {
	Name           string
	Category       string
	Mode           string
	PlannedSeconds int64
	MinimumSeconds int64
}

// Validate applies the provisional input ranges: planned 1 min to 24 h, minimum between 0 and planned.
func (s TaskSettings) Validate() error {
	if strings.TrimSpace(s.Name) == "" || !utf8.ValidString(s.Name) || utf8.RuneCountInString(s.Name) > 100 {
		return ErrInvalid
	}
	if !categories[s.Category] || !modes[s.Mode] {
		return ErrInvalid
	}
	if s.PlannedSeconds < 60 || s.PlannedSeconds > 86400 || s.MinimumSeconds < 0 || s.MinimumSeconds > s.PlannedSeconds {
		return ErrInvalid
	}
	return nil
}

type Task struct {
	ID        string
	Settings  TaskSettings
	Version   int64
	CreatedAt time.Time
	UpdatedAt time.Time
}

const (
	Running   = "RUNNING"
	Paused    = "PAUSED"
	Finalized = "FINALIZED"
	Aborted   = "ABORTED"
)

type Segment struct {
	Start          time.Time `json:"start"`
	End            time.Time `json:"end"`
	Classification string    `json:"classification"`
	Reasons        []string  `json:"reasons,omitempty"`
}

// Totals are milliseconds per activity class. Sub-second precision is kept, never truncated.
type Totals struct {
	Task, Related, Distraction, Unknown, Idle int64
}

func (t Totals) Active() int64 { return t.Task + t.Related + t.Distraction + t.Unknown + t.Idle }
func (t Totals) Work() int64   { return t.Task + t.Related }

// Scores returns B100, Q and Wrate; nil when the denominator is 0.
func (t Totals) Scores() (focus, quality, workRate *float64) {
	ratio := func(n, d int64, scale float64) *float64 {
		if d == 0 {
			return nil
		}
		v := scale * float64(n) / float64(d)
		return &v
	}
	return ratio(t.Work(), t.Work()+t.Distraction, 100), ratio(t.Work()+t.Distraction+t.Idle, t.Active(), 1), ratio(t.Work(), t.Active(), 1)
}

type Session struct {
	ID                 string
	UserID             string
	DeviceID           string
	TaskID             string
	Snapshot           TaskSettings
	Status             string
	Version            int64
	StartedAt          time.Time
	RunningSince       *time.Time
	ServerActiveMillis int64
	PausedAt           *time.Time
	EndedAt            *time.Time
	AcceptedSeq        int64
	LastSegmentEnd     *time.Time
	Totals             Totals
}

func (s *Session) Open() bool { return s.Status == Running || s.Status == Paused }

// MinimumReached compares active time (pauses excluded) with the minimum fixed at start.
func (s *Session) MinimumReached() bool { return s.Totals.Active() >= s.Snapshot.MinimumSeconds*1000 }

func NewSession(id, userID, deviceID string, task Task, now time.Time) Session {
	return Session{ID: id, UserID: userID, DeviceID: deviceID, TaskID: task.ID, Snapshot: task.Settings, Status: Running, Version: 1, StartedAt: now, RunningSince: &now}
}

// ValidateSegments checks shape only; ordering against the session is checked by Apply.
func ValidateSegments(segments []Segment) error {
	if len(segments) > maxSegments {
		return ErrInvalid
	}
	for _, seg := range segments {
		if seg.Start.IsZero() || !seg.End.After(seg.Start) || !classes[seg.Classification] || len(seg.Reasons) > 20 {
			return ErrInvalid
		}
		for _, r := range seg.Reasons {
			if r == "" || len(r) > 100 || !utf8.ValidString(r) {
				return ErrInvalid
			}
		}
	}
	return nil
}

// Apply adds segments to the totals. They must not overlap earlier segments, must not start before
// the last pause point, and the total must stay within the server-observed running time plus grace.
func (s *Session) Apply(segments []Segment, now time.Time) error {
	if err := ValidateSegments(segments); err != nil {
		return err
	}
	next := s.Totals
	last := s.LastSegmentEnd
	for _, seg := range segments {
		if (last != nil && seg.Start.Before(*last)) || (s.PausedAt != nil && seg.Start.Before(*s.PausedAt)) {
			return ErrOverlap
		}
		ms := seg.End.Sub(seg.Start).Milliseconds()
		switch seg.Classification {
		case "TASK":
			next.Task += ms
		case "RELATED_TRANSITION":
			next.Related += ms
		case "DISTRACTION":
			next.Distraction += ms
		case "UNKNOWN":
			next.Unknown += ms
		case "IDLE":
			next.Idle += ms
		}
		end := seg.End
		last = &end
	}
	if next.Active() > s.serverActive(now)+ActivityGrace.Milliseconds() {
		return ErrTooMuch
	}
	s.Totals, s.LastSegmentEnd = next, last
	return nil
}

func (s *Session) serverActive(now time.Time) int64 {
	ms := s.ServerActiveMillis
	if s.RunningSince != nil && now.After(*s.RunningSince) {
		ms += now.Sub(*s.RunningSince).Milliseconds()
	}
	return ms
}

func (s *Session) stopClock(now time.Time) {
	s.ServerActiveMillis = s.serverActive(now)
	s.RunningSince = nil
}

func (s *Session) checkSeq(lastSeq int64) error {
	switch {
	case lastSeq > s.AcceptedSeq:
		return ErrMissing
	case lastSeq < s.AcceptedSeq:
		return ErrInvalid
	}
	return nil
}

// Pause requires every batch up to lastSeq to be accepted (and therefore evaluated).
func (s *Session) Pause(pausedAt time.Time, lastSeq int64, now time.Time) error {
	if s.Status != Running {
		return ErrState
	}
	if err := s.checkSeq(lastSeq); err != nil {
		return err
	}
	if pausedAt.IsZero() || (s.LastSegmentEnd != nil && pausedAt.Before(*s.LastSegmentEnd)) {
		return ErrInvalid
	}
	s.stopClock(now)
	s.Status, s.PausedAt = Paused, &pausedAt
	s.Version++
	return nil
}

func (s *Session) Resume(now time.Time) error {
	if s.Status != Paused {
		return ErrState
	}
	s.Status, s.RunningSince = Running, &now
	s.Version++
	return nil
}

// End finishes or aborts. Finishing needs complete records and the minimum duration; aborting needs neither.
// Remaining segments are counted for the minimum check and kept as history, but never rewarded.
func (s *Session) End(abort bool, endedAt time.Time, lastSeq int64, remaining []Segment, now time.Time) error {
	if !s.Open() {
		return ErrState
	}
	if endedAt.IsZero() || lastSeq < 0 {
		return ErrInvalid
	}
	if !abort {
		if err := s.checkSeq(lastSeq); err != nil {
			return err
		}
	}
	if err := s.Apply(remaining, now); err != nil {
		return err
	}
	if !abort && !s.MinimumReached() {
		return ErrMinimum
	}
	s.stopClock(now)
	s.Status = Finalized
	if abort {
		s.Status = Aborted
	}
	s.EndedAt = &endedAt
	s.Version++
	return nil
}
