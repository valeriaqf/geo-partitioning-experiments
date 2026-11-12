-- Deterministic synthetic data.
SET database = geo_db;

INSERT INTO research_projects (name) VALUES ('Research A'), ('Research B'), ('Research C');

INSERT INTO units (name, country) VALUES
    ('Unit USA-1', 'USA'),
    ('Unit USA-2', 'USA'),
    ('Unit EUR-1', 'Germany'),
    ('Unit EUR-2', 'France');

-- 100 doctors per region
INSERT INTO doctors (crdb_region, name, unit_id)
SELECT 'usa'::crdb_internal_region, 'Doctor USA ' || g, (SELECT id FROM units WHERE name = 'Unit USA-1')
FROM generate_series(1, 100) AS g;

INSERT INTO doctors (crdb_region, name, unit_id)
SELECT 'eur'::crdb_internal_region, 'Doctor EUR ' || g, (SELECT id FROM units WHERE name = 'Unit EUR-1')
FROM generate_series(1, 100) AS g;

-- 1000 patients per region, each linked to a doctor of the same region
INSERT INTO patients (crdb_region, name, doctor_id, file_ref)
SELECT 'usa'::crdb_internal_region, 'Patient USA ' || g,
       (SELECT id FROM doctors WHERE crdb_region = 'usa' AND name = 'Doctor USA ' || ((g % 100) + 1)),
       's3://synthetic/usa/img_' || g || '.jpg'
FROM generate_series(1, 1000) AS g;

INSERT INTO patients (crdb_region, name, doctor_id, file_ref)
SELECT 'eur'::crdb_internal_region, 'Patient EUR ' || g,
       (SELECT id FROM doctors WHERE crdb_region = 'eur' AND name = 'Doctor EUR ' || ((g % 100) + 1)),
       's3://synthetic/eur/img_' || g || '.jpg'
FROM generate_series(1, 1000) AS g;

-- Every doctor linked to the 3 research_projects (row inherits the doctor's region)
INSERT INTO doctor_research_projects (crdb_region, doctor_id, research_project_id)
SELECT p.crdb_region, p.id, s.id FROM doctors AS p CROSS JOIN research_projects AS s;
