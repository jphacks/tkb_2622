package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/database"
	focuspersistence "github.com/jphacks/tkb_2622/backend/internal/focus/adapter/persistence"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	grouppersistence "github.com/jphacks/tkb_2622/backend/internal/group/adapter/persistence"
	group "github.com/jphacks/tkb_2622/backend/internal/group/application"
	"github.com/jphacks/tkb_2622/backend/internal/identity/adapter/auth"
	"github.com/jphacks/tkb_2622/backend/internal/identity/adapter/persistence"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
	restrictionpersistence "github.com/jphacks/tkb_2622/backend/internal/restriction/adapter/persistence"
	restriction "github.com/jphacks/tkb_2622/backend/internal/restriction/application"
	rewardpersistence "github.com/jphacks/tkb_2622/backend/internal/reward/adapter/persistence"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
	"github.com/jphacks/tkb_2622/backend/internal/server"
	workflowadapter "github.com/jphacks/tkb_2622/backend/internal/workflow/adapter"
	workflow "github.com/jphacks/tkb_2622/backend/internal/workflow/application"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("server failed", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	n, err := strconv.Atoi(port)
	if err != nil || n < 1 || n > 65535 {
		return errors.New("PORT must be between 1 and 65535")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	audience := os.Getenv("SUPABASE_JWT_AUDIENCE")
	if audience == "" {
		audience = "authenticated"
	}
	verifier, err := auth.New(auth.Config{Issuer: os.Getenv("SUPABASE_JWT_ISSUER"), Audience: audience, AllowLocalHTTP: os.Getenv("AUTH_ALLOW_LOCAL_HTTP") == "true"})
	if err != nil {
		return err
	}
	db, err := database.Open(ctx)
	if err != nil {
		return err
	}
	defer db.Close()
	identityService := application.New(persistence.New(db))
	handler := server.Handler(server.Deps{
		Identity:    identityService,
		Verifier:    verifier,
		Focus:       focus.New(focuspersistence.NewStore(db)),
		Groups:      group.New(grouppersistence.New(db)),
		Sessions:    workflow.New(workflowadapter.NewRunner(db), server.Devices{Identity: identityService}),
		Wallets:     reward.New(rewardpersistence.New(db)),
		Restriction: restriction.New(restrictionpersistence.NewStore(db)),
		EnableDocs:  os.Getenv("API_DOCS_ENABLED") == "true",
	})
	srv := &http.Server{
		Addr: net.JoinHostPort("", port), Handler: handler,
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second,
	}
	done := make(chan error, 1)
	go func() { done <- srv.ListenAndServe() }()
	logger.Info("server starting", "port", port)
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdown); err != nil {
			_ = srv.Close()
			return err
		}
		if err := <-done; !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		logger.Info("server stopped")
		return nil
	}
}
