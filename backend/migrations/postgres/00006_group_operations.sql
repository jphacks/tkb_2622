-- +goose Up
CREATE TABLE app.group_operations (
    user_id UUID NOT NULL REFERENCES app.users(id),
    operation_id UUID NOT NULL,
    request_hash TEXT NOT NULL,
    response JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, operation_id)
);

REVOKE ALL ON app.group_operations FROM PUBLIC;

-- +goose Down
DROP TABLE app.group_operations;
