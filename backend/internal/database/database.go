package database

import (
	"context"
	"database/sql"
	"errors"
	"net/url"
	"os"
	"time"

	_ "github.com/tursodatabase/libsql-client-go/libsql"
	_ "modernc.org/sqlite"
)

// Open is shared by database tooling. Connection errors are deliberately sanitized.
func Open(ctx context.Context) (*sql.DB, error) {
	driver := os.Getenv("DB_DRIVER")
	if driver == "" {
		driver = "sqlite"
	}
	var dsn string
	switch driver {
	case "sqlite":
		dsn = os.Getenv("SQLITE_PATH")
		if dsn == "" {
			dsn = "app.db"
		}
	case "libsql":
		u, err := url.Parse(os.Getenv("TURSO_DATABASE_URL"))
		if err != nil || u == nil || u.Host == "" || (u.Scheme != "libsql" && u.Scheme != "https") {
			return nil, errors.New("TURSO_DATABASE_URL must be a libsql or https URL")
		}
		token := os.Getenv("TURSO_AUTH_TOKEN")
		if token == "" {
			return nil, errors.New("TURSO_AUTH_TOKEN is required")
		}
		q := u.Query()
		q.Set("authToken", token)
		u.RawQuery = q.Encode()
		dsn = u.String()
	default:
		return nil, errors.New("DB_DRIVER must be sqlite or libsql")
	}
	db, err := sql.Open(driver, dsn)
	if err != nil {
		return nil, errors.New("database open failed")
	}
	db.SetMaxOpenConns(1)
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		_ = db.Close()
		return nil, errors.New("database connection failed (check configuration and connectivity)")
	}
	return db, nil
}
