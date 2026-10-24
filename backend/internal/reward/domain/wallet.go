package domain

import "errors"

var (
	ErrNegativeBalance    = errors.New("reward balance cannot be negative")
	ErrNegativeCredit     = errors.New("credit seconds cannot be negative")
	ErrInvalidReservation = errors.New("reservation seconds must be positive")
	ErrInsufficientBalance = errors.New("insufficient reward balance")
	ErrBalanceOverflow    = errors.New("reward balance overflow")
)

// RewardBalance tracks the unused reward seconds available in the current session.
// Reserved seconds are removed from the wallet and belong to a usage grant.
type RewardBalance struct {
	balanceSeconds int64
}

// NewRewardBalance restores a reward balance from persisted seconds.
func NewRewardBalance(balanceSeconds int64) (RewardBalance, error) {
	if balanceSeconds < 0 {
		return RewardBalance{}, ErrNegativeBalance
	}
	return RewardBalance{balanceSeconds: balanceSeconds}, nil
}

// BalanceSeconds returns the currently available reward seconds.
func (w RewardBalance) BalanceSeconds() int64 {
	return w.balanceSeconds
}

// Credit adds already-calculated reward seconds to the wallet.
// A zero credit is a no-op; reward calculation and duplicate-grant checks live
// outside this domain object.
func (w RewardBalance) Credit(seconds int64) (RewardBalance, error) {
	if seconds < 0 {
		return RewardBalance{}, ErrNegativeCredit
	}
	if seconds == 0 {
		return w, nil
	}

	const maxInt64 = int64(^uint64(0) >> 1)
	if w.balanceSeconds > maxInt64-seconds {
		return RewardBalance{}, ErrBalanceOverflow
	}
	return RewardBalance{balanceSeconds: w.balanceSeconds + seconds}, nil
}

// Reserve removes positive seconds from the wallet for one usage grant.
// The caller persists the wallet change and grant in the same transaction.
func (w RewardBalance) Reserve(seconds int64) (RewardBalance, error) {
	if seconds <= 0 {
		return RewardBalance{}, ErrInvalidReservation
	}
	if seconds > w.balanceSeconds {
		return RewardBalance{}, ErrInsufficientBalance
	}
	return RewardBalance{balanceSeconds: w.balanceSeconds - seconds}, nil
}

// DiscardOnSessionEnd clears all unused reward seconds and returns the amount
// to record as discarded. It does not create a transaction by itself.
func (w RewardBalance) DiscardOnSessionEnd() (RewardBalance, int64) {
	return RewardBalance{}, w.balanceSeconds
}
