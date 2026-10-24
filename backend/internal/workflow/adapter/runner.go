// Package adapter binds focus, reward and restriction operations to one database transaction for the workflow.
package adapter

import (
	"context"
	"database/sql"

	"github.com/jphacks/tkb_2622/backend/internal/database"
	focuspersistence "github.com/jphacks/tkb_2622/backend/internal/focus/adapter/persistence"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	restrictionpersistence "github.com/jphacks/tkb_2622/backend/internal/restriction/adapter/persistence"
	restriction "github.com/jphacks/tkb_2622/backend/internal/restriction/application"
	rewardpersistence "github.com/jphacks/tkb_2622/backend/internal/reward/adapter/persistence"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
	"github.com/jphacks/tkb_2622/backend/internal/workflow/application"
)

type Runner struct{ db *sql.DB }

func NewRunner(db *sql.DB) *Runner { return &Runner{db: db} }

func (r *Runner) InUserTx(ctx context.Context, userID string, fn func(application.Focus, application.Reward, application.Restriction) error) error {
	return database.InUserTx(ctx, r.db, userID, func(tx *sql.Tx) error {
		return fn(focus.NewLifecycle(focuspersistence.New(tx)), reward.New(rewardpersistence.New(tx)), restriction.NewControl(restrictionpersistence.New(tx)))
	})
}
