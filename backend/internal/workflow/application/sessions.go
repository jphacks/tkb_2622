// Package application coordinates focus, reward and restriction in one transaction per operation:
// session state, batch acceptance, interim grants, usage grants, control revisions and the operation record.
package application

import (
	"context"
	"errors"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	restriction "github.com/jphacks/tkb_2622/backend/internal/restriction/application"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
)

// Focus is the subset of focus operations the workflow needs, bound to the current transaction.
type Focus interface {
	Replay(ctx context.Context, a focus.Actor, kind, operationID, hash string, out any) (bool, error)
	Record(ctx context.Context, a focus.Actor, kind, operationID, hash, resourceID string, out any) error
	Get(ctx context.Context, a focus.Actor, sessionID string) (focus.Session, error)
	Start(ctx context.Context, a focus.Actor, taskID string, taskVersion int64, now time.Time) (focus.Session, error)
	AcceptBatch(ctx context.Context, a focus.Actor, in focus.BatchInput, now time.Time) (focus.Receipt, focus.Session, error)
	Pause(ctx context.Context, a focus.Actor, sessionID string, expectedVersion int64, pausedAt time.Time, lastSeq int64, now time.Time) (focus.Session, error)
	Resume(ctx context.Context, a focus.Actor, sessionID string, expectedVersion int64, now time.Time) (focus.Session, error)
	End(ctx context.Context, a focus.Actor, abort bool, sessionID string, expectedVersion int64, endedAt time.Time, lastSeq int64, remaining []focus.Segment, now time.Time) (focus.Session, error)
}

// Reward is the subset of wallet operations the workflow needs, bound to the current transaction.
type Reward interface {
	Balance(ctx context.Context, userID string) (reward.Wallet, error)
	Summary(ctx context.Context, sessionID string) (reward.Summary, error)
	Open(ctx context.Context, userID, sessionID string) (reward.Wallet, error)
	Accrue(ctx context.Context, userID, sessionID string, workMillis, throughSeq int64) (int64, reward.Wallet, error)
	Spend(ctx context.Context, userID, sessionID, grantID string, seconds int64) (reward.Wallet, error)
	Discard(ctx context.Context, userID, sessionID string) (int64, reward.Wallet, error)
}

// Restriction is the subset of restriction operations the workflow needs, bound to the current transaction.
type Restriction interface {
	Replay(ctx context.Context, userID, kind, operationID, hash string, out any) (bool, error)
	Record(ctx context.Context, userID, kind, operationID, hash, resourceID string, out any) error
	View(ctx context.Context, userID string) (restriction.View, error)
	BeginSession(ctx context.Context, userID, sessionID, iPhoneID, operationID string, now time.Time) (restriction.View, error)
	ResumeSession(ctx context.Context, userID, operationID string, now time.Time) (restriction.View, error)
	EndSession(ctx context.Context, userID string, abort bool, operationID string, now time.Time) (restriction.View, error)
	Issue(ctx context.Context, userID, sessionID, deviceID string, seconds int64, now time.Time) (restriction.Grant, restriction.View, error)
}

// Devices finds the user's restriction target from identity's public operations.
type Devices interface {
	// ActiveIPhone returns the active iPhone ID or apperr.ErrNotFound.
	ActiveIPhone(ctx context.Context, userID string) (string, error)
}

// Runner commits only when fn returns nil; the operations must not be used after fn returns.
type Runner interface {
	InUserTx(ctx context.Context, userID string, fn func(Focus, Reward, Restriction) error) error
}

type SessionResult struct {
	Session     focus.Session
	Balance     reward.Wallet
	Discarded   int64
	Restriction restriction.View
}
type BatchResult struct {
	Receipt focus.Receipt
	Earned  int64
	Balance reward.Wallet
}
type SessionDetail struct {
	Session focus.Session
	Reward  reward.Summary
}
type ReserveResult struct {
	Grant       restriction.Grant
	Balance     reward.Wallet
	Restriction restriction.View
}

type Sessions struct {
	run     Runner
	devices Devices
	now     func() time.Time
}

func New(run Runner, devices Devices) *Sessions {
	return &Sessions{run: run, devices: devices, now: func() time.Time { return time.Now().UTC() }}
}

// requestHash binds a request to the calling device so another device cannot replay its result.
func requestHash(request any, deviceID string) string {
	return focus.Hash(struct {
		Request any
		Device  string
	}{request, deviceID})
}

// mutate runs a session operation idempotently: a committed result is returned for the same request.
func (w *Sessions) mutate(ctx context.Context, a focus.Actor, kind, operationID string, request any, fn func(Focus, Reward, Restriction, time.Time) (SessionResult, error)) (out SessionResult, err error) {
	if !focus.ValidID(operationID) {
		return SessionResult{}, apperr.ErrInvalid
	}
	hash := requestHash(request, a.DeviceID)
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward, x Restriction) error {
		if ok, e := f.Replay(ctx, a, kind, operationID, hash, &out); e != nil || ok {
			return e
		}
		res, e := fn(f, r, x, w.now())
		if e != nil {
			return e
		}
		out = res
		return f.Record(ctx, a, kind, operationID, hash, res.Session.ID, out)
	})
	return
}

type StartInput struct {
	OperationID, TaskID string
	TaskVersion         int64
}

// Start opens a RUNNING session, binds a zero-balance wallet and requests the shield on the user's iPhone.
func (w *Sessions) Start(ctx context.Context, a focus.Actor, in StartInput) (SessionResult, error) {
	if !focus.ValidID(in.TaskID) || in.TaskVersion < 1 {
		return SessionResult{}, apperr.ErrInvalid
	}
	return w.mutate(ctx, a, "start", in.OperationID, in, func(f Focus, r Reward, x Restriction, now time.Time) (SessionResult, error) {
		iPhone, err := w.devices.ActiveIPhone(ctx, a.UserID)
		if errors.Is(err, apperr.ErrNotFound) {
			return SessionResult{}, errors.Join(apperr.ErrPrecondition, errors.New("register an iPhone as the restriction target first"))
		}
		if err != nil {
			return SessionResult{}, err
		}
		s, err := f.Start(ctx, a, in.TaskID, in.TaskVersion, now)
		if err != nil {
			return SessionResult{}, err
		}
		wallet, err := r.Open(ctx, a.UserID, s.ID)
		if err != nil {
			return SessionResult{}, err
		}
		v, err := x.BeginSession(ctx, a.UserID, s.ID, iPhone, in.OperationID, now)
		return SessionResult{Session: s, Balance: wallet, Restriction: v}, err
	})
}

// Upload accepts a batch and grants the interim reward for newly contiguous records in the same transaction.
func (w *Sessions) Upload(ctx context.Context, a focus.Actor, in focus.BatchInput) (out BatchResult, err error) {
	if !focus.ValidID(in.SessionID) || !focus.ValidID(in.BatchID) || in.Seq < 1 || len(in.EvaluatorVersion) > 100 || len(in.RulesVersion) > 100 {
		return BatchResult{}, apperr.ErrInvalid
	}
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward, _ Restriction) error {
		receipt, s, e := f.AcceptBatch(ctx, a, in, w.now())
		if e != nil {
			return e
		}
		out.Receipt = receipt
		if s.Open() {
			out.Earned, out.Balance, e = r.Accrue(ctx, a.UserID, s.ID, s.Totals.Work(), s.AcceptedSeq)
		} else {
			out.Balance, e = r.Balance(ctx, a.UserID)
		}
		return e
	})
	return
}

type PauseInput struct {
	OperationID, SessionID string
	ExpectedVersion        int64
	PausedAt               time.Time
	LastSeq                int64
}

// Pause confirms records through LastSeq are accepted and evaluated, then allows break usage.
func (w *Sessions) Pause(ctx context.Context, a focus.Actor, in PauseInput) (SessionResult, error) {
	if !focus.ValidID(in.SessionID) || in.ExpectedVersion < 1 || in.LastSeq < 0 {
		return SessionResult{}, apperr.ErrInvalid
	}
	return w.mutate(ctx, a, "pause", in.OperationID, in, func(f Focus, r Reward, x Restriction, now time.Time) (SessionResult, error) {
		s, err := f.Pause(ctx, a, in.SessionID, in.ExpectedVersion, in.PausedAt, in.LastSeq, now)
		if err != nil {
			return SessionResult{}, err
		}
		_, wallet, err := r.Accrue(ctx, a.UserID, s.ID, s.Totals.Work(), s.AcceptedSeq)
		if err != nil {
			return SessionResult{}, err
		}
		v, err := x.View(ctx, a.UserID)
		return SessionResult{Session: s, Balance: wallet, Restriction: v}, err
	})
}

type ResumeInput struct {
	OperationID, SessionID string
	ExpectedVersion        int64
}

// Resume keeps the unused balance, expires the open usage grant without refund and requests the shield again.
func (w *Sessions) Resume(ctx context.Context, a focus.Actor, in ResumeInput) (SessionResult, error) {
	if !focus.ValidID(in.SessionID) || in.ExpectedVersion < 1 {
		return SessionResult{}, apperr.ErrInvalid
	}
	return w.mutate(ctx, a, "resume", in.OperationID, in, func(f Focus, r Reward, x Restriction, now time.Time) (SessionResult, error) {
		s, err := f.Resume(ctx, a, in.SessionID, in.ExpectedVersion, now)
		if err != nil {
			return SessionResult{}, err
		}
		wallet, err := r.Balance(ctx, a.UserID)
		if err != nil {
			return SessionResult{}, err
		}
		v, err := x.ResumeSession(ctx, a.UserID, in.OperationID, now)
		return SessionResult{Session: s, Balance: wallet, Restriction: v}, err
	})
}

type EndInput struct {
	OperationID, SessionID string
	ExpectedVersion        int64
	EndedAt                time.Time
	LastSeq                int64
	Remaining              []focus.Segment
}

// Finish ends normally (records complete, minimum reached); no additional grant, the unused balance is discarded.
func (w *Sessions) Finish(ctx context.Context, a focus.Actor, in EndInput) (SessionResult, error) {
	return w.end(ctx, a, false, in)
}

// Abort ends without the minimum or complete records; the unused balance is discarded, spent rewards stay.
func (w *Sessions) Abort(ctx context.Context, a focus.Actor, in EndInput) (SessionResult, error) {
	return w.end(ctx, a, true, in)
}

func (w *Sessions) end(ctx context.Context, a focus.Actor, abort bool, in EndInput) (SessionResult, error) {
	if !focus.ValidID(in.SessionID) || in.ExpectedVersion < 1 || in.LastSeq < 0 {
		return SessionResult{}, apperr.ErrInvalid
	}
	kind := "finish"
	if abort {
		kind = "abort"
	}
	return w.mutate(ctx, a, kind, in.OperationID, in, func(f Focus, r Reward, x Restriction, now time.Time) (SessionResult, error) {
		s, err := f.End(ctx, a, abort, in.SessionID, in.ExpectedVersion, in.EndedAt, in.LastSeq, in.Remaining, now)
		if err != nil {
			return SessionResult{}, err
		}
		discarded, wallet, err := r.Discard(ctx, a.UserID, s.ID)
		if err != nil {
			return SessionResult{}, err
		}
		v, err := x.EndSession(ctx, a.UserID, abort, in.OperationID, now)
		return SessionResult{Session: s, Balance: wallet, Discarded: discarded, Restriction: v}, err
	})
}

// Detail returns a session with its earned, spent and discarded seconds from one consistent snapshot.
func (w *Sessions) Detail(ctx context.Context, a focus.Actor, sessionID string) (out SessionDetail, err error) {
	if !focus.ValidID(sessionID) {
		return SessionDetail{}, apperr.ErrInvalid
	}
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward, _ Restriction) error {
		s, e := f.Get(ctx, a, sessionID)
		if e != nil {
			return e
		}
		out.Session = s
		out.Reward, e = r.Summary(ctx, s.ID)
		return e
	})
	return
}

type ReserveInput struct {
	OperationID, SessionID, DeviceID string
	ExpectedSessionVersion           int64
	RequestedSeconds                 int64
}

// maxGrantSeconds bounds one usage grant to the longest possible balance (a 24 h task at the current rate).
const maxGrantSeconds = 86400

// Reserve spends balance and issues a timed unlock to the calling iPhone. The session must be PAUSED with every
// accepted record evaluated, and no grant may be open. The operation record is owned by restriction.
func (w *Sessions) Reserve(ctx context.Context, a focus.Actor, in ReserveInput) (out ReserveResult, err error) {
	if !focus.ValidID(in.OperationID) || !focus.ValidID(in.SessionID) || in.ExpectedSessionVersion < 1 || in.RequestedSeconds < 1 || in.RequestedSeconds > maxGrantSeconds {
		return ReserveResult{}, apperr.ErrInvalid
	}
	if a.DeviceID == "" || a.DevicePlatform != "IOS" || a.DeviceID != in.DeviceID {
		return ReserveResult{}, errors.Join(apperr.ErrForbidden, errors.New("only the registered iPhone can reserve a usage grant"))
	}
	hash := requestHash(in, a.DeviceID)
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward, x Restriction) error {
		if ok, e := x.Replay(ctx, a.UserID, "reserve", in.OperationID, hash, &out); e != nil || ok {
			return e
		}
		s, e := f.Get(ctx, a, in.SessionID)
		if e != nil {
			return e
		}
		if s.Status != "PAUSED" {
			return errors.Join(apperr.ErrPrecondition, errors.New("usage grants are only available while the session is paused"))
		}
		if s.Version != in.ExpectedSessionVersion {
			return apperr.ErrConflict
		}
		wallet, e := r.Balance(ctx, a.UserID)
		if e != nil {
			return e
		}
		if wallet.SessionID != s.ID || wallet.EvaluatedSeq != s.AcceptedSeq {
			return errors.Join(apperr.ErrPrecondition, errors.New("records before the pause are not evaluated yet"))
		}
		now := w.now()
		g, v, e := x.Issue(ctx, a.UserID, s.ID, in.DeviceID, in.RequestedSeconds, now)
		if e != nil {
			return e
		}
		if wallet, e = r.Spend(ctx, a.UserID, s.ID, g.ID, in.RequestedSeconds); e != nil {
			return e
		}
		out = ReserveResult{Grant: g, Balance: wallet, Restriction: v}
		return x.Record(ctx, a.UserID, "reserve", in.OperationID, hash, g.ID, out)
	})
	return
}
