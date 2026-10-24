package server

import (
	"net/http"

	"connectrpc.com/connect"
	"connectrpc.com/grpchealth"
	"github.com/jphacks/tkb_2622/backend/gen/identity/v1/identityv1connect"
	identityconnect "github.com/jphacks/tkb_2622/backend/internal/identity/adapter/connect"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
)

// Handler exposes only process health; it intentionally does not probe the database.
func Handler(service *application.Service, verifier identityconnect.Verifier) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte("{\"status\":\"ok\"}\n"))
	})
	mux.Handle(grpchealth.NewHandler(grpchealth.NewStaticChecker()))
	mux.Handle(identityv1connect.NewIdentityServiceHandler(identityconnect.New(service), connect.WithInterceptors(identityconnect.AuthInterceptor(verifier)), connect.WithReadMaxBytes(64*1024)))
	return mux
}
