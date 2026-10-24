package server

import (
	"net/http"

	"connectrpc.com/grpchealth"
)

// Handler exposes only process health; it intentionally does not probe the database.
func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte("{\"status\":\"ok\"}\n"))
	})
	mux.Handle(grpchealth.NewHandler(grpchealth.NewStaticChecker()))
	return mux
}
