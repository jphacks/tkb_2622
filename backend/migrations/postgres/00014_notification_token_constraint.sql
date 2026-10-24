-- +goose Up
ALTER TABLE app.notification_endpoints
    DROP CONSTRAINT IF EXISTS notification_endpoints_apns_token_check;

ALTER TABLE app.notification_endpoints
    ADD CONSTRAINT notification_endpoints_apns_token_check
    CHECK (
        apns_token ~ '^[0-9a-f]+$'
        AND length(apns_token) BETWEEN 64 AND 512
        AND length(apns_token) % 2 = 0
    );

-- +goose Down
ALTER TABLE app.notification_endpoints
    DROP CONSTRAINT IF EXISTS notification_endpoints_apns_token_check;

ALTER TABLE app.notification_endpoints
    ADD CONSTRAINT notification_endpoints_apns_token_check
    CHECK (apns_token ~ '^[0-9a-f]{64,512}$' AND length(apns_token) % 2 = 0);
