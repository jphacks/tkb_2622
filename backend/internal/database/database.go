package database

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
)

func Open(ctx context.Context) (*sql.DB, error) { return OpenURL(ctx, os.Getenv("DATABASE_URL")) }
func OpenURL(ctx context.Context, dsn string) (*sql.DB, error) {
	if dsn == "" {
		return nil, errors.New("database URL is required")
	}
	config, err := pgx.ParseConfig(dsn)
	if err != nil {
		return nil, errors.New("invalid database configuration")
	}
	// No server-side prepared statements: compatible with Supavisor transaction mode.
	config.DefaultQueryExecMode = pgx.QueryExecModeExec
	config.ConnectTimeout = 10 * time.Second
	db := stdlib.OpenDB(*config)
	maxConnections := 5
	if raw := os.Getenv("DB_MAX_CONNECTIONS"); raw != "" {
		n, e := strconv.Atoi(raw)
		if e != nil || n < 1 || n > 100 {
			db.Close()
			return nil, errors.New("DB_MAX_CONNECTIONS must be between 1 and 100")
		}
		maxConnections = n
	}
	db.SetMaxOpenConns(maxConnections)
	db.SetMaxIdleConns(maxConnections)
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetConnMaxIdleTime(5 * time.Minute)
	ping, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err = db.PingContext(ping); err != nil {
		db.Close()
		return nil, errors.New("database connection failed (check configuration and connectivity)")
	}
	return db, nil
}
