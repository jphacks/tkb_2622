package persistence

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/database"
	q "github.com/jphacks/tkb_2622/backend/internal/focus/adapter/persistence/sqlc"
	"github.com/jphacks/tkb_2622/backend/internal/focus/application"
	"github.com/jphacks/tkb_2622/backend/internal/focus/domain"
)

// Store opens per-user transactions for single-module focus operations.
type Store struct{ db *sql.DB }

func NewStore(db *sql.DB) *Store { return &Store{db: db} }

func (s *Store) InUserTx(ctx context.Context, userID string, fn func(application.Repository) error) error {
	return database.InUserTx(ctx, s.db, userID, func(tx *sql.Tx) error { return fn(New(tx)) })
}
func (s *Store) Reader() application.Repository { return New(s.db) }

// Repository works on a *sql.DB or on the *sql.Tx of a workflow transaction.
type Repository struct {
	q  *q.Queries
	db q.DBTX
}

func New(db q.DBTX) *Repository { return &Repository{q: q.New(db), db: db} }

func uid(s string) uuid.UUID { return uuid.MustParse(s) }
func translate(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return application.ErrNotFound
	}
	return err
}
func nullTime(t *time.Time) sql.NullTime {
	if t == nil {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: *t, Valid: true}
}
func timePtr(t sql.NullTime) *time.Time {
	if !t.Valid {
		return nil
	}
	v := t.Time.UTC()
	return &v
}
func asTask(t q.AppTask) domain.Task {
	return domain.Task{ID: t.ID.String(), Settings: domain.TaskSettings{Name: t.Name, Category: t.Category, Mode: t.Mode, PlannedSeconds: t.PlannedSeconds, MinimumSeconds: t.MinimumSeconds}, Version: t.Version, CreatedAt: t.CreatedAt.UTC(), UpdatedAt: t.UpdatedAt.UTC()}
}
func asSession(s q.AppWorkSession) domain.Session {
	return domain.Session{
		ID: s.ID.String(), UserID: s.UserID.String(), DeviceID: s.DeviceID.String(), TaskID: s.TaskID.String(),
		Snapshot: domain.TaskSettings{Name: s.TaskName, Category: s.Category, Mode: s.Mode, PlannedSeconds: s.PlannedSeconds, MinimumSeconds: s.MinimumSeconds},
		Status:   s.Status, Version: s.Version, StartedAt: s.StartedAt.UTC(), RunningSince: timePtr(s.RunningSince), ServerActiveMillis: s.ServerActiveMillis,
		PausedAt: timePtr(s.PausedAt), EndedAt: timePtr(s.EndedAt), AcceptedSeq: s.AcceptedSeq, LastSegmentEnd: timePtr(s.LastSegmentEnd),
		Totals: domain.Totals{Task: s.TaskMillis, Related: s.RelatedMillis, Distraction: s.DistractionMillis, Unknown: s.UnknownMillis, Idle: s.IdleMillis},
	}
}
func asBatch(b q.AppActivityBatch) (application.Batch, error) {
	out := application.Batch{SessionID: b.SessionID.String(), BatchID: b.BatchID.String(), Hash: b.RequestHash, Status: b.Status, EvaluatorVersion: b.EvaluatorVersion, RulesVersion: b.RulesVersion, Seq: b.Seq}
	return out, json.Unmarshal(b.Segments, &out.Segments)
}

func (r *Repository) CreateTask(ctx context.Context, userID string, t domain.Task) (domain.Task, error) {
	row, err := r.q.CreateTask(ctx, q.CreateTaskParams{ID: uid(t.ID), UserID: uid(userID), Name: t.Settings.Name, Category: t.Settings.Category, Mode: t.Settings.Mode, PlannedSeconds: t.Settings.PlannedSeconds, MinimumSeconds: t.Settings.MinimumSeconds})
	return asTask(row), err
}
func (r *Repository) UpdateTask(ctx context.Context, userID string, t domain.Task, expectedVersion int64) (domain.Task, error) {
	row, err := r.q.UpdateTask(ctx, q.UpdateTaskParams{UserID: uid(userID), ID: uid(t.ID), Name: t.Settings.Name, Category: t.Settings.Category, Mode: t.Settings.Mode, PlannedSeconds: t.Settings.PlannedSeconds, MinimumSeconds: t.Settings.MinimumSeconds, Version: expectedVersion})
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Task{}, application.ErrConflict
	}
	return asTask(row), err
}
func (r *Repository) GetTask(ctx context.Context, userID, taskID string) (domain.Task, error) {
	row, err := r.q.GetTask(ctx, q.GetTaskParams{UserID: uid(userID), ID: uid(taskID)})
	return asTask(row), translate(err)
}
func (r *Repository) ListTasks(ctx context.Context, userID, after string, limit int) ([]domain.Task, error) {
	cursor := uuid.Nil
	if after != "" {
		cursor = uid(after)
	}
	rows, err := r.q.ListTasks(ctx, q.ListTasksParams{UserID: uid(userID), ID: cursor, Limit: int32(limit)})
	if err != nil {
		return nil, err
	}
	out := make([]domain.Task, 0, len(rows))
	for _, t := range rows {
		out = append(out, asTask(t))
	}
	return out, nil
}

func (r *Repository) CreateSession(ctx context.Context, s domain.Session) error {
	return r.q.CreateSession(ctx, q.CreateSessionParams{
		ID: uid(s.ID), UserID: uid(s.UserID), DeviceID: uid(s.DeviceID), TaskID: uid(s.TaskID),
		TaskName: s.Snapshot.Name, Category: s.Snapshot.Category, Mode: s.Snapshot.Mode, PlannedSeconds: s.Snapshot.PlannedSeconds, MinimumSeconds: s.Snapshot.MinimumSeconds,
		Status: s.Status, Version: s.Version, StartedAt: s.StartedAt, RunningSince: nullTime(s.RunningSince),
	})
}
func (r *Repository) GetSession(ctx context.Context, userID, sessionID string) (domain.Session, error) {
	row, err := r.q.GetSession(ctx, q.GetSessionParams{UserID: uid(userID), ID: uid(sessionID)})
	return asSession(row), translate(err)
}
func (r *Repository) ListSessions(ctx context.Context, userID string, before time.Time, beforeID string, limit int) ([]domain.Session, error) {
	query := `SELECT * FROM app.work_sessions WHERE user_id = $1 AND status IN ('FINALIZED', 'ABORTED')`
	args := []any{uid(userID)}
	if !before.IsZero() {
		query += ` AND (started_at, id) < ($2, $3)`
		args = append(args, before, uid(beforeID))
	}
	args = append(args, limit)
	query += fmt.Sprintf(` ORDER BY started_at DESC, id DESC LIMIT $%d`, len(args))
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]domain.Session, 0, limit)
	for rows.Next() {
		var row q.AppWorkSession
		if err := rows.Scan(
			&row.ID, &row.UserID, &row.DeviceID, &row.TaskID, &row.TaskName, &row.Category, &row.Mode,
			&row.PlannedSeconds, &row.MinimumSeconds, &row.Status, &row.Version, &row.StartedAt,
			&row.RunningSince, &row.ServerActiveMillis, &row.PausedAt, &row.EndedAt, &row.AcceptedSeq,
			&row.LastSegmentEnd, &row.TaskMillis, &row.RelatedMillis, &row.DistractionMillis,
			&row.UnknownMillis, &row.IdleMillis, &row.FinalSegments,
		); err != nil {
			return nil, err
		}
		out = append(out, asSession(row))
	}
	return out, rows.Err()
}
func (r *Repository) CurrentSession(ctx context.Context, userID string) (domain.Session, error) {
	row, err := r.q.CurrentSession(ctx, uid(userID))
	return asSession(row), translate(err)
}
func (r *Repository) UpdateSession(ctx context.Context, s domain.Session, prevVersion, prevAcceptedSeq int64) error {
	n, err := r.q.UpdateSession(ctx, q.UpdateSessionParams{
		UserID: uid(s.UserID), ID: uid(s.ID), Status: s.Status, Version: s.Version, RunningSince: nullTime(s.RunningSince), ServerActiveMillis: s.ServerActiveMillis,
		PausedAt: nullTime(s.PausedAt), EndedAt: nullTime(s.EndedAt), AcceptedSeq: s.AcceptedSeq, LastSegmentEnd: nullTime(s.LastSegmentEnd),
		TaskMillis: s.Totals.Task, RelatedMillis: s.Totals.Related, DistractionMillis: s.Totals.Distraction, UnknownMillis: s.Totals.Unknown, IdleMillis: s.Totals.Idle,
		Version_2: prevVersion, AcceptedSeq_2: prevAcceptedSeq,
	})
	if err != nil {
		return err
	}
	if n != 1 {
		return application.ErrConflict
	}
	return nil
}
func (r *Repository) SetFinalSegments(ctx context.Context, sessionID string, segments []domain.Segment) error {
	b, err := json.Marshal(segments)
	if err != nil {
		return err
	}
	return r.q.SetFinalSegments(ctx, q.SetFinalSegmentsParams{ID: uid(sessionID), FinalSegments: b})
}

func (r *Repository) GetBatch(ctx context.Context, sessionID string, seq int64) (application.Batch, error) {
	row, err := r.q.GetBatch(ctx, q.GetBatchParams{SessionID: uid(sessionID), Seq: seq})
	if err != nil {
		return application.Batch{}, translate(err)
	}
	return asBatch(row)
}
func (r *Repository) BatchByID(ctx context.Context, sessionID, batchID string) (application.Batch, error) {
	row, err := r.q.BatchByID(ctx, q.BatchByIDParams{SessionID: uid(sessionID), BatchID: uid(batchID)})
	if err != nil {
		return application.Batch{}, translate(err)
	}
	return asBatch(row)
}
func (r *Repository) InsertBatch(ctx context.Context, b application.Batch) error {
	segments, err := json.Marshal(b.Segments)
	if err != nil {
		return err
	}
	return r.q.InsertBatch(ctx, q.InsertBatchParams{SessionID: uid(b.SessionID), Seq: b.Seq, BatchID: uid(b.BatchID), RequestHash: b.Hash, Status: b.Status, EvaluatorVersion: b.EvaluatorVersion, RulesVersion: b.RulesVersion, Segments: segments})
}
func (r *Repository) SetBatchStatus(ctx context.Context, sessionID string, seq int64, status string) error {
	return r.q.SetBatchStatus(ctx, q.SetBatchStatusParams{SessionID: uid(sessionID), Seq: seq, Status: status})
}
func (r *Repository) DeleteBatch(ctx context.Context, sessionID string, seq int64) error {
	return r.q.DeleteBatch(ctx, q.DeleteBatchParams{SessionID: uid(sessionID), Seq: seq})
}
func (r *Repository) PendingSeqs(ctx context.Context, sessionID string) ([]int64, error) {
	return r.q.PendingSeqs(ctx, uid(sessionID))
}

func (r *Repository) GetOperation(ctx context.Context, userID, kind, operationID string) (application.Operation, error) {
	row, err := r.q.GetOperation(ctx, q.GetOperationParams{UserID: uid(userID), Kind: kind, OperationID: uid(operationID)})
	if err != nil {
		return application.Operation{}, translate(err)
	}
	return application.Operation{Hash: row.RequestHash, ResourceID: row.ResourceID.String(), Response: row.Response}, nil
}
func (r *Repository) SaveOperation(ctx context.Context, userID, kind, operationID string, op application.Operation) error {
	return r.q.SaveOperation(ctx, q.SaveOperationParams{UserID: uid(userID), Kind: kind, OperationID: uid(operationID), RequestHash: op.Hash, ResourceID: uid(op.ResourceID), Response: op.Response})
}
