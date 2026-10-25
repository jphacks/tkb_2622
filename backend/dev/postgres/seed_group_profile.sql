-- Local-only profile/group preview data. Never apply to staging or production.

SELECT id AS seed_user_id
FROM app.users
WHERE auth_provider = 'supabase'
  AND auth_subject = :'seed_auth_subject'::uuid
  AND status = 'ACTIVE' \gset

\if :{?seed_user_id}
\else
\echo 'No active app user matches SEED_AUTH_SUBJECT. Sign in to the local app first.'
SELECT 1 / 0;
\quit
\endif

SELECT EXISTS (
    SELECT 1 FROM app.groups
    WHERE id = 'f6262200-0000-4000-8000-000000000501'
      AND (created_by <> :'seed_user_id'::uuid OR name <> '朝の集中ルーム')
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
    WHERE id = 'f6262200-0000-4000-8000-000000000502'
      AND (group_id <> 'f6262200-0000-4000-8000-000000000501'::uuid
        OR user_id <> :'seed_user_id'::uuid)
    UNION ALL
    SELECT 1 FROM app.group_memberships
    WHERE id = 'f6262200-0000-4000-8000-000000000503'
      AND (group_id <> 'f6262200-0000-4000-8000-000000000501'::uuid
        OR user_id <> 'f6262200-0000-4000-8000-000000000599'::uuid)
    UNION ALL
    SELECT 1 FROM app.group_memberships
    WHERE group_id = 'f6262200-0000-4000-8000-000000000501'::uuid
      AND status = 'ACTIVE'
      AND ((user_id = :'seed_user_id'::uuid AND id <> 'f6262200-0000-4000-8000-000000000502'::uuid)
        OR (user_id = 'f6262200-0000-4000-8000-000000000599'::uuid AND id <> 'f6262200-0000-4000-8000-000000000503'::uuid))
) AS fixture_conflict \gset

\if :fixture_conflict
\echo 'A fixed profile/group fixture ID is already used by different data. No data was changed.'
SELECT 1 / 0;
\quit
\endif

BEGIN;

INSERT INTO app.groups (id, name, created_by, created_at)
VALUES ('f6262200-0000-4000-8000-000000000501', '朝の集中ルーム', :'seed_user_id'::uuid, now() - interval '5 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO app.users (id, auth_provider, auth_subject, status, created_at, display_name, avatar_id)
VALUES ('f6262200-0000-4000-8000-000000000599', 'supabase', 'f6262200-0000-4000-8000-000000000599', 'ACTIVE', now() - interval '5 days', 'こむぎ', 'puppy')
ON CONFLICT (id) DO UPDATE
SET status = EXCLUDED.status, display_name = EXCLUDED.display_name, avatar_id = EXCLUDED.avatar_id;

INSERT INTO app.group_memberships (id, group_id, user_id, status, joined_at)
VALUES
    ('f6262200-0000-4000-8000-000000000502', 'f6262200-0000-4000-8000-000000000501', :'seed_user_id'::uuid, 'ACTIVE', now() - interval '5 days'),
    ('f6262200-0000-4000-8000-000000000503', 'f6262200-0000-4000-8000-000000000501', 'f6262200-0000-4000-8000-000000000599', 'ACTIVE', now() - interval '4 days')
ON CONFLICT (id) DO UPDATE
SET group_id = EXCLUDED.group_id, user_id = EXCLUDED.user_id, status = EXCLUDED.status, joined_at = EXCLUDED.joined_at, left_at = NULL;

COMMIT;
\echo 'Seeded local profile preview group with two avatar IDs.'
