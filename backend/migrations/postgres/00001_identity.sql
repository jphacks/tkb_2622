-- +goose Up
CREATE SCHEMA IF NOT EXISTS app;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
CREATE TABLE app.users (
    id UUID PRIMARY KEY,
    auth_provider TEXT NOT NULL CHECK (auth_provider = 'supabase'),
    auth_subject UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISABLED')),
    UNIQUE (auth_provider, auth_subject)
);
CREATE TABLE app.devices (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app.users(id),
    registration_id UUID NOT NULL,
    auth_session_id UUID NOT NULL UNIQUE,
    platform TEXT NOT NULL CHECK (platform IN ('MACOS', 'WINDOWS', 'IOS')),
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED')),
    version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, registration_id)
);
CREATE UNIQUE INDEX one_active_iphone ON app.devices(user_id) WHERE platform = 'IOS' AND status = 'ACTIVE';
CREATE TABLE app.identity_operations (
    user_id UUID NOT NULL REFERENCES app.users(id),
    kind TEXT NOT NULL,
    operation_id UUID NOT NULL,
    request_hash TEXT NOT NULL,
    response JSONB NOT NULL,
    PRIMARY KEY (user_id, kind, operation_id)
);
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM PUBLIC;
-- +goose Down
DROP TABLE app.identity_operations;
DROP TABLE app.devices;
DROP TABLE app.users;
