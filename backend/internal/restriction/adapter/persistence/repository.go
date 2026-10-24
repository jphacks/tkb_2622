package persistence

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/database"
	q "github.com/jphacks/tkb_2622/backend/internal/restriction/adapter/persistence/sqlc"
	"github.com/jphacks/tkb_2622/backend/internal/restriction/application"
	"github.com/jphacks/tkb_2622/backend/internal/restriction/domain"
)

// Store opens per-user transactions for single-module restriction operations.
type Store struct{ db *sql.DB }

func NewStore(db *sql.DB) *Store { return &Store{db: db} }

func (s *Store) InUserTx(ctx context.Context, userID string, fn func(application.Repository) error) error {
	return database.InUserTx(ctx, s.db, userID, func(tx *sql.Tx) error { return fn(New(tx)) })
}
func (s *Store) Reader() application.Repository { return New(s.db) }

// Repository works on a *sql.DB or on the *sql.Tx of a workflow transaction.
type Repository struct{ q *q.Queries }

func New(db q.DBTX) *Repository { return &Repository{q: q.New(db)} }

func uid(s string) uuid.UUID { return uuid.MustParse(s) }
func nullID(s string) uuid.NullUUID {
	if s == "" {
		return uuid.NullUUID{}
	}
	return uuid.NullUUID{UUID: uid(s), Valid: true}
}
func idString(id uuid.NullUUID) string {
	if !id.Valid {
		return ""
	}
	return id.UUID.String()
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
func nullInt(v *int64) sql.NullInt64 {
	if v == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: *v, Valid: true}
}
func intPtr(v sql.NullInt64) *int64 {
	if !v.Valid {
		return nil
	}
	return &v.Int64
}
func translate(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return apperr.ErrNotFound
	}
	return err
}
func affected(n int64, err error) error {
	if err != nil {
		return err
	}
	if n != 1 {
		return apperr.ErrConflict
	}
	return nil
}

func asGrant(g q.AppUsageGrant) domain.Grant {
	return domain.Grant{
		ID: g.ID.String(), UserID: g.UserID.String(), DeviceID: g.DeviceID.String(), SessionID: g.SessionID.String(),
		RequestedSeconds: g.RequestedSeconds, ReservedSeconds: g.ReservedSeconds, Status: g.Status, ControlRevision: g.ControlRevision,
		IssuedAt: g.IssuedAt.UTC(), ActivatedAt: timePtr(g.ActivatedAt), ReportSeq: g.ReportSeq, ReportedSeconds: g.ReportedSeconds,
		LastObservedAt: timePtr(g.LastObservedAt), ConsumedSeconds: intPtr(g.ConsumedSeconds), DiscardedSeconds: intPtr(g.DiscardedSeconds),
		EndReason: g.EndReason.String, EndedByOperation: g.EndedByOperationID, CompletedAt: timePtr(g.CompletedAt), Version: g.Version,
	}
}

func (r *Repository) GetPolicy(ctx context.Context, userID, deviceID string) (domain.Policy, error) {
	p, err := r.q.GetPolicy(ctx, q.GetPolicyParams{UserID: uid(userID), DeviceID: uid(deviceID)})
	if err != nil {
		return domain.Policy{}, translate(err)
	}
	return domain.Policy{DeviceID: p.DeviceID.String(), UserID: p.UserID.String(), TargetMode: p.TargetMode, UsageTimeMode: p.UsageTimeMode, AllowedAppsPolicy: p.AllowedAppsPolicy, Enabled: p.Enabled, Configured: p.Configured, DeviceConfigVersion: p.DeviceConfigVersion, Version: p.Version, UpdatedAt: p.UpdatedAt.UTC()}, nil
}
func (r *Repository) SavePolicy(ctx context.Context, p domain.Policy) error {
	if p.Version == 1 {
		return r.q.InsertPolicy(ctx, q.InsertPolicyParams{DeviceID: uid(p.DeviceID), UserID: uid(p.UserID), Enabled: p.Enabled, TargetMode: p.TargetMode, DeviceConfigVersion: p.DeviceConfigVersion, Configured: p.Configured})
	}
	return affected(r.q.UpdatePolicy(ctx, q.UpdatePolicyParams{UserID: uid(p.UserID), DeviceID: uid(p.DeviceID), Enabled: p.Enabled, TargetMode: p.TargetMode, DeviceConfigVersion: p.DeviceConfigVersion, Configured: p.Configured, Version: p.Version - 1}))
}

func (r *Repository) GetGrant(ctx context.Context, userID, grantID string) (domain.Grant, error) {
	g, err := r.q.GetGrant(ctx, q.GetGrantParams{UserID: uid(userID), ID: uid(grantID)})
	return asGrant(g), translate(err)
}
func (r *Repository) OpenGrant(ctx context.Context, userID string) (domain.Grant, error) {
	g, err := r.q.OpenGrant(ctx, uid(userID))
	return asGrant(g), translate(err)
}
func (r *Repository) InsertGrant(ctx context.Context, g domain.Grant) error {
	return r.q.InsertGrant(ctx, q.InsertGrantParams{ID: uid(g.ID), UserID: uid(g.UserID), DeviceID: uid(g.DeviceID), SessionID: uid(g.SessionID), RequestedSeconds: g.RequestedSeconds, ReservedSeconds: g.ReservedSeconds, Status: g.Status, ControlRevision: g.ControlRevision, IssuedAt: g.IssuedAt})
}
func (r *Repository) UpdateGrant(ctx context.Context, g domain.Grant) error {
	return affected(r.q.UpdateGrant(ctx, q.UpdateGrantParams{
		UserID: uid(g.UserID), ID: uid(g.ID), Status: g.Status, ActivatedAt: nullTime(g.ActivatedAt), ReportSeq: g.ReportSeq, ReportedSeconds: g.ReportedSeconds,
		LastObservedAt: nullTime(g.LastObservedAt), ConsumedSeconds: nullInt(g.ConsumedSeconds), DiscardedSeconds: nullInt(g.DiscardedSeconds),
		EndReason: sql.NullString{String: g.EndReason, Valid: g.EndReason != ""}, EndedByOperationID: g.EndedByOperation, CompletedAt: nullTime(g.CompletedAt),
		Version: g.Version - 1,
	}))
}

func (r *Repository) GetState(ctx context.Context, userID string) (domain.State, error) {
	s, err := r.q.GetState(ctx, uid(userID))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.NewState(userID), nil
	}
	if err != nil {
		return domain.State{}, err
	}
	return domain.State{
		UserID: userID, DeviceID: idString(s.DeviceID), SessionID: idString(s.SessionID), ControlRevision: s.ControlRevision, DesiredMode: s.DesiredMode,
		ActiveGrantID: idString(s.ActiveGrantID), AppliedRevision: s.AppliedRevision, ShieldStatus: s.ShieldStatus, PermissionStatus: s.PermissionStatus,
		LastAppliedAt: timePtr(s.LastAppliedAt), LastReportedAt: timePtr(s.LastReportedAt), FailureReason: s.FailureReason, Version: s.Version,
	}, nil
}
func (r *Repository) SaveState(ctx context.Context, s domain.State) error {
	if s.Version == 1 {
		return r.q.InsertState(ctx, q.InsertStateParams{
			UserID: uid(s.UserID), DeviceID: nullID(s.DeviceID), SessionID: nullID(s.SessionID), ControlRevision: s.ControlRevision, DesiredMode: s.DesiredMode,
			ActiveGrantID: nullID(s.ActiveGrantID), AppliedRevision: s.AppliedRevision, ShieldStatus: s.ShieldStatus, PermissionStatus: s.PermissionStatus,
			LastAppliedAt: nullTime(s.LastAppliedAt), LastReportedAt: nullTime(s.LastReportedAt), FailureReason: s.FailureReason,
		})
	}
	return affected(r.q.UpdateState(ctx, q.UpdateStateParams{
		UserID: uid(s.UserID), DeviceID: nullID(s.DeviceID), SessionID: nullID(s.SessionID), ControlRevision: s.ControlRevision, DesiredMode: s.DesiredMode,
		ActiveGrantID: nullID(s.ActiveGrantID), AppliedRevision: s.AppliedRevision, ShieldStatus: s.ShieldStatus, PermissionStatus: s.PermissionStatus,
		LastAppliedAt: nullTime(s.LastAppliedAt), LastReportedAt: nullTime(s.LastReportedAt), FailureReason: s.FailureReason, Version: s.Version - 1,
	}))
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
