package domain

import "testing"

func TestPolicyDueRoundsDownToSeconds(t *testing.T) {
	cases := []struct{ work, want int64 }{{0, 0}, {-1, 0}, {2999, 0}, {3000, 1}, {900_000, 300}, {900_999, 300}}
	for _, c := range cases {
		if got := CurrentPolicy.Due(c.work); got != c.want {
			t.Errorf("Due(%d) = %d, want %d", c.work, got, c.want)
		}
	}
}

func TestIncrementIsIndependentOfBatchSplitting(t *testing.T) {
	// 10 batches of 2.9 s each must not earn less or more than one batch of 29 s.
	var earned, work int64
	for i := 0; i < 10; i++ {
		work += 2900
		earned += CurrentPolicy.Increment(work, earned)
	}
	if want := CurrentPolicy.Due(29000); earned != want {
		t.Fatalf("split earned %d, want %d", earned, want)
	}
	if got := CurrentPolicy.Increment(work, earned); got != 0 {
		t.Fatalf("replay earned %d more", got)
	}
}
