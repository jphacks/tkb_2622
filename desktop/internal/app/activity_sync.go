package app

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jphacks/tkb_2622/desktop/internal/cloud"
	"github.com/jphacks/tkb_2622/desktop/internal/evaluation"
	"github.com/jphacks/tkb_2622/desktop/internal/monitor"
	"github.com/jphacks/tkb_2622/desktop/internal/session"
)

const (
	cloudSyncFileName     = "cloud-activity-outbox.json"
	maxCloudSyncBytes     = 8 << 20
	activityBatchInterval = 10 * time.Second
	activityStableDelay   = 10 * time.Second
)

type activitySyncState struct {
	SessionID          string             `json:"sessionId"`
	NextSequence       int64              `json:"nextSequence"`
	AcceptedThroughSeq int64              `json:"acceptedThroughSeq"`
	ProducedThrough    time.Time          `json:"producedThrough"`
	Items              []activitySyncItem `json:"items"`
}

type activitySyncItem struct {
	Kind      string                   `json:"kind"`
	Batch     *cloud.ActivityBatch     `json:"batch,omitempty"`
	Operation *pendingSessionOperation `json:"operation,omitempty"`
}

type pendingSessionOperation struct {
	Kind              string                  `json:"kind"`
	ID                string                  `json:"id"`
	ExpectedVersion   int64                   `json:"expectedVersion"`
	OccurredAt        time.Time               `json:"occurredAt"`
	LastSequence      int64                   `json:"lastSequence"`
	Remaining         []cloud.ActivitySegment `json:"remaining,omitempty"`
	RemainingPrepared bool                    `json:"remainingPrepared,omitempty"`
}

func (s *stateStore) LoadActivitySyncState() (activitySyncState, bool, error) {
	path := filepath.Join(filepath.Dir(s.path), cloudSyncFileName)
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return activitySyncState{}, false, nil
	}
	if err != nil {
		return activitySyncState{}, false, fmt.Errorf("activity outbox could not be opened: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return activitySyncState{}, false, fmt.Errorf("activity outbox could not be inspected: %w", err)
	}
	if !info.Mode().IsRegular() {
		return activitySyncState{}, false, errors.New("activity outbox is not a regular file")
	}
	data, err := io.ReadAll(io.LimitReader(file, maxCloudSyncBytes+1))
	if err != nil {
		return activitySyncState{}, false, fmt.Errorf("activity outbox could not be read: %w", err)
	}
	if len(data) > maxCloudSyncBytes {
		return activitySyncState{}, false, errors.New("activity outbox exceeds size limit")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var state activitySyncState
	if err := decoder.Decode(&state); err != nil {
		return activitySyncState{}, false, fmt.Errorf("activity outbox is invalid: %w", err)
	}
	if normalizeActivitySyncIDs(&state) {
		if err := s.SaveActivitySyncState(state); err != nil {
			return activitySyncState{}, false, err
		}
	}
	if err := validateActivitySyncState(state); err != nil {
		return activitySyncState{}, false, err
	}
	return state, true, nil
}

// normalizeActivitySyncIDs upgrades IDs written by earlier Desktop builds. Those builds
// stored UUID bytes without separators, which the backend correctly rejects as invalid IDs.
func normalizeActivitySyncIDs(state *activitySyncState) bool {
	changed := false
	for index := range state.Items {
		item := &state.Items[index]
		if item.Batch != nil {
			if id, ok := canonicalUUID(item.Batch.BatchID); ok {
				item.Batch.BatchID = id
				changed = true
			}
		}
		if item.Operation != nil {
			if id, ok := canonicalUUID(item.Operation.ID); ok {
				item.Operation.ID = id
				changed = true
			}
		}
	}
	return changed
}

func canonicalUUID(id string) (string, bool) {
	if len(id) != 32 {
		return id, false
	}
	if _, err := hex.DecodeString(id); err != nil {
		return id, false
	}
	return id[:8] + "-" + id[8:12] + "-" + id[12:16] + "-" + id[16:20] + "-" + id[20:], true
}

func (s *stateStore) SaveActivitySyncState(state activitySyncState) error {
	if err := validateActivitySyncState(state); err != nil {
		return err
	}
	data, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("activity outbox could not be encoded: %w", err)
	}
	if len(data) > maxCloudSyncBytes {
		return errors.New("activity outbox exceeds size limit")
	}
	path := filepath.Join(filepath.Dir(s.path), cloudSyncFileName)
	temporaryPath := path + ".tmp"
	file, err := os.OpenFile(temporaryPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("temporary activity outbox could not be created: %w", err)
	}
	writeErr := file.Chmod(0o600)
	if writeErr == nil {
		_, writeErr = file.Write(data)
	}
	if writeErr == nil {
		writeErr = file.Sync()
	}
	closeErr := file.Close()
	if err := errors.Join(writeErr, closeErr); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("activity outbox could not be saved: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		_ = os.Remove(temporaryPath)
		return fmt.Errorf("activity outbox could not be committed: %w", err)
	}
	return nil
}

func validateActivitySyncState(state activitySyncState) error {
	if state.SessionID == "" {
		if state.NextSequence != 0 || state.AcceptedThroughSeq != 0 || !state.ProducedThrough.IsZero() || len(state.Items) != 0 {
			return errors.New("activity outbox has data without a session ID")
		}
		return nil
	}
	if state.NextSequence < 1 || state.AcceptedThroughSeq < 0 || state.AcceptedThroughSeq >= state.NextSequence {
		return errors.New("activity outbox sequence state is invalid")
	}
	lastSequence := state.AcceptedThroughSeq
	for index, item := range state.Items {
		switch item.Kind {
		case "batch":
			if item.Batch == nil || item.Operation != nil || item.Batch.SessionID != state.SessionID || item.Batch.BatchID == "" || item.Batch.Seq != lastSequence+1 || len(item.Batch.Segments) == 0 {
				return fmt.Errorf("activity outbox batch %d is invalid", index)
			}
			lastSequence = item.Batch.Seq
		case "pause", "resume", "finish", "abort":
			if item.Operation == nil || item.Batch != nil || item.Operation.Kind != item.Kind || item.Operation.ID == "" || item.Operation.OccurredAt.IsZero() || item.Operation.ExpectedVersion < 0 || item.Operation.LastSequence < 0 {
				return fmt.Errorf("activity outbox operation %d is invalid", index)
			}
			if item.Operation.Kind == "abort" && item.Operation.LastSequence > lastSequence {
				return fmt.Errorf("activity outbox abort %d refers to an unsent batch", index)
			}
			if item.Operation.Kind == "abort" && item.Operation.RemainingPrepared &&
				(item.Operation.ExpectedVersion < 1 || item.Operation.LastSequence != state.AcceptedThroughSeq || index != len(state.Items)-1) {
				return fmt.Errorf("activity outbox abort %d has an invalid prepared request", index)
			}
		default:
			return fmt.Errorf("activity outbox item %d has an unknown kind", index)
		}
	}
	if lastSequence >= state.NextSequence {
		return errors.New("activity outbox next sequence is not ahead of queued batches")
	}
	return nil
}

func newActivitySyncState(sessionID string, startAt time.Time, acceptedThrough int64) activitySyncState {
	return activitySyncState{
		SessionID: sessionID, NextSequence: acceptedThrough + 1,
		AcceptedThroughSeq: acceptedThrough, ProducedThrough: startAt,
		Items: []activitySyncItem{},
	}
}

func clipActivitySegments(segments []evaluation.ActivitySegment, after, through time.Time) []cloud.ActivitySegment {
	if after.IsZero() || !through.After(after) {
		return nil
	}
	clipped := make([]cloud.ActivitySegment, 0, len(segments))
	for _, segment := range segments {
		start, end := segment.StartTime, segment.EndTime
		if !end.After(after) || !start.Before(through) {
			continue
		}
		if start.Before(after) {
			start = after
		}
		if end.After(through) {
			end = through
		}
		if !end.After(start) {
			continue
		}
		clipped = append(clipped, cloud.ActivitySegment{
			StartTime: start, EndTime: end, Classification: segment.Classification,
		})
	}
	return clipped
}

func subtractPauseRanges(segments []cloud.ActivitySegment, pauses []evaluation.PauseRange) []cloud.ActivitySegment {
	result := make([]cloud.ActivitySegment, 0, len(segments))
	for _, segment := range segments {
		parts := []cloud.ActivitySegment{segment}
		for _, pause := range pauses {
			if !pause.EndAt.After(pause.StartAt) {
				continue
			}
			next := make([]cloud.ActivitySegment, 0, len(parts)+1)
			for _, part := range parts {
				if !pause.StartAt.Before(part.EndTime) || !pause.EndAt.After(part.StartTime) {
					next = append(next, part)
					continue
				}
				if part.StartTime.Before(pause.StartAt) {
					left := part
					left.EndTime = pause.StartAt
					next = append(next, left)
				}
				if part.EndTime.After(pause.EndAt) {
					right := part
					right.StartTime = pause.EndAt
					next = append(next, right)
				}
			}
			parts = next
		}
		result = append(result, parts...)
	}
	return result
}

func sameActivitySegments(a, b []cloud.ActivitySegment) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !a[i].StartTime.Equal(b[i].StartTime) || !a[i].EndTime.Equal(b[i].EndTime) ||
			a[i].Classification != b[i].Classification || len(a[i].Reasons) != len(b[i].Reasons) {
			return false
		}
		for j := range a[i].Reasons {
			if a[i].Reasons[j] != b[i].Reasons[j] {
				return false
			}
		}
	}
	return true
}

func (a *App) repairOutboxPauseGaps(state *activitySyncState) (bool, error) {
	a.mu.Lock()
	recorder := a.recorder
	if recorder == nil {
		a.mu.Unlock()
		return false, nil
	}
	records, err := recorder.ReadRecords()
	a.mu.Unlock()
	if err != nil {
		return false, err
	}
	pauses := evaluation.PauseRanges(records)
	if len(pauses) == 0 {
		return false, nil
	}
	changed := false
	for i := range state.Items {
		item := &state.Items[i]
		if item.Batch != nil {
			segments := subtractPauseRanges(item.Batch.Segments, pauses)
			if !sameActivitySegments(segments, item.Batch.Segments) {
				item.Batch.Segments = segments
				changed = true
			}
		}
		if item.Operation != nil {
			segments := subtractPauseRanges(item.Operation.Remaining, pauses)
			if !sameActivitySegments(segments, item.Operation.Remaining) {
				item.Operation.Remaining = segments
				changed = true
			}
		}
	}
	return changed, nil
}

func collectorHealthyForBatch(state string) bool {
	switch state {
	case "running", "paused", "finished", "aborted":
		return true
	default:
		return false
	}
}

func (a *App) enqueueActivityBatchLocked(state *activitySyncState, workSession session.WorkSession, records []monitor.Record, through time.Time, collectorHealthy, final bool) (bool, error) {
	if through.IsZero() || !through.After(state.ProducedThrough) {
		return false, nil
	}
	_, segments, evaluatorVersion, err := evaluation.EvaluateDetailed(records, workSession, through)
	if err != nil {
		return false, err
	}
	items := clipActivitySegments(segments, state.ProducedThrough, through)
	state.ProducedThrough = through
	if len(items) == 0 {
		return true, nil
	}
	batchID, err := monitor.NewSessionID()
	if err != nil {
		return false, fmt.Errorf("activity batch ID could not be generated: %w", err)
	}
	batch := activitySyncItem{Kind: "batch", Batch: &cloud.ActivityBatch{
		SessionID: state.SessionID, BatchID: batchID, Seq: state.NextSequence,
		EvaluatorVersion: evaluatorVersion, RulesVersion: workSession.RulesVersion,
		CollectorHealthy: collectorHealthy, Segments: items,
	}}
	if final {
		for index, item := range state.Items {
			if item.Operation != nil && (item.Kind == "pause" || item.Kind == "finish") {
				state.Items = append(state.Items, activitySyncItem{})
				copy(state.Items[index+1:], state.Items[index:])
				state.Items[index] = batch
				item.Operation.LastSequence = state.NextSequence
				state.Items[index+1] = item
				state.NextSequence++
				return true, nil
			}
		}
	}
	state.Items = append(state.Items, batch)
	state.NextSequence++
	return true, nil
}

func makeCloudOperation(kind string, version, lastSequence int64, at time.Time, remaining []cloud.ActivitySegment) (*pendingSessionOperation, error) {
	id, err := monitor.NewSessionID()
	if err != nil {
		return nil, fmt.Errorf("cloud session operation ID could not be generated: %w", err)
	}
	return &pendingSessionOperation{
		Kind: kind, ID: id, ExpectedVersion: version, OccurredAt: at,
		LastSequence: lastSequence, Remaining: append([]cloud.ActivitySegment(nil), remaining...),
	}, nil
}

func (a *App) prepareActivitySync(at time.Time, final bool) error {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	return a.prepareActivitySyncLocked(at, final)
}

func (a *App) prepareActivitySyncLocked(at time.Time, final bool) error {
	a.mu.Lock()
	state := a.engine.Snapshot()
	if state.Session == nil || state.Session.ServerVersion < 1 || state.Session.ID == "" || a.store == nil || a.recorder == nil {
		a.mu.Unlock()
		return nil
	}
	workSession := *state.Session
	store := a.store
	monitorStatus := state.Monitor
	if !final && monitorStatus.State != "running" {
		a.mu.Unlock()
		return nil
	}
	records, err := a.recorder.ReadRecords()
	a.mu.Unlock()
	if err != nil {
		return err
	}
	syncState, _, err := store.LoadActivitySyncState()
	if err != nil {
		return err
	}
	if syncState.SessionID != workSession.ID {
		if len(syncState.Items) > 0 {
			return errors.New("activity outbox still contains another session")
		}
		startAt := at
		for _, record := range records {
			if record.Kind == "started" {
				startAt = record.RecordedAt
				break
			}
		}
		syncState = newActivitySyncState(workSession.ID, startAt, 0)
	}
	through := at
	if !final {
		through = through.Add(-activityStableDelay)
	}
	changed, err := a.enqueueActivityBatchLocked(&syncState, workSession, records, through, collectorHealthyForBatch(monitorStatus.State), final)
	if err != nil {
		return err
	}
	if err := store.SaveActivitySyncState(syncState); err != nil {
		return err
	}
	if changed {
		a.markActivitySyncQueued()
	}
	return nil
}

func (a *App) flushActivitySync(ctx context.Context) error {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	if a.cloudClient == nil || a.store == nil {
		return errors.New("cloud activity sync is not configured")
	}
	auth, err := a.currentCloudAuthLocked(ctx)
	if err != nil {
		return err
	}
	return a.flushActivitySyncLocked(ctx, auth)
}

func (a *App) flushActivitySyncLocked(ctx context.Context, auth cloud.AuthSession) error {
	a.mu.Lock()
	store := a.store
	a.mu.Unlock()
	if store == nil {
		return errors.New("local activity outbox is unavailable")
	}
	state, exists, err := store.LoadActivitySyncState()
	if err != nil {
		return err
	}
	if !exists || state.SessionID == "" {
		return nil
	}
	if len(state.Items) == 0 {
		a.markActivitySyncComplete()
		return nil
	}
	for index := range state.Items {
		item := state.Items[index]
		if item.Kind != "abort" || item.Operation.RemainingPrepared {
			continue
		}
		state, err = a.prepareAbortActivitySyncLocked(ctx, auth, state, index)
		if err != nil {
			a.markActivitySyncPending()
			return err
		}
		break
	}
	if operation := pendingFinalActivityOperation(state.Items); operation != nil && state.ProducedThrough.Before(operation.OccurredAt) {
		if err := a.prepareActivitySyncLocked(operation.OccurredAt, true); err != nil {
			a.markActivitySyncPending()
			return err
		}
		state, _, err = store.LoadActivitySyncState()
		if err != nil {
			a.markActivitySyncPending()
			return err
		}
	}
	repairedPauseGaps := false
	for len(state.Items) > 0 {
		item := state.Items[0]
		switch item.Kind {
		case "batch":
			receipt, balance, err := a.cloudClient.UploadActivityBatch(ctx, auth, *item.Batch)
			if err != nil {
				if !repairedPauseGaps && strings.Contains(err.Error(), "reported activity exceeds server-observed running time") {
					changed, repairErr := a.repairOutboxPauseGaps(&state)
					if repairErr == nil && changed {
						if saveErr := store.SaveActivitySyncState(state); saveErr == nil {
							repairedPauseGaps = true
							continue
						}
					}
				}
				a.markActivitySyncPending()
				return err
			}
			if receipt.Status == "PENDING" || receipt.AcceptedThroughSeq < item.Batch.Seq {
				err := errors.New("server activity batches are not contiguous yet")
				a.markActivitySyncPending()
				return err
			}
			if receipt.Status == "HISTORY" {
				err := errors.New("server stored this activity batch as history without reward evaluation")
				a.markActivitySyncPending()
				return err
			}
			if receipt.AcceptedThroughSeq > state.AcceptedThroughSeq {
				state.AcceptedThroughSeq = receipt.AcceptedThroughSeq
				state.Items = dropAcceptedActivityBatches(state.Items, receipt.AcceptedThroughSeq, &state.ProducedThrough)
			} else {
				state.Items = state.Items[1:]
			}
			if err := store.SaveActivitySyncState(state); err != nil {
				a.markActivitySyncPending()
				return err
			}
			a.applyCloudBalance(state.SessionID, balance)
		case "pause", "resume", "finish", "abort":
			operation := item.Operation
			if operation.ExpectedVersion == 0 {
				operation.ExpectedVersion = a.cloudSessionVersion(state.SessionID)
				if operation.ExpectedVersion < 1 {
					err := errors.New("server session version is unavailable for a queued action")
					a.markActivitySyncPending()
					return err
				}
				if err := store.SaveActivitySyncState(state); err != nil {
					a.markActivitySyncPending()
					return err
				}
			}
			version, balance, discarded, reward, err := a.sendActivityOperation(ctx, auth, state.SessionID, operation)
			if err != nil {
				if !repairedPauseGaps && strings.Contains(err.Error(), "reported activity exceeds server-observed running time") {
					changed, repairErr := a.repairOutboxPauseGaps(&state)
					if repairErr == nil && changed {
						if saveErr := store.SaveActivitySyncState(state); saveErr == nil {
							repairedPauseGaps = true
							continue
						}
					}
				}
				a.markActivitySyncPending()
				return err
			}
			state.Items = state.Items[1:]
			if err := store.SaveActivitySyncState(state); err != nil {
				a.markActivitySyncPending()
				return err
			}
			a.applyCloudOperation(state.SessionID, operation.Kind, version, balance, discarded, reward, hasPendingCloudOperation(state.Items))
		default:
			return errors.New("activity outbox contains an unsupported operation")
		}
	}
	a.markActivitySyncComplete()
	return nil
}

func dropAcceptedActivityBatches(items []activitySyncItem, acceptedThrough int64, producedThrough *time.Time) []activitySyncItem {
	firstPending := 0
	for firstPending < len(items) {
		item := items[firstPending]
		if item.Kind != "batch" || item.Batch.Seq > acceptedThrough {
			break
		}
		for _, segment := range item.Batch.Segments {
			if segment.EndTime.After(*producedThrough) {
				*producedThrough = segment.EndTime
			}
		}
		firstPending++
	}
	return items[firstPending:]
}

func hasPendingCloudOperation(items []activitySyncItem) bool {
	for _, item := range items {
		if item.Operation != nil {
			return true
		}
	}
	return false
}

func pendingFinalActivityOperation(items []activitySyncItem) *pendingSessionOperation {
	for _, item := range items {
		if item.Operation != nil && (item.Kind == "pause" || item.Kind == "finish") {
			return item.Operation
		}
	}
	return nil
}

func (a *App) sendActivityOperation(ctx context.Context, auth cloud.AuthSession, sessionID string, operation *pendingSessionOperation) (int64, cloud.Balance, int64, *cloud.RewardSummary, error) {
	switch operation.Kind {
	case "pause":
		remote, balance, err := a.cloudClient.PauseSession(ctx, auth, operation.ID, sessionID, operation.ExpectedVersion, operation.OccurredAt, operation.LastSequence)
		return remote.Version, balance, 0, nil, err
	case "resume":
		remote, balance, err := a.cloudClient.ResumeSession(ctx, auth, operation.ID, sessionID, operation.ExpectedVersion)
		return remote.Version, balance, 0, nil, err
	case "finish", "abort":
		var remote cloud.SessionResult
		var err error
		if operation.Kind == "finish" {
			remote, err = a.cloudClient.FinishSession(ctx, auth, operation.ID, sessionID, operation.ExpectedVersion, operation.OccurredAt, operation.LastSequence, nil)
		} else {
			remote, err = a.cloudClient.AbortSessionWithActivity(ctx, auth, operation.ID, sessionID, operation.ExpectedVersion, operation.OccurredAt, operation.LastSequence, operation.Remaining)
		}
		if err != nil {
			return 0, cloud.Balance{}, 0, nil, err
		}
		_, reward, err := a.cloudClient.GetSession(ctx, auth, sessionID)
		if err != nil {
			return 0, cloud.Balance{}, remote.Discarded, nil, err
		}
		return remote.Session.Version, remote.Balance, remote.Discarded, &reward, nil
	default:
		return 0, cloud.Balance{}, 0, nil, fmt.Errorf("unsupported cloud session operation %q", operation.Kind)
	}
}

func (a *App) markActivitySyncPending(cause ...error) {
	a.mu.Lock()
	now := time.Now()
	message := "作業記録はこのMacに保存され、サーバーへの送信を待っています。"
	if len(cause) > 0 && cause[0] != nil {
		detail := strings.TrimSpace(cause[0].Error())
		if detail != "" {
			runes := []rune(detail)
			if len(runes) > 240 {
				detail = string(runes[:240])
			}
			message += " " + detail
		}
	}
	a.engine.SetSyncStatus("pending", now)
	a.engine.SetFailure("cloud_activity_sync", message, true, now)
	a.persistLocked(now)
	state := a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
}

func (a *App) markActivitySyncQueued() {
	a.mu.Lock()
	now := time.Now()
	a.engine.SetSyncStatus("pending", now)
	a.persistLocked(now)
	state := a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
}

func (a *App) markActivitySyncComplete() {
	a.mu.Lock()
	now := time.Now()
	a.engine.SetSyncStatus("synced", now)
	a.engine.SetCloudOperationPending(false, now)
	state := a.engine.Snapshot()
	a.persistLocked(now)
	state = a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
}

func (a *App) applyCloudBalance(sessionID string, balance cloud.Balance) {
	a.mu.Lock()
	now := time.Now()
	a.engine.SetCloudBalance(sessionID, int(balance.BalanceSeconds), now)
	a.persistLocked(now)
	state := a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
}

func (a *App) applyCloudOperation(sessionID, kind string, version int64, balance cloud.Balance, discarded int64, reward *cloud.RewardSummary, operationPending bool) {
	a.mu.Lock()
	now := time.Now()
	a.engine.SetServerVersion(sessionID, version, now)
	a.engine.SetCloudBalance(sessionID, int(balance.BalanceSeconds), now)
	a.engine.SetCloudOperationPending(operationPending, now)
	if kind == "finish" || kind == "abort" {
		a.engine.ClearCloudBalance(now)
		if reward != nil {
			a.engine.SetResultReward(sessionID, session.RewardSummary{
				EarnedSeconds: int(reward.EarnedSeconds), SpentSeconds: int(reward.SpentSeconds),
				DiscardedSeconds: int(reward.DiscardedSeconds), Status: reward.Status, Reason: reward.Reason,
				PolicyVersion: reward.PolicyVersion, GrantStopped: reward.GrantStopped,
			}, now)
		}
	}
	state := a.engine.Snapshot()
	a.persistLocked(now)
	state = a.engine.Snapshot()
	a.mu.Unlock()
	a.emitState(state)
}

func (a *App) cloudSessionVersion(sessionID string) int64 {
	a.mu.Lock()
	defer a.mu.Unlock()
	state := a.engine.Snapshot()
	if state.Session != nil && state.Session.ID == sessionID {
		return state.Session.ServerVersion
	}
	if state.CloudSession != nil && state.CloudSession.ID == sessionID {
		return state.CloudSession.Version
	}
	return 0
}

func (a *App) queueAndPrepareCloudOperation(kind string, at time.Time) error {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	if err := a.queueCloudOperationLocked(kind, at, nil); err != nil {
		return err
	}
	if kind == "pause" || kind == "finish" {
		return a.prepareActivitySyncLocked(at, true)
	}
	return nil
}

func (a *App) queueCloudOperationLocked(kind string, at time.Time, remaining []cloud.ActivitySegment) error {
	a.mu.Lock()
	state := a.engine.Snapshot()
	if state.Session == nil || state.Session.ServerVersion < 1 || a.store == nil {
		a.mu.Unlock()
		return errors.New("cloud-managed session is unavailable")
	}
	sessionID, version, store := state.Session.ID, state.Session.ServerVersion, a.store
	a.mu.Unlock()
	syncState, _, err := store.LoadActivitySyncState()
	if err != nil {
		return err
	}
	if syncState.SessionID != sessionID {
		return errors.New("activity outbox does not match the current session")
	}
	versionForOperation := version
	if hasPendingCloudOperation(syncState.Items) {
		lastOperation := (*pendingSessionOperation)(nil)
		for _, item := range syncState.Items {
			if item.Operation != nil {
				lastOperation = item.Operation
			}
		}
		if kind != "pause" || lastOperation == nil || lastOperation.Kind != "resume" {
			return errors.New("a cloud session operation is already pending")
		}
		versionForOperation = 0
	}
	op, err := makeCloudOperation(kind, versionForOperation, syncState.NextSequence-1, at, remaining)
	if err != nil {
		return err
	}
	syncState.Items = append(syncState.Items, activitySyncItem{Kind: kind, Operation: op})
	if err := store.SaveActivitySyncState(syncState); err != nil {
		return err
	}
	a.mu.Lock()
	a.engine.SetCloudOperationPending(true, time.Now())
	a.engine.SetSyncStatus("pending", time.Now())
	a.persistLocked(time.Now())
	a.mu.Unlock()
	return nil
}

func (a *App) prepareAbortActivitySyncLocked(ctx context.Context, auth cloud.AuthSession, state activitySyncState, operationIndex int) (activitySyncState, error) {
	if operationIndex < 0 || operationIndex >= len(state.Items) || state.Items[operationIndex].Kind != "abort" || state.Items[operationIndex].Operation == nil {
		return state, errors.New("abort operation is missing from the activity outbox")
	}
	operation := state.Items[operationIndex].Operation
	if operation.RemainingPrepared {
		return state, nil
	}
	remote, err := a.cloudClient.GetCurrentSession(ctx, auth)
	if err != nil {
		return state, err
	}
	if remote == nil || remote.ID != state.SessionID || (remote.Status != "RUNNING" && remote.Status != "PAUSED") {
		return state, errors.New("server session is no longer open for abort")
	}
	a.mu.Lock()
	current := a.engine.Snapshot().Session
	store, recorder := a.store, a.recorder
	if current == nil || current.ID != state.SessionID || store == nil || recorder == nil {
		a.mu.Unlock()
		return state, errors.New("local activity capture is unavailable for abort")
	}
	workSession := *current
	records, err := recorder.ReadRecords()
	a.mu.Unlock()
	if err != nil {
		return state, err
	}
	_, segments, _, err := evaluation.EvaluateDetailed(records, workSession, operation.OccurredAt)
	if err != nil {
		return state, err
	}
	state, err = prepareAbortOutbox(state, *remote, segments)
	if err != nil {
		return state, err
	}
	if err := store.SaveActivitySyncState(state); err != nil {
		return state, err
	}
	return state, nil
}

func prepareAbortOutbox(state activitySyncState, remote cloud.Session, evaluated []evaluation.ActivitySegment) (activitySyncState, error) {
	if remote.ID != state.SessionID || remote.Version < 1 || remote.AcceptedThroughSeq < state.AcceptedThroughSeq {
		return state, errors.New("server activity sequence is behind the saved outbox")
	}
	if remote.AcceptedThroughSeq > state.AcceptedThroughSeq {
		expected := state.AcceptedThroughSeq + 1
		for _, item := range state.Items {
			if item.Kind != "batch" || item.Batch.Seq != expected {
				break
			}
			expected++
			if expected > remote.AcceptedThroughSeq {
				break
			}
		}
		if expected <= remote.AcceptedThroughSeq {
			return state, errors.New("server accepted activity batches that are missing from the local outbox")
		}
		state.Items = dropAcceptedActivityBatches(state.Items, remote.AcceptedThroughSeq, &state.ProducedThrough)
		state.AcceptedThroughSeq = remote.AcceptedThroughSeq
	}
	remaining := make([]cloud.ActivitySegment, 0)
	kept := make([]activitySyncItem, 0, len(state.Items))
	for _, item := range state.Items {
		if item.Kind == "batch" {
			if item.Batch.Seq > state.AcceptedThroughSeq {
				remaining = append(remaining, item.Batch.Segments...)
			}
			continue
		}
		kept = append(kept, item)
	}
	var operation *pendingSessionOperation
	for _, item := range kept {
		if item.Kind == "abort" {
			operation = item.Operation
			break
		}
	}
	if operation == nil {
		return state, errors.New("abort operation was lost while preparing its activity segments")
	}
	remaining = append(remaining, clipActivitySegments(evaluated, state.ProducedThrough, operation.OccurredAt)...)
	sort.Slice(remaining, func(i, j int) bool { return remaining[i].StartTime.Before(remaining[j].StartTime) })
	for index := 1; index < len(remaining); index++ {
		if remaining[index].StartTime.Before(remaining[index-1].EndTime) {
			return state, errors.New("abort activity segments overlap")
		}
	}
	state.Items = kept
	operation.ExpectedVersion = remote.Version
	operation.LastSequence = remote.AcceptedThroughSeq
	operation.Remaining = remaining
	operation.RemainingPrepared = true
	return state, nil
}

func (a *App) syncActivity(ctx context.Context) {
	state := a.snapshot()
	if state.Session != nil && state.Session.ServerVersion > 0 {
		if state.Session.Status == "RUNNING" && !state.CloudOperationPending {
			if err := a.prepareActivitySync(time.Now(), false); err != nil {
				a.markActivitySyncPending(err)
				return
			}
		} else if state.Session.Status == "PAUSED" || state.Session.Status == "FINALIZED" || state.Session.Status == "ABORTED" {
			a.mu.Lock()
			store := a.store
			a.mu.Unlock()
			if store != nil {
				syncState, exists, err := store.LoadActivitySyncState()
				if err != nil {
					a.markActivitySyncPending(err)
					return
				}
				if exists {
					if operation := pendingFinalActivityOperation(syncState.Items); operation != nil && syncState.ProducedThrough.Before(operation.OccurredAt) {
						if err := a.prepareActivitySync(operation.OccurredAt, true); err != nil {
							a.markActivitySyncPending(err)
							return
						}
					}
				}
			}
		}
	}
	a.mu.Lock()
	store, client := a.store, a.cloudClient
	a.mu.Unlock()
	if store == nil {
		return
	}
	syncState, exists, err := store.LoadActivitySyncState()
	if err != nil {
		a.markActivitySyncPending(err)
		return
	}
	if !exists || len(syncState.Items) == 0 {
		if exists && state.Session != nil && state.Session.ServerVersion > 0 {
			a.markActivitySyncComplete()
		}
		return
	}
	if client == nil {
		a.markActivitySyncPending()
		return
	}
	if err := a.flushActivitySync(ctx); err != nil {
		a.markActivitySyncPending(err)
	}
}

func (a *App) ensureActivitySyncState(sessionID string, acceptedThrough int64) error {
	a.cloudMu.Lock()
	defer a.cloudMu.Unlock()
	return a.ensureActivitySyncStateLocked(sessionID, acceptedThrough)
}

func (a *App) ensureActivitySyncStateLocked(sessionID string, acceptedThrough int64) error {
	a.mu.Lock()
	store, recorder := a.store, a.recorder
	a.mu.Unlock()
	if store == nil {
		return errors.New("local activity outbox is unavailable")
	}
	state, exists, err := store.LoadActivitySyncState()
	if err != nil {
		return err
	}
	if exists && state.SessionID == sessionID {
		if acceptedThrough < state.AcceptedThroughSeq {
			return errors.New("server activity sequence is behind the saved outbox")
		}
		if acceptedThrough > state.AcceptedThroughSeq {
			expected := state.AcceptedThroughSeq + 1
			for _, item := range state.Items {
				if item.Kind != "batch" || item.Batch.Seq != expected {
					break
				}
				expected++
				if expected > acceptedThrough {
					break
				}
			}
			if expected <= acceptedThrough {
				return errors.New("server accepted activity batches that are missing from the local outbox")
			}
			state.Items = dropAcceptedActivityBatches(state.Items, acceptedThrough, &state.ProducedThrough)
			state.AcceptedThroughSeq = acceptedThrough
			if state.NextSequence <= acceptedThrough {
				state.NextSequence = acceptedThrough + 1
			}
		}
		return store.SaveActivitySyncState(state)
	}
	if exists && len(state.Items) > 0 {
		return errors.New("saved activity outbox belongs to another session")
	}
	if acceptedThrough > 0 {
		return errors.New("server accepted activity batches but the local outbox is missing")
	}
	startAt := time.Time{}
	if recorder != nil {
		a.mu.Lock()
		records, readErr := recorder.ReadRecords()
		a.mu.Unlock()
		if readErr == nil {
			for _, record := range records {
				if record.Kind == "started" {
					startAt = record.RecordedAt
					break
				}
			}
		}
	}
	if startAt.IsZero() {
		startAt = time.Now()
	}
	return store.SaveActivitySyncState(newActivitySyncState(sessionID, startAt, acceptedThrough))
}
