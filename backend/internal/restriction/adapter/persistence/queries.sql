-- name: GetPolicy :one
SELECT * FROM app.restriction_policies WHERE user_id = $1 AND device_id = $2;
-- name: InsertPolicy :exec
INSERT INTO app.restriction_policies (device_id, user_id, enabled, target_mode, device_config_version, configured)
VALUES ($1, $2, $3, $4, $5, $6);
-- name: UpdatePolicy :execrows
UPDATE app.restriction_policies SET enabled = $3, target_mode = $4, device_config_version = $5, configured = $6, version = version + 1, updated_at = now()
WHERE user_id = $1 AND device_id = $2 AND version = $7;
-- name: GetGrant :one
SELECT * FROM app.usage_grants WHERE user_id = $1 AND id = $2;
-- name: OpenGrant :one
SELECT * FROM app.usage_grants WHERE user_id = $1 AND status IN ('RESERVED', 'ACTIVATED');
-- name: InsertGrant :exec
INSERT INTO app.usage_grants (id, user_id, device_id, session_id, requested_seconds, reserved_seconds, status, control_revision, issued_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);
-- name: UpdateGrant :execrows
UPDATE app.usage_grants SET status = $3, activated_at = $4, report_seq = $5, reported_seconds = $6, last_observed_at = $7,
    consumed_seconds = $8, discarded_seconds = $9, end_reason = $10, ended_by_operation_id = $11, completed_at = $12, version = version + 1
WHERE user_id = $1 AND id = $2 AND version = $13;
-- name: GetState :one
SELECT * FROM app.restriction_states WHERE user_id = $1;
-- name: InsertState :exec
INSERT INTO app.restriction_states (user_id, device_id, session_id, control_revision, desired_mode, active_grant_id, applied_revision,
    shield_status, permission_status, last_applied_at, last_reported_at, failure_reason)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);
-- name: UpdateState :execrows
UPDATE app.restriction_states SET device_id = $2, session_id = $3, control_revision = $4, desired_mode = $5, active_grant_id = $6,
    applied_revision = $7, shield_status = $8, permission_status = $9, last_applied_at = $10, last_reported_at = $11, failure_reason = $12,
    version = version + 1
WHERE user_id = $1 AND version = $13;
-- name: GetOperation :one
SELECT * FROM app.restriction_operations WHERE user_id = $1 AND kind = $2 AND operation_id = $3;
-- name: SaveOperation :exec
INSERT INTO app.restriction_operations (user_id, kind, operation_id, request_hash, resource_id, response)
VALUES ($1, $2, $3, $4, $5, $6);
