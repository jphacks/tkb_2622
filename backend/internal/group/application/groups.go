package application

import (
	"context"
	"encoding/base64"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/group/domain"
)

var (
	ErrUnauthenticated = apperr.ErrUnauthenticated
	ErrInvalid         = apperr.ErrInvalid
	ErrNotFound        = apperr.ErrNotFound
	ErrConflict        = apperr.ErrConflict
	ErrPrecondition    = apperr.ErrPrecondition
)

type Repository interface {
	ListGroups(context.Context, string) ([]domain.Group, error)
	ListWorkStarts(context.Context, string, time.Time, string, int) ([]domain.WorkStart, error)
	ListFocusedGroupMembers(context.Context, string) ([]domain.FocusedMember, error)
	CreateGroup(context.Context, string, string, string) (domain.Group, error)
	CreateInvitation(context.Context, string, string, string) (domain.Invitation, error)
	AcceptInvitation(context.Context, string, string, string) (domain.Group, error)
	LeaveGroup(context.Context, string, string, string) (domain.LeaveResult, error)
}

type Service struct{ repo Repository }

func New(repo Repository) *Service { return &Service{repo: repo} }

func (s *Service) ListGroups(ctx context.Context, userID string) ([]domain.Group, error) {
	id, err := uuid.Parse(userID)
	if err != nil || id == uuid.Nil || id.String() != userID {
		return nil, ErrUnauthenticated
	}
	return s.repo.ListGroups(ctx, userID)
}

func (s *Service) ListWorkStarts(ctx context.Context, userID string, after time.Time, afterID string, limit int) ([]domain.WorkStart, error) {
	if !validUserID(userID) {
		return nil, ErrUnauthenticated
	}
	if after.IsZero() || limit < 1 || limit > 100 || (afterID != "" && !validUUID(afterID)) {
		return nil, ErrInvalid
	}
	return s.repo.ListWorkStarts(ctx, userID, after, afterID, limit)
}

func (s *Service) ListFocusedGroupMembers(ctx context.Context, userID string) ([]domain.FocusedMember, error) {
	if !validUserID(userID) {
		return nil, ErrUnauthenticated
	}
	return s.repo.ListFocusedGroupMembers(ctx, userID)
}

func (s *Service) CreateGroup(ctx context.Context, userID, operationID, name string) (domain.Group, error) {
	id, err := uuid.Parse(userID)
	if err != nil || id == uuid.Nil || id.String() != userID {
		return domain.Group{}, ErrUnauthenticated
	}
	op, err := uuid.Parse(operationID)
	if err != nil || op == uuid.Nil || op.String() != operationID {
		return domain.Group{}, ErrInvalid
	}
	name = strings.TrimSpace(name)
	if name == "" || !utf8.ValidString(name) || utf8.RuneCountInString(name) > 100 {
		return domain.Group{}, ErrInvalid
	}
	return s.repo.CreateGroup(ctx, userID, operationID, name)
}

func (s *Service) CreateInvitation(ctx context.Context, userID, operationID, groupID string) (domain.Invitation, error) {
	if !validUserID(userID) {
		return domain.Invitation{}, ErrUnauthenticated
	}
	if !validUUID(operationID) || !validUUID(groupID) {
		return domain.Invitation{}, ErrInvalid
	}
	return s.repo.CreateInvitation(ctx, userID, operationID, groupID)
}

func (s *Service) AcceptInvitation(ctx context.Context, userID, operationID, token string) (domain.Group, error) {
	if !validUserID(userID) {
		return domain.Group{}, ErrUnauthenticated
	}
	if !validUUID(operationID) || !validInvitationToken(token) {
		return domain.Group{}, ErrInvalid
	}
	return s.repo.AcceptInvitation(ctx, userID, operationID, token)
}

func (s *Service) LeaveGroup(ctx context.Context, userID, operationID, groupID string) (domain.LeaveResult, error) {
	if !validUserID(userID) {
		return domain.LeaveResult{}, ErrUnauthenticated
	}
	if !validUUID(operationID) || !validUUID(groupID) {
		return domain.LeaveResult{}, ErrInvalid
	}
	return s.repo.LeaveGroup(ctx, userID, operationID, groupID)
}

func validUserID(value string) bool {
	id, err := uuid.Parse(value)
	return err == nil && id != uuid.Nil && id.String() == value
}

func validUUID(value string) bool {
	id, err := uuid.Parse(value)
	return err == nil && id != uuid.Nil && id.String() == value
}

func validInvitationToken(value string) bool {
	decoded, err := base64.RawURLEncoding.DecodeString(value)
	return err == nil && len(decoded) == 32
}
