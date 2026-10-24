// Package focusconnect converts FocusService RPCs to focus and workflow operations.
package focusconnect

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/focus/v1"
	rewardv1 "github.com/jphacks/tkb_2622/backend/gen/reward/v1"
	"github.com/jphacks/tkb_2622/backend/internal/focus/application"
	reward "github.com/jphacks/tkb_2622/backend/internal/reward/application"
	workflow "github.com/jphacks/tkb_2622/backend/internal/workflow/application"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// ResolveActor identifies the caller from the verified request context.
type ResolveActor func(context.Context) (application.Actor, error)

type Handler struct {
	resolve  ResolveActor
	service  *application.Service
	sessions *workflow.Sessions
}

func New(resolve ResolveActor, service *application.Service, sessions *workflow.Sessions) *Handler {
	return &Handler{resolve: resolve, service: service, sessions: sessions}
}

// Error converts focus application errors to connect errors for handlers that share the actor resolution.
func Error(err error) error { return rpcError(err) }

func rpcError(err error) error {
	code := connect.CodeInternal
	message := "operation failed"
	detail := strings.ReplaceAll(err.Error(), "\n", ": ")
	switch {
	case errors.Is(err, application.ErrUnauthenticated):
		code, message = connect.CodeUnauthenticated, detail
	case errors.Is(err, application.ErrForbidden):
		code, message = connect.CodePermissionDenied, detail
	case errors.Is(err, application.ErrNotFound):
		code, message = connect.CodeNotFound, detail
	case errors.Is(err, application.ErrInvalid):
		code, message = connect.CodeInvalidArgument, detail
	case errors.Is(err, application.ErrConflict):
		code, message = connect.CodeAborted, detail
	case errors.Is(err, application.ErrMissing), errors.Is(err, application.ErrPrecondition):
		code, message = connect.CodeFailedPrecondition, detail
	case errors.Is(err, context.Canceled):
		code, message = connect.CodeCanceled, "request canceled"
	case errors.Is(err, context.DeadlineExceeded):
		code, message = connect.CodeDeadlineExceeded, "request timed out"
	}
	return connect.NewError(code, errors.New(message))
}

var (
	categoryOut = map[string]v1.TaskCategory{"PROGRAMMING": v1.TaskCategory_TASK_CATEGORY_PROGRAMMING, "DOCUMENT_WRITING": v1.TaskCategory_TASK_CATEGORY_DOCUMENT_WRITING, "READING": v1.TaskCategory_TASK_CATEGORY_READING, "DESIGN": v1.TaskCategory_TASK_CATEGORY_DESIGN, "STUDY": v1.TaskCategory_TASK_CATEGORY_STUDY, "OTHER": v1.TaskCategory_TASK_CATEGORY_OTHER}
	modeOut     = map[string]v1.FocusMode{"NORMAL": v1.FocusMode_FOCUS_MODE_NORMAL, "READING": v1.FocusMode_FOCUS_MODE_READING, "VIDEO": v1.FocusMode_FOCUS_MODE_VIDEO}
	statusOut   = map[string]v1.SessionStatus{"RUNNING": v1.SessionStatus_SESSION_STATUS_RUNNING, "PAUSED": v1.SessionStatus_SESSION_STATUS_PAUSED, "FINALIZED": v1.SessionStatus_SESSION_STATUS_FINALIZED, "ABORTED": v1.SessionStatus_SESSION_STATUS_ABORTED}
	batchOut    = map[string]v1.BatchStatus{"ACCEPTED": v1.BatchStatus_BATCH_STATUS_ACCEPTED, "PENDING": v1.BatchStatus_BATCH_STATUS_PENDING, "HISTORY": v1.BatchStatus_BATCH_STATUS_HISTORY}
	classIn     = map[v1.ActivityClass]string{v1.ActivityClass_ACTIVITY_CLASS_TASK: "TASK", v1.ActivityClass_ACTIVITY_CLASS_RELATED_TRANSITION: "RELATED_TRANSITION", v1.ActivityClass_ACTIVITY_CLASS_DISTRACTION: "DISTRACTION", v1.ActivityClass_ACTIVITY_CLASS_UNKNOWN: "UNKNOWN", v1.ActivityClass_ACTIVITY_CLASS_IDLE: "IDLE"}
	kindIn      = map[v1.OperationKind]string{v1.OperationKind_OPERATION_KIND_START: "start", v1.OperationKind_OPERATION_KIND_PAUSE: "pause", v1.OperationKind_OPERATION_KIND_RESUME: "resume", v1.OperationKind_OPERATION_KIND_FINISH: "finish", v1.OperationKind_OPERATION_KIND_ABORT: "abort"}
)

func settingsIn(s *v1.TaskSettings) application.TaskSettings {
	if s == nil {
		return application.TaskSettings{}
	}
	return application.TaskSettings{Name: s.Name, Category: strings.TrimPrefix(s.Category.String(), "TASK_CATEGORY_"), Mode: strings.TrimPrefix(s.Mode.String(), "FOCUS_MODE_"), PlannedSeconds: s.PlannedSeconds, MinimumSeconds: s.MinimumSeconds}
}
func settingsOut(s application.TaskSettings) *v1.TaskSettings {
	return &v1.TaskSettings{Name: s.Name, Category: categoryOut[s.Category], Mode: modeOut[s.Mode], PlannedSeconds: s.PlannedSeconds, MinimumSeconds: s.MinimumSeconds}
}
func task(t application.Task) *v1.Task {
	return &v1.Task{Id: t.ID, Settings: settingsOut(t.Settings), Version: t.Version, CreatedAt: timestamppb.New(t.CreatedAt), UpdatedAt: timestamppb.New(t.UpdatedAt)}
}
func session(s application.Session) *v1.Session {
	t := s.Totals
	out := &v1.Session{
		Id: s.ID, DeviceId: s.DeviceID, TaskId: s.TaskID, TaskSnapshot: settingsOut(s.Snapshot), Status: statusOut[s.Status], Version: s.Version,
		StartedAt: timestamppb.New(s.StartedAt), AcceptedThroughSeq: s.AcceptedSeq, MinimumReached: s.MinimumReached(),
		Durations: &v1.Durations{TaskMillis: t.Task, RelatedTransitionMillis: t.Related, DistractionMillis: t.Distraction, UnknownMillis: t.Unknown, IdleMillis: t.Idle, ActiveMillis: t.Active(), WorkMillis: t.Work()},
	}
	if s.PausedAt != nil && s.Status == "PAUSED" {
		out.PausedAt = timestamppb.New(*s.PausedAt)
	}
	if s.EndedAt != nil {
		out.EndedAt = timestamppb.New(*s.EndedAt)
	}
	out.FocusScore, out.Quality, out.WorkRate = t.Scores()
	return out
}
func balance(w reward.Wallet) *rewardv1.RewardBalance {
	return &rewardv1.RewardBalance{SessionId: w.SessionID, BalanceSeconds: w.BalanceSeconds, Version: w.Version, EvaluatedThroughSeq: w.EvaluatedSeq}
}
func segments(in []*v1.ActivitySegment) ([]application.Segment, error) {
	out := make([]application.Segment, 0, len(in))
	for _, s := range in {
		class, ok := classIn[s.GetClassification()]
		if s == nil || !ok || !s.StartTime.IsValid() || !s.EndTime.IsValid() {
			return nil, application.ErrInvalid
		}
		out = append(out, application.Segment{Start: s.StartTime.AsTime(), End: s.EndTime.AsTime(), Classification: class, Reasons: s.Reasons})
	}
	return out, nil
}

func (h *Handler) CreateTask(ctx context.Context, req *connect.Request[v1.CreateTaskRequest]) (*connect.Response[v1.CreateTaskResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	t, err := h.service.CreateTask(ctx, a, req.Msg.OperationId, settingsIn(req.Msg.Settings))
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.CreateTaskResponse{Task: task(t)}), nil
}
func (h *Handler) UpdateTask(ctx context.Context, req *connect.Request[v1.UpdateTaskRequest]) (*connect.Response[v1.UpdateTaskResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	t, err := h.service.UpdateTask(ctx, a, req.Msg.OperationId, req.Msg.TaskId, req.Msg.ExpectedVersion, settingsIn(req.Msg.Settings))
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.UpdateTaskResponse{Task: task(t)}), nil
}
func (h *Handler) GetTask(ctx context.Context, req *connect.Request[v1.GetTaskRequest]) (*connect.Response[v1.GetTaskResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	t, err := h.service.GetTask(ctx, a, req.Msg.TaskId)
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.GetTaskResponse{Task: task(t)}), nil
}
func (h *Handler) ListTasks(ctx context.Context, req *connect.Request[v1.ListTasksRequest]) (*connect.Response[v1.ListTasksResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	after := ""
	if req.Msg.PageToken != "" {
		b, e := base64.RawURLEncoding.DecodeString(req.Msg.PageToken)
		if e != nil || len(b) != 36 {
			return nil, rpcError(application.ErrInvalid)
		}
		after = string(b)
	}
	page, err := h.service.ListTasks(ctx, a, after, int(req.Msg.PageSize))
	if err != nil {
		return nil, rpcError(err)
	}
	res := &v1.ListTasksResponse{Tasks: []*v1.Task{}}
	for _, t := range page.Tasks {
		res.Tasks = append(res.Tasks, task(t))
	}
	if page.Next != "" {
		res.NextPageToken = base64.RawURLEncoding.EncodeToString([]byte(page.Next))
	}
	return connect.NewResponse(res), nil
}

func (h *Handler) StartSession(ctx context.Context, req *connect.Request[v1.StartSessionRequest]) (*connect.Response[v1.StartSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	r, err := h.sessions.Start(ctx, a, workflow.StartInput{OperationID: req.Msg.OperationId, TaskID: req.Msg.TaskId, TaskVersion: req.Msg.TaskVersion})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.StartSessionResponse{Session: session(r.Session), Balance: balance(r.Balance)}), nil
}
func (h *Handler) UploadActivityBatch(ctx context.Context, req *connect.Request[v1.UploadActivityBatchRequest]) (*connect.Response[v1.UploadActivityBatchResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	segs, err := segments(req.Msg.Segments)
	if err != nil {
		return nil, rpcError(err)
	}
	r, err := h.sessions.Upload(ctx, a, application.BatchInput{SessionID: req.Msg.SessionId, BatchID: req.Msg.BatchId, Seq: req.Msg.Seq, EvaluatorVersion: req.Msg.EvaluatorVersion, RulesVersion: req.Msg.RulesVersion, Segments: segs})
	if err != nil {
		return nil, rpcError(err)
	}
	rc := r.Receipt
	return connect.NewResponse(&v1.UploadActivityBatchResponse{
		Receipt: &v1.ActivityReceipt{BatchId: rc.BatchID, Seq: rc.Seq, Status: batchOut[rc.Status], AcceptedThroughSeq: rc.AcceptedThroughSeq, MissingSeqs: rc.MissingSeqs, EarnedSeconds: r.Earned},
		Balance: balance(r.Balance),
	}), nil
}
func (h *Handler) PauseSession(ctx context.Context, req *connect.Request[v1.PauseSessionRequest]) (*connect.Response[v1.PauseSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	if !req.Msg.PausedAt.IsValid() {
		return nil, rpcError(application.ErrInvalid)
	}
	r, err := h.sessions.Pause(ctx, a, workflow.PauseInput{OperationID: req.Msg.OperationId, SessionID: req.Msg.SessionId, ExpectedVersion: req.Msg.ExpectedVersion, PausedAt: req.Msg.PausedAt.AsTime(), LastSeq: req.Msg.LastSeq})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.PauseSessionResponse{Session: session(r.Session), Balance: balance(r.Balance)}), nil
}
func (h *Handler) ResumeSession(ctx context.Context, req *connect.Request[v1.ResumeSessionRequest]) (*connect.Response[v1.ResumeSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	r, err := h.sessions.Resume(ctx, a, workflow.ResumeInput{OperationID: req.Msg.OperationId, SessionID: req.Msg.SessionId, ExpectedVersion: req.Msg.ExpectedVersion})
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.ResumeSessionResponse{Session: session(r.Session), Balance: balance(r.Balance)}), nil
}
func (h *Handler) endInput(msg interface {
	GetOperationId() string
	GetSessionId() string
	GetExpectedVersion() int64
	GetEndedAt() *timestamppb.Timestamp
	GetLastSeq() int64
	GetRemainingSegments() []*v1.ActivitySegment
}) (workflow.EndInput, error) {
	if !msg.GetEndedAt().IsValid() {
		return workflow.EndInput{}, application.ErrInvalid
	}
	segs, err := segments(msg.GetRemainingSegments())
	if err != nil {
		return workflow.EndInput{}, err
	}
	return workflow.EndInput{OperationID: msg.GetOperationId(), SessionID: msg.GetSessionId(), ExpectedVersion: msg.GetExpectedVersion(), EndedAt: msg.GetEndedAt().AsTime(), LastSeq: msg.GetLastSeq(), Remaining: segs}, nil
}
func (h *Handler) FinishSession(ctx context.Context, req *connect.Request[v1.FinishSessionRequest]) (*connect.Response[v1.FinishSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	in, err := h.endInput(req.Msg)
	if err != nil {
		return nil, rpcError(err)
	}
	r, err := h.sessions.Finish(ctx, a, in)
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.FinishSessionResponse{Session: session(r.Session), DiscardedSeconds: r.Discarded, Balance: balance(r.Balance)}), nil
}
func (h *Handler) AbortSession(ctx context.Context, req *connect.Request[v1.AbortSessionRequest]) (*connect.Response[v1.AbortSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	in, err := h.endInput(req.Msg)
	if err != nil {
		return nil, rpcError(err)
	}
	r, err := h.sessions.Abort(ctx, a, in)
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.AbortSessionResponse{Session: session(r.Session), DiscardedSeconds: r.Discarded, Balance: balance(r.Balance)}), nil
}
func (h *Handler) GetCurrentSession(ctx context.Context, req *connect.Request[v1.GetCurrentSessionRequest]) (*connect.Response[v1.GetCurrentSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	s, ok, err := h.service.CurrentSession(ctx, a)
	if err != nil {
		return nil, rpcError(err)
	}
	res := &v1.GetCurrentSessionResponse{}
	if ok {
		res.Session = session(s)
	}
	return connect.NewResponse(res), nil
}
func (h *Handler) GetSession(ctx context.Context, req *connect.Request[v1.GetSessionRequest]) (*connect.Response[v1.GetSessionResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	d, err := h.sessions.Detail(ctx, a, req.Msg.SessionId)
	if err != nil {
		return nil, rpcError(err)
	}
	return connect.NewResponse(&v1.GetSessionResponse{Session: session(d.Session), Reward: &rewardv1.RewardSummary{EarnedSeconds: d.Reward.EarnedSeconds, SpentSeconds: d.Reward.SpentSeconds, DiscardedSeconds: d.Reward.DiscardedSeconds}}), nil
}
func (h *Handler) GetSessionOperation(ctx context.Context, req *connect.Request[v1.GetSessionOperationRequest]) (*connect.Response[v1.GetSessionOperationResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, rpcError(err)
	}
	sessionID, found, err := h.service.Operation(ctx, a, kindIn[req.Msg.Kind], req.Msg.OperationId)
	if err != nil {
		return nil, rpcError(err)
	}
	res := &v1.GetSessionOperationResponse{Status: v1.OperationStatus_OPERATION_STATUS_NOT_FOUND}
	if found {
		res.Status, res.SessionId = v1.OperationStatus_OPERATION_STATUS_SUCCEEDED, sessionID
	}
	return connect.NewResponse(res), nil
}
