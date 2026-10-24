package groupconnect

import (
	"context"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/group/v1"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/group/application"
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
			})
		}
		response.Groups = append(response.Groups, out)
	}
	return connect.NewResponse(response), nil
}
