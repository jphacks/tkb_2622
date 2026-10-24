// Package application runs wallet operations. Callers decide the transaction; every method here
// works on the repository it was built with, so a workflow can combine it with other modules.
package application

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/reward/domain"
)

type Transaction struct {
	ID, UserID, SessionID, Type, SourceID string
	AmountSeconds, BalanceAfter           int64
}
type Grant struct {
	ID, SessionID, UserID, TransactionID string
	PolicyVersion                        int32
	FromSeq, ToSeq, EarnedSeconds        int64
}

type Repository interface {
	// Wallet returns the user's wallet, or a zero wallet when none exists yet.
	Wallet(ctx context.Context, userID string) (domain.Wallet, error)
	// SaveWallet writes w if the stored version is w.Version-1 (or the wallet is new when w.Version is 1).
	SaveWallet(ctx context.Context, w domain.Wallet) error
	AddTransaction(ctx context.Context, t Transaction) error
	AddGrant(ctx context.Context, g Grant) error
	Summary(ctx context.Context, sessionID string) (domain.Summary, error)
}

type Wallets struct {
	repo   Repository
	policy domain.Policy
}

func New(repo Repository) *Wallets { return &Wallets{repo: repo, policy: domain.CurrentPolicy} }

func (w *Wallets) Balance(ctx context.Context, userID string) (domain.Wallet, error) {
	return w.repo.Wallet(ctx, userID)
}
func (w *Wallets) Summary(ctx context.Context, sessionID string) (domain.Summary, error) {
	return w.repo.Summary(ctx, sessionID)
}

// Open binds the wallet to a newly started session with a zero balance.
func (w *Wallets) Open(ctx context.Context, userID, sessionID string) (domain.Wallet, error) {
	wallet, err := w.repo.Wallet(ctx, userID)
	if err != nil {
		return domain.Wallet{}, err
	}
	if wallet.BalanceSeconds != 0 {
		return domain.Wallet{}, domain.ErrState
	}
	wallet.UserID, wallet.SessionID, wallet.EvaluatedSeq = userID, sessionID, 0
	wallet.Version++
	return wallet, w.repo.SaveWallet(ctx, wallet)
}

// Accrue grants the interim reward for the session's cumulative work time evaluated through throughSeq.
// Replays and re-splits of batches cannot increase the reward because the total is recomputed from the cumulative time.
func (w *Wallets) Accrue(ctx context.Context, userID, sessionID string, workMillis, throughSeq int64) (int64, domain.Wallet, error) {
	wallet, err := w.repo.Wallet(ctx, userID)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	if wallet.SessionID != sessionID {
		return 0, domain.Wallet{}, domain.ErrState
	}
	if throughSeq <= wallet.EvaluatedSeq {
		return 0, wallet, nil
	}
	summary, err := w.repo.Summary(ctx, sessionID)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	earned := w.policy.Increment(workMillis, summary.EarnedSeconds)
	from := wallet.EvaluatedSeq + 1
	wallet, err = wallet.Credit(earned)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	wallet.EvaluatedSeq = throughSeq
	wallet.Version++
	if err = w.repo.SaveWallet(ctx, wallet); err != nil {
		return 0, domain.Wallet{}, err
	}
	if earned > 0 {
		t := Transaction{ID: uuid.NewString(), UserID: userID, SessionID: sessionID, Type: "EARN", SourceID: fmt.Sprintf("activity:%d-%d", from, throughSeq), AmountSeconds: earned, BalanceAfter: wallet.BalanceSeconds}
		if err = w.repo.AddTransaction(ctx, t); err != nil {
			return 0, domain.Wallet{}, err
		}
		g := Grant{ID: uuid.NewString(), SessionID: sessionID, UserID: userID, TransactionID: t.ID, PolicyVersion: w.policy.Version, FromSeq: from, ToSeq: throughSeq, EarnedSeconds: earned}
		if err = w.repo.AddGrant(ctx, g); err != nil {
			return 0, domain.Wallet{}, err
		}
	}
	return earned, wallet, nil
}

// Spend deducts a usage grant from the balance. The grant's remainder is never refunded on expiry.
func (w *Wallets) Spend(ctx context.Context, userID, sessionID, grantID string, seconds int64) (domain.Wallet, error) {
	wallet, err := w.repo.Wallet(ctx, userID)
	if err != nil {
		return domain.Wallet{}, err
	}
	if wallet.SessionID != sessionID {
		return domain.Wallet{}, domain.ErrState
	}
	wallet, err = wallet.Reserve(seconds)
	if err != nil {
		return domain.Wallet{}, errors.Join(apperr.ErrPrecondition, err)
	}
	wallet.Version++
	if err = w.repo.SaveWallet(ctx, wallet); err != nil {
		return domain.Wallet{}, err
	}
	t := Transaction{ID: uuid.NewString(), UserID: userID, SessionID: sessionID, Type: "SPEND", SourceID: "grant:" + grantID, AmountSeconds: -seconds, BalanceAfter: wallet.BalanceSeconds}
	return wallet, w.repo.AddTransaction(ctx, t)
}

// Discard zeroes the unused balance when the session finishes or aborts and detaches the wallet.
func (w *Wallets) Discard(ctx context.Context, userID, sessionID string) (int64, domain.Wallet, error) {
	wallet, err := w.repo.Wallet(ctx, userID)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	if wallet.SessionID != sessionID {
		return 0, domain.Wallet{}, domain.ErrState
	}
	wallet, discarded := wallet.DiscardOnSessionEnd()
	wallet.Version++
	if err = w.repo.SaveWallet(ctx, wallet); err != nil {
		return 0, domain.Wallet{}, err
	}
	if discarded > 0 {
		t := Transaction{ID: uuid.NewString(), UserID: userID, SessionID: sessionID, Type: "DISCARD", SourceID: "session-end:" + sessionID, AmountSeconds: -discarded, BalanceAfter: 0}
		if err = w.repo.AddTransaction(ctx, t); err != nil {
			return 0, domain.Wallet{}, err
		}
	}
	return discarded, wallet, nil
}

type Wallet = domain.Wallet
type Summary = domain.Summary
