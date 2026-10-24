package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	restriction "github.com/jphacks/tkb_2622/backend/internal/restriction/application"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
)

const (
	testOperationID = "00000000-0000-4000-8000-000000000001"
	testTaskID      = "00000000-0000-4000-8000-000000000002"
	testSessionID   = "00000000-0000-4000-8000-000000000003"
)

type trackingTestRunner struct {
	focus       *trackingTestFocus
	reward      *trackingTestReward
	restriction *trackingTestRestriction
}

func (r trackingTestRunner) InUserTx(_ context.Context, _ string, fn func(Focus, Reward, Restriction) error) error {
	return fn(r.focus, r.reward, r.restriction)
}

type trackingTestDevices struct {
	iPhoneID string
	err      error
}

func (d trackingTestDevices) ActiveIPhone(context.Context, string) (string, error) {
	return d.iPhoneID, d.err
}

type trackingTestFocus struct {
	session           focus.Session
	startTrackingOnly bool
	operationIDs      map[string]bool
}

func (f *trackingTestFocus) Replay(_ context.Context, _ focus.Actor, kind, operationID, _ string, _ any) (bool, error) {
	return f.operationIDs[kind+":"+operationID], nil
}
func (f *trackingTestFocus) Record(_ context.Context, _ focus.Actor, kind, operationID, _, _ string, _ any) error {
	if f.operationIDs == nil {
		f.operationIDs = make(map[string]bool)
	}
	f.operationIDs[kind+":"+operationID] = true
	return nil
}
func (f *trackingTestFocus) Get(context.Context, focus.Actor, string) (focus.Session, error) {
	return f.session, nil
}
func (f *trackingTestFocus) Start(_ context.Context, a focus.Actor, _ string, _ int64, trackingOnly bool, now time.Time) (focus.Session, error) {
	f.startTrackingOnly = trackingOnly
	f.session = focus.Session{ID: testSessionID, UserID: a.UserID, DeviceID: a.DeviceID, TrackingOnly: trackingOnly, Status: "RUNNING", Version: 1, StartedAt: now}
	return f.session, nil
}
func (f *trackingTestFocus) AcceptBatch(context.Context, focus.Actor, focus.BatchInput, time.Time) (focus.Receipt, focus.Session, error) {
	return focus.Receipt{}, f.session, nil
}
func (f *trackingTestFocus) Pause(context.Context, focus.Actor, string, int64, time.Time, int64, time.Time) (focus.Session, error) {
	f.session.Status, f.session.Version = "PAUSED", f.session.Version+1
	return f.session, nil
}
func (f *trackingTestFocus) Resume(context.Context, focus.Actor, string, int64, time.Time) (focus.Session, error) {
	f.session.Status, f.session.Version = "RUNNING", f.session.Version+1
	return f.session, nil
}
func (f *trackingTestFocus) End(_ context.Context, _ focus.Actor, abort bool, _ string, _ int64, endedAt time.Time, _ int64, _ []focus.Segment, _ time.Time) (focus.Session, error) {
	if abort {
		f.session.Status = "ABORTED"
	} else {
		f.session.Status = "FINALIZED"
	}
	f.session.EndedAt, f.session.RunningSince = &endedAt, nil
	f.session.Version++
	return f.session, nil
}

type trackingTestReward struct {
	openCalls, accrueCalls, discardCalls int
	wallet                               reward.Wallet
}

func (r *trackingTestReward) Balance(context.Context, string) (reward.Wallet, error) {
	return r.wallet, nil
}
func (r *trackingTestReward) Summary(context.Context, string) (reward.Summary, error) {
	return reward.Summary{}, nil
}
func (r *trackingTestReward) Open(_ context.Context, userID, sessionID string) (reward.Wallet, error) {
	r.openCalls++
	r.wallet = reward.Wallet{UserID: userID, SessionID: sessionID}
	return r.wallet, nil
}
func (r *trackingTestReward) Accrue(_ context.Context, _, _ string, _, throughSeq int64) (int64, reward.Wallet, error) {
	r.accrueCalls++
	r.wallet.EvaluatedSeq = throughSeq
	return 0, r.wallet, nil
}
func (r *trackingTestReward) Spend(context.Context, string, string, string, int64) (reward.Wallet, error) {
	return r.wallet, nil
}
func (r *trackingTestReward) Discard(_ context.Context, _, _ string) (int64, reward.Wallet, error) {
	r.discardCalls++
	discarded := r.wallet.BalanceSeconds
	r.wallet.SessionID, r.wallet.BalanceSeconds, r.wallet.EvaluatedSeq = "", 0, 0
	return discarded, r.wallet, nil
}

type trackingTestRestriction struct {
	beginErr                                     error
	beginCalls, viewCalls, resumeCalls, endCalls int
}

func (r *trackingTestRestriction) Replay(context.Context, string, string, string, string, any) (bool, error) {
	return false, nil
}
func (r *trackingTestRestriction) Record(context.Context, string, string, string, string, string, any) error {
	return nil
}
func (r *trackingTestRestriction) View(context.Context, string) (restriction.View, error) {
	r.viewCalls++
	return restriction.View{}, nil
}
func (r *trackingTestRestriction) BeginSession(context.Context, string, string, string, string, time.Time) (restriction.View, error) {
	r.beginCalls++
	return restriction.View{}, r.beginErr
}
func (r *trackingTestRestriction) ResumeSession(context.Context, string, string, time.Time) (restriction.View, error) {
	r.resumeCalls++
	return restriction.View{}, nil
}
func (r *trackingTestRestriction) EndSession(context.Context, string, bool, string, time.Time) (restriction.View, error) {
	r.endCalls++
	return restriction.View{}, nil
}
func (r *trackingTestRestriction) Issue(context.Context, string, string, string, int64, time.Time) (restriction.Grant, restriction.View, error) {
	return restriction.Grant{}, restriction.View{}, nil
}

func testSessions(device Devices) (*Sessions, *trackingTestFocus, *trackingTestReward, *trackingTestRestriction) {
	focusRepo, rewardRepo, restrictionRepo := &trackingTestFocus{}, &trackingTestReward{}, &trackingTestRestriction{}
	runner := trackingTestRunner{focus: focusRepo, reward: rewardRepo, restriction: restrictionRepo}
	return New(runner, device), focusRepo, rewardRepo, restrictionRepo
}

func testActor() focus.Actor {
	return focus.Actor{UserID: "user", DeviceID: "mac", DevicePlatform: "MACOS"}
}

func TestStartWithoutIPhoneUsesTrackingOnly(t *testing.T) {
	sessions, focusRepo, rewardRepo, restrictionRepo := testSessions(trackingTestDevices{err: apperr.ErrNotFound})
	result, err := sessions.Start(context.Background(), testActor(), StartInput{OperationID: testOperationID, TaskID: testTaskID, TaskVersion: 1})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	if !result.Session.TrackingOnly || !focusRepo.startTrackingOnly {
		t.Fatal("session was not saved in tracking-only mode")
	}
	if rewardRepo.openCalls != 1 {
		t.Fatalf("wallet open calls = %d, want 1", rewardRepo.openCalls)
	}
	if restrictionRepo.beginCalls != 0 {
		t.Fatalf("restriction begin calls = %d, want 0", restrictionRepo.beginCalls)
	}
}

func TestStartWithIPhonePreservesRestrictionPolicyError(t *testing.T) {
	policyErr := errors.New("restriction policy is disabled")
	sessions, focusRepo, _, restrictionRepo := testSessions(trackingTestDevices{iPhoneID: "iphone"})
	restrictionRepo.beginErr = policyErr
	_, err := sessions.Start(context.Background(), testActor(), StartInput{OperationID: testOperationID, TaskID: testTaskID, TaskVersion: 1})
	if !errors.Is(err, policyErr) {
		t.Fatalf("Start() error = %v, want policy error", err)
	}
	if focusRepo.startTrackingOnly {
		t.Fatal("registered iPhone session was marked tracking-only")
	}
	if restrictionRepo.beginCalls != 1 {
		t.Fatalf("restriction begin calls = %d, want 1", restrictionRepo.beginCalls)
	}
}

func TestStartWithIPhoneUsesRestrictionFlow(t *testing.T) {
	sessions, focusRepo, _, restrictionRepo := testSessions(trackingTestDevices{iPhoneID: "iphone"})
	result, err := sessions.Start(context.Background(), testActor(), StartInput{OperationID: testOperationID, TaskID: testTaskID, TaskVersion: 1})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	if result.Session.TrackingOnly || focusRepo.startTrackingOnly {
		t.Fatal("registered iPhone session was marked tracking-only")
	}
	if restrictionRepo.beginCalls != 1 {
		t.Fatalf("restriction begin calls = %d, want 1", restrictionRepo.beginCalls)
	}
}

func TestTrackingOnlyLifecycleSkipsRestrictionAndDiscardsSessionBalance(t *testing.T) {
	sessions, _, rewardRepo, restrictionRepo := testSessions(trackingTestDevices{err: apperr.ErrNotFound})
	actor := testActor()
	started, err := sessions.Start(context.Background(), actor, StartInput{OperationID: testOperationID, TaskID: testTaskID, TaskVersion: 1})
	if err != nil {
		t.Fatal(err)
	}
	paused, err := sessions.Pause(context.Background(), actor, PauseInput{OperationID: "00000000-0000-4000-8000-000000000004", SessionID: started.Session.ID, ExpectedVersion: 1})
	if err != nil {
		t.Fatal(err)
	}
	if !paused.Session.TrackingOnly || rewardRepo.accrueCalls != 1 || restrictionRepo.viewCalls != 0 {
		t.Fatal("tracking-only pause did not accrue rewards without reading restriction state")
	}
	resumed, err := sessions.Resume(context.Background(), actor, ResumeInput{OperationID: "00000000-0000-4000-8000-000000000005", SessionID: paused.Session.ID, ExpectedVersion: 2})
	if err != nil {
		t.Fatal(err)
	}
	if !resumed.Session.TrackingOnly || restrictionRepo.resumeCalls != 0 {
		t.Fatal("tracking-only resume called restriction processing")
	}
	rewardRepo.wallet.BalanceSeconds = 60
	finished, err := sessions.Finish(context.Background(), actor, EndInput{OperationID: "00000000-0000-4000-8000-000000000006", SessionID: resumed.Session.ID, ExpectedVersion: 3, EndedAt: time.Now(), LastSeq: 0})
	if err != nil {
		t.Fatal(err)
	}
	if !finished.Session.TrackingOnly || finished.Balance.BalanceSeconds != 0 || finished.Discarded != 60 {
		t.Fatal("tracking-only finish did not discard the session balance")
	}
	if restrictionRepo.endCalls != 0 {
		t.Fatal("tracking-only finish called restriction processing")
	}
}

func TestTrackingOnlyAbortSkipsRestrictionAndDiscardsSessionBalance(t *testing.T) {
	sessions, _, rewardRepo, restrictionRepo := testSessions(trackingTestDevices{err: apperr.ErrNotFound})
	actor := testActor()
	started, err := sessions.Start(context.Background(), actor, StartInput{OperationID: testOperationID, TaskID: testTaskID, TaskVersion: 1})
	if err != nil {
		t.Fatal(err)
	}
	rewardRepo.wallet.BalanceSeconds = 30
	aborted, err := sessions.Abort(context.Background(), actor, EndInput{OperationID: "00000000-0000-4000-8000-000000000007", SessionID: started.Session.ID, ExpectedVersion: 1, EndedAt: time.Now(), LastSeq: 0})
	if err != nil {
		t.Fatal(err)
	}
	if !aborted.Session.TrackingOnly || aborted.Balance.BalanceSeconds != 0 || aborted.Discarded != 30 {
		t.Fatal("tracking-only abort did not discard the session balance")
	}
	if restrictionRepo.endCalls != 0 {
		t.Fatal("tracking-only abort called restriction processing")
	}
}
