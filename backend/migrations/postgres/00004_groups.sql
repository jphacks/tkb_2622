-- +goose Up
CREATE TABLE app.groups (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
    created_by UUID NOT NULL REFERENCES app.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app.group_memberships (
    id UUID PRIMARY KEY,
    group_id UUID NOT NULL REFERENCES app.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app.users(id),
    status TEXT NOT NULL CHECK (status IN ('ACTIVE', 'LEFT')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at TIMESTAMPTZ,
    CHECK ((status = 'ACTIVE' AND left_at IS NULL) OR (status = 'LEFT' AND left_at IS NOT NULL))
);

CREATE UNIQUE INDEX one_active_group_membership
    ON app.group_memberships(group_id, user_id) WHERE status = 'ACTIVE';
CREATE INDEX group_memberships_user
    ON app.group_memberships(user_id, group_id) WHERE status = 'ACTIVE';
CREATE INDEX group_memberships_group
    ON app.group_memberships(group_id, user_id) WHERE status = 'ACTIVE';

REVOKE ALL ON app.groups, app.group_memberships FROM PUBLIC;

-- +goose Down
DROP TABLE app.group_memberships;
DROP TABLE app.groups;
