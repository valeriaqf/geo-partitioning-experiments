-- Validation case V8: each regional application profile may write rows ONLY of its own region.
-- Uses CockroachDB row-level security (RLS, available since v25.2). Run after 04_roles_views.sql.
-- Admins and the table owner (root) are exempt from RLS, and views are evaluated with the
-- view owner's privileges, so the read paths of V1 to V7 are not affected.
SET database = geo_db;
GRANT INSERT ON patients TO app_usa, app_eur;
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS write_own_region_usa ON patients;
DROP POLICY IF EXISTS write_own_region_eur ON patients;
CREATE POLICY write_own_region_usa ON patients FOR INSERT TO app_usa WITH CHECK (crdb_region = 'usa');
CREATE POLICY write_own_region_eur ON patients FOR INSERT TO app_eur WITH CHECK (crdb_region = 'eur');
