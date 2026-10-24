-- name: CreateTask :one
INSERT INTO app.tasks (id, user_id, name, category, mode, planned_seconds, minimum_seconds)
VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *;
-- name: UpdateTask :one
UPDATE app.tasks SET name = $3, category = $4, mode = $5, planned_seconds = $6, minimum_seconds = $7, version = version + 1, updated_at = now()
WHERE user_id = $1 AND id = $2 AND version = $8 RETURNING *;
-- name: GetTask :one
SELECT * FROM app.tasks WHERE user_id = $1 AND id = $2;
-- name: ListTasks :many
SELECT * FROM app.tasks WHERE user_id = $1 AND id > $2 ORDER BY id LIMIT $3;
-- name: CreateSession :exec
INSERT INTO app.work_sessions (id, user_id, device_id, task_id, task_name, category, mode, planned_seconds, minimum_seconds, status, version, started_at, running_since)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13);
-- name: GetSession :one
SELECT * FROM app.work_sessions WHERE user_id = $1 AND id = $2;
-- name: CurrentSession :one
SELECT * FROM app.work_sessions WHERE user_id = $1 AND status IN ('RUNNING', 'PAUSED');
-- name: UpdateSession :execrows
UPDATE app.work_sessions SET status = $3, version = $4, running_since = $5, server_active_millis = $6, paused_at = $7, ended_at = $8,
    accepted_seq = $9, last_segment_end = $10, task_millis = $11, related_millis = $12, distraction_millis = $13, unknown_millis = $14, idle_millis = $15
WHERE user_id = $1 AND id = $2 AND version = $16 AND accepted_seq = $17;
-- name: SetFinalSegments :exec
UPDATE app.work_sessions SET final_segments = $2 WHERE id = $1;
-- name: GetBatch :one
SELECT * FROM app.activity_batches WHERE session_id = $1 AND seq = $2;
-- name: BatchByID :one
SELECT * FROM app.activity_batches WHERE session_id = $1 AND batch_id = $2;
-- name: InsertBatch :exec
INSERT INTO app.activity_batches (session_id, seq, batch_id, request_hash, status, evaluator_version, rules_version, segments)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
-- name: SetBatchStatus :exec
UPDATE app.activity_batches SET status = $3 WHERE session_id = $1 AND seq = $2;
-- name: DeleteBatch :exec
DELETE FROM app.activity_batches WHERE session_id = $1 AND seq = $2;
-- name: PendingSeqs :many
SELECT seq FROM app.activity_batches WHERE session_id = $1 AND status = 'PENDING' ORDER BY seq;
-- name: GetOperation :one
SELECT * FROM app.focus_operations WHERE user_id = $1 AND kind = $2 AND operation_id = $3;
-- name: SaveOperation :exec
INSERT INTO app.focus_operations (user_id, kind, operation_id, request_hash, resource_id, response)
VALUES ($1, $2, $3, $4, $5, $6);
