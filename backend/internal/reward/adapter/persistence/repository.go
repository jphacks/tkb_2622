package persistence

import (
	"context"
	"database/sql"
	"errors"

	"github.com/google/uuid"
	q "github.com/jphacks/tkb_2622/backend/internal/reward/adapter/persistence/sqlc"
	"github.com/jphacks/tkb_2622/backend/internal/reward/application"
	"github.com/jphacks/tkb_2622/backend/internal/reward/domain"
)

// ErrVersion reports a lost update; the caller's transaction must be rolled back.
var ErrVersion = errors.New("reward wallet was modified concurrently")

// Repository works on a *sql.DB or on the *sql.Tx of a workflow transaction.
type Repository struct{ q *q.Queries }

func New(db q.DBTX) *Repository { return &Repository{q: q.New(db)} }

func nullID(s string) uuid.NullUUID {
	if s == "" {
		return uuid.NullUUID{}
	}
	return uuid.NullUUID{UUID: uuid.MustParse(s), Valid: true}
}

func (r *Repository) Wallet(ctx context.Context, userID string) (domain.Wallet, error) {
	w, err := r.q.GetWallet(ctx, uuid.MustParse(userID))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Wallet{UserID: userID}, nil
	}
	if err != nil {
		return domain.Wallet{}, err
	}
	out := domain.Wallet{UserID: userID, BalanceSeconds: w.BalanceSeconds, EvaluatedSeq: w.EvaluatedSeq, Version: w.Version}
	if w.SessionID.Valid {
		out.SessionID = w.SessionID.UUID.String()
	}
	return out, nil
}

func (r *Repository) SaveWallet(ctx context.Context, w domain.Wallet) error {
	if w.Version == 1 {
		return r.q.InsertWallet(ctx, q.InsertWalletParams{UserID: uuid.MustParse(w.UserID), SessionID: nullID(w.SessionID), BalanceSeconds: w.BalanceSeconds, EvaluatedSeq: w.EvaluatedSeq})
	}
	n, err := r.q.UpdateWallet(ctx, q.UpdateWalletParams{UserID: uuid.MustParse(w.UserID), SessionID: nullID(w.SessionID), BalanceSeconds: w.BalanceSeconds, EvaluatedSeq: w.EvaluatedSeq, Version: w.Version - 1})
	if err != nil {
		return err
	}
	if n != 1 {
		return ErrVersion
	}
	return nil
}

func (r *Repository) AddTransaction(ctx context.Context, t application.Transaction) error {
	return r.q.AddTransaction(ctx, q.AddTransactionParams{ID: uuid.MustParse(t.ID), UserID: uuid.MustParse(t.UserID), SessionID: uuid.MustParse(t.SessionID), Type: t.Type, AmountSeconds: t.AmountSeconds, SourceID: t.SourceID, BalanceAfter: t.BalanceAfter})
}

func (r *Repository) AddGrant(ctx context.Context, g application.Grant) error {
	return r.q.AddGrant(ctx, q.AddGrantParams{ID: uuid.MustParse(g.ID), SessionID: uuid.MustParse(g.SessionID), UserID: uuid.MustParse(g.UserID), PolicyVersion: g.PolicyVersion, SourceFromSeq: g.FromSeq, SourceToSeq: g.ToSeq, EarnedSeconds: g.EarnedSeconds, TransactionID: uuid.MustParse(g.TransactionID)})
}

func (r *Repository) Summary(ctx context.Context, sessionID string) (domain.Summary, error) {
	s, err := r.q.SessionSummary(ctx, uuid.MustParse(sessionID))
	if err != nil {
		return domain.Summary{}, err
	}
	return domain.Summary{EarnedSeconds: s.Earned, SpentSeconds: s.Spent, DiscardedSeconds: s.Discarded}, nil
}
