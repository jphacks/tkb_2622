-- +goose Up
ALTER TABLE app.users
    ADD COLUMN display_name TEXT NOT NULL DEFAULT 'メンバー'
    CHECK (char_length(display_name) BETWEEN 1 AND 30);

-- +goose Down
ALTER TABLE app.users DROP COLUMN display_name;
