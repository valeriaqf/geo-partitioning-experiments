-- Optional configuration, NOT part of the original PoC: the native placement policy.
-- PLACEMENT RESTRICTED removes the non-voting replicas that regional tables (REGIONAL BY ROW / BY TABLE)
-- keep outside their home region. It works with SURVIVE ZONE FAILURE (not with REGION survival) and does
-- not change GLOBAL tables. Cockroach Labs documents it as "not recommended", kept for backwards
-- compatibility, and suggests super regions instead (see README).
SET database = geo_db;
SET enable_multiregion_placement_policy = on;
ALTER DATABASE geo_db PLACEMENT RESTRICTED;
