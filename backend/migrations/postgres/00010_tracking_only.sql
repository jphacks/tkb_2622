-- +goose Up
-- StatementBegin/End keeps goose from splitting the DO block at its inner semicolons.
-- +goose StatementBegin
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'app' AND table_name = 'work_sessions' AND column_name = 'tracking_only'
    ) THEN
        ALTER TABLE app.work_sessions
            ADD COLUMN tracking_only BOOLEAN NOT NULL DEFAULT FALSE;
        COMMENT ON COLUMN app.work_sessions.tracking_only IS 'created by migration 10_tracking_only';
    END IF;
END;
$$;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$
BEGIN
    IF (
        SELECT pg_catalog.col_description('app.work_sessions'::regclass, attnum)
        FROM pg_catalog.pg_attribute
        WHERE attrelid = 'app.work_sessions'::regclass AND attname = 'tracking_only'
    ) = 'created by migration 10_tracking_only' THEN
        ALTER TABLE app.work_sessions DROP COLUMN tracking_only;
    END IF;
END;
$$;
-- +goose StatementEnd
