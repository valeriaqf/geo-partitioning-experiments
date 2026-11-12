-- Synthetic multi-region schema (no real data). Regions: usa (primary) and eur.
DROP DATABASE IF EXISTS geo_db CASCADE;
CREATE DATABASE geo_db;
ALTER DATABASE geo_db SET PRIMARY REGION "usa";
ALTER DATABASE geo_db ADD REGION "eur";
ALTER DATABASE geo_db SURVIVE ZONE FAILURE;

SET database = geo_db;

-- GLOBAL tables: metadata without personal data, readable with low latency from any region.
CREATE TABLE research_projects (
    id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name STRING NOT NULL UNIQUE
) LOCALITY GLOBAL;

-- Only id, name and country: the jurisdiction of a record comes from its row region, not from the unit.
CREATE TABLE units (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name    STRING NOT NULL,
    country STRING NOT NULL
) LOCALITY GLOBAL;

-- REGIONAL BY ROW tables: each row lives in the region given by crdb_region.
CREATE TABLE doctors (
    id      UUID NOT NULL DEFAULT gen_random_uuid(),
    name    STRING NOT NULL,
    unit_id UUID,
    PRIMARY KEY (id)
) LOCALITY REGIONAL BY ROW;

CREATE TABLE patients (
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    name         STRING NOT NULL,
    doctor_id UUID,
    file_ref    STRING,          -- simulates a pointer to an image stored in the row's region
    PRIMARY KEY (id)
) LOCALITY REGIONAL BY ROW;

CREATE TABLE doctor_research_projects (
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL,
    research_project_id     UUID NOT NULL,
    PRIMARY KEY (id)
) LOCALITY REGIONAL BY ROW;
