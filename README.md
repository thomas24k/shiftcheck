# ShiftCheck

Three AI colleagues teach a new maintenance technician to **reason** through a real machine fault, not just follow a checklist.

- **Marco** (senior technician, coach) asks Socratic questions built from the live sensor data and never gives the answer away.
- **Dana** (safety inspector) stops any unsafe move, such as touching the machine before lockout/tagout. Safety stops are hard-coded rules, never left to the AI.
- **Frank** (plant manager) runs a downtime-cost meter and tempts the trainee to skip steps.

Before every action the trainee must state a hypothesis ("I think it's X because Y"). At the end of the shift, a **Bruin** pipeline scores the session on five skills against the real bearing state and an expert playbook. The agents then pick the next scenario from the trainee's weakest skill.

Built for Track 3, "Grow with Agents".

## How it works

```
sensor CSV + playbook ──► Bruin (DuckDB) ──► baseline, fault signatures, scenario timelines
                                                           │
trainee actions ──► FastAPI app ──► Claude (Marco/Dana/Frank dialogue)
                        │
                        ├──► Telem web search (expert sources for the fault)
                        ▼
              logs/*.csv ──► Bruin ──► scores ► feedback (evidence-checked) ► verdict
```

1. **Replay:** the page plays back real readings: 2 hours healthy, then the fault.
2. **Act:** every hypothesis and action is logged with the sensor reading at that moment.
3. **Talk:** Claude writes each colleague's line from the data, the trainee's reasoning and the hidden true fault.
4. **Score:** at the end of the shift the app runs `bruin run`. Bruin grades five skills (0–20 each):
   - diagnosis
   - ruled-out alternatives
   - use of evidence
   - fix choice
   - safety & verification
5. **Feedback you can trust:** each feedback line must point to a real logged event or sensor reading. Each "outside fact" must cite a URL that Telem actually returned. Bruin blocks any other line and shows the count and the reason on the verdict screen.
6. **Adapt:** attempt 2 is chosen from the weakest skill. Scenario 2 is the "fix that made it worse" grease trap.

### Bruin pipeline (16 assets, 33 quality checks)

| Layer | Assets |
|---|---|
| raw / seed | `raw.bearing_metrics`, `seed.hypotheses`, `seed.solutions`, `seed.procedure`, `raw.trainee_events`, `raw.agent_feedback`, `raw.telem_sources` |
| staging | `stg.bearing_readings` (clean names, 2-minute timestamps, state labels) |
| marts | `mart.baseline`, `mart.state_signatures`, `mart.scenario_timeline`, `mart.trainee_scores`, `mart.feedback_candidates`, `mart.feedback`, `mart.feedback_blocked`, `mart.verdict` |

Custom checks include:
- **Each fault has a best fix:** every fault state has at least one "best" solution in the playbook.
- **Faults differ from healthy:** every fault's sensor signature differs from the healthy baseline.
- **Playbook matches the data:** this check caught that the original playbook clue for excess grease (rising temperature) was wrong. In the data, a-RMS rises instead.
- **Feedback has real evidence:** every feedback line cites a real event or reading.
- **Outside facts have real sources:** every outside fact cites a real Telem source.

To see the lineage:

```bash
bruin lineage pipeline/assets/mart/verdict.sql
```

## Run it

You need [uv](https://docs.astral.sh/uv/) and the [Bruin CLI](https://getbruin.com).

```bash
cp .env.example .env          # then paste your Anthropic and Telem keys
mkdir -p logs
bruin run pipeline            # builds shiftcheck.duckdb from the CSVs
uv run uvicorn backend.app:app --port 8765
```

Open http://localhost:8765. Without API keys the app still runs: the colleagues fall back to scripted lines and Telem is skipped.

## Sponsor tools

| Tool | Used for |
|---|---|
| **Bruin** | The whole data layer: ingest, staging, baseline, scenario timelines, scoring, evidence-checked feedback, verdict, quality checks, lineage |
| **Telem** | Web search across several providers for expert sources that back the "outside fact" feedback lines |
| **Claude (Anthropic API)** | Dialogue for Marco, Dana and Frank, the agents' huddle, and end-of-shift feedback |

## Data

Bearing vibration metrics: Zenodo record [7589904](https://zenodo.org/records/7589904), International Hellenic University.
- **Signals:** V-RMS, a-RMS, a-Peak, Crest and Temperature, one reading every 2 minutes.
- **Test rig:** a 6204 2RS bearing, a 0.75 kW 1450 rpm motor and an i=80 reducer.
- **States:**
  - 1 = sealed with the recommended grease (healthy)
  - 2 = unsealed, no grease
  - 3 = unsealed, excess grease

The record doesn't state a license. It's credited here, and all rights stay with the authors.

## Honest limits

- **Prototype.** The machine is a 2.5D drawing, not a simulator. After a correct fix, the replay switches back to healthy readings.
- **One trainee at a time.** Sessions live in memory, and Bruin reruns the whole pipeline at the end of each shift (about 1 second, plus Claude and Telem calls, about 13 seconds in total).
- **Fixed scoring rules.** The rules are deliberately simple and readable SQL, not a validated assessment model.
- **Two fault scenarios**, both from one test rig.
