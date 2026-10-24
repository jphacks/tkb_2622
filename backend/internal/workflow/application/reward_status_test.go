package application

import (
	"testing"

	focus "github.com/jphacks/tkb_2622/backend/internal/focus/domain"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
)

func TestCurrentRewardStatusDoesNotFinalizeUnmetConditionsDuringOpenSession(t *testing.T) {
	s := focus.Session{
		Status: "RUNNING",
		Totals: focus.Totals{Task: 100_000, Unknown: 200_000},
	}
	summary := currentRewardStatus(s, reward.Summary{PolicyVersion: 2, CollectorHealthy: true})
	if summary.Status != reward.StatusPending || summary.Reason != "coverage_below_70_percent" {
		t.Fatalf("open session status = %+v, want pending with the current reason", summary)
	}
}

func TestCurrentRewardStatusMarksFinalSessionWithoutGrantIneligible(t *testing.T) {
	s := focus.Session{Status: "FINALIZED", Totals: focus.Totals{Task: 100_000, Unknown: 200_000}}
	summary := currentRewardStatus(s, reward.Summary{PolicyVersion: 2, CollectorHealthy: true})
	if summary.Status != reward.StatusIneligible || summary.Reason != "no_reward_granted" {
		t.Fatalf("final session status = %+v, want ineligible without reward", summary)
	}
}
