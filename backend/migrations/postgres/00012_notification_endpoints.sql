-- +goose Up
CREATE TABLE app.notification_endpoints (
    device_id UUID PRIMARY KEY REFERENCES app.devices(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    apns_environment TEXT NOT NULL CHECK (apns_environment IN ('development', 'production')),
    apns_token TEXT NOT NULL CHECK (apns_token ~ '^[0-9a-f]{64,512}$' AND length(apns_token) % 2 = 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (apns_environment, apns_token)
);

REVOKE ALL ON app.notification_endpoints FROM PUBLIC;

-- +goose Down
DROP TABLE app.notification_endpoints;
