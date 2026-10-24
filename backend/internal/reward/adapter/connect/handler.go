// Package rewardconnect converts RewardService RPCs to wallet reads.
package rewardconnect

import (
	"context"
	"errors"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/reward/v1"
	"github.com/jphacks/tkb_2622/backend/internal/reward/application"
)

// ResolveUser returns the business user ID of the caller, or a connect error.
type ResolveUser func(context.Context) (string, error)

type Handler struct {
	resolve ResolveUser
	wallets *application.Wallets
}

func New(resolve ResolveUser, wallets *application.Wallets) *Handler {
	return &Handler{resolve: resolve, wallets: wallets}
}

func (h *Handler) GetBalance(ctx context.Context, req *connect.Request[v1.GetBalanceRequest]) (*connect.Response[v1.GetBalanceResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, err
	}
	w, err := h.wallets.Balance(ctx, userID)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return nil, connect.NewError(connect.CodeCanceled, errors.New("request canceled"))
		}
		return nil, connect.NewError(connect.CodeInternal, errors.New("operation failed"))
	}
	return connect.NewResponse(&v1.GetBalanceResponse{Balance: &v1.RewardBalance{SessionId: w.SessionID, BalanceSeconds: w.BalanceSeconds, Version: w.Version, EvaluatedThroughSeq: w.EvaluatedSeq}}), nil
}
