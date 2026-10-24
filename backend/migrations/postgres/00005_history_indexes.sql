-- +goose Up
CREATE INDEX work_sessions_history ON app.work_sessions(user_id, started_at DESC, id DESC)
    WHERE status IN ('FINALIZED', 'ABORTED');
CREATE INDEX reward_transactions_history ON app.reward_transactions(user_id, occurred_at DESC, id DESC);

-- +goose Down
DROP INDEX app.reward_transactions_history;
DROP INDEX app.work_sessions_history;
