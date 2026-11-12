-- Extra access profile for validation case V7 (--insecure mode: no password, local test environment only).
-- admin_sens: administrator allowed to read personal data of BOTH regions, but only through the
-- region-filtered views (never the base tables). Run after 04_roles_views.sql.
SET database = geo_db;
CREATE USER IF NOT EXISTS admin_sens;
GRANT SELECT ON v_patients_usa, v_patients_eur,
                v_doctors_usa, v_doctors_eur,
                v_doctor_research_projects_usa, v_doctor_research_projects_eur TO admin_sens;
GRANT SELECT ON research_projects, units, v_region_metadata TO admin_sens;
