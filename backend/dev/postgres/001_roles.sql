-- Local development only. Production credentials must be provisioned separately.
CREATE ROLE tkb_app LOGIN PASSWORD 'local-app-only';
CREATE SCHEMA IF NOT EXISTS app;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO tkb_app;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tkb_app;
