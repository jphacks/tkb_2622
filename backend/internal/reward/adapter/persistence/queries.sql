-- name: GetWallet :one
SELECT * FROM app.reward_wallets WHERE user_id = $1;
-- name: InsertWallet :exec
INSERT INTO app.reward_wallets (user_id, session_id, balance_seconds, evaluated_seq, version)
VALUES ($1, $2, $3, $4, 1);
-- name: UpdateWallet :execrows
UPDATE app.reward_wallets SET session_id = $2, balance_seconds = $3, evaluated_seq = $4, version = version + 1, updated_at = now()
WHERE user_id = $1 AND version = $5;
-- name: AddTransaction :exec
INSERT INTO app.reward_transactions (id, user_id, session_id, type, amount_seconds, source_id, balance_after)
VALUES ($1, $2, $3, $4, $5, $6, $7);
-- name: AddGrant :exec
INSERT INTO app.reward_grants (id, session_id, user_id, policy_version, source_from_seq, source_to_seq, earned_seconds, transaction_id)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
-- name: SessionSummary :one
SELECT
    COALESCE(SUM(amount_seconds) FILTER (WHERE type = 'EARN'), 0)::BIGINT AS earned,
    COALESCE(-SUM(amount_seconds) FILTER (WHERE type = 'SPEND'), 0)::BIGINT AS spent,
    COALESCE(-SUM(amount_seconds) FILTER (WHERE type = 'DISCARD'), 0)::BIGINT AS discarded
FROM app.reward_transactions WHERE session_id = $1;
