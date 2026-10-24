package server

import (
	"context"
	"errors"
	"net/http"

	"connectrpc.com/connect"
	"connectrpc.com/grpchealth"
	"github.com/jphacks/tkb_2622/backend/gen/focus/v1/focusv1connect"
	"github.com/jphacks/tkb_2622/backend/gen/identity/v1/identityv1connect"
	"github.com/jphacks/tkb_2622/backend/gen/reward/v1/rewardv1connect"
	"github.com/jphacks/tkb_2622/backend/internal/docs"
	focusconnect "github.com/jphacks/tkb_2622/backend/internal/focus/adapter/connect"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	identityconnect "github.com/jphacks/tkb_2622/backend/internal/identity/adapter/connect"
	identity "github.com/jphacks/tkb_2622/backend/internal/identity/application"
	rewardconnect "github.com/jphacks/tkb_2622/backend/internal/reward/adapter/connect"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
	workflow "github.com/jphacks/tkb_2622/backend/internal/workflow/application"
)

type Deps struct {
	Identity *identity.Service
	Verifier identityconnect.Verifier
	Focus    *focus.Service
	Sessions *workflow.Sessions
	Wallets  *reward.Wallets
	// EnableDocs adds the Swagger UI at /docs and should stay off outside local development.
	EnableDocs bool
}

// actor maps the verified principal to the caller's business user and device via identity's public operation.
func actor(service *identity.Service) focusconnect.ResolveActor {
	return func(ctx context.Context) (focus.Actor, error) {
		a, err := service.ResolveActor(ctx, identityconnect.PrincipalFromContext(ctx))
		switch {
		case errors.Is(err, identity.ErrUnauthenticated):
			return focus.Actor{}, focus.ErrUnauthenticated
		case errors.Is(err, identity.ErrForbidden):
			return focus.Actor{}, focus.ErrForbidden
		case errors.Is(err, identity.ErrNotFound):
			return focus.Actor{}, errors.Join(focus.ErrPrecondition, errors.New("call EnsureUser first"))
		case err != nil:
			return focus.Actor{}, err
		}
		return focus.Actor{UserID: a.UserID, DeviceID: a.DeviceID, DevicePlatform: a.DevicePlatform}, nil
	}
}

// Handler exposes only process health; it intentionally does not probe the database.
func Handler(d Deps) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte("{\"status\":\"ok\"}\n"))
	})
	mux.Handle(grpchealth.NewHandler(grpchealth.NewStaticChecker()))
	auth := connect.WithInterceptors(identityconnect.AuthInterceptor(d.Verifier))
	mux.Handle(identityv1connect.NewIdentityServiceHandler(identityconnect.New(d.Identity), auth, connect.WithReadMaxBytes(64*1024)))
	resolve := actor(d.Identity)
	mux.Handle(focusv1connect.NewFocusServiceHandler(focusconnect.New(resolve, d.Focus, d.Sessions), auth, connect.WithReadMaxBytes(1024*1024)))
	mux.Handle(rewardv1connect.NewRewardServiceHandler(rewardconnect.New(func(ctx context.Context) (string, error) {
		a, err := resolve(ctx)
		if err != nil {
			return "", focusconnect.Error(err)
		}
		return a.UserID, nil
	}, d.Wallets), auth, connect.WithReadMaxBytes(64*1024)))
	if d.EnableDocs {
		docs.Register(mux)
	}
	return mux
}
