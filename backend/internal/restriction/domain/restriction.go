// Package domain holds the restriction rules: usage grant lifecycle and the desired/reported control state.
package domain

import (
	"errors"
	"time"
)

var (
	ErrInvalid   = errors.New("invalid input")
	ErrState     = errors.New("grant state does not allow this operation")
	ErrIntegrity = errors.New("usage report decreases or exceeds the reserved seconds")
	ErrRevision  = errors.New("reported control revision is newer than the server's")
	ErrReportSeq = errors.New("same report seq with different content")
)

const (
	Reserved         = "RESERVED"
	Activated        = "ACTIVATED"
	Exhausted        = "EXHAUSTED"
	Revoked          = "REVOKED"
	ActivationFailed = "ACTIVATION_FAILED"

	Unrestricted = "UNRESTRICTED"
	Shielded     = "SHIELDED"
	TimedUnlock  = "TIMED_UNLOCK"
	SessionEnded = "SESSION_ENDED"
)

var (
	targetModes  = map[string]bool{"SELECTED_APPS": true, "DEVICE_WIDE": true}
	shieldStates = map[string]bool{"SHIELDED": true, "UNSHIELDED": true, "UNKNOWN": true, "ERROR": true}
	permissions  = map[string]bool{"GRANTED": true, "DENIED": true, "NOT_DETERMINED": true}
)

// Policy is metadata only; Apple selection tokens never leave the device.
type Policy struct {
	DeviceID, UserID, TargetMode, UsageTimeMode, AllowedAppsPolicy string
	Enabled, Configured                                            bool
	DeviceConfigVersion, Version                                   int64
	UpdatedAt                                                      time.Time
}

func (p Policy) Validate() error {
	if !targetModes[p.TargetMode] || p.DeviceConfigVersion < 0 {
		return ErrInvalid
	}
	return nil
}

// Status derives the reported policy status from the latest permission report.
func (p Policy) Status(permission string) string {
	switch {
	case !p.Enabled:
		return "DISABLED"
	case permission != "GRANTED":
		return "PERMISSION_REQUIRED"
	}
	return "ENABLED"
}

type Grant struct {
	ID, UserID, DeviceID, SessionID string
	RequestedSeconds                int64
	ReservedSeconds                 int64
	Status                          string
	ControlRevision                 int64
	IssuedAt                        time.Time
	ActivatedAt                     *time.Time
	ReportSeq                       int64
	ReportedSeconds                 int64
	LastObservedAt                  *time.Time
	// Confirmed values; nil until confirmed, never guessed.
	ConsumedSeconds  *int64
	DiscardedSeconds *int64
	EndReason        string
	EndedByOperation string
	CompletedAt      *time.Time
	Version          int64
}

func (g *Grant) Open() bool { return g.Status == Reserved || g.Status == Activated }

func (g *Grant) settle(consumed int64) {
	discarded := g.ReservedSeconds - consumed
	g.ConsumedSeconds, g.DiscardedSeconds = &consumed, &discarded
}

// Revoke ends an open grant because work started, resumed, finished or aborted. The remaining time is
// discarded without refund; consumed seconds stay unconfirmed until the device's final report.
func (g *Grant) Revoke(reason, operationID string, now time.Time) error {
	if !g.Open() {
		return ErrState
	}
	g.Status, g.EndReason, g.EndedByOperation, g.CompletedAt = Revoked, reason, operationID, &now
	if g.ReportedSeconds == g.ReservedSeconds {
		g.settle(g.ReservedSeconds)
	}
	g.Version++
	return nil
}

// Activate records the device's confirmation that the timed unlock was applied.
func (g *Grant) Activate(at time.Time) bool {
	if g.Status != Reserved {
		return false
	}
	g.Status, g.ActivatedAt = Activated, &at
	g.Version++
	return true
}

// FailActivation ends a grant the device could not apply. Refund conditions are undecided, so nothing is returned.
func (g *Grant) FailActivation(now time.Time) bool {
	if g.Status != Reserved {
		return false
	}
	g.Status, g.EndReason, g.CompletedAt = ActivationFailed, "ACTIVATION_FAILED", &now
	g.Version++
	return true
}

// Report applies a cumulative usage report. Older seqs are ignored (changed=false). A report reaching the
// reserved seconds exhausts an open grant. For a revoked grant, final=true settles consumed and discarded.
func (g *Grant) Report(seq, cumulative int64, observedAt time.Time, final bool, now time.Time) (changed bool, err error) {
	if seq < 1 || cumulative < 0 || observedAt.IsZero() {
		return false, ErrInvalid
	}
	if seq < g.ReportSeq {
		return false, nil
	}
	if seq == g.ReportSeq {
		if cumulative != g.ReportedSeconds {
			return false, ErrReportSeq
		}
		return false, nil
	}
	if cumulative < g.ReportedSeconds || cumulative > g.ReservedSeconds {
		return false, ErrIntegrity
	}
	switch g.Status {
	case Reserved, Activated:
		if g.ActivatedAt == nil {
			g.ActivatedAt = &observedAt
		}
		g.Status = Activated
		if cumulative == g.ReservedSeconds {
			g.Status, g.EndReason, g.CompletedAt = Exhausted, "USAGE_EXHAUSTED", &now
			g.settle(g.ReservedSeconds)
		}
	case Revoked:
		if g.ConsumedSeconds != nil {
			return false, ErrState
		}
		if final {
			g.settle(cumulative)
		}
	default:
		return false, ErrState
	}
	g.ReportSeq, g.ReportedSeconds, g.LastObservedAt = seq, cumulative, &observedAt
	g.Version++
	return true, nil
}

// State is the per-user control state: what the server wants the iPhone to apply and what it last reported.
type State struct {
	UserID, DeviceID, SessionID    string
	ControlRevision                int64
	DesiredMode                    string
	ActiveGrantID                  string
	AppliedRevision                int64
	ShieldStatus, PermissionStatus string
	LastAppliedAt, LastReportedAt  *time.Time
	FailureReason                  string
	Version                        int64
}

func NewState(userID string) State {
	return State{UserID: userID, DesiredMode: Unrestricted, ShieldStatus: "UNKNOWN", PermissionStatus: "NOT_DETERMINED"}
}

// Want issues a new control revision. The device must apply the newest revision only.
func (s *State) Want(mode, grantID string) {
	s.ControlRevision++
	s.DesiredMode, s.ActiveGrantID = mode, grantID
}

// Report records a device report. A report older than the applied revision only refreshes the report time
// and permission so that it never overrides a newer applied state.
func (s *State) Report(revision int64, shield, permission string, appliedAt time.Time, failure string, now time.Time) (applied bool, err error) {
	if revision < 0 || !shieldStates[shield] || !permissions[permission] || appliedAt.IsZero() || len(failure) > 500 {
		return false, ErrInvalid
	}
	if revision > s.ControlRevision {
		return false, ErrRevision
	}
	s.LastReportedAt, s.PermissionStatus = &now, permission
	if revision < s.AppliedRevision {
		return false, nil
	}
	s.AppliedRevision, s.ShieldStatus, s.LastAppliedAt, s.FailureReason = revision, shield, &appliedAt, failure
	return true, nil
}
