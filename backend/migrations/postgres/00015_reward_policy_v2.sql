-- +goose Up
ALTER TABLE app.reward_wallets
    ADD COLUMN policy_version INTEGER NOT NULL DEFAULT 1 CHECK (policy_version > 0),
    ADD COLUMN grant_stopped BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN stop_reason TEXT NOT NULL DEFAULT '',
    ADD COLUMN collector_healthy BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE app.activity_batches
    ADD COLUMN collector_healthy BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE app.reward_session_outcomes (
    session_id UUID PRIMARY KEY REFERENCES app.work_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    policy_version INTEGER NOT NULL CHECK (policy_version > 0),
    status TEXT NOT NULL CHECK (status IN ('GRANTED', 'INELIGIBLE')),
    reason TEXT NOT NULL DEFAULT '',
    grant_stopped BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

REVOKE ALL ON app.reward_session_outcomes FROM PUBLIC;

-- +goose Down
DROP TABLE app.reward_session_outcomes;
ALTER TABLE app.reward_wallets
    DROP COLUMN collector_healthy,
    DROP COLUMN stop_reason,
    DROP COLUMN grant_stopped,
    DROP COLUMN policy_version;
ALTER TABLE app.activity_batches
    DROP COLUMN collector_healthy;
