# ShiftCheck — Handoff Brief (hackathon, deadline 6:00 PM PT today)

## Event constraints
- Track 3 "Grow with Agents": agents play expert roles as visible characters, 2–3 agents coordinate about the human, agents adapt to performance, session ends with a clear result + evidence-based feedback.
- Bruin is mandatory (target: Best use of Bruin, $1000/$500). Second tool: Telem AI (search/fetch, 3 prizes). Demo video must be made in AdaL.
- All code written during the event. Submit public repo + demo at https://hackathons.crewbasecollective.com before 6 PM.

## Product
ShiftCheck: three AI colleagues teach a new-joiner maintenance technician to *reason* through a machine fault. They challenge every hypothesis, stop unsafe moves, apply production pressure, and pick the next scenario from the trainee's weakest skill. Bruin turns real sensor data + an expert playbook + every trainee action into evidence-based scores.

## Characters
- Marco, senior technician (coach): Socratic, graduated hints; silent when the trainee is right for the right reason; challenges "right action, wrong reason".
- Dana, safety inspector (examiner): freezes the sim on any unsafe action (no lockout, no try-start) and explains why.
- Frank, plant manager (boss): downtime cost ticking; pushes to skip steps; tests judgment.
- Visible "huddle" panel where the agents talk about the trainee between steps.

## UX (web app, 2.5D, no real 3D, no smart glasses)
- Left: clickable drawing of a geared motor driving a conveyor (motor, coupling, reducer, bearing, grease point) + live gauges (V-RMS, a-Peak, Crest, Temperature) replaying real data.
- Right: three characters with speech bubbles. Bottom: action buttons + mandatory one-line hypothesis ("I think it's X because Y") before each action.
- End: verdict (Certified / Needs retraining), 5-dimension score (diagnosis, ruled-out alternatives, evidence, fix choice, safety & verification); each feedback item links to the logged hypothesis/action and data point. Then attempt 2, progress shown.

## Data
- Sensor: Zenodo record 7589904 `bearing_vibration_metrics.csv` (International Hellenic University; license not stated — credit it). Columns: V-RMS, a-RMS, a-Peak, Crest, Temperature, Bearing State. Readings every 2 min. Rig: 6204 2RS bearing, 0.75 kW 1450 rpm Bonfiglioli BN80B4 motor, i=80 reducer, coupler.
- Bearing State: 1 = sealed, recommended grease (healthy baseline); 2 = unsealed, no grease; 3 = unsealed, excess grease.
- Playbook seeds (playbook/): hypotheses.csv, solutions.csv, procedure.csv.

## Scenarios
1. "Dry bearing": healthy (1) → no grease (2). Best fix: lockout, try-start, regrease, restart, verify vs baseline.
2. "The fix that made it worse": healthy (1) → excess grease (3). Trap: adding more grease. Best fix: purge excess, run-in, verify temperature.
Agents choose scenario 2 based on the trainee's scenario 1 behavior.

## Bruin pipeline (DuckDB local)
- raw.bearing_metrics (CSV seed/ingestr), seed.hypotheses, seed.solutions, seed.procedure
- stg.bearing_readings (clean names, ts = row_number × 2 min, state labels)
- mart.baseline (per-metric normal ranges from state 1)
- mart.state_signatures (state 2 and 3 vs baseline — used to validate the playbook evidence)
- mart.scenario_timeline (healthy rows then fault rows)
- raw.trainee_events (hypotheses, actions, timestamps — written by the app)
- mart.trainee_scores (5 dimensions, graded against Bearing State + playbook)
- mart.feedback (each item requires evidence_ref → event id and/or reading id; Telem source_url for outside facts)
- mart.verdict (runs only if checks pass)
- Checks: not_null, physical ranges, each fault state has ≥1 "best" solution, every hypothesis has a ruled_out rule, fault signature differs from baseline, every feedback row's evidence_ref exists (custom) → failing rows are blocked and counted.
- Agents read mart.trainee_scores via `bruin mcp` / DuckDB to adapt. Show `bruin lineage` in the demo.

## Stack
Python FastAPI backend + LLM for the three agents + Telem API; React/Vite (or plain HTML) frontend; DuckDB; Bruin CLI.

## Timeline
- until 3:45 core loop (pipeline + agents + UI); 3:45–4:30 checks visible, numbers, polish; FEATURE FREEZE 4:30
- 4:30–5:15 AdaL demo video; 5:15–5:45 README (sponsor table, architecture, honest limits) + submit.

## Demo script (~2 min)
Alarm → trainee guesses wrong reason → coach challenges → skips lockout → inspector stops → fixes, verifies → verdict with evidence links + "N unsupported feedback lines blocked by Bruin" → attempt 2 (excess grease trap) → better score → close on Bruin lineage + Telem traces.
