/* @bruin
name: stg.bearing_readings
type: duckdb.sql
description: Clean sensor readings with a reading id, a timestamp (2 min apart) and a state label.
depends: [raw.bearing_metrics]
materialization:
  type: table
columns:
  - name: reading_id
    checks: [{name: not_null}, {name: unique}]
  - name: v_rms
    checks: [{name: not_null}, {name: positive}]
  - name: a_peak
    checks: [{name: not_null}, {name: positive}]
  - name: temperature
    description: Physical range for a running bearing housing.
    checks: [{name: not_null}, {name: min, value: -10}, {name: max, value: 120}]
  - name: bearing_state
    checks: [{name: accepted_values, value: [1, 2, 3]}]
@bruin */
select
  row_number() over (order by bearing_state::int) as reading_id,
  timestamp '2026-01-01 00:00:00' + (row_number() over (order by bearing_state::int) - 1) * interval 2 minute as ts,
  v_rms::double  as v_rms,
  a_rms::double  as a_rms,
  a_peak::double as a_peak,
  crest::double  as crest,
  temperature::double as temperature,
  bearing_state::integer as bearing_state,
  case bearing_state::integer when 1 then 'healthy: sealed, recommended grease'
       when 2 then 'fault: unsealed, no grease' else 'fault: unsealed, excess grease' end as state_label
from raw.bearing_metrics
