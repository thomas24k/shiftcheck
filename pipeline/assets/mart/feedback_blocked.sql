/* @bruin
name: mart.feedback_blocked
type: duckdb.sql
description: Feedback lines Bruin refused to show because their evidence does not exist. Shown in the app as "N unsupported lines blocked".
depends: [mart.feedback_candidates, mart.feedback]
materialization:
  type: table
@bruin */
select c.* from mart.feedback_candidates c
anti join mart.feedback f on f.session_id = c.session_id and f.message = c.message and f.evidence_ref is not distinct from c.evidence_ref
