// Package application coordinates focus and reward in one transaction per operation:
// session state, batch acceptance, interim grants, balance discard and the operation record.
package application

import (
	"context"
	"time"

	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
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
	Discard(ctx context.Context, userID, sessionID string) (int64, reward.Wallet, error)
}

// Runner commits only when fn returns nil; Focus and Reward must not be used after fn returns.
type Runner interface {
	InUserTx(ctx context.Context, userID string, fn func(Focus, Reward) error) error
}

type SessionResult struct {
	Session   focus.Session
	Balance   reward.Wallet
	Discarded int64
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

type Sessions struct {
	run Runner
	now func() time.Time
}

func New(run Runner) *Sessions {
	return &Sessions{run: run, now: func() time.Time { return time.Now().UTC() }}
}

// mutate runs a session operation idempotently: a committed result is returned for the same request.
func (w *Sessions) mutate(ctx context.Context, a focus.Actor, kind, operationID string, request any, fn func(Focus, Reward, time.Time) (SessionResult, error)) (out SessionResult, err error) {
	if !focus.ValidID(operationID) {
		return SessionResult{}, focus.ErrInvalid
	}
	// The measuring device is part of the request so another device cannot replay this result.
	hash := focus.Hash(struct {
		Request any
		Device  string
	}{request, a.DeviceID})
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward) error {
		if ok, e := f.Replay(ctx, a, kind, operationID, hash, &out); e != nil || ok {
			return e
		}
		res, e := fn(f, r, w.now())
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

// Start opens a RUNNING session and binds a zero-balance wallet to it.
func (w *Sessions) Start(ctx context.Context, a focus.Actor, in StartInput) (SessionResult, error) {
	if !focus.ValidID(in.TaskID) || in.TaskVersion < 1 {
		return SessionResult{}, focus.ErrInvalid
	}
	return w.mutate(ctx, a, "start", in.OperationID, in, func(f Focus, r Reward, now time.Time) (SessionResult, error) {
		s, err := f.Start(ctx, a, in.TaskID, in.TaskVersion, now)
		if err != nil {
			return SessionResult{}, err
		}
		wallet, err := r.Open(ctx, a.UserID, s.ID)
		return SessionResult{Session: s, Balance: wallet}, err
	})
}

// Upload accepts a batch and grants the interim reward for newly contiguous records in the same transaction.
func (w *Sessions) Upload(ctx context.Context, a focus.Actor, in focus.BatchInput) (out BatchResult, err error) {
	if !focus.ValidID(in.SessionID) || !focus.ValidID(in.BatchID) || in.Seq < 1 || len(in.EvaluatorVersion) > 100 || len(in.RulesVersion) > 100 {
		return BatchResult{}, focus.ErrInvalid
	}
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward) error {
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
		return SessionResult{}, focus.ErrInvalid
	}
	return w.mutate(ctx, a, "pause", in.OperationID, in, func(f Focus, r Reward, now time.Time) (SessionResult, error) {
		s, err := f.Pause(ctx, a, in.SessionID, in.ExpectedVersion, in.PausedAt, in.LastSeq, now)
		if err != nil {
			return SessionResult{}, err
		}
		_, wallet, err := r.Accrue(ctx, a.UserID, s.ID, s.Totals.Work(), s.AcceptedSeq)
		return SessionResult{Session: s, Balance: wallet}, err
	})
}

type ResumeInput struct {
	OperationID, SessionID string
	ExpectedVersion        int64
}

// Resume keeps the unused balance. Expiring the open usage grant arrives with the Restriction API.
func (w *Sessions) Resume(ctx context.Context, a focus.Actor, in ResumeInput) (SessionResult, error) {
	if !focus.ValidID(in.SessionID) || in.ExpectedVersion < 1 {
		return SessionResult{}, focus.ErrInvalid
	}
	return w.mutate(ctx, a, "resume", in.OperationID, in, func(f Focus, r Reward, now time.Time) (SessionResult, error) {
		s, err := f.Resume(ctx, a, in.SessionID, in.ExpectedVersion, now)
		if err != nil {
			return SessionResult{}, err
		}
		wallet, err := r.Balance(ctx, a.UserID)
		return SessionResult{Session: s, Balance: wallet}, err
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
		return SessionResult{}, focus.ErrInvalid
	}
	kind := "finish"
	if abort {
		kind = "abort"
	}
	return w.mutate(ctx, a, kind, in.OperationID, in, func(f Focus, r Reward, now time.Time) (SessionResult, error) {
		s, err := f.End(ctx, a, abort, in.SessionID, in.ExpectedVersion, in.EndedAt, in.LastSeq, in.Remaining, now)
		if err != nil {
			return SessionResult{}, err
		}
		discarded, wallet, err := r.Discard(ctx, a.UserID, s.ID)
		return SessionResult{Session: s, Balance: wallet, Discarded: discarded}, err
	})
}

// Detail returns a session with its earned, spent and discarded seconds from one consistent snapshot.
func (w *Sessions) Detail(ctx context.Context, a focus.Actor, sessionID string) (out SessionDetail, err error) {
	if !focus.ValidID(sessionID) {
		return SessionDetail{}, focus.ErrInvalid
	}
	err = w.run.InUserTx(ctx, a.UserID, func(f Focus, r Reward) error {
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
