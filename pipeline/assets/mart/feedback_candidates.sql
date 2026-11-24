/* @bruin
name: mart.feedback_candidates
type: duckdb.sql
description: Every feedback line anyone wants to give (rules + AI agents), with the evidence it claims. Not yet filtered.
depends: [mart.trainee_scores, raw.trainee_events, raw.agent_feedback, seed.hypotheses, seed.solutions]
materialization:
  type: table
@bruin */
with ev as (select * from raw.trainee_events), sc as (select * from mart.trainee_scores),
rules as (
  -- diagnosis
  select sc.session_id, 'rules' as agent, 'diagnosis' as dimension,
    case when sc.diagnosis = 20 then 'Correct diagnosis: ' || h.hypothesis || '. ' || h.supporting_evidence || '.'
         else 'Your final hypothesis did not match the data. The pattern fits ' || h.hypothesis || ': ' || h.supporting_evidence || '.' end as message,
    (select 'E:' || arg_max(e.event_id, e.ts) from ev e where e.session_id = sc.session_id and e.kind = 'hypothesis') as evidence_ref
  from sc join seed.hypotheses h on h.hypothesis_id = sc.true_h
  union all
  -- fix
  select sc.session_id, 'rules', 'fix_choice', 'Fix chosen (' || s.rating || '): ' || s.action || '. ' || s.tradeoff_explained_by_coach,
    (select 'E:' || min(e.event_id) from ev e where e.session_id = sc.session_id and e.code = 'fix')
  from sc join seed.solutions s on s.solution_id = sc.solution_id
  union all
  -- each unsafe stop
  select e.session_id, 'Dana', 'safety_verification', 'Stopped for safety: ' || e.text, 'E:' || e.event_id
  from ev e where e.code = 'unsafe_stop'
  union all
  -- missing verification
  select sc.session_id, 'rules', 'safety_verification',
    'You restarted but did not compare readings to the healthy baseline. A fix is not done until the data says so.',
    (select 'E:' || max(e.event_id) from ev e where e.session_id = sc.session_id and e.code = 'restart')
  from sc where sc.safety_verification < 20 and exists (select 1 from ev e where e.session_id = sc.session_id and e.code = 'restart')
    and not exists (select 1 from ev e where e.session_id = sc.session_id and e.code = 'verify')
)
select * from rules
union all
select session_id, agent, dimension, message, evidence_ref from raw.agent_feedback
