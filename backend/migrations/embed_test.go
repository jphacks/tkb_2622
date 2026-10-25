package migrations_test

import (
	"database/sql"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jphacks/tkb_2622/backend/migrations"
	"github.com/pressly/goose/v3"
)

// NewProvider rejects duplicate versions without connecting to the database.
func TestProviderAcceptsFiles(t *testing.T) {
	db, err := sql.Open("pgx", "postgres://localhost/unused")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := goose.NewProvider(goose.DialectPostgres, db, migrations.Files); err != nil {
		t.Fatal(err)
	}
}
