-- +goose Up
-- One durable, deduplicated event per newly started session that belongs to a group.
CREATE TABLE app.group_work_start_events (
    session_id UUID PRIMARY KEY REFERENCES app.work_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app.users(id),
    started_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX group_work_start_events_started
    ON app.group_work_start_events(started_at, session_id);

REVOKE ALL ON app.group_work_start_events FROM PUBLIC;

-- +goose Down
DROP TABLE app.group_work_start_events;
