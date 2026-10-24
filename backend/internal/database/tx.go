package database

import (
	"context"
	"database/sql"
)

// InUserTx runs fn in one transaction serialized per user by a transaction-scoped advisory lock,
// so that one user's session changes and reward grants never interleave, even across instances.
// fn must not keep tx after it returns. The transaction commits only when fn returns nil.
func InUserTx(ctx context.Context, db *sql.DB, userID string, fn func(*sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", "user:"+userID); err != nil {
		return err
	}
	if err = fn(tx); err != nil {
		return err
	}
	return tx.Commit()
}
