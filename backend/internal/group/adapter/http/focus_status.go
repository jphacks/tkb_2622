package grouphttp

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/group/application"
	identityconnect "github.com/jphacks/tkb_2622/backend/internal/identity/adapter/connect"
	identityapp "github.com/jphacks/tkb_2622/backend/internal/identity/application"
)

type FocusStatusHandler struct {
	verifier identityconnect.Verifier
	identity *identityapp.Service
	groups   *application.Service
}

func NewFocusStatusHandler(verifier identityconnect.Verifier, identity *identityapp.Service, groups *application.Service) *FocusStatusHandler {
	return &FocusStatusHandler{verifier: verifier, identity: identity, groups: groups}
}

type focusedMembersResponse struct {
	Members   []focusedMember `json:"members"`
	UpdatedAt string          `json:"updated_at"`
}

type focusedMember struct {
	DisplayName string `json:"display_name"`
	AvatarID    string `json:"avatar_id"`
	StartedAt   string `json:"started_at"`
}

func (h *FocusStatusHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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

	members, err := h.groups.ListFocusedGroupMembers(r.Context(), actor.UserID)
	if err != nil {
		switch {
		case errors.Is(err, application.ErrUnauthenticated):
			writeError(w, http.StatusUnauthorized, "unauthenticated")
		default:
			writeError(w, http.StatusInternalServerError, "internal_error")
		}
		return
	}

	response := focusedMembersResponse{
		Members:   make([]focusedMember, 0, len(members)),
		UpdatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	for _, member := range members {
		response.Members = append(response.Members, focusedMember{
			DisplayName: member.DisplayName,
			AvatarID:    member.AvatarID,
			StartedAt:   member.StartedAt.Format(time.RFC3339Nano),
		})
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(response)
}
