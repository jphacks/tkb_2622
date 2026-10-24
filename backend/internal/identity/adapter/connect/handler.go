package identityconnect

import (
	"context"
	"encoding/base64"
	"errors"
	"time"

	"connectrpc.com/connect"
	v1 "github.com/jphacks/tkb_2622/backend/gen/identity/v1"
	"github.com/jphacks/tkb_2622/backend/internal/identity/application"
	"github.com/jphacks/tkb_2622/backend/internal/identity/domain"
)

type Verifier interface {
	Verify(context.Context, string) (application.Principal, error)
}
type principalKey struct{}

func AuthInterceptor(verifier Verifier) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			if len(req.Header().Values("Authorization")) != 1 {
				return nil, rpcError(application.ErrUnauthenticated)
			}
			p, err := verifier.Verify(ctx, req.Header().Get("Authorization"))
			if err != nil {
				return nil, rpcError(application.ErrUnauthenticated)
			}
			return next(context.WithValue(ctx, principalKey{}, p), req)
		}
	}
}
func principal(ctx context.Context) application.Principal {
	p, _ := ctx.Value(principalKey{}).(application.Principal)
	return p
}

type Handler struct{ service *application.Service }

func New(service *application.Service) *Handler { return &Handler{service: service} }
func rpcError(err error) error {
	code := connect.CodeInternal
	message := "operation failed"
	switch {
	case errors.Is(err, application.ErrUnauthenticated):
		code = connect.CodeUnauthenticated
		message = err.Error()
	case errors.Is(err, application.ErrForbidden):
		code = connect.CodePermissionDenied
		message = err.Error()
	case errors.Is(err, application.ErrNotFound):
		code = connect.CodeNotFound
		message = err.Error()
	case errors.Is(err, application.ErrInvalid):
		code = connect.CodeInvalidArgument
		message = err.Error()
	case errors.Is(err, application.ErrConflict):
		code = connect.CodeAborted
		message = err.Error()
	case errors.Is(err, application.ErrPrecondition):
		code = connect.CodeFailedPrecondition
		message = err.Error()
	case errors.Is(err, context.Canceled):
		code = connect.CodeCanceled
		message = "request canceled"
	case errors.Is(err, context.DeadlineExceeded):
		code = connect.CodeDeadlineExceeded
		message = "request timed out"
	}
	return connect.NewError(code, errors.New(message))
}
func user(u domain.User) *v1.User {
	return &v1.User{Id: u.ID, Status: u.Status, CreatedAt: u.CreatedAt.UTC().Format(time.RFC3339Nano)}
}
func device(d domain.Device) *v1.Device {
	return &v1.Device{Id: d.ID, Platform: v1.Platform(v1.Platform_value["PLATFORM_"+d.Platform]), Name: d.Name, Status: d.Status, Version: d.Version, CreatedAt: d.CreatedAt.UTC().Format(time.RFC3339Nano)}
}
func (h *Handler) EnsureUser(ctx context.Context, req *connect.Request[v1.EnsureUserRequest]) (*connect.Response[v1.EnsureUserResponse], error) {
	u, e := h.service.EnsureUser(ctx, principal(ctx), req.Msg.OperationId)
	if e != nil {
		return nil, rpcError(e)
	}
	return connect.NewResponse(&v1.EnsureUserResponse{User: user(u)}), nil
}
func (h *Handler) GetMe(ctx context.Context, req *connect.Request[v1.GetMeRequest]) (*connect.Response[v1.GetMeResponse], error) {
	u, e := h.service.GetMe(ctx, principal(ctx))
	if e != nil {
		return nil, rpcError(e)
	}
	return connect.NewResponse(&v1.GetMeResponse{User: user(u)}), nil
}
func (h *Handler) RegisterDevice(ctx context.Context, req *connect.Request[v1.RegisterDeviceRequest]) (*connect.Response[v1.RegisterDeviceResponse], error) {
	platforms := map[v1.Platform]string{v1.Platform_PLATFORM_MACOS: "MACOS", v1.Platform_PLATFORM_WINDOWS: "WINDOWS", v1.Platform_PLATFORM_IOS: "IOS"}
	d, e := h.service.RegisterDevice(ctx, principal(ctx), application.RegisterInput{OperationID: req.Msg.OperationId, RegistrationID: req.Msg.RegistrationId, Name: req.Msg.Name, Platform: platforms[req.Msg.Platform]})
	if e != nil {
		return nil, rpcError(e)
	}
	return connect.NewResponse(&v1.RegisterDeviceResponse{Device: device(d)}), nil
}
func (h *Handler) ListDevices(ctx context.Context, req *connect.Request[v1.ListDevicesRequest]) (*connect.Response[v1.ListDevicesResponse], error) {
	after := ""
	if req.Msg.PageToken != "" {
		b, e := base64.RawURLEncoding.DecodeString(req.Msg.PageToken)
		if e != nil || len(b) != 36 {
			return nil, rpcError(application.ErrInvalid)
		}
		after = string(b)
	}
	page, e := h.service.ListDevices(ctx, principal(ctx), after, int(req.Msg.PageSize))
	if e != nil {
		return nil, rpcError(e)
	}
	res := &v1.ListDevicesResponse{}
	for _, d := range page.Devices {
		res.Devices = append(res.Devices, device(d))
	}
	if page.Next != "" {
		res.NextPageToken = base64.RawURLEncoding.EncodeToString([]byte(page.Next))
	}
	return connect.NewResponse(res), nil
}
func (h *Handler) RevokeDevice(ctx context.Context, req *connect.Request[v1.RevokeDeviceRequest]) (*connect.Response[v1.RevokeDeviceResponse], error) {
	d, e := h.service.RevokeDevice(ctx, principal(ctx), application.RevokeInput{OperationID: req.Msg.OperationId, DeviceID: req.Msg.DeviceId, ExpectedVersion: req.Msg.ExpectedVersion})
	if e != nil {
		return nil, rpcError(e)
	}
	return connect.NewResponse(&v1.RevokeDeviceResponse{Device: device(d)}), nil
}
