-- +goose Up
ALTER TABLE app.users
    ADD COLUMN IF NOT EXISTS avatar_id TEXT NOT NULL DEFAULT 'chick'
    CHECK (avatar_id IN (
        'dragon', 'puppy', 'cat', 'hedgehog', 'rabbit',
        'chick', 'bird', 'penguin_blue', 'penguin_pink', 'slime'
    ));

-- +goose Down
ALTER TABLE app.users DROP COLUMN IF EXISTS avatar_id;
