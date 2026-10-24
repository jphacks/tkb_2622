-- +goose Up
CREATE TABLE users (
    id TEXT NOT NULL PRIMARY KEY,
    auth_provider TEXT NOT NULL,
    auth_subject TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISABLED')),
    UNIQUE (auth_provider, auth_subject)
);

-- +goose Down
DROP TABLE users;
