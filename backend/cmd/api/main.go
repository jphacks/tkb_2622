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
	"github.com/jphacks/tkb_2622/backend/internal/identity/adapter/auth"
	"github.com/jphacks/tkb_2622/backend/internal/identity/adapter/persistence"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
	"github.com/jphacks/tkb_2622/backend/internal/server"
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
	service := application.New(persistence.New(db))
	srv := &http.Server{
		Addr: net.JoinHostPort("", port), Handler: server.Handler(service, verifier, os.Getenv("API_DOCS_ENABLED") == "true"),
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
