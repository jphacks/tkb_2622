package server

import (
	"context"
	"errors"
	"net/http"

	"connectrpc.com/connect"
	"connectrpc.com/grpchealth"
	"github.com/jphacks/tkb_2622/backend/gen/focus/v1/focusv1connect"
	"github.com/jphacks/tkb_2622/backend/gen/group/v1/groupv1connect"
	"github.com/jphacks/tkb_2622/backend/gen/identity/v1/identityv1connect"
	"github.com/jphacks/tkb_2622/backend/gen/restriction/v1/restrictionv1connect"
	"github.com/jphacks/tkb_2622/backend/gen/reward/v1/rewardv1connect"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/docs"
	focusconnect "github.com/jphacks/tkb_2622/backend/internal/focus/adapter/connect"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	groupconnect "github.com/jphacks/tkb_2622/backend/internal/group/adapter/connect"
	grouphttp "github.com/jphacks/tkb_2622/backend/internal/group/adapter/http"
	group "github.com/jphacks/tkb_2622/backend/internal/group/application"
	identityconnect "github.com/jphacks/tkb_2622/backend/internal/identity/adapter/connect"
	identity "github.com/jphacks/tkb_2622/backend/internal/identity/application"
	restrictionconnect "github.com/jphacks/tkb_2622/backend/internal/restriction/adapter/connect"
	restriction "github.com/jphacks/tkb_2622/backend/internal/restriction/application"
	rewardconnect "github.com/jphacks/tkb_2622/backend/internal/reward/adapter/connect"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
	workflow "github.com/jphacks/tkb_2622/backend/internal/workflow/application"
)

type Deps struct {
	Identity      *identity.Service
	Verifier      identityconnect.Verifier
	Focus         *focus.Service
	Groups        *group.Service
	Sessions      *workflow.Sessions
	Wallets       *reward.Wallets
	Restriction   *restriction.Service
	Notifications interface {
		DispatchSession(context.Context, string) error
	}
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

// Devices adapts identity's public operation to the workflow's Devices port.
type Devices struct{ Identity *identity.Service }

func (d Devices) ActiveIPhone(ctx context.Context, userID string) (string, error) {
	id, err := d.Identity.ActiveIPhone(ctx, userID)
	if errors.Is(err, identity.ErrNotFound) {
		return "", apperr.ErrNotFound
	}
	return id, err
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
	mux.Handle(focusv1connect.NewFocusServiceHandler(focusconnect.New(resolve, d.Focus, d.Sessions, d.Notifications), auth, connect.WithReadMaxBytes(1024*1024)))
	resolveGroupUser := func(ctx context.Context) (string, error) {
		a, err := d.Identity.ResolveActor(ctx, identityconnect.PrincipalFromContext(ctx))
		switch {
		case errors.Is(err, identity.ErrUnauthenticated):
			return "", apperr.ErrUnauthenticated
		case errors.Is(err, identity.ErrForbidden):
			return "", apperr.ErrForbidden
		case errors.Is(err, identity.ErrNotFound):
			return "", errors.Join(apperr.ErrPrecondition, errors.New("call EnsureUser first"))
		case err != nil:
			return "", err
		default:
			return a.UserID, nil
		}
	}
	mux.Handle(groupv1connect.NewGroupServiceHandler(groupconnect.New(resolveGroupUser, d.Groups), auth, connect.WithReadMaxBytes(64*1024)))
	mux.Handle("GET /v1/group/work-starts", grouphttp.NewWorkStartsHandler(d.Verifier, d.Identity, d.Groups))
	mux.Handle(rewardv1connect.NewRewardServiceHandler(rewardconnect.New(func(ctx context.Context) (string, error) {
		a, err := resolve(ctx)
		if err != nil {
			return "", apperr.Connect(err)
		}
		return a.UserID, nil
	}, d.Wallets), auth, connect.WithReadMaxBytes(64*1024)))
	mux.Handle(restrictionv1connect.NewRestrictionServiceHandler(restrictionconnect.New(func(ctx context.Context) (restriction.Actor, error) {
		a, err := resolve(ctx)
		return restriction.Actor{UserID: a.UserID, DeviceID: a.DeviceID, DevicePlatform: a.DevicePlatform}, err
	}, d.Restriction, d.Sessions), auth, connect.WithReadMaxBytes(64*1024)))
	if d.EnableDocs {
		docs.Register(mux)
	}
	return mux
}
