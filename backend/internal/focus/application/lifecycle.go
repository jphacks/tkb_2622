package application

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/focus/domain"
)

// maxSeqAhead bounds how far ahead of the accepted range an out-of-order batch may be.
const maxSeqAhead = 1000

type BatchInput struct {
	SessionID, BatchID, EvaluatorVersion, RulesVersion string
	Seq                                                int64
	Segments                                           []Segment
}

type Receipt struct {
	BatchID            string
	Seq                int64
	Status             string
	AcceptedThroughSeq int64
	MissingSeqs        []int64
}

// Lifecycle runs session operations on a repository bound to the caller's transaction.
// The workflow owns the transaction; Lifecycle never begins or commits one.
type Lifecycle struct{ repo Repository }

func NewLifecycle(repo Repository) *Lifecycle { return &Lifecycle{repo: repo} }

// Replay returns the saved result of an operation. A different request under the same ID is a conflict.
func (l *Lifecycle) Replay(ctx context.Context, a Actor, kind, operationID, hash string, out any) (bool, error) {
	op, err := l.repo.GetOperation(ctx, a.UserID, kind, operationID)
	if errors.Is(err, ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if op.Hash != hash {
		return false, ErrConflict
	}
	return true, json.Unmarshal(op.Response, out)
}

func (l *Lifecycle) Record(ctx context.Context, a Actor, kind, operationID, hash, resourceID string, out any) error {
	b, err := json.Marshal(out)
	if err != nil {
		return err
	}
	return l.repo.SaveOperation(ctx, a.UserID, kind, operationID, Operation{Hash: hash, ResourceID: resourceID, Response: b})
}

// Get reads a session of the caller inside the current transaction.
func (l *Lifecycle) Get(ctx context.Context, a Actor, sessionID string) (Session, error) {
	return l.repo.GetSession(ctx, a.UserID, sessionID)
}

// Start creates a RUNNING session on the caller's PC with a snapshot of the task.
func (l *Lifecycle) Start(ctx context.Context, a Actor, taskID string, taskVersion int64, now time.Time) (Session, error) {
	if !a.isPC() {
		return Session{}, errors.Join(ErrPrecondition, errors.New("register this PC as a device first"))
	}
	task, err := l.repo.GetTask(ctx, a.UserID, taskID)
	if err != nil {
		return Session{}, err
	}
	if task.Version != taskVersion {
		return Session{}, ErrConflict
	}
	if _, err = l.repo.CurrentSession(ctx, a.UserID); err == nil {
		return Session{}, errors.Join(ErrPrecondition, errors.New("an unfinished session already exists"))
	} else if !errors.Is(err, ErrNotFound) {
		return Session{}, err
	}
	s := domain.NewSession(uuid.NewString(), a.UserID, a.DeviceID, task, now)
	return s, l.repo.CreateSession(ctx, s)
}

// own loads a session that the caller's PC measures.
func (l *Lifecycle) own(ctx context.Context, a Actor, sessionID string) (Session, error) {
	s, err := l.repo.GetSession(ctx, a.UserID, sessionID)
	if err != nil {
		return Session{}, err
	}
	if s.DeviceID != a.DeviceID {
		return Session{}, ErrForbidden
	}
	return s, nil
}

// AcceptBatch stores a batch and advances the contiguous accepted range. Out-of-order batches wait as
// PENDING; batches arriving after the session ended are kept as HISTORY and never counted.
func (l *Lifecycle) AcceptBatch(ctx context.Context, a Actor, in BatchInput, now time.Time) (Receipt, Session, error) {
	s, err := l.own(ctx, a, in.SessionID)
	if err != nil {
		return Receipt{}, Session{}, err
	}
	hash := Hash(in)
	if b, e := l.repo.BatchByID(ctx, in.SessionID, in.BatchID); e == nil {
		if b.Hash != hash {
			return Receipt{}, Session{}, ErrConflict
		}
		r, e := l.receipt(ctx, s, b)
		return r, s, e
	} else if !errors.Is(e, ErrNotFound) {
		return Receipt{}, Session{}, e
	}
	if _, e := l.repo.GetBatch(ctx, in.SessionID, in.Seq); e == nil {
		return Receipt{}, Session{}, ErrConflict
	} else if !errors.Is(e, ErrNotFound) {
		return Receipt{}, Session{}, e
	}
	if in.Seq > s.AcceptedSeq+maxSeqAhead {
		return Receipt{}, Session{}, ErrInvalid
	}
	if err = domain.ValidateSegments(in.Segments); err != nil {
		return Receipt{}, Session{}, translate(err)
	}
	b := Batch{SessionID: in.SessionID, BatchID: in.BatchID, Hash: hash, EvaluatorVersion: in.EvaluatorVersion, RulesVersion: in.RulesVersion, Seq: in.Seq, Segments: in.Segments}
	switch {
	case !s.Open():
		b.Status = "HISTORY"
	case s.Status == domain.Paused:
		return Receipt{}, Session{}, errors.Join(ErrPrecondition, errors.New("session is paused"))
	case in.Seq > s.AcceptedSeq+1:
		b.Status = "PENDING"
	default:
		b.Status = "ACCEPTED"
		if err = s.Apply(in.Segments, now); err != nil {
			return Receipt{}, Session{}, translate(err)
		}
	}
	if err = l.repo.InsertBatch(ctx, b); err != nil {
		return Receipt{}, Session{}, err
	}
	if b.Status == "ACCEPTED" {
		prevSeq := s.AcceptedSeq
		s.AcceptedSeq = in.Seq
		if err = l.drainPending(ctx, &s, now); err != nil {
			return Receipt{}, Session{}, err
		}
		if err = l.repo.UpdateSession(ctx, s, s.Version, prevSeq); err != nil {
			return Receipt{}, Session{}, err
		}
	}
	r, err := l.receipt(ctx, s, b)
	return r, s, err
}

// drainPending accepts waiting batches that have become contiguous. A waiting batch that fails
// validation is dropped so that its seq is reported missing again.
func (l *Lifecycle) drainPending(ctx context.Context, s *Session, now time.Time) error {
	for {
		b, err := l.repo.GetBatch(ctx, s.ID, s.AcceptedSeq+1)
		if errors.Is(err, ErrNotFound) {
			return nil
		}
		if err != nil {
			return err
		}
		if b.Status != "PENDING" {
			return nil
		}
		if s.Apply(b.Segments, now) != nil {
			return l.repo.DeleteBatch(ctx, s.ID, b.Seq)
		}
		if err = l.repo.SetBatchStatus(ctx, s.ID, b.Seq, "ACCEPTED"); err != nil {
			return err
		}
		s.AcceptedSeq = b.Seq
	}
}

func (l *Lifecycle) receipt(ctx context.Context, s Session, b Batch) (Receipt, error) {
	status := b.Status
	if status == "PENDING" && b.Seq <= s.AcceptedSeq {
		status = "ACCEPTED"
	}
	r := Receipt{BatchID: b.BatchID, Seq: b.Seq, Status: status, AcceptedThroughSeq: s.AcceptedSeq, MissingSeqs: []int64{}}
	if !s.Open() {
		return r, nil
	}
	pending, err := l.repo.PendingSeqs(ctx, s.ID)
	if err != nil {
		return Receipt{}, err
	}
	next := s.AcceptedSeq + 1
	for _, seq := range pending {
		for ; next < seq; next++ {
			r.MissingSeqs = append(r.MissingSeqs, next)
		}
		next = seq + 1
	}
	return r, nil
}

func (l *Lifecycle) transition(ctx context.Context, a Actor, sessionID string, expectedVersion int64, change func(*Session) error) (Session, error) {
	s, err := l.own(ctx, a, sessionID)
	if err != nil {
		return Session{}, err
	}
	if s.Version != expectedVersion {
		return Session{}, ErrConflict
	}
	prevVersion, prevSeq := s.Version, s.AcceptedSeq
	if err = change(&s); err != nil {
		return Session{}, translate(err)
	}
	return s, l.repo.UpdateSession(ctx, s, prevVersion, prevSeq)
}

// Pause succeeds only when every batch through lastSeq is accepted; the workflow evaluates rewards in the same transaction.
func (l *Lifecycle) Pause(ctx context.Context, a Actor, sessionID string, expectedVersion int64, pausedAt time.Time, lastSeq int64, now time.Time) (Session, error) {
	return l.transition(ctx, a, sessionID, expectedVersion, func(s *Session) error { return s.Pause(pausedAt, lastSeq, now) })
}

func (l *Lifecycle) Resume(ctx context.Context, a Actor, sessionID string, expectedVersion int64, now time.Time) (Session, error) {
	return l.transition(ctx, a, sessionID, expectedVersion, func(s *Session) error { return s.Resume(now) })
}

// End finishes (abort=false) or aborts the session and keeps the unsent segments as history.
func (l *Lifecycle) End(ctx context.Context, a Actor, abort bool, sessionID string, expectedVersion int64, endedAt time.Time, lastSeq int64, remaining []Segment, now time.Time) (Session, error) {
	s, err := l.transition(ctx, a, sessionID, expectedVersion, func(s *Session) error { return s.End(abort, endedAt, lastSeq, remaining, now) })
	if err != nil || len(remaining) == 0 {
		return s, err
	}
	return s, l.repo.SetFinalSegments(ctx, s.ID, remaining)
}
