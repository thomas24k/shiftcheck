/* @bruin
name: mart.feedback
type: duckdb.sql
description: Feedback shown to the trainee. A line survives only if its evidence_ref points to a real logged event (E:<id>) or sensor reading (R:<id>), and any outside fact cites a URL that Telem actually returned.
depends: [mart.feedback_candidates, raw.trainee_events, stg.bearing_readings, raw.telem_sources]
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
  - name: every_outside_fact_has_a_real_source
    description: Outside facts must cite a URL that Telem returned for this session.
    query: |
      select count(*) from mart.feedback f
      where (f.kind = 'outside_fact' or f.source_url is not null)
        and not exists (select 1 from raw.telem_sources t where t.url = f.source_url and t.session_id = f.session_id)
    value: 0
@bruin */
select c.* from mart.feedback_candidates c
where (exists (select 1 from raw.trainee_events e where 'E:' || e.event_id = c.evidence_ref and e.session_id = c.session_id)
   or exists (select 1 from stg.bearing_readings r where 'R:' || r.reading_id = c.evidence_ref))
  and ((c.kind <> 'outside_fact' and c.source_url is null)
       or exists (select 1 from raw.telem_sources t where t.url = c.source_url and t.session_id = c.session_id))
