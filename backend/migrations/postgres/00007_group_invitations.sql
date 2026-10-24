-- +goose Up
ALTER TABLE app.group_operations ADD COLUMN kind TEXT NOT NULL DEFAULT 'create';
ALTER TABLE app.group_operations DROP CONSTRAINT group_operations_pkey;
ALTER TABLE app.group_operations ADD PRIMARY KEY (user_id, kind, operation_id);

CREATE TABLE app.group_invitations (
    id UUID PRIMARY KEY,
    group_id UUID NOT NULL REFERENCES app.groups(id) ON DELETE CASCADE,
    invited_by UUID NOT NULL REFERENCES app.users(id),
    token_hash TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_by UUID REFERENCES app.users(id),
    accepted_at TIMESTAMPTZ,
    CHECK ((status = 'ACCEPTED' AND accepted_by IS NOT NULL AND accepted_at IS NOT NULL)
        OR (status <> 'ACCEPTED' AND accepted_by IS NULL AND accepted_at IS NULL))
);

CREATE INDEX group_invitations_group_pending
    ON app.group_invitations(group_id, expires_at) WHERE status = 'PENDING';

REVOKE ALL ON app.group_invitations FROM PUBLIC;

-- +goose Down
DROP TABLE app.group_invitations;
ALTER TABLE app.group_operations DROP CONSTRAINT group_operations_pkey;
ALTER TABLE app.group_operations DROP COLUMN kind;
ALTER TABLE app.group_operations ADD PRIMARY KEY (user_id, operation_id);
