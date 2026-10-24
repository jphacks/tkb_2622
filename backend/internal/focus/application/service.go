// Package application runs focus operations. Task operations and reads are single-module;
// session lifecycle operations are exposed through Lifecycle for the workflow to combine with reward.
package application

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/focus/domain"
)

var (
	ErrUnauthenticated = errors.New("authentication required")
	ErrForbidden       = errors.New("access denied")
	ErrNotFound        = errors.New("resource not found")
	ErrInvalid         = errors.New("invalid request")
	ErrConflict        = errors.New("state or operation conflicts")
	ErrPrecondition    = errors.New("operation precondition not met")
	// ErrMissing is retryable with the same operation ID once the earlier batches are accepted.
	ErrMissing = errors.New("earlier activity batches have not been accepted yet")
)

type (
	Task         = domain.Task
	TaskSettings = domain.TaskSettings
	Session      = domain.Session
	Segment      = domain.Segment
)

// Actor is the verified caller: the business user and the device registered for its auth session (if any).
type Actor struct {
	UserID         string
	DeviceID       string
	DevicePlatform string
}

func (a Actor) isPC() bool {
	return a.DeviceID != "" && (a.DevicePlatform == "MACOS" || a.DevicePlatform == "WINDOWS")
}

type Batch struct {
	SessionID, BatchID, Hash, Status, EvaluatorVersion, RulesVersion string
	Seq                                                              int64
	Segments                                                         []Segment
}
type Operation struct {
	Hash, ResourceID string
	Response         []byte
}
type TaskPage struct {
	Tasks []Task
	Next  string
}

// Repository is implemented on the DB or on a transaction. Methods return ErrNotFound for missing rows.
type Repository interface {
	CreateTask(ctx context.Context, userID string, t Task) (Task, error)
	UpdateTask(ctx context.Context, userID string, t Task, expectedVersion int64) (Task, error)
	GetTask(ctx context.Context, userID, taskID string) (Task, error)
	ListTasks(ctx context.Context, userID, after string, limit int) ([]Task, error)
	CreateSession(ctx context.Context, s Session) error
	GetSession(ctx context.Context, userID, sessionID string) (Session, error)
	CurrentSession(ctx context.Context, userID string) (Session, error)
	// UpdateSession saves s if the stored row still has prevVersion and prevAcceptedSeq.
	UpdateSession(ctx context.Context, s Session, prevVersion, prevAcceptedSeq int64) error
	SetFinalSegments(ctx context.Context, sessionID string, segments []Segment) error
	GetBatch(ctx context.Context, sessionID string, seq int64) (Batch, error)
	BatchByID(ctx context.Context, sessionID, batchID string) (Batch, error)
	InsertBatch(ctx context.Context, b Batch) error
	SetBatchStatus(ctx context.Context, sessionID string, seq int64, status string) error
	DeleteBatch(ctx context.Context, sessionID string, seq int64) error
	PendingSeqs(ctx context.Context, sessionID string) ([]int64, error)
	GetOperation(ctx context.Context, userID, kind, operationID string) (Operation, error)
	SaveOperation(ctx context.Context, userID, kind, operationID string, op Operation) error
}

// Store runs fn in a transaction serialized per user; Reader serves side-effect-free queries.
type Store interface {
	InUserTx(ctx context.Context, userID string, fn func(Repository) error) error
	Reader() Repository
}

type Service struct {
	store Store
	now   func() time.Time
}

func New(store Store) *Service {
	return &Service{store: store, now: func() time.Time { return time.Now().UTC() }}
}

func ValidID(s string) bool {
	id, err := uuid.Parse(s)
	return err == nil && id != uuid.Nil && id.String() == s
}

func Hash(v any) string {
	b, _ := json.Marshal(v)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// translate maps domain rule violations to application errors.
func translate(err error) error {
	switch {
	case errors.Is(err, domain.ErrInvalid), errors.Is(err, domain.ErrOverlap), errors.Is(err, domain.ErrTooMuch):
		return errors.Join(ErrInvalid, err)
	case errors.Is(err, domain.ErrState), errors.Is(err, domain.ErrMinimum):
		return errors.Join(ErrPrecondition, err)
	case errors.Is(err, domain.ErrMissing):
		return ErrMissing
	}
	return err
}

func (s *Service) CreateTask(ctx context.Context, a Actor, operationID string, settings TaskSettings) (out Task, err error) {
	if !ValidID(operationID) {
		return Task{}, ErrInvalid
	}
	if err = settings.Validate(); err != nil {
		return Task{}, translate(err)
	}
	err = s.store.InUserTx(ctx, a.UserID, func(repo Repository) error {
		l := Lifecycle{repo: repo}
		h := Hash(settings)
		if ok, e := l.Replay(ctx, a, "create_task", operationID, h, &out); e != nil || ok {
			return e
		}
		t, e := repo.CreateTask(ctx, a.UserID, Task{ID: uuid.NewString(), Settings: settings})
		if e != nil {
			return e
		}
		out = t
		return l.Record(ctx, a, "create_task", operationID, h, t.ID, out)
	})
	return
}

// UpdateTask changes future sessions only; running sessions keep their snapshot.
func (s *Service) UpdateTask(ctx context.Context, a Actor, operationID, taskID string, expectedVersion int64, settings TaskSettings) (out Task, err error) {
	if !ValidID(operationID) || !ValidID(taskID) || expectedVersion < 1 {
		return Task{}, ErrInvalid
	}
	if err = settings.Validate(); err != nil {
		return Task{}, translate(err)
	}
	err = s.store.InUserTx(ctx, a.UserID, func(repo Repository) error {
		l := Lifecycle{repo: repo}
		h := Hash(struct {
			TaskID   string
			Version  int64
			Settings TaskSettings
		}{taskID, expectedVersion, settings})
		if ok, e := l.Replay(ctx, a, "update_task", operationID, h, &out); e != nil || ok {
			return e
		}
		current, e := repo.GetTask(ctx, a.UserID, taskID)
		if e != nil {
			return e
		}
		if current.Version != expectedVersion {
			return ErrConflict
		}
		current.Settings = settings
		t, e := repo.UpdateTask(ctx, a.UserID, current, expectedVersion)
		if e != nil {
			return e
		}
		out = t
		return l.Record(ctx, a, "update_task", operationID, h, t.ID, out)
	})
	return
}

func (s *Service) GetTask(ctx context.Context, a Actor, taskID string) (Task, error) {
	if !ValidID(taskID) {
		return Task{}, ErrInvalid
	}
	return s.store.Reader().GetTask(ctx, a.UserID, taskID)
}

func (s *Service) ListTasks(ctx context.Context, a Actor, after string, size int) (TaskPage, error) {
	if size < 0 || size > 100 || (after != "" && !ValidID(after)) {
		return TaskPage{}, ErrInvalid
	}
	if size == 0 {
		size = 20
	}
	tasks, err := s.store.Reader().ListTasks(ctx, a.UserID, after, size+1)
	if err != nil {
		return TaskPage{}, err
	}
	page := TaskPage{Tasks: tasks}
	if len(tasks) > size {
		page.Tasks = tasks[:size]
		page.Next = tasks[size-1].ID
	}
	return page, nil
}

// CurrentSession returns the unfinished session, or ok=false when there is none.
func (s *Service) CurrentSession(ctx context.Context, a Actor) (Session, bool, error) {
	session, err := s.store.Reader().CurrentSession(ctx, a.UserID)
	if errors.Is(err, ErrNotFound) {
		return Session{}, false, nil
	}
	return session, err == nil, err
}

func (s *Service) GetSession(ctx context.Context, a Actor, sessionID string) (Session, error) {
	if !ValidID(sessionID) {
		return Session{}, ErrInvalid
	}
	return s.store.Reader().GetSession(ctx, a.UserID, sessionID)
}

var sessionKinds = map[string]bool{"start": true, "pause": true, "resume": true, "finish": true, "abort": true}

// Operation reports whether a session operation committed and which session it targeted.
func (s *Service) Operation(ctx context.Context, a Actor, kind, operationID string) (sessionID string, found bool, err error) {
	if !sessionKinds[kind] || !ValidID(operationID) {
		return "", false, ErrInvalid
	}
	op, err := s.store.Reader().GetOperation(ctx, a.UserID, kind, operationID)
	if errors.Is(err, ErrNotFound) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return op.ResourceID, true, nil
}
