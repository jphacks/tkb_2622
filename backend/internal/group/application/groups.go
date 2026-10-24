package application

import (
	"context"

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
