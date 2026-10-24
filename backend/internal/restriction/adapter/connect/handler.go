// Package restrictionconnect converts RestrictionService RPCs to restriction and workflow operations.
package restrictionconnect

import (
	"context"
	"strings"
	"time"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/restriction/v1"
	rewardv1 "github.com/jphacks/tkb_2622/backend/gen/reward/v1"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	focus "github.com/jphacks/tkb_2622/backend/internal/focus/application"
	"github.com/jphacks/tkb_2622/backend/internal/restriction/application"
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

var (
	grantStatusOut = map[string]v1.GrantStatus{"RESERVED": v1.GrantStatus_GRANT_STATUS_RESERVED, "ACTIVATED": v1.GrantStatus_GRANT_STATUS_ACTIVATED, "EXHAUSTED": v1.GrantStatus_GRANT_STATUS_EXHAUSTED, "REVOKED": v1.GrantStatus_GRANT_STATUS_REVOKED, "ACTIVATION_FAILED": v1.GrantStatus_GRANT_STATUS_ACTIVATION_FAILED}
	kindIn         = map[v1.OperationKind]string{v1.OperationKind_OPERATION_KIND_UPDATE_POLICY: "update_policy", v1.OperationKind_OPERATION_KIND_RESERVE: "reserve", v1.OperationKind_OPERATION_KIND_REPORT_STATE: "report_state", v1.OperationKind_OPERATION_KIND_REPORT_USAGE: "report_usage"}
)

func ts(t *time.Time) *timestamppb.Timestamp {
	if t == nil {
		return nil
	}
	return timestamppb.New(*t)
}
func enumName(name, prefix string) string { return strings.TrimPrefix(name, prefix) }

// GrantMessage converts a usage grant for any handler that returns one.
func GrantMessage(g application.Grant) *v1.UsageGrant {
	return &v1.UsageGrant{
		Id: g.ID, SessionId: g.SessionID, DeviceId: g.DeviceID, RequestedSeconds: g.RequestedSeconds, ReservedSeconds: g.ReservedSeconds,
		Status: grantStatusOut[g.Status], ControlRevision: g.ControlRevision, IssuedAt: timestamppb.New(g.IssuedAt), ActivatedAt: ts(g.ActivatedAt),
		ReportedSeconds: g.ReportedSeconds, ConsumedSeconds: g.ConsumedSeconds, DiscardedSeconds: g.DiscardedSeconds,
		EndReason: v1.GrantEndReason(v1.GrantEndReason_value["GRANT_END_REASON_"+g.EndReason]), EndedByOperationId: g.EndedByOperation, CompletedAt: ts(g.CompletedAt),
	}
}

// StateMessage converts the control state for any handler that returns one (focus session responses included).
func StateMessage(v application.View) *v1.RestrictionState {
	s := v.State
	out := &v1.RestrictionState{
		SessionId: s.SessionID, DeviceId: s.DeviceID, ControlRevision: s.ControlRevision,
		DesiredMode:  v1.DesiredMode(v1.DesiredMode_value["DESIRED_MODE_"+s.DesiredMode]),
		ShieldStatus: v1.ShieldStatus(v1.ShieldStatus_value["SHIELD_STATUS_"+s.ShieldStatus]), PermissionStatus: v1.PermissionStatus(v1.PermissionStatus_value["PERMISSION_STATUS_"+s.PermissionStatus]),
		AppliedRevision: s.AppliedRevision, LastAppliedAt: ts(s.LastAppliedAt), LastReportedAt: ts(s.LastReportedAt), FailureReason: s.FailureReason,
	}
	if v.ActiveGrant != nil {
		out.ActiveGrant = GrantMessage(*v.ActiveGrant)
	}
	return out
}

func policy(p application.PolicyView) *v1.RestrictionPolicy {
	return &v1.RestrictionPolicy{
		DeviceId: p.Policy.DeviceID, Status: v1.PolicyStatus(v1.PolicyStatus_value["POLICY_STATUS_"+p.Status]),
		TargetMode:    v1.TargetMode(v1.TargetMode_value["TARGET_MODE_"+p.Policy.TargetMode]),
		UsageTimeMode: p.Policy.UsageTimeMode, AllowedAppsPolicy: p.Policy.AllowedAppsPolicy, DeviceConfigVersion: p.Policy.DeviceConfigVersion,
		Configured: p.Policy.Configured, Version: p.Policy.Version, UpdatedAt: timestamppb.New(p.Policy.UpdatedAt),
	}
}

func (h *Handler) UpdateRestrictionPolicy(ctx context.Context, req *connect.Request[v1.UpdateRestrictionPolicyRequest]) (*connect.Response[v1.UpdateRestrictionPolicyResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	m := req.Msg
	p, err := h.service.UpdatePolicy(ctx, a, application.PolicyInput{OperationID: m.OperationId, DeviceID: m.DeviceId, ExpectedVersion: m.ExpectedVersion, Enabled: m.Enabled, Configured: m.Configured, TargetMode: enumName(m.TargetMode.String(), "TARGET_MODE_"), DeviceConfigVersion: m.DeviceConfigVersion})
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.UpdateRestrictionPolicyResponse{Policy: policy(p)}), nil
}

func (h *Handler) GetRestrictionPolicy(ctx context.Context, req *connect.Request[v1.GetRestrictionPolicyRequest]) (*connect.Response[v1.GetRestrictionPolicyResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	p, err := h.service.GetPolicy(ctx, a, req.Msg.DeviceId)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.GetRestrictionPolicyResponse{Policy: policy(p)}), nil
}

func (h *Handler) ReserveUsageGrant(ctx context.Context, req *connect.Request[v1.ReserveUsageGrantRequest]) (*connect.Response[v1.ReserveUsageGrantResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	m := req.Msg
	r, err := h.sessions.Reserve(ctx, focus.Actor{UserID: a.UserID, DeviceID: a.DeviceID, DevicePlatform: a.DevicePlatform}, workflow.ReserveInput{OperationID: m.OperationId, SessionID: m.SessionId, DeviceID: m.DeviceId, ExpectedSessionVersion: m.ExpectedSessionVersion, RequestedSeconds: m.RequestedSeconds})
	if err != nil {
		return nil, apperr.Connect(err)
	}
	w := r.Balance
	return connect.NewResponse(&v1.ReserveUsageGrantResponse{
		Grant:   GrantMessage(r.Grant),
		Balance: &rewardv1.RewardBalance{SessionId: w.SessionID, BalanceSeconds: w.BalanceSeconds, Version: w.Version, EvaluatedThroughSeq: w.EvaluatedSeq},
		State:   StateMessage(r.Restriction),
	}), nil
}

func (h *Handler) GetUsageGrant(ctx context.Context, req *connect.Request[v1.GetUsageGrantRequest]) (*connect.Response[v1.GetUsageGrantResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	g, err := h.service.GetGrant(ctx, a, req.Msg.GrantId)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.GetUsageGrantResponse{Grant: GrantMessage(g)}), nil
}

func (h *Handler) GetRestrictionState(ctx context.Context, req *connect.Request[v1.GetRestrictionStateRequest]) (*connect.Response[v1.GetRestrictionStateResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	v, err := h.service.GetState(ctx, a)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.GetRestrictionStateResponse{State: StateMessage(v)}), nil
}

func (h *Handler) ReportRestrictionState(ctx context.Context, req *connect.Request[v1.ReportRestrictionStateRequest]) (*connect.Response[v1.ReportRestrictionStateResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	m := req.Msg
	if !m.AppliedAt.IsValid() {
		return nil, apperr.Connect(apperr.ErrInvalid)
	}
	r, err := h.service.ReportState(ctx, a, application.StateReport{
		OperationID: m.OperationId, DeviceID: m.DeviceId, GrantID: m.GrantId, ControlRevision: m.ControlRevision,
		ShieldStatus: enumName(m.ShieldStatus.String(), "SHIELD_STATUS_"), Permission: enumName(m.PermissionStatus.String(), "PERMISSION_STATUS_"),
		AppliedAt: m.AppliedAt.AsTime(), FailureReason: m.FailureReason,
	})
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.ReportRestrictionStateResponse{Applied: r.Applied, State: StateMessage(r.View)}), nil
}

func (h *Handler) ReportUsage(ctx context.Context, req *connect.Request[v1.ReportUsageRequest]) (*connect.Response[v1.ReportUsageResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	m := req.Msg
	if !m.ObservedAt.IsValid() {
		return nil, apperr.Connect(apperr.ErrInvalid)
	}
	r, err := h.service.ReportUsage(ctx, a, application.UsageReport{OperationID: m.OperationId, GrantID: m.GrantId, ReportSeq: m.ReportSeq, CumulativeSeconds: m.CumulativeSeconds, ObservedAt: m.ObservedAt.AsTime(), Final: m.Final})
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.ReportUsageResponse{Grant: GrantMessage(r.Grant), State: StateMessage(r.View)}), nil
}

func (h *Handler) GetRestrictionOperation(ctx context.Context, req *connect.Request[v1.GetRestrictionOperationRequest]) (*connect.Response[v1.GetRestrictionOperationResponse], error) {
	a, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	resourceID, found, err := h.service.Operation(ctx, a, kindIn[req.Msg.Kind], req.Msg.OperationId)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	res := &v1.GetRestrictionOperationResponse{Status: v1.OperationStatus_OPERATION_STATUS_NOT_FOUND}
	if found {
		res.Status, res.ResourceId = v1.OperationStatus_OPERATION_STATUS_SUCCEEDED, resourceID
	}
	return connect.NewResponse(res), nil
}
