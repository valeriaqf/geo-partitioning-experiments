-- Optional configuration, NOT part of the original PoC: super regions (the mechanism Cockroach Labs
-- currently recommends for data domiciling, instead of PLACEMENT RESTRICTED).
-- Each super region keeps ALL replicas (voting and non-voting) of regional data whose home region is
-- a member inside the super region. Here each super region has a single database region, so with
-- SURVIVE ZONE FAILURE the "eur" data needs 3 nodes in eur: expected to work in 3+3, not in 3+1.
-- System ranges (meta, liveness, etc.) are NOT affected by super regions.
-- If the SET below fails with "unrecognized configuration parameter", the feature is already enabled
-- by default in this version: delete that line and run again.
SET database = geo_db;
SET enable_super_regions = 'on';
ALTER DATABASE geo_db ADD SUPER REGION "eua" VALUES "usa";
ALTER DATABASE geo_db ADD SUPER REGION "europa" VALUES "eur";
SHOW SUPER REGIONS FROM DATABASE geo_db;
