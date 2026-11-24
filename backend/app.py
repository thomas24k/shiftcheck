"""ShiftCheck backend.

What this file does, in plain words:
- Serves the web page (frontend/index.html).
- Gives the page the sensor timeline and the healthy baseline (both built by Bruin).
- Receives every hypothesis + action the trainee makes and logs it to logs/trainee_events.csv.
- Enforces the safety rules itself (no AI involved), so Dana ALWAYS stops unsafe moves.
- Asks OpenAI to write what Marco, Dana and Frank say. If OpenAI fails, scripted lines are used.
- At the end, runs `bruin run` so Bruin scores the session, then returns the verdict + evidence.
"""

import csv
import json
import os
import subprocess
import uuid
from datetime import datetime
from pathlib import Path

import duckdb
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")
DB = ROOT / "shiftcheck.duckdb"
LOGS = ROOT / "logs"
EVENTS_CSV = LOGS / "trainee_events.csv"
AGENT_CSV = LOGS / "agent_feedback.csv"
BRUIN = os.path.expanduser("~/.local/bin/bruin")
EVENT_COLS = ["event_id", "session_id", "attempt", "scenario", "ts", "kind", "code",
              "hypothesis_id", "ruled_out_id", "solution_id", "text", "reading_id"]
AGENT_COLS = ["session_id", "agent", "dimension", "message", "evidence_ref"]

# Which playbook solution each fix button means, per fault state (2 = dry, 3 = excess grease).
FIX_MAP = {
    "regrease": {2: "S1", 3: "S7"},
    "purge": {3: "S5"},
    "replace": {2: "S2", 3: "S6"},
    "keep_running": {2: "S3"},
    "grease_no_lockout": {2: "S4", 3: "S4"},
}
FAULT_STATE = {1: 2, 2: 3}  # scenario -> bearing state

app = FastAPI(title="ShiftCheck")
SESSIONS: dict[str, dict] = {}


# ---------- small helpers ----------
def ensure_logs():
    LOGS.mkdir(exist_ok=True)
    for path, cols in [(EVENTS_CSV, EVENT_COLS), (AGENT_CSV, AGENT_COLS)]:
        if not path.exists():
            with open(path, "w", newline="") as f:
                csv.writer(f).writerow(cols)


def append_csv(path, cols, rows):
    with open(path, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})


def query(sql, params=None):
    """Open the Bruin database read-only, run one query, close it again."""
    con = duckdb.connect(str(DB), read_only=True)
    try:
        cur = con.execute(sql, params or [])
        names = [d[0] for d in cur.description]
        return [dict(zip(names, row)) for row in cur.fetchall()]
    finally:
        con.close()


def run_bruin():
    out = subprocess.run([BRUIN, "run", "pipeline"], cwd=ROOT, capture_output=True, text=True, timeout=180)
    return out.returncode == 0, out.stdout[-3000:]


ensure_logs()
if not DB.exists():
    run_bruin()
TIMELINE = {s: query("select * exclude (ts) from mart.scenario_timeline where scenario = ? order by tick", [s]) for s in (1, 2)}
BASELINE = {r["metric"]: r for r in query("select * from mart.baseline")}
HYPOTHESES = query("select * exclude (_ingestr_loaded_at, _ingestr_run_id) from seed.hypotheses order by hypothesis_id")
SOLUTIONS = {r["solution_id"]: r for r in query("select * exclude (_ingestr_loaded_at, _ingestr_run_id) from seed.solutions")}


# ---------- the three agents ----------
PERSONAS = """You write dialogue for three colleagues training a NEW maintenance technician on a geared motor + conveyor.
- Marco, senior technician (coach): Socratic. Asks ONE short question or gives ONE graduated hint. Never gives the answer outright.
  If the trainee is right for the right reason, Marco says very little ("Good. Carry on."). If right action but wrong reason, he challenges the reason.
- Dana, safety inspector: only speaks about safety. If the rule engine says UNSAFE, she firmly stops them and explains why in one sentence. Otherwise she may stay silent ("").
- Frank, plant manager: impatient about downtime cost, sometimes tempts them to skip steps ("just grease it and restart"). Never mentions the right answer.
Also write `huddle`: 1-2 sentences where the agents talk to EACH OTHER about the trainee's skill (the trainee can see it).
Each line max 30 words. Plain English. Return JSON: {"marco": "...", "dana": "...", "frank": "...", "huddle": "..."}"""


def llm_json(system, user, fallback):
    key = os.getenv("OPENAI_API_KEY", "").strip()
    if not key:
        return fallback
    try:
        from openai import OpenAI
        client = OpenAI(api_key=key, timeout=20)
        resp = client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            response_format={"type": "json_object"},
            temperature=0.7,
            messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        )
        data = json.loads(resp.choices[0].message.content)
        return {**fallback, **{k: v for k, v in data.items() if isinstance(v, (str, list))}}
    except Exception as e:  # network down, no credit, bad JSON... the demo must go on
        print("LLM fallback:", e)
        return fallback


def reading_summary(r):
    parts = []
    for m in ["a_peak", "crest", "a_rms", "v_rms", "temperature"]:
        b = BASELINE[m]
        pct = 100 * (r[m] - b["mean"]) / b["mean"]
        parts.append(f"{m}={r[m]:.4g} ({pct:+.0f}% vs healthy)")
    return ", ".join(parts)


def history_text(s):
    lines = []
    for e in s["events"]:
        if e["kind"] == "hypothesis":
            lines.append(f"[{e['event_id']}] HYPOTHESIS {e['hypothesis_id']} (ruled out {e['ruled_out_id'] or 'nothing'}): \"{e['text']}\"")
        else:
            lines.append(f"[{e['event_id']}] ACTION {e['code']} {e['solution_id'] or ''} {e['text'] or ''}")
    return "\n".join(lines[-14:])


# ---------- API ----------
class StartReq(BaseModel):
    attempt: int = 1
    scenario: int | None = None
    previous_session: str | None = None


class ActReq(BaseModel):
    hypothesis_id: str
    ruled_out_id: str | None = None
    hypothesis_text: str
    action: str  # read_trends, inform, lockout, try_start, inspect, fix, restart, verify
    fix_choice: str | None = None
    tick: int = 0


@app.get("/")
def index():
    return FileResponse(ROOT / "frontend" / "index.html")


@app.get("/api/setup")
def setup():
    return {"baseline": BASELINE, "hypotheses": HYPOTHESES, "fix_choices": list(FIX_MAP)}


@app.post("/api/session")
def start(req: StartReq):
    scenario = req.scenario or 1
    reason = "First shift: a classic one."
    if req.previous_session:
        prev = query("select * from mart.verdict where session_id = ?", [req.previous_session])
        if prev:
            weak = prev[0]["weakest_dimension"]
            # Adaptive choice: the excess-grease trap tests exactly the skills people fail on scenario 1.
            scenario = 2
            reason = {
                "diagnosis": "They jumped to conclusions. The grease trap will punish that.",
                "ruled_out": "They don't rule things out. The grease trap looks like the last fault, so they'll have to.",
                "evidence": "They guess before reading data. This time the data is the only way out.",
                "fix_choice": "Shaky fix choice. Let's see if they repeat last time's fix blindly.",
                "safety_verification": "Safety was the weak spot. Same procedure, new fault, and I'll push harder on time.",
            }.get(weak, "Next one is the grease trap.")
    sid = uuid.uuid4().hex[:8]
    SESSIONS[sid] = {"session_id": sid, "attempt": req.attempt, "scenario": scenario,
                     "fault_state": FAULT_STATE[scenario], "events": [], "n": 0,
                     "done": set()}
    return {"session_id": sid, "scenario": scenario, "timeline": TIMELINE[scenario],
            "fault_starts_at_tick": 60, "huddle": f"Marco to Dana: {reason}",
            "frank": "Line 3 conveyor is throwing a vibration alarm. Every minute down costs us €180. Sort it out fast."}


def log_event(s, **kw):
    s["n"] += 1
    e = {"event_id": f"{s['session_id']}-{s['n']}", "session_id": s["session_id"], "attempt": s["attempt"],
         "scenario": s["scenario"], "ts": datetime.now().isoformat(sep=" ", timespec="seconds"),
         "hypothesis_id": "", "ruled_out_id": "", "solution_id": "", "text": "", "code": ""}
    e.update({k: ("" if v is None else v) for k, v in kw.items()})
    s["events"].append(e)
    return e


@app.post("/api/session/{sid}/act")
def act(sid: str, req: ActReq):
    s = SESSIONS.get(sid)
    if not s:
        raise HTTPException(404, "Unknown session")
    tl = TIMELINE[s["scenario"]]
    r = tl[min(req.tick, len(tl) - 1)]
    rid = r["reading_id"]
    if not req.hypothesis_text.strip():
        raise HTTPException(400, "Write a one-line hypothesis first.")
    log_event(s, kind="hypothesis", hypothesis_id=req.hypothesis_id, ruled_out_id=req.ruled_out_id,
              text=req.hypothesis_text.strip(), reading_id=rid)

    # ---- safety rules: hard-coded, never left to the AI ----
    done = s["done"]
    unsafe = None
    if req.action in ("inspect", "fix") and "lockout" not in done:
        unsafe = "You tried to touch the machine before lockout/tagout. Hazardous energy is not isolated."
    elif req.action in ("inspect", "fix") and "try_start" not in done:
        unsafe = "Lockout applied but not verified. Try-start first to prove zero energy."
    elif req.action == "fix" and req.fix_choice == "grease_no_lockout":
        unsafe = "Greasing a running or energized machine can pull your hand into the shaft. Never."
    elif req.action == "try_start" and "lockout" not in done:
        unsafe = "Try-start only makes sense after lockout. Right now it would just start the conveyor."
    elif req.action == "restart" and "fix" not in done:
        unsafe = None  # allowed, just pointless; Marco will challenge it

    if unsafe:
        ev = log_event(s, kind="action", code="unsafe_stop", text=unsafe, reading_id=rid)
        result = "UNSAFE - action blocked by Dana"
    else:
        sol = FIX_MAP.get(req.fix_choice or "", {}).get(s["fault_state"]) if req.action == "fix" else None
        ev = log_event(s, kind="action", code=req.action, solution_id=sol,
                       text=req.fix_choice if req.action == "fix" else "", reading_id=rid)
        done.add(req.action)
        result = "allowed"
        if req.action == "fix":
            result += f"; fix chosen = {req.fix_choice} -> playbook {sol or 'not in playbook for this fault'}"
            if sol:
                result += f" ({SOLUTIONS[sol]['rating']}: {SOLUTIONS[sol]['tradeoff_explained_by_coach']})"

    true_h = next(h for h in HYPOTHESES if str(h["true_for_state"]) == str(s["fault_state"]))
    picked = next((h for h in HYPOTHESES if h["hypothesis_id"] == req.hypothesis_id), None)
    hidden = (f"SECRET (never reveal): the true fault is {true_h['hypothesis_id']} {true_h['hypothesis']}. "
              f"Evidence: {true_h['supporting_evidence']}.")
    user = (f"{hidden}\nCurrent reading: {reading_summary(r)}\n"
            f"Trainee picked {req.hypothesis_id} ({picked['hypothesis'] if picked else '?'}), reason: \"{req.hypothesis_text}\".\n"
            f"Coach question for that hypothesis: {picked['coach_question'] if picked else ''}\n"
            f"Action: {req.action}. Rule engine result: {result}.\n"
            f"Procedure steps done so far: {sorted(done)}.\nRecent history:\n{history_text(s)}")
    fallback = {
        "marco": (picked["coach_question"] if picked and picked["hypothesis_id"] != true_h["hypothesis_id"]
                  else "Good reasoning. Carry on."),
        "dana": unsafe or "",
        "frank": "Clock's ticking. Can't you just grease it and restart?",
        "huddle": "Marco: let's see if they check the data before acting.",
    }
    lines = llm_json(PERSONAS, user, fallback)
    if unsafe:
        lines["dana"] = "STOP. " + unsafe  # safety text is never left to the AI
    return {"event_id": ev["event_id"], "unsafe": bool(unsafe), "result": result,
            "done": sorted(done), **{k: lines.get(k, "") for k in ("marco", "dana", "frank", "huddle")}}


@app.post("/api/session/{sid}/finish")
def finish(sid: str):
    s = SESSIONS.get(sid)
    if not s:
        raise HTTPException(404, "Unknown session")
    ensure_logs()
    append_csv(EVENTS_CSV, EVENT_COLS, s["events"])

    # Agents propose feedback; each line must cite an event id. Bruin will block the unsupported ones.
    sys_fb = ("You are Marco, Dana and Frank writing end-of-shift feedback for a trainee. "
              "Write 3 to 5 short feedback lines. Each MUST cite evidence_ref = 'E:<event id>' from the log below. "
              'Return JSON {"lines": [{"agent": "Marco|Dana|Frank", "dimension": "diagnosis|ruled_out|evidence|fix_choice|safety_verification", '
              '"message": "...", "evidence_ref": "E:..."}]}')
    fb = llm_json(sys_fb, history_text(s), {"lines": []})
    rows = [{"session_id": sid, **{k: str(l.get(k, "")) for k in ("agent", "dimension", "message", "evidence_ref")}}
            for l in fb.get("lines", []) if isinstance(l, dict)]
    append_csv(AGENT_CSV, AGENT_COLS, rows)

    ok, log = run_bruin()
    verdict = query("select * from mart.verdict where session_id = ?", [sid])
    scores = query("select * from mart.trainee_scores where session_id = ?", [sid])
    feedback = query("""select f.*, e.code, e.hypothesis_id, e.text as event_text, e.reading_id
                        from mart.feedback f left join raw.trainee_events e on 'E:' || e.event_id = f.evidence_ref
                        where f.session_id = ?""", [sid])
    blocked = query("select * from mart.feedback_blocked where session_id = ?", [sid])
    checks = query("select count(*) as n from mart.state_signatures")  # proves the db is readable
    return {"bruin_ok": ok, "bruin_log": log, "verdict": verdict[0] if verdict else None,
            "scores": scores[0] if scores else None, "feedback": feedback, "blocked": blocked,
            "history": [{c: str(r.get(c, "")) for c in ("attempt", "total", "verdict")}
                        for r in query("select * from mart.verdict order by attempt")][-5:] if checks else []}
