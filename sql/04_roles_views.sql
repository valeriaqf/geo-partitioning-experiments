-- Access profiles (--insecure mode: no passwords, local test environment only).
-- No application role reads the base tables; each one only sees region-filtered views.
SET database = geo_db;

CREATE USER IF NOT EXISTS app_usa;      -- doctor/app in region usa
CREATE USER IF NOT EXISTS app_eur;      -- doctor/app in region eur
CREATE USER IF NOT EXISTS admin_meta;   -- administrator: metadata only, no personal data

CREATE OR REPLACE VIEW v_doctors_usa AS SELECT id, name, unit_id FROM doctors WHERE crdb_region = 'usa';
CREATE OR REPLACE VIEW v_doctors_eur AS SELECT id, name, unit_id FROM doctors WHERE crdb_region = 'eur';

CREATE OR REPLACE VIEW v_patients_usa AS SELECT id, name, doctor_id, file_ref FROM patients WHERE crdb_region = 'usa';
CREATE OR REPLACE VIEW v_patients_eur AS SELECT id, name, doctor_id, file_ref FROM patients WHERE crdb_region = 'eur';

CREATE OR REPLACE VIEW v_doctor_research_projects_usa AS SELECT id, doctor_id, research_project_id FROM doctor_research_projects WHERE crdb_region = 'usa';
CREATE OR REPLACE VIEW v_doctor_research_projects_eur AS SELECT id, doctor_id, research_project_id FROM doctor_research_projects WHERE crdb_region = 'eur';

-- Consolidated view WITHOUT personal data: row counts per region only
CREATE OR REPLACE VIEW v_region_metadata AS
    SELECT crdb_region::STRING AS region, 'doctors' AS table_name, count(*) AS row_count FROM doctors GROUP BY crdb_region
    UNION ALL
    SELECT crdb_region::STRING, 'patients', count(*) FROM patients GROUP BY crdb_region
    UNION ALL
    SELECT crdb_region::STRING, 'doctor_research_projects', count(*) FROM doctor_research_projects GROUP BY crdb_region;

GRANT SELECT ON research_projects, units TO app_usa, app_eur, admin_meta;
GRANT SELECT ON v_doctors_usa, v_patients_usa, v_doctor_research_projects_usa TO app_usa;
GRANT SELECT ON v_doctors_eur, v_patients_eur, v_doctor_research_projects_eur TO app_eur;
GRANT SELECT ON v_region_metadata TO admin_meta;
