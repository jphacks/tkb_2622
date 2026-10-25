-- Local development fixtures for the mobile app.
-- Run only through `make -C backend seed`; never apply this file to staging or production.

SELECT id AS seed_user_id
FROM app.users
WHERE auth_provider = 'supabase'
  AND auth_subject = :'seed_auth_subject'::uuid
  AND status = 'ACTIVE' \gset

\if :{?seed_user_id}
\else
\echo 'No active app user matches SEED_AUTH_SUBJECT. Sign in to the local app first.'
\quit 3
\endif

SELECT id AS seed_device_id
FROM app.devices
WHERE user_id = :'seed_user_id'::uuid
  AND platform = 'IOS'
  AND status = 'ACTIVE' \gset

\if :{?seed_device_id}
\else
\echo 'No active iOS device is registered for this user. Sign in and register the device first.'
\quit 3
\endif

-- The seed owns a fixed set of IDs. Refuse to mix its financial/session state with
-- unrelated account data, and refuse an existing open session rather than replace it.
SELECT EXISTS (
    SELECT 1 FROM app.tasks
    WHERE user_id = :'seed_user_id'::uuid
      AND id NOT IN (
        'f6262200-0000-4000-8000-000000000001',
        'f6262200-0000-4000-8000-000000000002'
      )
    UNION ALL
    SELECT 1 FROM app.work_sessions
    WHERE user_id = :'seed_user_id'::uuid
      AND id NOT IN (
        'f6262200-0000-4000-8000-000000000101',
        'f6262200-0000-4000-8000-000000000102',
        'f6262200-0000-4000-8000-000000000103'
      )
    UNION ALL
    SELECT 1 FROM app.reward_transactions
    WHERE user_id = :'seed_user_id'::uuid
      AND id NOT IN (
        'f6262200-0000-4000-8000-000000000201',
        'f6262200-0000-4000-8000-000000000202',
        'f6262200-0000-4000-8000-000000000203',
        'f6262200-0000-4000-8000-000000000204',
        'f6262200-0000-4000-8000-000000000205',
        'f6262200-0000-4000-8000-000000000206'
      )
    UNION ALL
    SELECT 1 FROM app.reward_wallets
    WHERE user_id = :'seed_user_id'::uuid
      AND session_id IS DISTINCT FROM 'f6262200-0000-4000-8000-000000000101'::uuid
    UNION ALL
    SELECT 1 FROM app.work_sessions
    WHERE user_id = :'seed_user_id'::uuid
      AND status IN ('RUNNING', 'PAUSED')
      AND id <> 'f6262200-0000-4000-8000-000000000101'
) AS seed_conflict \gset

\if :seed_conflict
\echo 'This account already has non-fixture focus/reward data or another open session. Use a clean development account; no data was changed.'
\quit 3
\endif

-- These policy/state rows are specific to the registered iOS device. Do not overwrite
-- settings or live control state that differ from the fixture on a rerun.
SELECT EXISTS (
    SELECT 1 FROM app.restriction_policies
    WHERE device_id = :'seed_device_id'::uuid
      AND (user_id <> :'seed_user_id'::uuid
        OR enabled IS DISTINCT FROM true
        OR target_mode <> 'SELECTED_APPS'
        OR device_config_version <> 1
        OR configured IS DISTINCT FROM true)
    UNION ALL
    SELECT 1 FROM app.restriction_states
    WHERE user_id = :'seed_user_id'::uuid
      AND (device_id IS DISTINCT FROM :'seed_device_id'::uuid
        OR session_id IS DISTINCT FROM 'f6262200-0000-4000-8000-000000000101'::uuid
        OR control_revision <> 4
        OR desired_mode <> 'SHIELDED'
        OR active_grant_id IS NOT NULL
        OR applied_revision <> 4
        OR shield_status <> 'SHIELDED'
        OR permission_status <> 'GRANTED')
) AS restriction_conflict \gset

\if :restriction_conflict
\echo 'The iOS device already has non-fixture restriction data. No data was changed.'
\quit 3
\endif

SELECT EXISTS (
    SELECT 1 FROM app.tasks
    WHERE id IN ('f6262200-0000-4000-8000-000000000001', 'f6262200-0000-4000-8000-000000000002')
      AND user_id <> :'seed_user_id'::uuid
    UNION ALL
    SELECT 1 FROM app.work_sessions
    WHERE id IN ('f6262200-0000-4000-8000-000000000101', 'f6262200-0000-4000-8000-000000000102', 'f6262200-0000-4000-8000-000000000103')
      AND user_id <> :'seed_user_id'::uuid
    UNION ALL
    SELECT 1 FROM app.reward_transactions
    WHERE id IN (
        'f6262200-0000-4000-8000-000000000201', 'f6262200-0000-4000-8000-000000000202',
        'f6262200-0000-4000-8000-000000000203', 'f6262200-0000-4000-8000-000000000204',
        'f6262200-0000-4000-8000-000000000205', 'f6262200-0000-4000-8000-000000000206'
    ) AND user_id <> :'seed_user_id'::uuid
    UNION ALL
    SELECT 1 FROM app.reward_grants
    WHERE id IN ('f6262200-0000-4000-8000-000000000401', 'f6262200-0000-4000-8000-000000000402', 'f6262200-0000-4000-8000-000000000403')
      AND user_id <> :'seed_user_id'::uuid
    UNION ALL
    SELECT 1 FROM app.activity_batches
    WHERE batch_id IN ('f6262200-0000-4000-8000-000000000301', 'f6262200-0000-4000-8000-000000000302')
      AND session_id <> 'f6262200-0000-4000-8000-000000000101'::uuid
    UNION ALL
    SELECT 1 FROM app.groups
    WHERE id = 'f6262200-0000-4000-8000-000000000501'
      AND created_by <> :'seed_user_id'::uuid
    UNION ALL
    SELECT 1 FROM app.users
    WHERE id = 'f6262200-0000-4000-8000-000000000599'
      AND (auth_provider <> 'supabase' OR auth_subject <> 'f6262200-0000-4000-8000-000000000599'::uuid)
    UNION ALL
    SELECT 1 FROM app.users
    WHERE auth_provider = 'supabase'
      AND auth_subject = 'f6262200-0000-4000-8000-000000000599'::uuid
      AND id <> 'f6262200-0000-4000-8000-000000000599'::uuid
    UNION ALL
    SELECT 1 FROM app.group_memberships
    WHERE id IN ('f6262200-0000-4000-8000-000000000502', 'f6262200-0000-4000-8000-000000000503')
      AND (group_id <> 'f6262200-0000-4000-8000-000000000501'::uuid
        OR user_id NOT IN (:'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000599'::uuid))
) AS fixture_id_conflict \gset

\if :fixture_id_conflict
\echo 'A fixed fixture ID is already owned by another account. No data was changed.'
\quit 3
\endif

BEGIN;

INSERT INTO app.tasks (id, user_id, name, category, mode, planned_seconds, minimum_seconds, version, created_at, updated_at)
VALUES
    ('f6262200-0000-4000-8000-000000000001', :'seed_user_id'::uuid, '企画書を仕上げる', 'DOCUMENT_WRITING', 'NORMAL', 3600, 1800, 1, now() - interval '4 days', now() - interval '4 days'),
    ('f6262200-0000-4000-8000-000000000002', :'seed_user_id'::uuid, '技術記事を読む', 'READING', 'READING', 2700, 1200, 1, now() - interval '3 days', now() - interval '3 days')
ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    name = EXCLUDED.name,
    category = EXCLUDED.category,
    mode = EXCLUDED.mode,
    planned_seconds = EXCLUDED.planned_seconds,
    minimum_seconds = EXCLUDED.minimum_seconds,
    version = EXCLUDED.version,
    created_at = EXCLUDED.created_at,
    updated_at = EXCLUDED.updated_at;

INSERT INTO app.work_sessions (
    id, user_id, device_id, task_id, task_name, category, mode, planned_seconds, minimum_seconds,
    status, version, started_at, running_since, server_active_millis, paused_at, ended_at,
    accepted_seq, last_segment_end, task_millis, related_millis, distraction_millis, unknown_millis,
    idle_millis, final_segments
)
VALUES
    ('f6262200-0000-4000-8000-000000000101', :'seed_user_id'::uuid, :'seed_device_id'::uuid,
     'f6262200-0000-4000-8000-000000000001', '企画書を仕上げる', 'DOCUMENT_WRITING', 'NORMAL', 3600, 1800,
     'PAUSED', 2, now() - interval '22 minutes', NULL, 1200000, now() - interval '2 minutes', NULL,
     2, now() - interval '2 minutes', 1020000, 120000, 60000, 0, 0, '[]'::jsonb),
    ('f6262200-0000-4000-8000-000000000102', :'seed_user_id'::uuid, :'seed_device_id'::uuid,
     'f6262200-0000-4000-8000-000000000002', '技術記事を読む', 'READING', 'READING', 2700, 1200,
     'FINALIZED', 4, now() - interval '3 days', NULL, 2700000, NULL, now() - interval '3 days' + interval '45 minutes',
     3, now() - interval '3 days' + interval '45 minutes', 2400000, 180000, 120000, 0, 0, '[]'::jsonb),
    ('f6262200-0000-4000-8000-000000000103', :'seed_user_id'::uuid, :'seed_device_id'::uuid,
     'f6262200-0000-4000-8000-000000000001', '企画書を仕上げる', 'DOCUMENT_WRITING', 'NORMAL', 3600, 1800,
     'ABORTED', 2, now() - interval '1 day' - interval '12 minutes', NULL, 720000, NULL, now() - interval '1 day',
     1, now() - interval '1 day', 540000, 0, 180000, 0, 0, '[]'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    device_id = EXCLUDED.device_id,
    task_id = EXCLUDED.task_id,
    task_name = EXCLUDED.task_name,
    category = EXCLUDED.category,
    mode = EXCLUDED.mode,
    planned_seconds = EXCLUDED.planned_seconds,
    minimum_seconds = EXCLUDED.minimum_seconds,
    status = EXCLUDED.status,
    version = EXCLUDED.version,
    started_at = EXCLUDED.started_at,
    running_since = EXCLUDED.running_since,
    server_active_millis = EXCLUDED.server_active_millis,
    paused_at = EXCLUDED.paused_at,
    ended_at = EXCLUDED.ended_at,
    accepted_seq = EXCLUDED.accepted_seq,
    last_segment_end = EXCLUDED.last_segment_end,
    task_millis = EXCLUDED.task_millis,
    related_millis = EXCLUDED.related_millis,
    distraction_millis = EXCLUDED.distraction_millis,
    unknown_millis = EXCLUDED.unknown_millis,
    idle_millis = EXCLUDED.idle_millis,
    final_segments = EXCLUDED.final_segments;

INSERT INTO app.activity_batches (session_id, seq, batch_id, request_hash, status, evaluator_version, rules_version, segments, received_at)
VALUES
    ('f6262200-0000-4000-8000-000000000101', 1, 'f6262200-0000-4000-8000-000000000301', repeat('1', 64), 'ACCEPTED', 'dev-seed-v1', 'dev-seed-v1',
     jsonb_build_array(
       jsonb_build_object('start', now() - interval '22 minutes', 'end', now() - interval '14 minutes', 'classification', 'TASK'),
       jsonb_build_object('start', now() - interval '14 minutes', 'end', now() - interval '12 minutes', 'classification', 'RELATED_TRANSITION')
     ), now() - interval '12 minutes'),
    ('f6262200-0000-4000-8000-000000000101', 2, 'f6262200-0000-4000-8000-000000000302', repeat('2', 64), 'ACCEPTED', 'dev-seed-v1', 'dev-seed-v1',
     jsonb_build_array(
       jsonb_build_object('start', now() - interval '12 minutes', 'end', now() - interval '3 minutes', 'classification', 'TASK'),
       jsonb_build_object('start', now() - interval '3 minutes', 'end', now() - interval '2 minutes', 'classification', 'DISTRACTION')
     ), now() - interval '2 minutes')
ON CONFLICT (session_id, seq) DO UPDATE SET
    batch_id = EXCLUDED.batch_id,
    request_hash = EXCLUDED.request_hash,
    status = EXCLUDED.status,
    evaluator_version = EXCLUDED.evaluator_version,
    rules_version = EXCLUDED.rules_version,
    segments = EXCLUDED.segments,
    received_at = EXCLUDED.received_at;

INSERT INTO app.reward_transactions (id, user_id, session_id, type, amount_seconds, source_id, balance_after, occurred_at)
VALUES
    ('f6262200-0000-4000-8000-000000000201', :'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000102', 'EARN', 2400, 'dev-seed-finalized-earn', 2400, now() - interval '3 days' + interval '46 minutes'),
    ('f6262200-0000-4000-8000-000000000202', :'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000102', 'SPEND', -600, 'dev-seed-finalized-spend', 1800, now() - interval '3 days' + interval '47 minutes'),
    ('f6262200-0000-4000-8000-000000000203', :'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000102', 'DISCARD', -1800, 'dev-seed-finalized-discard', 0, now() - interval '3 days' + interval '48 minutes'),
    ('f6262200-0000-4000-8000-000000000204', :'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000103', 'EARN', 600, 'dev-seed-aborted-earn', 600, now() - interval '1 day' + interval '1 minute'),
    ('f6262200-0000-4000-8000-000000000205', :'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000103', 'DISCARD', -600, 'dev-seed-aborted-discard', 0, now() - interval '1 day' + interval '2 minutes'),
    ('f6262200-0000-4000-8000-000000000206', :'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000101', 'EARN', 1800, 'dev-seed-current-earn', 1800, now() - interval '2 minutes')
ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    session_id = EXCLUDED.session_id,
    type = EXCLUDED.type,
    amount_seconds = EXCLUDED.amount_seconds,
    source_id = EXCLUDED.source_id,
    balance_after = EXCLUDED.balance_after,
    occurred_at = EXCLUDED.occurred_at;

INSERT INTO app.reward_grants (id, session_id, user_id, policy_version, source_from_seq, source_to_seq, earned_seconds, transaction_id, granted_at)
VALUES
    ('f6262200-0000-4000-8000-000000000401', 'f6262200-0000-4000-8000-000000000102', :'seed_user_id'::uuid, 1, 1, 3, 2400, 'f6262200-0000-4000-8000-000000000201', now() - interval '3 days' + interval '46 minutes'),
    ('f6262200-0000-4000-8000-000000000402', 'f6262200-0000-4000-8000-000000000103', :'seed_user_id'::uuid, 1, 1, 1, 600, 'f6262200-0000-4000-8000-000000000204', now() - interval '1 day' + interval '1 minute'),
    ('f6262200-0000-4000-8000-000000000403', 'f6262200-0000-4000-8000-000000000101', :'seed_user_id'::uuid, 1, 1, 2, 1800, 'f6262200-0000-4000-8000-000000000206', now() - interval '2 minutes')
ON CONFLICT (id) DO UPDATE SET
    session_id = EXCLUDED.session_id,
    user_id = EXCLUDED.user_id,
    policy_version = EXCLUDED.policy_version,
    source_from_seq = EXCLUDED.source_from_seq,
    source_to_seq = EXCLUDED.source_to_seq,
    earned_seconds = EXCLUDED.earned_seconds,
    transaction_id = EXCLUDED.transaction_id,
    granted_at = EXCLUDED.granted_at;

INSERT INTO app.reward_wallets (user_id, session_id, balance_seconds, evaluated_seq, version, updated_at)
VALUES (:'seed_user_id'::uuid, 'f6262200-0000-4000-8000-000000000101', 1800, 2, 1, now())
ON CONFLICT (user_id) DO UPDATE SET
    session_id = EXCLUDED.session_id,
    balance_seconds = EXCLUDED.balance_seconds,
    evaluated_seq = EXCLUDED.evaluated_seq,
    version = EXCLUDED.version,
    updated_at = EXCLUDED.updated_at;

INSERT INTO app.restriction_policies (device_id, user_id, enabled, target_mode, device_config_version, configured, version, updated_at)
VALUES (:'seed_device_id'::uuid, :'seed_user_id'::uuid, true, 'SELECTED_APPS', 1, true, 1, now())
ON CONFLICT (device_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    enabled = EXCLUDED.enabled,
    target_mode = EXCLUDED.target_mode,
    usage_time_mode = 'ACTIVE_USAGE',
    allowed_apps_policy = 'ALL_APPS_EXCEPT_SAFARI',
    device_config_version = EXCLUDED.device_config_version,
    configured = EXCLUDED.configured,
    version = EXCLUDED.version,
    updated_at = EXCLUDED.updated_at;

INSERT INTO app.restriction_states (
    user_id, device_id, session_id, control_revision, desired_mode, active_grant_id,
    applied_revision, shield_status, permission_status, last_applied_at, last_reported_at,
    failure_reason, version
)
VALUES (:'seed_user_id'::uuid, :'seed_device_id'::uuid, 'f6262200-0000-4000-8000-000000000101', 4, 'SHIELDED', NULL,
        4, 'SHIELDED', 'GRANTED', now() - interval '2 minutes', now() - interval '2 minutes', '', 1)
ON CONFLICT (user_id) DO UPDATE SET
    device_id = EXCLUDED.device_id,
    session_id = EXCLUDED.session_id,
    control_revision = EXCLUDED.control_revision,
    desired_mode = EXCLUDED.desired_mode,
    active_grant_id = EXCLUDED.active_grant_id,
    applied_revision = EXCLUDED.applied_revision,
    shield_status = EXCLUDED.shield_status,
    permission_status = EXCLUDED.permission_status,
    last_applied_at = EXCLUDED.last_applied_at,
    last_reported_at = EXCLUDED.last_reported_at,
    failure_reason = EXCLUDED.failure_reason,
    version = EXCLUDED.version;

INSERT INTO app.groups (id, name, created_by, created_at)
VALUES ('f6262200-0000-4000-8000-000000000501', '朝の集中ルーム', :'seed_user_id'::uuid, now() - interval '5 days')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, created_by = EXCLUDED.created_by, created_at = EXCLUDED.created_at;

INSERT INTO app.users (id, auth_provider, auth_subject, status, created_at, display_name, avatar_id)
VALUES ('f6262200-0000-4000-8000-000000000599', 'supabase', 'f6262200-0000-4000-8000-000000000599', 'ACTIVE', now() - interval '5 days', 'こむぎ', 'puppy')
ON CONFLICT (id) DO UPDATE SET status = 'ACTIVE', display_name = EXCLUDED.display_name, avatar_id = EXCLUDED.avatar_id;

INSERT INTO app.group_memberships (id, group_id, user_id, status, joined_at)
VALUES
    ('f6262200-0000-4000-8000-000000000502', 'f6262200-0000-4000-8000-000000000501', :'seed_user_id'::uuid, 'ACTIVE', now() - interval '5 days'),
    ('f6262200-0000-4000-8000-000000000503', 'f6262200-0000-4000-8000-000000000501', 'f6262200-0000-4000-8000-000000000599', 'ACTIVE', now() - interval '4 days')
ON CONFLICT (id) DO UPDATE SET group_id = EXCLUDED.group_id, user_id = EXCLUDED.user_id, status = EXCLUDED.status, joined_at = EXCLUDED.joined_at;

COMMIT;

\echo 'Seeded local fixture data: one paused session, two history sessions, reward ledger, restriction state, and one group.'
