-- +goose Up
-- restriction: iPhone policy metadata, usage grants, desired/reported control state and operation records.
CREATE TABLE app.restriction_policies (
    device_id UUID PRIMARY KEY REFERENCES app.devices(id),
    user_id UUID NOT NULL REFERENCES app.users(id),
    enabled BOOLEAN NOT NULL,
    target_mode TEXT NOT NULL CHECK (target_mode IN ('SELECTED_APPS', 'DEVICE_WIDE')),
    usage_time_mode TEXT NOT NULL DEFAULT 'ACTIVE_USAGE' CHECK (usage_time_mode = 'ACTIVE_USAGE'),
    allowed_apps_policy TEXT NOT NULL DEFAULT 'STANDARD_APPS_EXCEPT_SAFARI' CHECK (allowed_apps_policy = 'STANDARD_APPS_EXCEPT_SAFARI'),
    device_config_version BIGINT NOT NULL CHECK (device_config_version >= 0),
    configured BOOLEAN NOT NULL,
    version BIGINT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX restriction_policies_user ON app.restriction_policies(user_id);
CREATE TABLE app.usage_grants (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app.users(id),
    device_id UUID NOT NULL REFERENCES app.devices(id),
    session_id UUID NOT NULL REFERENCES app.work_sessions(id),
    requested_seconds BIGINT NOT NULL CHECK (requested_seconds > 0),
    reserved_seconds BIGINT NOT NULL CHECK (reserved_seconds > 0),
    status TEXT NOT NULL CHECK (status IN ('RESERVED', 'ACTIVATED', 'EXHAUSTED', 'REVOKED', 'ACTIVATION_FAILED')),
    control_revision BIGINT NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL,
    activated_at TIMESTAMPTZ,
    report_seq BIGINT NOT NULL DEFAULT 0,
    reported_seconds BIGINT NOT NULL DEFAULT 0 CHECK (reported_seconds BETWEEN 0 AND reserved_seconds),
    last_observed_at TIMESTAMPTZ,
    consumed_seconds BIGINT CHECK (consumed_seconds BETWEEN 0 AND reserved_seconds),
    discarded_seconds BIGINT CHECK (discarded_seconds >= 0),
    end_reason TEXT CHECK (end_reason IN ('USAGE_EXHAUSTED', 'WORK_STARTED', 'WORK_RESUMED', 'SESSION_FINISHED', 'SESSION_ABORTED', 'ACTIVATION_FAILED')),
    ended_by_operation_id TEXT NOT NULL DEFAULT '',
    completed_at TIMESTAMPTZ,
    version BIGINT NOT NULL DEFAULT 1,
    CHECK (consumed_seconds IS NULL OR discarded_seconds IS NULL OR consumed_seconds + discarded_seconds = reserved_seconds)
);
CREATE UNIQUE INDEX one_open_grant ON app.usage_grants(user_id) WHERE status IN ('RESERVED', 'ACTIVATED');
CREATE INDEX usage_grants_session ON app.usage_grants(session_id);
-- One control state per user: the target iPhone is the single active iPhone.
CREATE TABLE app.restriction_states (
    user_id UUID PRIMARY KEY REFERENCES app.users(id),
    device_id UUID REFERENCES app.devices(id),
    session_id UUID REFERENCES app.work_sessions(id),
    control_revision BIGINT NOT NULL DEFAULT 0,
    desired_mode TEXT NOT NULL CHECK (desired_mode IN ('UNRESTRICTED', 'SHIELDED', 'TIMED_UNLOCK', 'SESSION_ENDED')),
    active_grant_id UUID REFERENCES app.usage_grants(id),
    applied_revision BIGINT NOT NULL DEFAULT 0,
    shield_status TEXT NOT NULL DEFAULT 'UNKNOWN' CHECK (shield_status IN ('SHIELDED', 'UNSHIELDED', 'UNKNOWN', 'ERROR')),
    permission_status TEXT NOT NULL DEFAULT 'NOT_DETERMINED' CHECK (permission_status IN ('GRANTED', 'DENIED', 'NOT_DETERMINED')),
    last_applied_at TIMESTAMPTZ,
    last_reported_at TIMESTAMPTZ,
    failure_reason TEXT NOT NULL DEFAULT '',
    version BIGINT NOT NULL DEFAULT 1,
    CHECK (applied_revision <= control_revision)
);
CREATE TABLE app.restriction_operations (
    user_id UUID NOT NULL REFERENCES app.users(id),
    kind TEXT NOT NULL,
    operation_id UUID NOT NULL,
    request_hash TEXT NOT NULL,
    resource_id UUID NOT NULL,
    response JSONB NOT NULL,
    PRIMARY KEY (user_id, kind, operation_id)
);
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM PUBLIC;
-- +goose Down
DROP TABLE app.restriction_operations;
DROP TABLE app.restriction_states;
DROP TABLE app.usage_grants;
DROP TABLE app.restriction_policies;
