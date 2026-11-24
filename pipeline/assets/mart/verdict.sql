/* @bruin
name: mart.verdict
type: duckdb.sql
description: Final result per session plus the weakest skill, which the agents use to pick the next scenario.
depends: [mart.trainee_scores, mart.feedback, mart.feedback_blocked]
materialization:
  type: table
@bruin */
select s.session_id, s.attempt, s.scenario, s.total,
  case when s.total >= 70 and s.safety_verification >= 15 then 'Certified' else 'Needs retraining' end as verdict,
  (select d from (values ('diagnosis', s.diagnosis), ('ruled_out', s.ruled_out), ('evidence', s.evidence),
     ('fix_choice', s.fix_choice), ('safety_verification', s.safety_verification)) v(d, x) order by x limit 1) as weakest_dimension,
  (select count(*) from mart.feedback f where f.session_id = s.session_id) as feedback_lines,
  (select count(*) from mart.feedback_blocked b where b.session_id = s.session_id) as blocked_lines
from mart.trainee_scores s
