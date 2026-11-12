-- Manual zone configuration, applied on top of REGIONAL BY ROW.
-- usa: 3 replicas, only on nodes with region=usa.
-- eur: 1 replica (1 voter), only on the node with region=eur.
-- Without this block, the default REGIONAL BY ROW placement also keeps copies of each
-- region's rows in the other region (see README, "Baseline").
SET database = geo_db;
SET override_multi_region_zone_config = true;

ALTER PARTITION usa OF INDEX doctors@doctors_pkey CONFIGURE ZONE USING
    num_replicas = 3, constraints = '[+region=usa]', lease_preferences = '[[+region=usa]]';
ALTER PARTITION eur OF INDEX doctors@doctors_pkey CONFIGURE ZONE USING
    num_replicas = 1, num_voters = 1, constraints = '[+region=eur]', lease_preferences = '[[+region=eur]]';

ALTER PARTITION usa OF INDEX patients@patients_pkey CONFIGURE ZONE USING
    num_replicas = 3, constraints = '[+region=usa]', lease_preferences = '[[+region=usa]]';
ALTER PARTITION eur OF INDEX patients@patients_pkey CONFIGURE ZONE USING
    num_replicas = 1, num_voters = 1, constraints = '[+region=eur]', lease_preferences = '[[+region=eur]]';

ALTER PARTITION usa OF INDEX doctor_research_projects@doctor_research_projects_pkey CONFIGURE ZONE USING
    num_replicas = 3, constraints = '[+region=usa]', lease_preferences = '[[+region=usa]]';
ALTER PARTITION eur OF INDEX doctor_research_projects@doctor_research_projects_pkey CONFIGURE ZONE USING
    num_replicas = 1, num_voters = 1, constraints = '[+region=eur]', lease_preferences = '[[+region=eur]]';
