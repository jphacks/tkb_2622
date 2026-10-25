package notification

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"time"

	"github.com/google/uuid"
)

type Dispatcher struct {
	db     *sql.DB
	sender Sender
}

func NewDispatcher(db *sql.DB, sender Sender) *Dispatcher { return &Dispatcher{db: db, sender: sender} }

func (d *Dispatcher) DispatchSession(ctx context.Context, sessionID string) error {
	return d.dispatch(ctx, sessionID, 50)
}

func (d *Dispatcher) DispatchPending(ctx context.Context) error {
	return d.dispatch(ctx, "", 100)
}

func (d *Dispatcher) Run(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = 30 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			_ = d.DispatchPending(ctx)
		case <-ctx.Done():
			return
		}
	}
}

type pendingDelivery struct {
	id, sessionID, userID, deviceID, token, environment string
}

func (d *Dispatcher) dispatch(ctx context.Context, sessionID string, limit int) error {
	if d.sender == nil {
		return nil
	}
	tx, err := d.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `UPDATE app.notification_outbox SET status = 'PENDING', updated_at = now() WHERE status = 'SENDING' AND updated_at < now() - interval '5 minutes'`); err != nil {
		return err
	}
	query := `
		SELECT outbox.id, outbox.session_id, outbox.recipient_user_id, outbox.recipient_device_id,
		       endpoint.apns_token, endpoint.apns_environment
		FROM app.notification_outbox AS outbox
		JOIN app.notification_endpoints AS endpoint ON endpoint.device_id = outbox.recipient_device_id
		JOIN app.devices AS device ON device.id = outbox.recipient_device_id AND device.status = 'ACTIVE'
		JOIN app.users AS recipient ON recipient.id = outbox.recipient_user_id AND recipient.status = 'ACTIVE'
		WHERE outbox.status = 'PENDING'`
	args := []any{}
	if sessionID != "" {
		query += ` AND outbox.session_id = $1`
		args = append(args, uuid.MustParse(sessionID))
	}
	query += ` ORDER BY outbox.created_at, outbox.id LIMIT $` + strconv.Itoa(len(args)+1) + ` FOR UPDATE OF outbox SKIP LOCKED`
	args = append(args, limit)
	rows, err := tx.QueryContext(ctx, query, args...)
	if err != nil {
		return err
	}
	var deliveries []pendingDelivery
	for rows.Next() {
		var item pendingDelivery
		var id, session, user, device uuid.UUID
		if err := rows.Scan(&id, &session, &user, &device, &item.token, &item.environment); err != nil {
			_ = rows.Close()
			return err
		}
		item.id, item.sessionID, item.userID, item.deviceID = id.String(), session.String(), user.String(), device.String()
		deliveries = append(deliveries, item)
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return err
	}
	if err := rows.Close(); err != nil {
		return err
	}
	for _, item := range deliveries {
		if _, err := tx.ExecContext(ctx, `UPDATE app.notification_outbox SET status = 'SENDING', attempts = attempts + 1, updated_at = now() WHERE id = $1`, uuid.MustParse(item.id)); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	var failures int
	for _, item := range deliveries {
		active, err := d.isCurrentGroupMember(ctx, item)
		if err != nil {
			failures++
			_ = d.retry(ctx, item.id)
			continue
		}
		if !active {
			_, _ = d.db.ExecContext(ctx, `UPDATE app.notification_outbox SET status = 'SUPPRESSED', updated_at = now() WHERE id = $1 AND status = 'SENDING'`, uuid.MustParse(item.id))
			continue
		}
		if err := d.sender.Send(ctx, item.environment, item.token, item.id); err != nil {
			if errors.Is(err, ErrEndpointInvalid) {
				_, _ = d.db.ExecContext(ctx, `DELETE FROM app.notification_endpoints WHERE device_id = $1`, uuid.MustParse(item.deviceID))
				_, _ = d.db.ExecContext(ctx, `UPDATE app.notification_outbox SET status = 'SUPPRESSED', last_error = 'endpoint_invalid', updated_at = now() WHERE id = $1 AND status = 'SENDING'`, uuid.MustParse(item.id))
			} else {
				failures++
				_ = d.retry(ctx, item.id)
			}
			continue
		}
		if _, err := d.db.ExecContext(ctx, `UPDATE app.notification_outbox SET status = 'SENT', last_error = '', updated_at = now() WHERE id = $1 AND status = 'SENDING'`, uuid.MustParse(item.id)); err != nil {
			failures++
		}
	}
	if failures > 0 {
		return errors.New("one or more notifications could not be delivered")
	}
	return nil
}

func (d *Dispatcher) isCurrentGroupMember(ctx context.Context, item pendingDelivery) (bool, error) {
	var active bool
	err := d.db.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM app.group_work_start_events AS event
			JOIN app.group_memberships AS sender
			  ON sender.user_id = event.user_id AND sender.status = 'ACTIVE' AND sender.joined_at <= event.started_at
			JOIN app.group_memberships AS recipient
			  ON recipient.group_id = sender.group_id AND recipient.user_id = $2 AND recipient.status = 'ACTIVE' AND recipient.joined_at <= event.started_at
			JOIN app.devices AS device ON device.id = $3 AND device.user_id = recipient.user_id AND device.status = 'ACTIVE'
			JOIN app.notification_endpoints AS endpoint ON endpoint.device_id = device.id
			WHERE event.session_id = $1 AND event.user_id <> $2
		)`, uuid.MustParse(item.sessionID), uuid.MustParse(item.userID), uuid.MustParse(item.deviceID)).Scan(&active)
	return active, err
}

func (d *Dispatcher) retry(ctx context.Context, id string) error {
	_, err := d.db.ExecContext(ctx, `UPDATE app.notification_outbox SET status = 'PENDING', last_error = 'delivery_failed', updated_at = now() WHERE id = $1 AND status = 'SENDING'`, uuid.MustParse(id))
	return err
}
