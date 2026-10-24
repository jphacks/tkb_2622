package persistence

import (
	"context"
	"database/sql"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
)

// This integration test is opt-in and only accepts a loopback PostgreSQL URL.
// It verifies the user identity contract shared by independently authenticated clients.
func TestEnsureUserReturnsSameBusinessUserForSameSupabaseSubject(t *testing.T) {
	dsn := os.Getenv("IDENTITY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set IDENTITY_TEST_DATABASE_URL to a migrated local PostgreSQL database")
	}

	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("parse local test database URL: %v", err)
	}
	switch parsed.Hostname() {
	case "localhost", "127.0.0.1", "::1":
	default:
		t.Fatalf("identity integration test only accepts a loopback database host")
	}

	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatalf("open local test database: %v", err)
	}
	defer db.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("connect to local test database: %v", err)
	}

	subject := uuid.New()
	defer func() {
		_, _ = db.ExecContext(ctx, `DELETE FROM app.identity_operations WHERE user_id IN (
			SELECT id FROM app.users WHERE auth_provider = 'supabase' AND auth_subject = $1
		)`, subject)
		_, _ = db.ExecContext(ctx, `DELETE FROM app.users WHERE auth_provider = 'supabase' AND auth_subject = $1`, subject)
	}()

	repository := New(db)
	principal := application.Principal{Subject: subject.String(), SessionID: uuid.NewString()}
	first, err := repository.EnsureUser(ctx, principal, uuid.NewString())
	if err != nil {
		t.Fatalf("ensure user from first client session: %v", err)
	}
	second, err := repository.EnsureUser(ctx, principal, uuid.NewString())
	if err != nil {
		t.Fatalf("ensure user from second client session: %v", err)
	}
	if first.ID == "" || first.ID != second.ID {
		t.Fatalf("same Supabase subject mapped to different business users: first=%q second=%q", first.ID, second.ID)
	}
}
