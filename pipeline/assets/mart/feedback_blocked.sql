/* @bruin
name: mart.feedback_blocked
type: duckdb.sql
description: Feedback lines Bruin refused to show because their evidence does not exist. Shown in the app as "N unsupported lines blocked".
depends: [mart.feedback_candidates, mart.feedback, raw.telem_sources]
materialization:
  type: table
@bruin */
select c.*,
  case when c.kind = 'outside_fact' and c.source_url is null then 'outside fact with no source'
       when c.source_url is not null and not exists (select 1 from raw.telem_sources t where t.url = c.source_url and t.session_id = c.session_id)
         then 'source URL was never returned by Telem'
       else 'cited event or reading does not exist' end as block_reason
from mart.feedback_candidates c
anti join mart.feedback f on f.session_id = c.session_id and f.message = c.message and f.evidence_ref is not distinct from c.evidence_ref
