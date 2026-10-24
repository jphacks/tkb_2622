// Package domain holds the reward rules: conversion policy and wallet invariants.
package domain

import "errors"

var (
	ErrState        = errors.New("wallet does not belong to this session")
	ErrInsufficient = errors.New("insufficient reward balance")
)

// Policy converts work time (TASK + RELATED_TRANSITION) into break seconds.
type Policy struct {
	Version     int32
	Numerator   int64
	Denominator int64
}

// CurrentPolicy: 1/3 of work time, rounded down to whole seconds, no cap (15 min of work = 5 min break).
var CurrentPolicy = Policy{Version: 1, Numerator: 1, Denominator: 3}

// Due returns the total reward seconds for the cumulative work time of a session.
// Computing from the cumulative total makes the result independent of how batches are split or resent.
func (p Policy) Due(workMillis int64) int64 {
	if workMillis <= 0 {
		return 0
	}
	return workMillis * p.Numerator / (p.Denominator * 1000)
}

// Increment is the additional grant needed given what the session already earned. Never negative.
func (p Policy) Increment(workMillis, earned int64) int64 {
	if d := p.Due(workMillis) - earned; d > 0 {
		return d
	}
	return 0
}

type Wallet struct {
	UserID         string
	SessionID      string
	BalanceSeconds int64
	EvaluatedSeq   int64
	Version        int64
}

type Summary struct {
	EarnedSeconds, SpentSeconds, DiscardedSeconds int64
}
