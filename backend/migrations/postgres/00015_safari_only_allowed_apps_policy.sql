-- +goose Up
ALTER TABLE app.restriction_policies
    DROP CONSTRAINT restriction_policies_allowed_apps_policy_check;

UPDATE app.restriction_policies
SET allowed_apps_policy = 'ALL_APPS_EXCEPT_SAFARI';

ALTER TABLE app.restriction_policies
    ALTER COLUMN allowed_apps_policy SET DEFAULT 'ALL_APPS_EXCEPT_SAFARI',
    ADD CONSTRAINT restriction_policies_allowed_apps_policy_check
        CHECK (allowed_apps_policy = 'ALL_APPS_EXCEPT_SAFARI');

-- +goose Down
ALTER TABLE app.restriction_policies
    DROP CONSTRAINT restriction_policies_allowed_apps_policy_check;

UPDATE app.restriction_policies
SET allowed_apps_policy = 'STANDARD_APPS_EXCEPT_SAFARI';

ALTER TABLE app.restriction_policies
    ALTER COLUMN allowed_apps_policy SET DEFAULT 'STANDARD_APPS_EXCEPT_SAFARI',
    ADD CONSTRAINT restriction_policies_allowed_apps_policy_check
        CHECK (allowed_apps_policy = 'STANDARD_APPS_EXCEPT_SAFARI');
