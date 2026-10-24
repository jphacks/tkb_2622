-- +goose Up
CREATE TABLE app.notification_outbox (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES app.group_work_start_events(session_id) ON DELETE CASCADE,
    recipient_user_id UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    recipient_device_id UUID NOT NULL REFERENCES app.devices(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type = 'GROUP_WORK_STARTED'),
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENDING', 'SENT', 'SUPPRESSED')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session_id, recipient_device_id, type)
);

CREATE INDEX notification_outbox_pending ON app.notification_outbox(created_at, id) WHERE status = 'PENDING';
REVOKE ALL ON app.notification_outbox FROM PUBLIC;

-- +goose Down
DROP TABLE app.notification_outbox;
