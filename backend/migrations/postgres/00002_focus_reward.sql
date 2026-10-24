-- +goose Up
-- focus: tasks, work sessions, activity batches and session operation records.
CREATE TABLE app.tasks (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app.users(id),
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
    category TEXT NOT NULL CHECK (category IN ('PROGRAMMING', 'DOCUMENT_WRITING', 'READING', 'DESIGN', 'STUDY', 'OTHER')),
    mode TEXT NOT NULL CHECK (mode IN ('NORMAL', 'READING', 'VIDEO')),
    planned_seconds BIGINT NOT NULL CHECK (planned_seconds BETWEEN 60 AND 86400),
    minimum_seconds BIGINT NOT NULL CHECK (minimum_seconds BETWEEN 0 AND planned_seconds),
    version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX tasks_user ON app.tasks(user_id, id);
CREATE TABLE app.work_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app.users(id),
    device_id UUID NOT NULL REFERENCES app.devices(id),
    task_id UUID NOT NULL REFERENCES app.tasks(id),
    -- TaskSnapshot fixed at start.
    task_name TEXT NOT NULL,
    category TEXT NOT NULL,
    mode TEXT NOT NULL,
    planned_seconds BIGINT NOT NULL,
    minimum_seconds BIGINT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('RUNNING', 'PAUSED', 'FINALIZED', 'ABORTED')),
    version BIGINT NOT NULL DEFAULT 1,
    started_at TIMESTAMPTZ NOT NULL,
    -- Server-observed running time, the upper bound for reported activity.
    running_since TIMESTAMPTZ,
    server_active_millis BIGINT NOT NULL DEFAULT 0,
    paused_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    accepted_seq BIGINT NOT NULL DEFAULT 0,
    last_segment_end TIMESTAMPTZ,
    task_millis BIGINT NOT NULL DEFAULT 0,
    related_millis BIGINT NOT NULL DEFAULT 0,
    distraction_millis BIGINT NOT NULL DEFAULT 0,
    unknown_millis BIGINT NOT NULL DEFAULT 0,
    idle_millis BIGINT NOT NULL DEFAULT 0,
    -- Unsent segments delivered with finish/abort; history only, never rewarded.
    final_segments JSONB NOT NULL DEFAULT '[]'
);
CREATE UNIQUE INDEX one_open_session ON app.work_sessions(user_id) WHERE status IN ('RUNNING', 'PAUSED');
CREATE TABLE app.activity_batches (
    session_id UUID NOT NULL REFERENCES app.work_sessions(id),
    seq BIGINT NOT NULL CHECK (seq >= 1),
    batch_id UUID NOT NULL,
    request_hash TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('ACCEPTED', 'PENDING', 'HISTORY')),
    evaluator_version TEXT NOT NULL,
    rules_version TEXT NOT NULL,
    segments JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, seq),
    UNIQUE (session_id, batch_id)
);
CREATE TABLE app.focus_operations (
    user_id UUID NOT NULL REFERENCES app.users(id),
    kind TEXT NOT NULL,
    operation_id UUID NOT NULL,
    request_hash TEXT NOT NULL,
    resource_id UUID NOT NULL,
    response JSONB NOT NULL,
    PRIMARY KEY (user_id, kind, operation_id)
);
-- reward: wallet, transactions and interim grants.
CREATE TABLE app.reward_wallets (
    user_id UUID PRIMARY KEY REFERENCES app.users(id),
    session_id UUID REFERENCES app.work_sessions(id),
    balance_seconds BIGINT NOT NULL DEFAULT 0 CHECK (balance_seconds >= 0),
    evaluated_seq BIGINT NOT NULL DEFAULT 0,
    version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE app.reward_transactions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app.users(id),
    session_id UUID NOT NULL REFERENCES app.work_sessions(id),
    type TEXT NOT NULL CHECK (type IN ('EARN', 'SPEND', 'REFUND', 'DISCARD', 'ADJUST')),
    amount_seconds BIGINT NOT NULL,
    source_id TEXT NOT NULL,
    balance_after BIGINT NOT NULL CHECK (balance_after >= 0),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX reward_transactions_session ON app.reward_transactions(session_id);
CREATE TABLE app.reward_grants (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES app.work_sessions(id),
    user_id UUID NOT NULL REFERENCES app.users(id),
    policy_version INTEGER NOT NULL,
    -- Activity batch seqs (inclusive) whose evaluation produced this grant.
    source_from_seq BIGINT NOT NULL,
    source_to_seq BIGINT NOT NULL CHECK (source_to_seq >= source_from_seq),
    earned_seconds BIGINT NOT NULL CHECK (earned_seconds > 0),
    transaction_id UUID NOT NULL REFERENCES app.reward_transactions(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session_id, source_from_seq)
);
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM PUBLIC;
-- +goose Down
DROP TABLE app.reward_grants;
DROP TABLE app.reward_transactions;
DROP TABLE app.reward_wallets;
DROP TABLE app.focus_operations;
DROP TABLE app.activity_batches;
DROP TABLE app.work_sessions;
DROP TABLE app.tasks;
