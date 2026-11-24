/* @bruin
name: mart.scenario_timeline
type: duckdb.sql
description: What the trainee sees. 60 healthy readings (2 h) then 180 fault readings. Scenario 1 = dry bearing, scenario 2 = excess grease.
depends: [stg.bearing_readings]
materialization:
  type: table
columns:
  - name: reading_id
    checks: [{name: not_null}]
@bruin */
with s as (select * from (values (1, 2), (2, 3)) t(scenario, fault_state)),
healthy as (select * from stg.bearing_readings where bearing_state = 1 order by reading_id desc limit 60),
rows as (
  select s.scenario, r.* from s, healthy r
  union all
  select s.scenario, r.* from s join stg.bearing_readings r on r.bearing_state = s.fault_state
  qualify row_number() over (partition by s.scenario order by r.reading_id) <= 180
)
select scenario, row_number() over (partition by scenario order by bearing_state > 1, reading_id) - 1 as tick, *
  exclude (scenario)
from rows
