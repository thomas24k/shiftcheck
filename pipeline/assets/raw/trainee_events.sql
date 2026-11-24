/* @bruin
name: raw.trainee_events
type: duckdb.sql
description: Every hypothesis and action a trainee made, written by the ShiftCheck app to logs/trainee_events.csv.
materialization:
  type: table
columns:
  - name: event_id
    checks: [{name: not_null}, {name: unique}]
  - name: kind
    checks: [{name: accepted_values, value: [hypothesis, action]}]
@bruin */
select * from read_csv('logs/trainee_events.csv', header = true, delim = ',', quote = '"', escape = '"', columns = {
  'event_id': 'VARCHAR', 'session_id': 'VARCHAR', 'attempt': 'INTEGER', 'scenario': 'INTEGER',
  'ts': 'TIMESTAMP', 'kind': 'VARCHAR', 'code': 'VARCHAR', 'hypothesis_id': 'VARCHAR',
  'ruled_out_id': 'VARCHAR', 'solution_id': 'VARCHAR', 'text': 'VARCHAR', 'reading_id': 'INTEGER'})
