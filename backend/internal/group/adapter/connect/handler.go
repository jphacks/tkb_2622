package groupconnect

import (
	"context"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/group/v1"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/group/application"
	"github.com/jphacks/tkb_2622/backend/internal/group/domain"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type ResolveUser func(context.Context) (string, error)

type Handler struct {
	resolve ResolveUser
	service *application.Service
}

func New(resolve ResolveUser, service *application.Service) *Handler {
	return &Handler{resolve: resolve, service: service}
}

func (h *Handler) ListGroups(ctx context.Context, _ *connect.Request[v1.ListGroupsRequest]) (*connect.Response[v1.ListGroupsResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	groups, err := h.service.ListGroups(ctx, userID)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	response := &v1.ListGroupsResponse{Groups: make([]*v1.Group, 0, len(groups))}
	for _, group := range groups {
		response.Groups = append(response.Groups, groupMessage(group))
	}
	return connect.NewResponse(response), nil
}

func (h *Handler) CreateGroup(ctx context.Context, req *connect.Request[v1.CreateGroupRequest]) (*connect.Response[v1.CreateGroupResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	group, err := h.service.CreateGroup(ctx, userID, req.Msg.OperationId, req.Msg.Name)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.CreateGroupResponse{Group: groupMessage(group)}), nil
}

func (h *Handler) CreateInvitation(ctx context.Context, req *connect.Request[v1.CreateInvitationRequest]) (*connect.Response[v1.CreateInvitationResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	invitation, err := h.service.CreateInvitation(ctx, userID, req.Msg.OperationId, req.Msg.GroupId)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.CreateInvitationResponse{
		InvitationId: invitation.ID,
		Token:        invitation.Token,
		ExpiresAt:    timestamppb.New(invitation.ExpiresAt),
	}), nil
}

func (h *Handler) AcceptInvitation(ctx context.Context, req *connect.Request[v1.AcceptInvitationRequest]) (*connect.Response[v1.AcceptInvitationResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	group, err := h.service.AcceptInvitation(ctx, userID, req.Msg.OperationId, req.Msg.Token)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.AcceptInvitationResponse{Group: groupMessage(group)}), nil
}

func (h *Handler) LeaveGroup(ctx context.Context, req *connect.Request[v1.LeaveGroupRequest]) (*connect.Response[v1.LeaveGroupResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	result, err := h.service.LeaveGroup(ctx, userID, req.Msg.OperationId, req.Msg.GroupId)
	if err != nil {
		return nil, apperr.Connect(err)
	}
	return connect.NewResponse(&v1.LeaveGroupResponse{GroupDeleted: result.GroupDeleted}), nil
}

func groupMessage(group domain.Group) *v1.Group {
	out := &v1.Group{
		Id:        group.ID,
		Name:      group.Name,
		CreatedAt: timestamppb.New(group.CreatedAt),
		Members:   make([]*v1.GroupMember, 0, len(group.Members)),
	}
	for _, member := range group.Members {
		out.Members = append(out.Members, &v1.GroupMember{
			IsCurrentUser: member.IsCurrentUser,
			JoinedAt:      timestamppb.New(member.JoinedAt),
			DisplayName:   member.DisplayName,
		})
	}
	return out
}
