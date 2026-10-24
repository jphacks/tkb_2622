-- name: EnsureUser :one
INSERT INTO app.users (id, auth_provider, auth_subject) VALUES ($1, 'supabase', $2)
ON CONFLICT (auth_provider, auth_subject) DO UPDATE SET auth_subject = EXCLUDED.auth_subject
RETURNING *;
-- name: GetUser :one
SELECT * FROM app.users WHERE auth_provider = 'supabase' AND auth_subject = $1;
-- name: LockUser :one
SELECT * FROM app.users WHERE id = $1 FOR UPDATE;
-- name: SessionDevice :one
SELECT * FROM app.devices WHERE auth_session_id = $1;
-- name: GetDevice :one
SELECT * FROM app.devices WHERE user_id = $1 AND id = $2;
-- name: RegistrationDevice :one
SELECT * FROM app.devices WHERE user_id = $1 AND registration_id = $2;
-- name: ActiveIPhoneCount :one
SELECT count(*) FROM app.devices WHERE user_id = $1 AND platform = 'IOS' AND status = 'ACTIVE';
-- name: CreateDevice :one
INSERT INTO app.devices (id, user_id, registration_id, auth_session_id, platform, name)
VALUES ($1, $2, $3, $4, $5, $6) RETURNING *;
-- name: ListDevices :many
SELECT * FROM app.devices WHERE user_id = $1 AND id > $2 ORDER BY id LIMIT $3;
-- name: RevokeDevice :one
UPDATE app.devices SET status = 'REVOKED', version = version + 1
WHERE user_id = $1 AND id = $2 AND version = $3 AND status = 'ACTIVE' RETURNING *;
-- name: GetOperation :one
SELECT * FROM app.identity_operations WHERE user_id = $1 AND kind = $2 AND operation_id = $3;
-- name: SaveOperation :exec
INSERT INTO app.identity_operations (user_id, kind, operation_id, request_hash, response)
VALUES ($1, $2, $3, $4, $5);
-- name: ActiveIPhone :one
SELECT * FROM app.devices WHERE user_id = $1 AND platform = 'IOS' AND status = 'ACTIVE';
