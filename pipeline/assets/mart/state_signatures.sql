/* @bruin
name: mart.state_signatures
type: duckdb.sql
description: How each fault state differs from the healthy baseline. Used to prove the playbook clues are true in the data.
depends: [stg.bearing_readings, mart.baseline]
materialization:
  type: table
custom_checks:
  - name: every_fault_differs_from_baseline
    description: Each fault state must have at least one metric whose average is outside the healthy range.
    query: select count(*) from (select bearing_state from mart.state_signatures where bearing_state > 1 group by 1 having sum(outside_baseline::int) = 0)
    value: 0
  - name: excess_grease_distinguishable_from_dry
    description: Playbook says a-RMS rises only for excess grease. Check the data agrees.
    query: |
      select count(*) from mart.state_signatures
      where metric = 'a_rms' and ((bearing_state = 3 and not outside_baseline) or (bearing_state = 2 and outside_baseline))
    value: 0
@bruin */
with long as (
  unpivot (select bearing_state, v_rms, a_rms, a_peak, crest, temperature from stg.bearing_readings)
  on v_rms, a_rms, a_peak, crest, temperature into name metric value val
), agg as (select bearing_state, metric, avg(val) as mean from long group by 1, 2)
select a.bearing_state, a.metric, a.mean, b.mean as baseline_mean,
       round(100 * (a.mean - b.mean) / b.mean, 1) as pct_vs_baseline,
       (a.mean < b.low or a.mean > b.high) as outside_baseline
from agg a join mart.baseline b using (metric)
