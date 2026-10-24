package grouphttp

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/group/application"
	identityapp "github.com/jphacks/tkb_2622/backend/internal/identity/application"
	identityconnect "github.com/jphacks/tkb_2622/backend/internal/identity/adapter/connect"
)

type WorkStartsHandler struct {
	verifier identityconnect.Verifier
	identity *identityapp.Service
	groups   *application.Service
}

func NewWorkStartsHandler(verifier identityconnect.Verifier, identity *identityapp.Service, groups *application.Service) *WorkStartsHandler {
	return &WorkStartsHandler{verifier: verifier, identity: identity, groups: groups}
}

type workStartResponse struct {
	Events        []workStartEvent `json:"events"`
	NextStartedAt string           `json:"next_started_at,omitempty"`
	NextEventID   string           `json:"next_event_id,omitempty"`
}

type workStartEvent struct {
	EventID   string `json:"event_id"`
	StartedAt string `json:"started_at"`
}

func (h *WorkStartsHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed")
		return
	}
	principal, err := h.verifier.Verify(r.Context(), r.Header.Get("Authorization"))
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}
	actor, err := h.identity.ResolveActor(r.Context(), principal)
	if err != nil {
		switch {
		case errors.Is(err, identityapp.ErrForbidden):
			writeError(w, http.StatusForbidden, "forbidden")
		case errors.Is(err, identityapp.ErrNotFound):
			writeError(w, http.StatusPreconditionFailed, "ensure_user_required")
		default:
			writeError(w, http.StatusUnauthorized, "unauthenticated")
		}
		return
	}

	query := r.URL.Query()
	after, err := time.Parse(time.RFC3339Nano, query.Get("after_started_at"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_after_started_at")
		return
	}
	pageSize := 50
	if raw := query.Get("page_size"); raw != "" {
		pageSize, err = strconv.Atoi(raw)
		if err != nil || pageSize < 1 || pageSize > 100 {
			writeError(w, http.StatusBadRequest, "invalid_page_size")
			return
		}
	}
	events, err := h.groups.ListWorkStarts(r.Context(), actor.UserID, after, query.Get("after_event_id"), pageSize)
	if err != nil {
		switch {
		case errors.Is(err, application.ErrUnauthenticated):
			writeError(w, http.StatusUnauthorized, "unauthenticated")
		case errors.Is(err, application.ErrInvalid):
			writeError(w, http.StatusBadRequest, "invalid_cursor")
		default:
			writeError(w, http.StatusInternalServerError, "internal_error")
		}
		return
	}

	response := workStartResponse{Events: make([]workStartEvent, 0, len(events))}
	for _, event := range events {
		response.Events = append(response.Events, workStartEvent{EventID: event.ID, StartedAt: event.StartedAt.Format(time.RFC3339Nano)})
	}
	if len(events) > 0 {
		last := events[len(events)-1]
		response.NextStartedAt = last.StartedAt.Format(time.RFC3339Nano)
		response.NextEventID = last.ID
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(response)
}

func writeError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(struct {
		Error string `json:"error"`
	}{Error: code})
}
