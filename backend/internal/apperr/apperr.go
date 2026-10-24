// Package apperr defines the error kinds shared by business modules that take part in workflows,
// and their conversion to Connect errors. Wrap a kind with errors.Join to add a client-safe detail.
package apperr

import (
	"context"
	"errors"
	"strings"

	"connectrpc.com/connect"
)

var (
	ErrUnauthenticated = errors.New("authentication required")
	ErrForbidden       = errors.New("access denied")
	ErrNotFound        = errors.New("resource not found")
	ErrInvalid         = errors.New("invalid request")
	ErrConflict        = errors.New("state or operation conflicts")
	ErrPrecondition    = errors.New("operation precondition not met")
	// ErrMissing is retryable with the same operation ID once the earlier batches are accepted.
	ErrMissing = errors.New("earlier activity batches have not been accepted yet")
)

// Connect converts an error to a Connect error. Unknown errors become a generic internal error
// so that DB and implementation details never reach the client.
func Connect(err error) error {
	detail := strings.ReplaceAll(err.Error(), "\n", ": ")
	switch {
	case errors.Is(err, ErrUnauthenticated):
		return connect.NewError(connect.CodeUnauthenticated, errors.New(detail))
	case errors.Is(err, ErrForbidden):
		return connect.NewError(connect.CodePermissionDenied, errors.New(detail))
	case errors.Is(err, ErrNotFound):
		return connect.NewError(connect.CodeNotFound, errors.New(detail))
	case errors.Is(err, ErrInvalid):
		return connect.NewError(connect.CodeInvalidArgument, errors.New(detail))
	case errors.Is(err, ErrConflict):
		return connect.NewError(connect.CodeAborted, errors.New(detail))
	case errors.Is(err, ErrMissing), errors.Is(err, ErrPrecondition):
		return connect.NewError(connect.CodeFailedPrecondition, errors.New(detail))
	case errors.Is(err, context.Canceled):
		return connect.NewError(connect.CodeCanceled, errors.New("request canceled"))
	case errors.Is(err, context.DeadlineExceeded):
		return connect.NewError(connect.CodeDeadlineExceeded, errors.New("request timed out"))
	}
	return connect.NewError(connect.CodeInternal, errors.New("operation failed"))
}
