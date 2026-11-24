/* @bruin
name: mart.feedback
type: duckdb.sql
description: Feedback shown to the trainee. Only lines whose evidence_ref points to a real logged event (E:<id>) or sensor reading (R:<id>) survive.
depends: [mart.feedback_candidates, raw.trainee_events, stg.bearing_readings]
materialization:
  type: table
columns:
  - name: evidence_ref
    checks: [{name: not_null}]
custom_checks:
  - name: every_feedback_line_has_real_evidence
    description: No feedback without a real event or reading behind it.
    query: |
      select count(*) from mart.feedback f
      where not exists (select 1 from raw.trainee_events e where 'E:' || e.event_id = f.evidence_ref)
        and not exists (select 1 from stg.bearing_readings r where 'R:' || r.reading_id = f.evidence_ref)
    value: 0
@bruin */
select c.* from mart.feedback_candidates c
where exists (select 1 from raw.trainee_events e where 'E:' || e.event_id = c.evidence_ref and e.session_id = c.session_id)
   or exists (select 1 from stg.bearing_readings r where 'R:' || r.reading_id = c.evidence_ref)
