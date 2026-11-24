/* @bruin
name: raw.agent_feedback
type: duckdb.sql
description: Feedback lines the AI agents want to give. Each must cite evidence; Bruin blocks the ones that do not.
materialization:
  type: table
@bruin */
select * from read_csv('logs/agent_feedback.csv', header = true, delim = ',', quote = '"', escape = '"', columns = {
  'session_id': 'VARCHAR', 'agent': 'VARCHAR', 'dimension': 'VARCHAR', 'message': 'VARCHAR', 'evidence_ref': 'VARCHAR', 'kind': 'VARCHAR', 'source_url': 'VARCHAR'})
