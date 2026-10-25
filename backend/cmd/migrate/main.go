package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/database"
	"github.com/jphacks/tkb_2622/backend/migrations"
	"github.com/pressly/goose/v3"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("migration failed", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	if len(os.Args) != 2 || (os.Args[1] != "up" && os.Args[1] != "down" && os.Args[1] != "status") {
		return errors.New("usage: migrate up|down|status")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	db, err := database.OpenURL(ctx, os.Getenv("MIGRATION_DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	provider, err := goose.NewProvider(goose.DialectPostgres, db, migrations.Files)
	if err != nil {
		// The error only names migration files, never the connection URL.
		return fmt.Errorf("migration provider initialization failed: %w", err)
	}
	switch os.Args[1] {
	case "up":
		_, err = provider.Up(ctx)
	case "down":
		_, err = provider.Down(ctx)
	case "status":
		var statuses []*goose.MigrationStatus
		statuses, err = provider.Status(ctx)
		if err == nil {
			for _, status := range statuses {
				logger.Info("migration status", "version", status.Source.Version, "state", status.State)
			}
		}
	}
	if err != nil {
		return errors.New("migration operation failed (check database availability and schema)")
	}
	logger.Info("migration command completed", "command", os.Args[1])
	return nil
}
