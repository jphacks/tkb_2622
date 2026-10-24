package application

import (
	"context"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/identity/domain"
)

var (
	ErrUnauthenticated = errors.New("authentication required")
	ErrForbidden       = errors.New("access denied")
	ErrNotFound        = errors.New("resource not found")
	ErrInvalid         = errors.New("invalid request")
	ErrConflict        = errors.New("state or operation conflicts")
	ErrPrecondition    = errors.New("operation precondition not met")
)

// Principal contains verified identity only, never raw credentials or JWT types.
type Principal struct{ Subject, SessionID string }
type RegisterInput struct{ OperationID, RegistrationID, Platform, Name string }
type RevokeInput struct {
	OperationID, DeviceID string
	ExpectedVersion       int64
}

// Actor is the business user behind a principal and the device registered for its auth session.
// DeviceID is empty when the auth session has no registered device.
type Actor struct{ UserID, DeviceID, DevicePlatform string }
type DevicePage struct {
	Devices []domain.Device
	Next    string
}

type Repository interface {
	EnsureUser(context.Context, Principal, string) (domain.User, error)
	GetMe(context.Context, Principal) (domain.User, error)
	RegisterDevice(context.Context, Principal, RegisterInput) (domain.Device, error)
	ListDevices(context.Context, Principal, string, int) (DevicePage, error)
	RevokeDevice(context.Context, Principal, RevokeInput) (domain.Device, error)
	Actor(context.Context, Principal) (Actor, error)
	ActiveIPhone(ctx context.Context, userID string) (string, error)
}

type Service struct{ repo Repository }

func New(repo Repository) *Service { return &Service{repo: repo} }
func ValidID(s string) bool {
	id, err := uuid.Parse(s)
	return err == nil && id != uuid.Nil && id.String() == s
}
func validPrincipal(p Principal) bool { return ValidID(p.Subject) && ValidID(p.SessionID) }
func (s *Service) EnsureUser(ctx context.Context, p Principal, op string) (domain.User, error) {
	if !validPrincipal(p) {
		return domain.User{}, ErrUnauthenticated
	}
	if !ValidID(op) {
		return domain.User{}, ErrInvalid
	}
	return s.repo.EnsureUser(ctx, p, op)
}
func (s *Service) GetMe(ctx context.Context, p Principal) (domain.User, error) {
	if !validPrincipal(p) {
		return domain.User{}, ErrUnauthenticated
	}
	return s.repo.GetMe(ctx, p)
}
func (s *Service) RegisterDevice(ctx context.Context, p Principal, in RegisterInput) (domain.Device, error) {
	if !validPrincipal(p) {
		return domain.Device{}, ErrUnauthenticated
	}
	if !ValidID(in.OperationID) || !ValidID(in.RegistrationID) || strings.TrimSpace(in.Name) == "" || !utf8.ValidString(in.Name) || utf8.RuneCountInString(in.Name) > 100 {
		return domain.Device{}, ErrInvalid
	}
	if in.Platform != "MACOS" && in.Platform != "WINDOWS" && in.Platform != "IOS" {
		return domain.Device{}, ErrInvalid
	}
	return s.repo.RegisterDevice(ctx, p, in)
}
func (s *Service) ListDevices(ctx context.Context, p Principal, after string, size int) (DevicePage, error) {
	if !validPrincipal(p) {
		return DevicePage{}, ErrUnauthenticated
	}
	if size < 0 || size > 100 || (after != "" && !ValidID(after)) {
		return DevicePage{}, ErrInvalid
	}
	if size == 0 {
		size = 20
	}
	return s.repo.ListDevices(ctx, p, after, size)
}
func (s *Service) RevokeDevice(ctx context.Context, p Principal, in RevokeInput) (domain.Device, error) {
	if !validPrincipal(p) {
		return domain.Device{}, ErrUnauthenticated
	}
	if !ValidID(in.OperationID) || !ValidID(in.DeviceID) || in.ExpectedVersion < 1 {
		return domain.Device{}, ErrInvalid
	}
	return s.repo.RevokeDevice(ctx, p, in)
}

// ResolveActor is the public operation other modules use to identify the caller.
// It fails with ErrNotFound before EnsureUser and ErrForbidden for disabled users or revoked devices.
func (s *Service) ResolveActor(ctx context.Context, p Principal) (Actor, error) {
	if !validPrincipal(p) {
		return Actor{}, ErrUnauthenticated
	}
	return s.repo.Actor(ctx, p)
}

// ActiveIPhone returns the ID of the user's single active iPhone, or ErrNotFound.
func (s *Service) ActiveIPhone(ctx context.Context, userID string) (string, error) {
	if !ValidID(userID) {
		return "", ErrInvalid
	}
	return s.repo.ActiveIPhone(ctx, userID)
}
