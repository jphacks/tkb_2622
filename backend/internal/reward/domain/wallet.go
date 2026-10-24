package domain

import "errors"

var (
	ErrNegativeBalance    = errors.New("reward balance cannot be negative")
	ErrNegativeCredit     = errors.New("credit seconds cannot be negative")
	ErrInvalidReservation = errors.New("reservation seconds must be positive")
	ErrInsufficientBalance = ErrInsufficient
	ErrBalanceOverflow    = errors.New("reward balance overflow")
)

// NewWallet restores a wallet from a persisted balance.
func NewWallet(balanceSeconds int64) (Wallet, error) {
	if balanceSeconds < 0 {
		return Wallet{}, ErrNegativeBalance
	}
	return Wallet{BalanceSeconds: balanceSeconds}, nil
}

// AvailableSeconds returns the wallet balance available for a new usage grant.
func (w Wallet) AvailableSeconds() int64 {
	return w.BalanceSeconds
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
	if w.BalanceSeconds > maxInt64-seconds {
		return Wallet{}, ErrBalanceOverflow
	}
	w.BalanceSeconds += seconds
	return w, nil
}

// Reserve removes positive seconds from the wallet for one usage grant.
// The caller persists the wallet change and grant in the same transaction.
func (w Wallet) Reserve(seconds int64) (Wallet, error) {
	if seconds <= 0 {
		return Wallet{}, ErrInvalidReservation
	}
	if seconds > w.BalanceSeconds {
		return Wallet{}, ErrInsufficientBalance
	}
	w.BalanceSeconds -= seconds
	return w, nil
}

// DiscardOnSessionEnd clears all unused reward seconds and returns the amount
// to record as discarded. It does not create a transaction by itself.
func (w Wallet) DiscardOnSessionEnd() (Wallet, int64) {
	discarded := w.BalanceSeconds
	w.BalanceSeconds = 0
	w.SessionID = ""
	w.EvaluatedSeq = 0
	return w, discarded
}
