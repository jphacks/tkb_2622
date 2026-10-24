package domain

import "errors"

var (
	ErrNegativeBalance    = errors.New("reward balance cannot be negative")
	ErrNegativeCredit     = errors.New("credit seconds cannot be negative")
	ErrInvalidReservation = errors.New("reservation seconds must be positive")
	ErrInsufficientBalance = errors.New("insufficient reward balance")
	ErrBalanceOverflow    = errors.New("reward balance overflow")
)

// Wallet tracks the unused reward seconds available in the current session.
// Reserved seconds are removed from the wallet and belong to a usage grant.
type Wallet struct {
	balanceSeconds int64
}

// NewWallet restores a wallet from a persisted balance.
func NewWallet(balanceSeconds int64) (Wallet, error) {
	if balanceSeconds < 0 {
		return Wallet{}, ErrNegativeBalance
	}
	return Wallet{balanceSeconds: balanceSeconds}, nil
}

// BalanceSeconds returns the currently available reward seconds.
func (w Wallet) BalanceSeconds() int64 {
	return w.balanceSeconds
}

// Credit adds already-calculated reward seconds to the wallet.
// A zero credit is a no-op; reward calculation and duplicate-grant checks live
// outside this domain object.
func (w Wallet) Credit(seconds int64) (Wallet, error) {
	if seconds < 0 {
		return Wallet{}, ErrNegativeCredit
	}
	if seconds == 0 {
		return w, nil
	}

	const maxInt64 = int64(^uint64(0) >> 1)
	if w.balanceSeconds > maxInt64-seconds {
		return Wallet{}, ErrBalanceOverflow
	}
	return Wallet{balanceSeconds: w.balanceSeconds + seconds}, nil
}

// Reserve removes positive seconds from the wallet for one usage grant.
// The caller persists the wallet change and grant in the same transaction.
func (w Wallet) Reserve(seconds int64) (Wallet, error) {
	if seconds <= 0 {
		return Wallet{}, ErrInvalidReservation
	}
	if seconds > w.balanceSeconds {
		return Wallet{}, ErrInsufficientBalance
	}
	return Wallet{balanceSeconds: w.balanceSeconds - seconds}, nil
}

// DiscardOnSessionEnd clears all unused reward seconds and returns the amount
// to record as discarded. It does not create a transaction by itself.
func (w Wallet) DiscardOnSessionEnd() (Wallet, int64) {
	return Wallet{}, w.balanceSeconds
}
