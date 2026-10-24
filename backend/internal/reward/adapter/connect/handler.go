// Package rewardconnect converts RewardService RPCs to wallet reads.
package rewardconnect

import (
	"context"
	"errors"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/reward/v1"
	"github.com/jphacks/tkb_2622/backend/internal/apperr"
	"github.com/jphacks/tkb_2622/backend/internal/reward/application"
	"google.golang.org/protobuf/types/known/timestamppb"
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

func (h *Handler) ListTransactions(ctx context.Context, req *connect.Request[v1.ListTransactionsRequest]) (*connect.Response[v1.ListTransactionsResponse], error) {
	userID, err := h.resolve(ctx)
	if err != nil {
		return nil, err
	}
	page, err := h.wallets.ListTransactions(ctx, userID, req.Msg.PageToken, int(req.Msg.PageSize))
	if err != nil {
		return nil, apperr.Connect(err)
	}
	res := &v1.ListTransactionsResponse{Transactions: make([]*v1.RewardTransaction, 0, len(page.Transactions)), NextPageToken: page.Next}
	for _, tx := range page.Transactions {
		res.Transactions = append(res.Transactions, &v1.RewardTransaction{
			Id: tx.ID, SessionId: tx.SessionID, Type: tx.Type, AmountSeconds: tx.AmountSeconds,
			BalanceAfter: tx.BalanceAfter, OccurredAt: timestamppb.New(tx.OccurredAt),
		})
	}
	return connect.NewResponse(res), nil
}
