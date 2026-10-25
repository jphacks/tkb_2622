-- name: GetWallet :one
SELECT * FROM app.reward_wallets WHERE user_id = $1;
-- name: InsertWallet :exec
INSERT INTO app.reward_wallets (user_id, session_id, balance_seconds, evaluated_seq, version, policy_version, grant_stopped, stop_reason, collector_healthy)
VALUES ($1, $2, $3, $4, 1, $5, $6, $7, $8);
-- name: UpdateWallet :execrows
UPDATE app.reward_wallets SET session_id = $2, balance_seconds = $3, evaluated_seq = $4,
    policy_version = $5, grant_stopped = $6, stop_reason = $7, collector_healthy = $8,
    version = version + 1, updated_at = now()
WHERE user_id = $1 AND version = $9;
-- name: AddTransaction :exec
INSERT INTO app.reward_transactions (id, user_id, session_id, type, amount_seconds, source_id, balance_after)
VALUES ($1, $2, $3, $4, $5, $6, $7);
-- name: AddGrant :exec
INSERT INTO app.reward_grants (id, session_id, user_id, policy_version, source_from_seq, source_to_seq, earned_seconds, transaction_id)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
-- name: SessionSummary :one
SELECT
    COALESCE(SUM(t.amount_seconds) FILTER (WHERE t.type = 'EARN'), 0)::BIGINT AS earned,
    COALESCE(-SUM(t.amount_seconds) FILTER (WHERE t.type = 'SPEND'), 0)::BIGINT AS spent,
    COALESCE(-SUM(t.amount_seconds) FILTER (WHERE t.type = 'DISCARD'), 0)::BIGINT AS discarded,
    COALESCE(o.policy_version, w.policy_version, g.policy_version, 1)::INTEGER AS policy_version,
    COALESCE(o.status, CASE WHEN SUM(t.amount_seconds) FILTER (WHERE t.type = 'EARN') > 0 THEN 'GRANTED' ELSE NULL END)::TEXT AS status,
    COALESCE(o.reason, w.stop_reason, '')::TEXT AS reason,
    COALESCE(o.grant_stopped, w.grant_stopped, FALSE)::BOOLEAN AS grant_stopped,
    COALESCE(w.collector_healthy, FALSE)::BOOLEAN AS collector_healthy,
    (o.session_id IS NOT NULL)::BOOLEAN AS finalized
FROM (SELECT sqlc.arg(session_id)::UUID AS session_id) target
LEFT JOIN app.reward_transactions t ON t.session_id = target.session_id
LEFT JOIN app.reward_session_outcomes o ON o.session_id = target.session_id
LEFT JOIN app.reward_wallets w ON w.session_id = target.session_id
LEFT JOIN LATERAL (
    SELECT MAX(policy_version) AS policy_version FROM app.reward_grants WHERE session_id = target.session_id
) g ON TRUE
GROUP BY o.session_id, o.policy_version, o.status, o.reason, o.grant_stopped,
         w.policy_version, w.stop_reason, w.grant_stopped, w.collector_healthy, g.policy_version;
-- name: SaveOutcome :exec
INSERT INTO app.reward_session_outcomes (session_id, user_id, policy_version, status, reason, grant_stopped)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (session_id) DO UPDATE SET
    user_id = EXCLUDED.user_id, policy_version = EXCLUDED.policy_version,
    status = EXCLUDED.status, reason = EXCLUDED.reason,
    grant_stopped = EXCLUDED.grant_stopped, updated_at = now();
