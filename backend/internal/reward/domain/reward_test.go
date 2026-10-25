package domain

import "testing"

func TestPolicyV1DueRoundsDownToSeconds(t *testing.T) {
	cases := []struct{ work, want int64 }{{0, 0}, {-1, 0}, {2999, 0}, {3000, 1}, {900_000, 300}, {900_999, 300}}
	for _, c := range cases {
		if got := PolicyV1.Due(c.work); got != c.want {
			t.Errorf("Due(%d) = %d, want %d", c.work, got, c.want)
		}
	}
}

func TestPolicyV2UsesFiveMinuteWorkBlocks(t *testing.T) {
	cases := []struct{ work, want int64 }{
		{0, 0}, {299_999, 0}, {300_000, 60}, {599_999, 60}, {600_000, 120},
	}
	for _, c := range cases {
		if got := PolicyV2.Due(c.work); got != c.want {
			t.Errorf("Due(%d) = %d, want %d", c.work, got, c.want)
		}
	}
}

func TestIncrementIsIndependentOfBatchSplitting(t *testing.T) {
	// 20 batches of 15 s must earn the same as one 5 minute batch.
	var earned, work int64
	for i := 0; i < 20; i++ {
		work += 15_000
		earned += PolicyV2.Increment(work, earned)
	}
	if want := PolicyV2.Due(300_000); earned != want {
		t.Fatalf("split earned %d, want %d", earned, want)
	}
	if got := PolicyV2.Increment(work, earned); got != 0 {
		t.Fatalf("replay earned %d more", got)
	}
}

func TestEligibilityBoundaries(t *testing.T) {
	quality := 0.70
	healthy := true
	eligible := Eligibility{Quality: &quality, KnownActiveMillis: 300_000, CollectorHealthy: &healthy}
	if ok, reason := eligible.Check(true); !ok || reason != "" {
		t.Fatalf("exact policy boundary = %v, %q", ok, reason)
	}

	quality = 0.6999
	if ok, reason := eligible.Check(true); ok || reason != "coverage_below_70_percent" {
		t.Fatalf("low Q = %v, %q", ok, reason)
	}
	quality = 0.70
	healthy = false
	if ok, reason := eligible.Check(false); ok || reason != "collector_unhealthy" {
		t.Fatalf("unhealthy collector = %v, %q", ok, reason)
	}
}
