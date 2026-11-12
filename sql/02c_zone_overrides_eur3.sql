-- 3+3 scenario only: the PoC's manual zone configuration adapted to 3 nodes in region eur.
-- usa: 3 replicas, only on nodes with region=usa (same as the PoC).
-- eur: 3 replicas (3 voters), only on nodes with region=eur, instead of the PoC's single replica.
SET database = geo_db;
SET override_multi_region_zone_config = true;

ALTER PARTITION usa OF INDEX doctors@doctors_pkey CONFIGURE ZONE USING
    num_replicas = 3, constraints = '[+region=usa]', lease_preferences = '[[+region=usa]]';
ALTER PARTITION eur OF INDEX doctors@doctors_pkey CONFIGURE ZONE USING
    num_replicas = 3, num_voters = 3, constraints = '[+region=eur]', lease_preferences = '[[+region=eur]]';

ALTER PARTITION usa OF INDEX patients@patients_pkey CONFIGURE ZONE USING
    num_replicas = 3, constraints = '[+region=usa]', lease_preferences = '[[+region=usa]]';
ALTER PARTITION eur OF INDEX patients@patients_pkey CONFIGURE ZONE USING
    num_replicas = 3, num_voters = 3, constraints = '[+region=eur]', lease_preferences = '[[+region=eur]]';

ALTER PARTITION usa OF INDEX doctor_research_projects@doctor_research_projects_pkey CONFIGURE ZONE USING
    num_replicas = 3, constraints = '[+region=usa]', lease_preferences = '[[+region=usa]]';
ALTER PARTITION eur OF INDEX doctor_research_projects@doctor_research_projects_pkey CONFIGURE ZONE USING
    num_replicas = 3, num_voters = 3, constraints = '[+region=eur]', lease_preferences = '[[+region=eur]]';
