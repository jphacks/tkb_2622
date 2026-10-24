-- +goose Up
ALTER TABLE app.work_sessions
    ADD COLUMN tracking_only BOOLEAN NOT NULL DEFAULT FALSE;

-- +goose Down
ALTER TABLE app.work_sessions
    DROP COLUMN tracking_only;
