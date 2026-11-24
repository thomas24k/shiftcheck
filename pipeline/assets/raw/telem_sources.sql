/* @bruin
name: raw.telem_sources
type: duckdb.sql
description: Expert web sources Telem found for each session (search across several providers). Outside facts in feedback must cite one of these URLs.
materialization:
  type: table
columns:
  - name: url
    checks: [{name: not_null}]
@bruin */
select * from read_csv('logs/telem_sources.csv', header = true, delim = ',', quote = '"', escape = '"', columns = {
  'session_id': 'VARCHAR', 'query': 'VARCHAR', 'provider': 'VARCHAR', 'url': 'VARCHAR', 'title': 'VARCHAR', 'summary': 'VARCHAR'})
