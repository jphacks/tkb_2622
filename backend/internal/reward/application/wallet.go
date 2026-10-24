// Package application runs wallet operations. Callers decide the transaction; every method here
// works on the repository it was built with, so a workflow can combine it with other modules.
package application

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/reward/domain"
)

type Transaction struct {
	ID, UserID, SessionID, Type, SourceID string
	AmountSeconds, BalanceAfter           int64
	OccurredAt                            time.Time
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
	SaveOutcome(ctx context.Context, outcome domain.SessionOutcome) error
	ListTransactions(ctx context.Context, userID string, before time.Time, beforeID string, limit int) ([]Transaction, error)
}

type TransactionPage struct {
	Transactions []Transaction
	Next         string
}
type transactionCursor struct {
	OccurredAt time.Time `json:"occurred_at"`
	ID         string    `json:"id"`
}

type Wallets struct {
	repo Repository
}

func New(repo Repository) *Wallets { return &Wallets{repo: repo} }

func (w *Wallets) Balance(ctx context.Context, userID string) (domain.Wallet, error) {
	return w.repo.Wallet(ctx, userID)
}
func (w *Wallets) Summary(ctx context.Context, sessionID string) (domain.Summary, error) {
	return w.repo.Summary(ctx, sessionID)
}

// ListTransactions returns the caller's reward ledger newest first. Page tokens are opaque cursors.
func (w *Wallets) ListTransactions(ctx context.Context, userID, token string, size int) (TransactionPage, error) {
	if size < 0 || size > 100 {
		return TransactionPage{}, apperr.ErrInvalid
	}
	if size == 0 {
		size = 20
	}
	var cursor transactionCursor
	if token != "" {
		encoded, err := base64.RawURLEncoding.DecodeString(token)
		if err != nil || json.Unmarshal(encoded, &cursor) != nil || !validUUID(cursor.ID) || cursor.OccurredAt.IsZero() {
			return TransactionPage{}, apperr.ErrInvalid
		}
		cursor.OccurredAt = cursor.OccurredAt.UTC()
	}
	transactions, err := w.repo.ListTransactions(ctx, userID, cursor.OccurredAt, cursor.ID, size+1)
	if err != nil {
		return TransactionPage{}, err
	}
	page := TransactionPage{Transactions: transactions}
	if len(transactions) > size {
		page.Transactions = transactions[:size]
		last := page.Transactions[len(page.Transactions)-1]
		encoded, err := json.Marshal(transactionCursor{OccurredAt: last.OccurredAt, ID: last.ID})
		if err != nil {
			return TransactionPage{}, err
		}
		page.Next = base64.RawURLEncoding.EncodeToString(encoded)
	}
	return page, nil
}

func validUUID(value string) bool {
	id, err := uuid.Parse(value)
	return err == nil && id != uuid.Nil && id.String() == value
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
	wallet.PolicyVersion = domain.CurrentPolicy.Version
	wallet.GrantStopped, wallet.StopReason, wallet.CollectorHealthy = false, "", false
	wallet.Version++
	return wallet, w.repo.SaveWallet(ctx, wallet)
}

// Accrue grants only the cumulative delta when the session meets its reward policy.
func (w *Wallets) Accrue(ctx context.Context, userID, sessionID string, workMillis int64, eligibility domain.Eligibility, throughSeq int64) (int64, domain.Wallet, error) {
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
	if eligibility.CollectorHealthy != nil {
		wallet.CollectorHealthy = *eligibility.CollectorHealthy
	}
	if wallet.PolicyVersion == 0 {
		wallet.PolicyVersion = domain.CurrentPolicy.Version
	}
	policy, err := domain.PolicyForVersion(wallet.PolicyVersion)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	summary, err := w.repo.Summary(ctx, sessionID)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	eligible, reason := eligibility.Check(wallet.CollectorHealthy)
	if policy.Version == domain.PolicyV1.Version {
		eligible, reason = true, ""
	}
	if summary.EarnedSeconds > 0 && !eligible && !wallet.GrantStopped {
		wallet.GrantStopped, wallet.StopReason = true, reason
	}
	earned := int64(0)
	if eligible && !wallet.GrantStopped {
		earned = policy.Increment(workMillis, summary.EarnedSeconds)
	}
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
		g := Grant{ID: uuid.NewString(), SessionID: sessionID, UserID: userID, TransactionID: t.ID, PolicyVersion: policy.Version, FromSeq: from, ToSeq: throughSeq, EarnedSeconds: earned}
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
func (w *Wallets) Discard(ctx context.Context, userID, sessionID string, eligibility domain.Eligibility) (int64, domain.Wallet, error) {
	wallet, err := w.repo.Wallet(ctx, userID)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	if wallet.SessionID != sessionID {
		return 0, domain.Wallet{}, domain.ErrState
	}
	if eligibility.CollectorHealthy != nil {
		wallet.CollectorHealthy = *eligibility.CollectorHealthy
	}
	if wallet.PolicyVersion == 0 {
		wallet.PolicyVersion = domain.CurrentPolicy.Version
	}
	policy, err := domain.PolicyForVersion(wallet.PolicyVersion)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	summary, err := w.repo.Summary(ctx, sessionID)
	if err != nil {
		return 0, domain.Wallet{}, err
	}
	eligible, reason := eligibility.Check(wallet.CollectorHealthy)
	if policy.Version == domain.PolicyV1.Version {
		eligible, reason = true, ""
	}
	grantStopped := wallet.GrantStopped
	stopReason := wallet.StopReason
	if summary.EarnedSeconds > 0 {
		if !eligible && !wallet.GrantStopped {
			wallet.GrantStopped, wallet.StopReason = true, reason
		}
	} else if !eligible {
		wallet.StopReason = reason
	} else {
		wallet.StopReason = "no_reward_block"
	}
	status := domain.StatusIneligible
	if summary.EarnedSeconds > 0 {
		status = domain.StatusGranted
	}
	if summary.EarnedSeconds == 0 && wallet.StopReason == "" {
		wallet.StopReason = "no_reward_granted"
	}
	grantStopped = grantStopped || (summary.EarnedSeconds > 0 && !eligible)
	if stopReason == "" {
		stopReason = wallet.StopReason
	}
	policyVersion := wallet.PolicyVersion
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
	if err := w.repo.SaveOutcome(ctx, domain.SessionOutcome{
		SessionID: sessionID, UserID: userID, PolicyVersion: policyVersion,
		Status: status, Reason: stopReason, GrantStopped: grantStopped,
	}); err != nil {
		return 0, domain.Wallet{}, err
	}
	return discarded, wallet, nil
}

type Wallet = domain.Wallet
type Summary = domain.Summary
type Eligibility = domain.Eligibility
type Policy = domain.Policy

const (
	StatusPending    = domain.StatusPending
	StatusGranted    = domain.StatusGranted
	StatusIneligible = domain.StatusIneligible
)

var (
	PolicyV1         = domain.PolicyV1
	PolicyV2         = domain.PolicyV2
	CurrentPolicy    = domain.CurrentPolicy
	PolicyForVersion = domain.PolicyForVersion
)
