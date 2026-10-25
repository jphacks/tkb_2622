package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/restriction/domain"
)

func TestUpdatePolicyRebindsStateToNewRegisteredIPhone(t *testing.T) {
	userID := uuid.NewString()
	oldDeviceID := uuid.NewString()
	newDeviceID := uuid.NewString()
	store := &testStore{repo: &testRepository{
		policy: domain.Policy{
			UserID: userID, DeviceID: newDeviceID, Enabled: true, Configured: true,
			TargetMode: "SELECTED_APPS", UsageTimeMode: "ACTIVE_USAGE",
			AllowedAppsPolicy: "NONE", Version: 1,
		},
		state: domain.State{
			UserID: userID, DeviceID: oldDeviceID, SessionID: uuid.NewString(),
			ControlRevision: 4, DesiredMode: domain.Shielded, ActiveGrantID: "",
			AppliedRevision: 4, ShieldStatus: "SHIELDED", PermissionStatus: "GRANTED", Version: 2,
		},
	}}
	service := New(store)
	service.now = func() time.Time { return time.Date(2026, 10, 25, 0, 0, 0, 0, time.UTC) }

	_, err := service.UpdatePolicy(context.Background(), Actor{
		UserID: userID, DeviceID: newDeviceID, DevicePlatform: "IOS",
	}, PolicyInput{
		OperationID: uuid.NewString(), DeviceID: newDeviceID, ExpectedVersion: 1,
		Enabled: true, Configured: true, TargetMode: "SELECTED_APPS", DeviceConfigVersion: 5,
	})
	if err != nil {
		t.Fatalf("UpdatePolicy returned error: %v", err)
	}

	state := store.repo.state
	if state.DeviceID != newDeviceID {
		t.Fatalf("state target device = %q, want newly registered iPhone %q", state.DeviceID, newDeviceID)
	}
	if state.ControlRevision != 5 || state.AppliedRevision != 0 {
		t.Fatalf("rebound state revisions = control %d / applied %d, want 5 / 0", state.ControlRevision, state.AppliedRevision)
	}
	if state.ShieldStatus != "UNKNOWN" || state.PermissionStatus != "NOT_DETERMINED" || state.LastAppliedAt != nil {
		t.Fatalf("rebound state retained previous device report: %+v", state)
	}
}

type testStore struct{ repo *testRepository }

func (s *testStore) InUserTx(_ context.Context, _ string, fn func(Repository) error) error {
	return fn(s.repo)
}

func (s *testStore) Reader() Repository { return s.repo }

type testRepository struct {
	policy    domain.Policy
	state     domain.State
	operations map[string]Operation
}

func (r *testRepository) GetPolicy(_ context.Context, _, _ string) (Policy, error) {
	if r.policy.Version == 0 {
		return Policy{}, apperr.ErrNotFound
	}
	return r.policy, nil
}

func (r *testRepository) SavePolicy(_ context.Context, policy Policy) error {
	r.policy = policy
	return nil
}

func (*testRepository) GetGrant(context.Context, string, string) (Grant, error) {
	return Grant{}, apperr.ErrNotFound
}

func (*testRepository) OpenGrant(context.Context, string) (Grant, error) {
	return Grant{}, apperr.ErrNotFound
}

func (*testRepository) InsertGrant(context.Context, Grant) error { return nil }
func (*testRepository) UpdateGrant(context.Context, Grant) error { return nil }

func (r *testRepository) GetState(_ context.Context, _ string) (State, error) {
	return r.state, nil
}

func (r *testRepository) SaveState(_ context.Context, state State) error {
	r.state = state
	return nil
}

func (r *testRepository) GetOperation(_ context.Context, _, _, operationID string) (Operation, error) {
	if op, ok := r.operations[operationID]; ok {
		return op, nil
	}
	return Operation{}, apperr.ErrNotFound
}

func (r *testRepository) SaveOperation(_ context.Context, _, _, operationID string, op Operation) error {
	if r.operations == nil {
		r.operations = make(map[string]Operation)
	}
	if _, exists := r.operations[operationID]; exists {
		return errors.New("operation already exists")
	}
	r.operations[operationID] = op
	return nil
}

