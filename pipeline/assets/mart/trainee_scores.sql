/* @bruin
name: mart.trainee_scores
type: duckdb.sql
description: |
  Five scores (0-20 each, 100 total) per training session, graded against the real bearing state and the expert playbook.
  diagnosis, ruled_out, evidence, fix_choice, safety_verification.
depends: [raw.trainee_events, seed.hypotheses, seed.solutions]
materialization:
  type: table
columns:
  - name: session_id
    checks: [{name: not_null}, {name: unique}]
  - name: total
    checks: [{name: min, value: 0}, {name: max, value: 100}]
@bruin */
with ev as (select *, row_number() over (partition by session_id order by ts, event_id) as seq from raw.trainee_events),
sess as (
  select session_id, any_value(attempt) as attempt, any_value(scenario) as scenario,
         case any_value(scenario) when 1 then 2 else 3 end as fault_state
  from ev group by 1
),
truth as (select s.*, h.hypothesis_id as true_h from sess s left join seed.hypotheses h on h.true_for_state::varchar = s.fault_state::varchar),
pos as (
  select session_id,
    min(seq) filter (kind = 'action' and code <> 'read_trends') as first_other_action,
    min(seq) filter (code = 'read_trends') as read_trends,
    min(seq) filter (code = 'lockout') as lockout,
    min(seq) filter (code = 'try_start') as try_start,
    min(seq) filter (code in ('inspect', 'fix')) as first_touch,
    min(seq) filter (code = 'fix') as fix,
    max(seq) filter (code = 'restart') as restart,
    max(seq) filter (code = 'verify') as verify,
    count(*) filter (code = 'unsafe_stop') as unsafe_stops,
    arg_min(solution_id, seq) filter (code = 'fix') as solution_id
  from ev group by 1
),
final_hyp as (
  select e.session_id, arg_max(e.hypothesis_id, e.seq) as final_h,
         count(*) as n_hyp,
         count(*) filter (regexp_matches(lower(e.text), 'peak|crest|rms|temp|vibration|baseline')) as n_cites_data
  from ev e join pos p using (session_id)
  where e.kind = 'hypothesis' and (p.fix is null or e.seq < p.fix) group by 1
),
ruled as (
  select e.session_id,
    count(distinct e.ruled_out_id) filter (e.ruled_out_id <> t.true_h) as good_ruleouts,
    count(*) filter (e.ruled_out_id = t.true_h) as bad_ruleouts
  from ev e join truth t using (session_id) where e.ruled_out_id is not null group by 1
),
scored as (
  select t.session_id, t.attempt, t.scenario, t.fault_state, t.true_h, f.final_h, p.solution_id, p.unsafe_stops,
    case when f.final_h = t.true_h then 20
         when exists (select 1 from ev e where e.session_id = t.session_id and e.hypothesis_id = t.true_h) then 10 else 0 end as diagnosis,
    greatest(0, least(20, 10 * coalesce(r.good_ruleouts, 0)) - 10 * coalesce(r.bad_ruleouts, 0)) as ruled_out,
    (case when p.read_trends is not null and p.read_trends < coalesce(p.first_other_action, 1e9) then 10 else 0 end)
    + (case when coalesce(f.n_hyp, 0) > 0 and f.n_cites_data * 2 >= f.n_hyp then 10 else 0 end) as evidence,
    coalesce(round(greatest(0, s.points::int) * 20.0 / 30)::int, 0) as fix_choice,
    greatest(0, 20
      - (case when p.lockout is null or p.lockout > coalesce(p.first_touch, 1e9) then 10 else 0 end)
      - (case when p.try_start is null or p.try_start > coalesce(p.fix, 1e9) then 5 else 0 end)
      - (case when p.restart is not null and (p.verify is null or p.verify < p.restart) then 10 else 0 end)
      - 5 * p.unsafe_stops) as safety_verification
  from truth t join pos p using (session_id)
  left join final_hyp f using (session_id) left join ruled r using (session_id)
  left join seed.solutions s on s.solution_id = p.solution_id
)
select *, diagnosis + ruled_out + evidence + fix_choice + safety_verification as total from scored
