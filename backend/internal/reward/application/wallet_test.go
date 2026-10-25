package application

import (
	"context"
	"testing"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/reward/domain"
)

const (
	rewardTestUserID    = "00000000-0000-4000-8000-000000000011"
	rewardTestSessionID = "00000000-0000-4000-8000-000000000012"
)

type memoryRepository struct {
	wallet       domain.Wallet
	summary      domain.Summary
	transactions []Transaction
	grants       []Grant
	outcome      domain.SessionOutcome
}

func (r *memoryRepository) Wallet(context.Context, string) (domain.Wallet, error) {
	return r.wallet, nil
}

func (r *memoryRepository) SaveWallet(_ context.Context, wallet domain.Wallet) error {
	r.wallet = wallet
	return nil
}

func (r *memoryRepository) HasTransactionSource(_ context.Context, userID, sourceID string) (bool, error) {
	for _, transaction := range r.transactions {
		if transaction.UserID == userID && transaction.SourceID == sourceID {
			return true, nil
		}
	}
	return false, nil
}

func (r *memoryRepository) AddTransaction(_ context.Context, transaction Transaction) error {
	r.transactions = append(r.transactions, transaction)
	switch transaction.Type {
	case "EARN":
		r.summary.EarnedSeconds += transaction.AmountSeconds
	case "SPEND":
		r.summary.SpentSeconds -= transaction.AmountSeconds
	case "DISCARD":
		r.summary.DiscardedSeconds -= transaction.AmountSeconds
	}
	return nil
}

func (r *memoryRepository) AddGrant(_ context.Context, grant Grant) error {
	r.grants = append(r.grants, grant)
	return nil
}

func (r *memoryRepository) Summary(context.Context, string) (domain.Summary, error) {
	return r.summary, nil
}

func (r *memoryRepository) SaveOutcome(_ context.Context, outcome domain.SessionOutcome) error {
	r.outcome = outcome
	return nil
}

func (r *memoryRepository) ListTransactions(context.Context, string, time.Time, string, int) ([]Transaction, error) {
	return nil, nil
}

func TestLocalInitialBalanceDoesNotStopOrOffsetWorkRewards(t *testing.T) {
	ctx := context.Background()
	repo := &memoryRepository{}
	wallets := NewWithPolicy(repo, PolicyTest)
	wallet, err := wallets.Open(ctx, rewardTestUserID, rewardTestSessionID)
	if err != nil || wallet.BalanceSeconds != 60 || wallet.PolicyVersion != PolicyTest.Version {
		t.Fatalf("initial wallet = %+v, err = %v; want 60 seconds on test policy", wallet, err)
	}
	quality, healthy := 0.80, true
	eligibility := domain.Eligibility{Quality: &quality, KnownActiveMillis: 30_000, CollectorHealthy: &healthy}
	earned, wallet, err := wallets.Accrue(ctx, rewardTestUserID, rewardTestSessionID, 30_000, eligibility, 1)
	if err != nil || earned != 0 || wallet.BalanceSeconds != 60 || wallet.GrantStopped {
		t.Fatalf("before first work minute: earned=%d wallet=%+v err=%v", earned, wallet, err)
	}
	eligibility.KnownActiveMillis = 60_000
	earned, wallet, err = wallets.Accrue(ctx, rewardTestUserID, rewardTestSessionID, 60_000, eligibility, 2)
	if err != nil || earned != 20 || wallet.BalanceSeconds != 80 {
		t.Fatalf("after first work minute: earned=%d balance=%d err=%v; want 20, 80", earned, wallet.BalanceSeconds, err)
	}
	if _, err := wallets.Spend(ctx, rewardTestUserID, rewardTestSessionID, "test-usage", 1); err != nil {
		t.Fatalf("spend one second: %v", err)
	}
	if _, _, err := wallets.Discard(ctx, rewardTestUserID, rewardTestSessionID, eligibility); err != nil {
		t.Fatal(err)
	}
	wallet, err = wallets.Open(ctx, rewardTestUserID, "00000000-0000-4000-8000-000000000013")
	if err != nil || wallet.BalanceSeconds != 0 {
		t.Fatalf("second session initial balance = %d, err = %v; want no repeated initial grant", wallet.BalanceSeconds, err)
	}
}

func TestV2StopsFurtherAwardsAfterEligibilityDropsWithoutClawback(t *testing.T) {
	repo := &memoryRepository{}
	wallets := New(repo)
	if _, err := wallets.Open(context.Background(), rewardTestUserID, rewardTestSessionID); err != nil {
		t.Fatal(err)
	}

	quality := 0.80
	healthy := true
	first := domain.Eligibility{Quality: &quality, KnownActiveMillis: 300_000, CollectorHealthy: &healthy}
	earned, wallet, err := wallets.Accrue(context.Background(), rewardTestUserID, rewardTestSessionID, 300_000, first, 1)
	if err != nil {
		t.Fatal(err)
	}
	if earned != 60 || wallet.BalanceSeconds != 60 {
		t.Fatalf("first grant = %d, balance = %d; want 60, 60", earned, wallet.BalanceSeconds)
	}

	quality = 0.69
	second := domain.Eligibility{Quality: &quality, KnownActiveMillis: 600_000, CollectorHealthy: &healthy}
	earned, wallet, err = wallets.Accrue(context.Background(), rewardTestUserID, rewardTestSessionID, 600_000, second, 2)
	if err != nil {
		t.Fatal(err)
	}
	if earned != 0 || wallet.BalanceSeconds != 60 || !wallet.GrantStopped {
		t.Fatalf("after eligibility drops: earned=%d balance=%d stopped=%v", earned, wallet.BalanceSeconds, wallet.GrantStopped)
	}
	if got := repo.summary.EarnedSeconds; got != 60 {
		t.Fatalf("stored earned seconds = %d, want 60", got)
	}

	if _, err := wallets.Spend(context.Background(), rewardTestUserID, rewardTestSessionID, "grant-id", 10); err != nil {
		t.Fatal(err)
	}
	discarded, wallet, err := wallets.Discard(context.Background(), rewardTestUserID, rewardTestSessionID, second)
	if err != nil {
		t.Fatal(err)
	}
	if discarded != 50 || wallet.BalanceSeconds != 0 || wallet.SessionID != "" {
		t.Fatalf("finish: discarded=%d balance=%d session=%q", discarded, wallet.BalanceSeconds, wallet.SessionID)
	}
	if repo.outcome.Status != domain.StatusGranted || !repo.outcome.GrantStopped || repo.outcome.Reason != "coverage_below_70_percent" {
		t.Fatalf("persisted outcome = %+v", repo.outcome)
	}
}
