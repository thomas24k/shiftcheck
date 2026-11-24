/* @bruin
name: mart.baseline
type: duckdb.sql
description: Normal operating range per metric, from the healthy bearing (state 1). 5th to 95th percentile.
depends: [stg.bearing_readings]
materialization:
  type: table
columns:
  - name: metric
    checks: [{name: not_null}, {name: unique}]
@bruin */
with long as (
  unpivot (select reading_id, v_rms, a_rms, a_peak, crest, temperature from stg.bearing_readings where bearing_state = 1)
  on v_rms, a_rms, a_peak, crest, temperature into name metric value val
)
select metric, avg(val) as mean, quantile_cont(val, 0.05) as low, quantile_cont(val, 0.95) as high
from long group by metric
