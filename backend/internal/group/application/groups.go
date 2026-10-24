package application

import (
	"context"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/group/domain"
)

var (
	ErrUnauthenticated = apperr.ErrUnauthenticated
	ErrInvalid         = apperr.ErrInvalid
)

type Repository interface {
	ListGroups(context.Context, string) ([]domain.Group, error)
	CreateGroup(context.Context, string, string, string) (domain.Group, error)
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
