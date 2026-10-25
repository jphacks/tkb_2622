package adapter

import (
	"context"
	"errors"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/database"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
	"github.com/jphacks/tkb_2622/backend/internal/workflow/application"
)

func TestRunnerStartsSessionWithConfiguredRewardPolicy(t *testing.T) {
	dsn := os.Getenv("WORKFLOW_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set WORKFLOW_TEST_DATABASE_URL to a migrated local PostgreSQL database")
	}
	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatal("invalid local test database URL")
	}
	switch parsed.Hostname() {
	case "localhost", "127.0.0.1", "::1":
	default:
		t.Fatal("workflow integration test only accepts a loopback database host")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, err := database.OpenURL(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	userID, deviceID, taskID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	if _, err := db.ExecContext(ctx, `INSERT INTO app.users (id, auth_provider, auth_subject) VALUES ($1, 'supabase', $2)`, userID, uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	defer func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cleanupCancel()
		for _, query := range []string{
			`DELETE FROM app.tasks WHERE user_id = $1`,
			`DELETE FROM app.devices WHERE user_id = $1`,
			`DELETE FROM app.users WHERE id = $1`,
		} {
			if _, err := db.ExecContext(cleanupCtx, query, userID); err != nil {
				t.Errorf("remove temporary workflow fixture: %v", err)
			}
		}
	}()
	if _, err := db.ExecContext(ctx, `INSERT INTO app.devices (id, user_id, registration_id, auth_session_id, platform, name) VALUES ($1, $2, $3, $4, 'MACOS', 'workflow test')`, deviceID, userID, uuid.NewString(), uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO app.tasks (id, user_id, name, category, mode, planned_seconds, minimum_seconds) VALUES ($1, $2, 'workflow test', 'PROGRAMMING', 'NORMAL', 300, 0)`, taskID, userID); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name    string
		runner  *Runner
		policy  int32
		initial int64
		earned  int64
	}{
		{"production", NewRunner(db), reward.PolicyV2.Version, 0, 0},
		{"local", NewRunnerWithPolicy(db, reward.PolicyTest), reward.PolicyTest.Version, 60, 20},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rollback := errors.New("rollback workflow fixture")
			err := tc.runner.InUserTx(ctx, userID, func(f application.Focus, r application.Reward, _ application.Restriction) error {
				s, err := f.Start(ctx, focus.Actor{UserID: userID, DeviceID: deviceID, DevicePlatform: "MACOS"}, taskID, 1, true, time.Now())
				if err != nil {
					return err
				}
				wallet, err := r.Open(ctx, userID, s.ID)
				if err != nil {
					return err
				}
				if wallet.PolicyVersion != tc.policy || wallet.BalanceSeconds != tc.initial {
					t.Errorf("started policy=%d balance=%d; want policy=%d balance=%d", wallet.PolicyVersion, wallet.BalanceSeconds, tc.policy, tc.initial)
				}
				quality, healthy := 0.80, true
				earned, wallet, err := r.Accrue(ctx, userID, s.ID, 60_000, reward.Eligibility{Quality: &quality, CollectorHealthy: &healthy, KnownActiveMillis: 60_000}, 1)
				if err != nil {
					return err
				}
				if earned != tc.earned || wallet.BalanceSeconds != tc.initial+tc.earned {
					t.Errorf("one work minute earned=%d balance=%d; want %d, %d", earned, wallet.BalanceSeconds, tc.earned, tc.initial+tc.earned)
				}
				return rollback
			})
			if !errors.Is(err, rollback) {
				t.Fatalf("workflow failed: %v", err)
			}
		})
	}
}
