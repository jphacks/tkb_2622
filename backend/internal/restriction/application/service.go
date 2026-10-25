// Package application runs restriction operations. iPhone reports and policy changes are single-module;
// grant issue and session-driven control changes are exposed through Control for the workflow.
package application

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/restriction/domain"
)

type (
	Policy = domain.Policy
	Grant  = domain.Grant
	State  = domain.State
)

// Actor is the verified caller and the device registered for its auth session (if any).
type Actor struct {
	UserID, DeviceID, DevicePlatform string
}

func (a Actor) iPhone(deviceID string) error {
	if a.DeviceID == "" || a.DevicePlatform != "IOS" {
		return errors.Join(apperr.ErrForbidden, errors.New("only the registered iPhone can do this"))
	}
	if deviceID != a.DeviceID {
		return errors.Join(apperr.ErrForbidden, errors.New("device_id must be the calling iPhone"))
	}
	return nil
}

// View is the control state with its active grant, as returned to clients.
type View struct {
	State       State
	ActiveGrant *Grant
}

type Operation struct {
	Hash, ResourceID string
	Response         []byte
}

// Repository is implemented on the DB or on a transaction. Getters return apperr.ErrNotFound for missing rows.
type Repository interface {
	GetPolicy(ctx context.Context, userID, deviceID string) (Policy, error)
	// SavePolicy inserts when p.Version is 1, otherwise updates if the stored version is p.Version-1.
	SavePolicy(ctx context.Context, p Policy) error
	GetGrant(ctx context.Context, userID, grantID string) (Grant, error)
	OpenGrant(ctx context.Context, userID string) (Grant, error)
	InsertGrant(ctx context.Context, g Grant) error
	// UpdateGrant saves g if the stored version is g.Version-1.
	UpdateGrant(ctx context.Context, g Grant) error
	// GetState returns domain.NewState(userID) with Version 0 when the user has no state yet.
	GetState(ctx context.Context, userID string) (State, error)
	// SaveState inserts when s.Version is 1, otherwise updates if the stored version is s.Version-1.
	SaveState(ctx context.Context, s State) error
	GetOperation(ctx context.Context, userID, kind, operationID string) (Operation, error)
	SaveOperation(ctx context.Context, userID, kind, operationID string, op Operation) error
}

type Store interface {
	InUserTx(ctx context.Context, userID string, fn func(Repository) error) error
	Reader() Repository
}

func validID(s string) bool {
	id, err := uuid.Parse(s)
	return err == nil && id != uuid.Nil && id.String() == s
}

func translate(err error) error {
	switch {
	case errors.Is(err, domain.ErrInvalid), errors.Is(err, domain.ErrIntegrity), errors.Is(err, domain.ErrRevision):
		return errors.Join(apperr.ErrInvalid, err)
	case errors.Is(err, domain.ErrReportSeq):
		return errors.Join(apperr.ErrConflict, err)
	case errors.Is(err, domain.ErrState):
		return errors.Join(apperr.ErrPrecondition, err)
	}
	return err
}

func view(ctx context.Context, repo Repository, userID string) (View, error) {
	s, err := repo.GetState(ctx, userID)
	if err != nil {
		return View{}, err
	}
	v := View{State: s}
	if s.ActiveGrantID != "" {
		g, err := repo.GetGrant(ctx, userID, s.ActiveGrantID)
		if err != nil {
			return View{}, err
		}
		v.ActiveGrant = &g
	}
	return v, nil
}

func saveState(ctx context.Context, repo Repository, s *State) error {
	s.Version++
	return repo.SaveState(ctx, *s)
}

// Control runs restriction steps inside the workflow's transaction. It never begins or commits one.
type Control struct{ repo Repository }

func NewControl(repo Repository) *Control { return &Control{repo: repo} }

func (c *Control) Replay(ctx context.Context, userID, kind, operationID, hash string, out any) (bool, error) {
	op, err := c.repo.GetOperation(ctx, userID, kind, operationID)
	if errors.Is(err, apperr.ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if op.Hash != hash {
		return false, apperr.ErrConflict
	}
	return true, json.Unmarshal(op.Response, out)
}

func (c *Control) Record(ctx context.Context, userID, kind, operationID, hash, resourceID string, out any) error {
	b, err := json.Marshal(out)
	if err != nil {
		return err
	}
	return c.repo.SaveOperation(ctx, userID, kind, operationID, Operation{Hash: hash, ResourceID: resourceID, Response: b})
}

func (c *Control) View(ctx context.Context, userID string) (View, error) {
	return view(ctx, c.repo, userID)
}

func (c *Control) revokeOpen(ctx context.Context, userID, reason, operationID string, now time.Time) error {
	g, err := c.repo.OpenGrant(ctx, userID)
	if errors.Is(err, apperr.ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	if err = g.Revoke(reason, operationID, now); err != nil {
		return err
	}
	return c.repo.UpdateGrant(ctx, g)
}

// BeginSession targets the user's iPhone, which needs an enabled policy, expires any open grant and requests the shield.
func (c *Control) BeginSession(ctx context.Context, userID, sessionID, iPhoneID, operationID string, now time.Time) (View, error) {
	p, err := c.repo.GetPolicy(ctx, userID, iPhoneID)
	if errors.Is(err, apperr.ErrNotFound) || (err == nil && !p.Enabled) {
		return View{}, errors.Join(apperr.ErrPrecondition, errors.New("enable the restriction policy on the iPhone first"))
	}
	if err != nil {
		return View{}, err
	}
	if err = c.revokeOpen(ctx, userID, "WORK_STARTED", operationID, now); err != nil {
		return View{}, err
	}
	s, err := c.repo.GetState(ctx, userID)
	if err != nil {
		return View{}, err
	}
	if s.DeviceID != iPhoneID {
		// A different iPhone has not reported anything for this state yet.
		s.AppliedRevision, s.ShieldStatus, s.PermissionStatus, s.LastAppliedAt, s.LastReportedAt, s.FailureReason = 0, "UNKNOWN", "NOT_DETERMINED", nil, nil, ""
	}
	s.DeviceID, s.SessionID = iPhoneID, sessionID
	s.Want(domain.Shielded, "")
	if err = saveState(ctx, c.repo, &s); err != nil {
		return View{}, err
	}
	return view(ctx, c.repo, userID)
}

// ResumeSession expires the open grant (its remainder is discarded, the wallet balance is kept) and requests the shield again.
func (c *Control) ResumeSession(ctx context.Context, userID, operationID string, now time.Time) (View, error) {
	if err := c.revokeOpen(ctx, userID, "WORK_RESUMED", operationID, now); err != nil {
		return View{}, err
	}
	s, err := c.repo.GetState(ctx, userID)
	if err != nil {
		return View{}, err
	}
	s.Want(domain.Shielded, "")
	if err = saveState(ctx, c.repo, &s); err != nil {
		return View{}, err
	}
	return view(ctx, c.repo, userID)
}

// EndSession expires the open grant and requests the unlock for the finished or aborted session.
func (c *Control) EndSession(ctx context.Context, userID string, abort bool, operationID string, now time.Time) (View, error) {
	reason := "SESSION_FINISHED"
	if abort {
		reason = "SESSION_ABORTED"
	}
	if err := c.revokeOpen(ctx, userID, reason, operationID, now); err != nil {
		return View{}, err
	}
	s, err := c.repo.GetState(ctx, userID)
	if err != nil {
		return View{}, err
	}
	s.SessionID = ""
	s.Want(domain.SessionEnded, "")
	if err = saveState(ctx, c.repo, &s); err != nil {
		return View{}, err
	}
	return view(ctx, c.repo, userID)
}

// Issue creates a grant for the paused session and requests the timed unlock. The workflow spends the balance.
func (c *Control) Issue(ctx context.Context, userID, sessionID, deviceID string, seconds int64, now time.Time) (Grant, View, error) {
	s, err := c.repo.GetState(ctx, userID)
	if err != nil {
		return Grant{}, View{}, err
	}
	if s.SessionID != sessionID || s.DeviceID != deviceID {
		return Grant{}, View{}, errors.Join(apperr.ErrPrecondition, errors.New("this iPhone is not the restriction target of the session"))
	}
	if _, err = c.repo.OpenGrant(ctx, userID); err == nil {
		return Grant{}, View{}, errors.Join(apperr.ErrPrecondition, errors.New("a usage grant is already open"))
	} else if !errors.Is(err, apperr.ErrNotFound) {
		return Grant{}, View{}, err
	}
	s.Want(domain.TimedUnlock, uuid.NewString())
	g := Grant{ID: s.ActiveGrantID, UserID: userID, DeviceID: deviceID, SessionID: sessionID, RequestedSeconds: seconds, ReservedSeconds: seconds, Status: domain.Reserved, ControlRevision: s.ControlRevision, IssuedAt: now, Version: 1}
	if err = c.repo.InsertGrant(ctx, g); err != nil {
		return Grant{}, View{}, err
	}
	if err = saveState(ctx, c.repo, &s); err != nil {
		return Grant{}, View{}, err
	}
	return g, View{State: s, ActiveGrant: &g}, nil
}

type Service struct {
	store Store
	now   func() time.Time
}

func New(store Store) *Service {
	return &Service{store: store, now: func() time.Time { return time.Now().UTC() }}
}

func hash(v any) string {
	b, _ := json.Marshal(v)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// mutate runs a single-module operation idempotently under the user's lock.
func (s *Service) mutate(ctx context.Context, a Actor, kind, operationID string, request any, out any, fn func(Repository, time.Time) (string, error)) error {
	if !validID(operationID) {
		return apperr.ErrInvalid
	}
	h := hash(struct {
		Request any
		Device  string
	}{request, a.DeviceID})
	return s.store.InUserTx(ctx, a.UserID, func(repo Repository) error {
		c := Control{repo: repo}
		if ok, e := c.Replay(ctx, a.UserID, kind, operationID, h, out); e != nil || ok {
			return e
		}
		resource, e := fn(repo, s.now())
		if e != nil {
			return translate(e)
		}
		return c.Record(ctx, a.UserID, kind, operationID, h, resource, out)
	})
}

type PolicyInput struct {
	OperationID, DeviceID string
	ExpectedVersion       int64
	Enabled, Configured   bool
	TargetMode            string
	DeviceConfigVersion   int64
}

// PolicyView is the policy with the status derived from the latest permission report.
type PolicyView struct {
	Policy Policy
	Status string
}

func permissionOf(ctx context.Context, repo Repository, userID, deviceID string) (string, error) {
	st, err := repo.GetState(ctx, userID)
	if err != nil || st.DeviceID != deviceID {
		return "NOT_DETERMINED", err
	}
	return st.PermissionStatus, nil
}

// UpdatePolicy creates (expected version 0) or updates the calling iPhone's policy. Rejected while a grant is open.
func (s *Service) UpdatePolicy(ctx context.Context, a Actor, in PolicyInput) (out PolicyView, err error) {
	if err = a.iPhone(in.DeviceID); err != nil {
		return PolicyView{}, err
	}
	if in.ExpectedVersion < 0 {
		return PolicyView{}, apperr.ErrInvalid
	}
	err = s.mutate(ctx, a, "update_policy", in.OperationID, in, &out, func(repo Repository, now time.Time) (string, error) {
		if _, e := repo.OpenGrant(ctx, a.UserID); e == nil {
			return "", errors.Join(apperr.ErrPrecondition, errors.New("cannot change the policy while a usage grant is open"))
		} else if !errors.Is(e, apperr.ErrNotFound) {
			return "", e
		}
		p, e := repo.GetPolicy(ctx, a.UserID, in.DeviceID)
		switch {
		case errors.Is(e, apperr.ErrNotFound):
			if in.ExpectedVersion != 0 {
				return "", apperr.ErrConflict
			}
			p = Policy{DeviceID: in.DeviceID, UserID: a.UserID, UsageTimeMode: "ACTIVE_USAGE", AllowedAppsPolicy: "ALL_APPS_EXCEPT_SAFARI"}
		case e != nil:
			return "", e
		case p.Version != in.ExpectedVersion:
			return "", apperr.ErrConflict
		}
		p.Enabled, p.Configured, p.TargetMode, p.DeviceConfigVersion = in.Enabled, in.Configured, in.TargetMode, in.DeviceConfigVersion
		p.Version, p.UpdatedAt = p.Version+1, now
		if e = p.Validate(); e != nil {
			return "", e
		}
		if e = repo.SavePolicy(ctx, p); e != nil {
			return "", e
		}
		state, e := repo.GetState(ctx, a.UserID)
		if e != nil {
			return "", e
		}
		if state.DeviceID != "" && state.DeviceID != p.DeviceID {
			// The authenticated actor is the sole active iPhone, and UpdatePolicy has already
			// rejected an open grant. Move the control state off the revoked previous device and
			// require the newly registered iPhone to report its actual Screen Time state.
			desiredMode := state.DesiredMode
			if desiredMode == domain.TimedUnlock {
				if state.SessionID != "" {
					desiredMode = domain.Shielded
				} else {
					desiredMode = domain.Unrestricted
				}
			}
			state.DeviceID = p.DeviceID
			state.AppliedRevision = 0
			state.ShieldStatus, state.PermissionStatus = "UNKNOWN", "NOT_DETERMINED"
			state.LastAppliedAt, state.LastReportedAt = nil, nil
			state.FailureReason = ""
			state.Want(desiredMode, "")
			if e = saveState(ctx, repo, &state); e != nil {
				return "", e
			}
		}
		permission, e := permissionOf(ctx, repo, a.UserID, p.DeviceID)
		out = PolicyView{Policy: p, Status: p.Status(permission)}
		return p.DeviceID, e
	})
	return
}

func (s *Service) GetPolicy(ctx context.Context, a Actor, deviceID string) (PolicyView, error) {
	if !validID(deviceID) {
		return PolicyView{}, apperr.ErrInvalid
	}
	repo := s.store.Reader()
	p, err := repo.GetPolicy(ctx, a.UserID, deviceID)
	if err != nil {
		return PolicyView{}, err
	}
	permission, err := permissionOf(ctx, repo, a.UserID, deviceID)
	return PolicyView{Policy: p, Status: p.Status(permission)}, err
}

func (s *Service) GetGrant(ctx context.Context, a Actor, grantID string) (Grant, error) {
	if !validID(grantID) {
		return Grant{}, apperr.ErrInvalid
	}
	return s.store.Reader().GetGrant(ctx, a.UserID, grantID)
}

func (s *Service) GetState(ctx context.Context, a Actor) (View, error) {
	return view(ctx, s.store.Reader(), a.UserID)
}

type StateReport struct {
	OperationID, DeviceID, GrantID string
	ControlRevision                int64
	ShieldStatus, Permission       string
	AppliedAt                      time.Time
	FailureReason                  string
}
type StateReportResult struct {
	Applied bool
	View    View
}

// ReportState records what the iPhone applied. With a grant ID it confirms or fails the timed unlock of that
// revision; a failed unlock ends the grant without refund and requests the shield again.
func (s *Service) ReportState(ctx context.Context, a Actor, in StateReport) (out StateReportResult, err error) {
	if err = a.iPhone(in.DeviceID); err != nil {
		return StateReportResult{}, err
	}
	if in.GrantID != "" && !validID(in.GrantID) {
		return StateReportResult{}, apperr.ErrInvalid
	}
	err = s.mutate(ctx, a, "report_state", in.OperationID, in, &out, func(repo Repository, now time.Time) (string, error) {
		st, e := repo.GetState(ctx, a.UserID)
		if e != nil {
			return "", e
		}
		if st.DeviceID == "" {
			st.DeviceID = a.DeviceID
		} else if st.DeviceID != a.DeviceID {
			return "", errors.Join(apperr.ErrForbidden, errors.New("this iPhone is not the restriction target"))
		}
		applied, e := st.Report(in.ControlRevision, in.ShieldStatus, in.Permission, in.AppliedAt, in.FailureReason, now)
		if e != nil {
			return "", e
		}
		if applied && in.GrantID != "" && in.GrantID == st.ActiveGrantID {
			g, e := repo.GetGrant(ctx, a.UserID, in.GrantID)
			if e != nil {
				return "", e
			}
			changed := false
			if g.ControlRevision == in.ControlRevision {
				switch in.ShieldStatus {
				case "UNSHIELDED":
					changed = g.Activate(in.AppliedAt)
				case "ERROR":
					if changed = g.FailActivation(now); changed && st.SessionID != "" {
						st.Want(domain.Shielded, "")
					}
				}
			}
			if changed {
				if e = repo.UpdateGrant(ctx, g); e != nil {
					return "", e
				}
			}
		}
		if e = saveState(ctx, repo, &st); e != nil {
			return "", e
		}
		v, e := view(ctx, repo, a.UserID)
		out = StateReportResult{Applied: applied, View: v}
		return st.DeviceID, e
	})
	return
}

type UsageReport struct {
	OperationID, GrantID string
	ReportSeq            int64
	CumulativeSeconds    int64
	ObservedAt           time.Time
	Final                bool
}
type UsageResult struct {
	Grant Grant
	View  View
}

// ReportUsage applies the cumulative usage of a grant. When it is used up during the session, the shield is requested.
func (s *Service) ReportUsage(ctx context.Context, a Actor, in UsageReport) (out UsageResult, err error) {
	if !validID(in.GrantID) {
		return UsageResult{}, apperr.ErrInvalid
	}
	err = s.mutate(ctx, a, "report_usage", in.OperationID, in, &out, func(repo Repository, now time.Time) (string, error) {
		g, e := repo.GetGrant(ctx, a.UserID, in.GrantID)
		if e != nil {
			return "", e
		}
		if e = a.iPhone(g.DeviceID); e != nil {
			return "", e
		}
		changed, e := g.Report(in.ReportSeq, in.CumulativeSeconds, in.ObservedAt, in.Final, now)
		if e != nil {
			return "", e
		}
		if changed {
			if e = repo.UpdateGrant(ctx, g); e != nil {
				return "", e
			}
			if g.Status == domain.Exhausted {
				st, e := repo.GetState(ctx, a.UserID)
				if e != nil {
					return "", e
				}
				if st.ActiveGrantID == g.ID && st.SessionID != "" {
					st.Want(domain.Shielded, "")
					if e = saveState(ctx, repo, &st); e != nil {
						return "", e
					}
				}
			}
		}
		v, e := view(ctx, repo, a.UserID)
		out = UsageResult{Grant: g, View: v}
		return g.ID, e
	})
	return
}

var operationKinds = map[string]bool{"update_policy": true, "reserve": true, "report_state": true, "report_usage": true}

func (s *Service) Operation(ctx context.Context, a Actor, kind, operationID string) (resourceID string, found bool, err error) {
	if !operationKinds[kind] || !validID(operationID) {
		return "", false, apperr.ErrInvalid
	}
	op, err := s.store.Reader().GetOperation(ctx, a.UserID, kind, operationID)
	if errors.Is(err, apperr.ErrNotFound) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return op.ResourceID, true, nil
}
