// Package domain holds the reward rules: conversion policy and wallet invariants.
package domain

import "errors"

var (
	ErrState        = errors.New("wallet does not belong to this session")
	ErrInsufficient = errors.New("insufficient reward balance")
	ErrPolicy       = errors.New("reward policy version is unavailable")
)

// Policy converts cumulative TASK + RELATED_TRANSITION time into break seconds.
type Policy struct {
	Version                  int32
	WorkBlockMillis          int64
	RewardBlockSeconds       int64
	MinimumKnownActiveMillis int64
	InitialBalanceSeconds    int64
}

var (
	// PolicyV1 preserves the original 1/3 conversion for sessions already in progress.
	PolicyV1 = Policy{Version: 1, WorkBlockMillis: 3_000, RewardBlockSeconds: 1}
	// PolicyV2 follows the provisional MVP rule: five minutes of related work earns one minute.
	PolicyV2 = Policy{Version: 2, WorkBlockMillis: 300_000, RewardBlockSeconds: 60, MinimumKnownActiveMillis: 300_000}
	// PolicyTest is enabled only by the local Compose API for iPhone usage-grant testing.
	PolicyTest    = Policy{Version: 3, WorkBlockMillis: 60_000, RewardBlockSeconds: 20, MinimumKnownActiveMillis: 60_000, InitialBalanceSeconds: 60}
	CurrentPolicy = PolicyV2
)

func PolicyForVersion(version int32) (Policy, error) {
	switch version {
	case PolicyV1.Version:
		return PolicyV1, nil
	case PolicyV2.Version:
		return PolicyV2, nil
	case PolicyTest.Version:
		return PolicyTest, nil
	default:
		return Policy{}, ErrPolicy
	}
}

// Due rounds cumulative related work down to complete policy blocks.
func (p Policy) Due(workMillis int64) int64 {
	if workMillis <= 0 || p.WorkBlockMillis <= 0 || p.RewardBlockSeconds <= 0 {
		return 0
	}
	return (workMillis / p.WorkBlockMillis) * p.RewardBlockSeconds
}

// Increment is the additional grant needed given what the session already earned. Never negative.
func (p Policy) Increment(workMillis, earned int64) int64 {
	if d := p.Due(workMillis) - earned; d > 0 {
		return d
	}
	return 0
}

type Eligibility struct {
	Quality           *float64
	KnownActiveMillis int64
	CollectorHealthy  *bool
}

func (e Eligibility) Check(collectorHealthy bool) (bool, string) {
	return e.CheckForPolicy(collectorHealthy, 300_000)
}

func (e Eligibility) CheckForPolicy(collectorHealthy bool, minimumKnownActiveMillis int64) (bool, string) {
	if !collectorHealthy {
		return false, "collector_unhealthy"
	}
	if e.Quality == nil || *e.Quality < 0.70 {
		return false, "coverage_below_70_percent"
	}
	if e.KnownActiveMillis < minimumKnownActiveMillis {
		return false, "known_active_below_5_minutes"
	}
	return true, ""
}

const (
	StatusPending    = "PENDING"
	StatusGranted    = "GRANTED"
	StatusIneligible = "INELIGIBLE"
)

type Wallet struct {
	UserID           string
	SessionID        string
	BalanceSeconds   int64
	EvaluatedSeq     int64
	Version          int64
	PolicyVersion    int32
	GrantStopped     bool
	StopReason       string
	CollectorHealthy bool
}

type Summary struct {
	EarnedSeconds, SpentSeconds, DiscardedSeconds int64
	PolicyVersion                                 int32
	Status                                        string
	Reason                                        string
	GrantStopped                                  bool
	CollectorHealthy                              bool
	Finalized                                     bool
}

type SessionOutcome struct {
	SessionID, UserID string
	PolicyVersion     int32
	Status            string
	Reason            string
	GrantStopped      bool
}
