---
description: "OMC `$autoresearch` reimplementation — stateful single-mission improvement loop (markdown decision log + max-runtime stop)"
---

# /autoresearch-loop

First action: `Read ~/.claude/commands/_shared/preamble.md` and apply all its rules. Korean output, .omc/ path discipline, cancel/context guards, external-plugin policy.

This command is a faithful local reimplementation of OMC `skills/autoresearch/SKILL.md`.

**Core contract** (preserved verbatim from upstream):
- Single mission only (v1 — multi-mission orchestration forbidden).
- Evaluator output MUST be JSON `{"pass": bool, "score"?: number}`.
- Non-passing iterations do NOT stop the loop.
- Stop conditions are explicit and bounded: `--max-runtime` is the primary stop hook.

## Pre-flight (mandatory first output)

1. **Argument parsing** (`$ARGUMENTS`):
   - `--mission <path>` — mission spec file (deep-interview spec works). Default: most recent `.omc/specs/deep-interview-*.md` + user confirm.
   - `--evaluator "<command>"` — shell command that exits 0 and prints JSON to stdout. Default: `.omc/autoresearch/<slug>/evaluator.json` → `command` key. If neither, ask user.
   - `--max-runtime <duration>` — e.g. `30m`, `2h`, `6h`. Default `2h`. Hard stop when elapsed.
   - `--max-iterations <N>` — default 50. OR-condition with max-runtime.
   - `--mission-dir <path>` — default `.omc/autoresearch/<mission-slug>/`.
   - `--resume <run-id>` — resume an existing run from its last iteration.

2. Apply preamble's session-ID resolution.

3. **Mission slug**: from mission filename, strip prefix and `.md`, kebab-case → `MISSION_SLUG`.

4. **Run ID**: if no `--resume`, generate new run: `RUN_ID = <ISO-8601-compact>-<random4>` (e.g., `20260522T103045Z-a3f7`).

5. **User-visible start message**:

   ```
   /autoresearch-loop 시작
   - Mission: {mission_path}
   - Mission slug: {MISSION_SLUG}
   - Run ID: {RUN_ID}
   - Evaluator: {command} (exit code + JSON 검증)
   - Max runtime: {duration} (hard stop)
   - Max iterations: {N}
   - 작업 디렉터리: .omc/autoresearch/{MISSION_SLUG}/runs/{RUN_ID}/
   ```

---

## Phase 0: Contract Verification

**Evaluator verification** (single dry-run):

1. Bash: execute evaluator command, capture stdout.
2. Parse stdout as JSON. Validate:
   - Required key: `pass` (boolean).
   - Optional key: `score` (number).
   - On parse failure or missing `pass`, emit error and abort:
     > Evaluator 가 contract 를 위반했습니다. stdout 에 `{"pass": bool, "score"?: number}` JSON 만 출력해야 합니다. 실제 출력:
     > ```
     > {captured stdout}
     > ```
     > 진행을 중단합니다. evaluator 를 수정한 뒤 재시도하세요.

3. If exit code 0/non-zero contradicts `pass` (e.g., exit 1 but `pass: true`), warn:
   > Evaluator exit code ({n}) 와 pass 값 ({bool}) 이 모순됩니다. exit code 는 무시하고 JSON 의 pass 값만 사용합니다.

**Mission verification**: Read mission file. Recommended sections:
- Goal / Mission Statement
- Success Criteria (how evaluator judges pass)
- Constraints
- Out of Scope

On missing items, warn and proceed (mission is user-provided, trust as-is).

---

## Phase 1: Run Initialization

1. `Bash: mkdir -p .omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}/evaluations`.

2. **Write mission.md** (only on non-resume): copy mission file to `.omc/autoresearch/${MISSION_SLUG}/mission.md` (if exists, compare timestamps and confirm with user before overwriting).

3. **Write evaluator.json**:
   ```json
   {
     "command": "<evaluator command>",
     "command_hash": "<sha256 of command string>",
     "first_recorded": "<ISO>",
     "dry_run_result": <parsed JSON from Phase 0>
   }
   ```
   Persist to `.omc/autoresearch/${MISSION_SLUG}/evaluator.json` (on resume, compare hash — if different, confirm change with user).

4. **State file**: `.omc/state/sessions/${SESSION_ID}/autoresearch-${MISSION_SLUG}-${RUN_ID}.json`:

   ```json
   {
     "active": true,
     "current_phase": "autoresearch-loop",
     "state": {
       "mission_slug": "${MISSION_SLUG}",
       "run_id": "${RUN_ID}",
       "mission_path": ".omc/autoresearch/${MISSION_SLUG}/mission.md",
       "evaluator_path": ".omc/autoresearch/${MISSION_SLUG}/evaluator.json",
       "run_dir": ".omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}",
       "started_at": "<ISO>",
       "max_runtime_seconds": <converted>,
       "deadline_at": "<ISO start + max_runtime>",
       "max_iterations": <N>,
       "iteration_count": 0,
       "passes": 0,
       "failures": 0,
       "last_evaluation": null,
       "stop_reason": null
     }
   }
   ```

5. **Decision-log header**: `.omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}/decision-log.md`:

   ```markdown
   # Autoresearch Decision Log

   - Mission: ${MISSION_SLUG}
   - Run: ${RUN_ID}
   - Started: <ISO>
   - Deadline: <ISO>
   - Evaluator: `<command>`

   ---
   ```

---

## Phase 2: Iteration Loop

Start `iteration_count = 1`. Repeat until any stop condition is met:
- Current time ≥ `deadline_at` (max-runtime reached)
- `iteration_count > max_iterations`
- User says "취소" / "stop" / "중단"
- Explicit terminal condition recorded (e.g., 5 consecutive evaluator passes + user declined to continue)

### Per iteration:

#### 2a. Experiment / Change Cycle

`Task(subagent_type="general-purpose", description="Autoresearch experiment iter ${N}", prompt=<experiment_prompt>)`:

> You are the autoresearch experiment agent. Respond in Korean. This iteration's goal: perform exactly ONE experiment/change that improves evaluator score for the mission.
>
> Mission:
> ```
> {mission.md content, prompt-safe if oversized}
> ```
>
> Evaluator command:
> ```
> {evaluator command}
> ```
>
> Last iteration ({N-1}) result:
> ```json
> {state.last_evaluation}
> ```
>
> Recent decision log (last 5 entries):
> ```markdown
> {decision-log.md tail}
> ```
>
> Procedure:
> 1. Analyze current state and last result. Form ONE hypothesis: "Changing X will improve score by Y."
> 2. Make the smallest change that tests the hypothesis (code/config/docs). No large refactors or bundled changes.
> 3. Summarize modified files and intent in 1–3 sentences.
> 4. End output with this JSON block (single line, no code fence):
>    ```
>    AUTORESEARCH_REPORT_BEGIN
>    {"hypothesis": "...", "change_summary": "...", "files_modified": [...], "expected_score_delta": <number or null>}
>    AUTORESEARCH_REPORT_END
>    ```

Parse JSON between `AUTORESEARCH_REPORT_BEGIN ... AUTORESEARCH_REPORT_END`. On missing/parse failure, substitute empty object and log warning.

#### 2b. Evaluator Execution

Bash: execute evaluator command. Capture stdout, parse JSON:

```json
{"pass": bool, "score"?: number}
```

On parse failure:
- Retry once (transient failure tolerance).
- On second failure: record this iteration's evaluation as `{"pass": false, "error": "evaluator_parse_failed", "raw_stdout": "..."}` and proceed (loop does not stop).

#### 2c. Result Persistence

1. **Machine-readable**: `.omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}/evaluations/iteration-{NNNN}.json`:

   ```json
   {
     "iteration": N,
     "timestamp": "<ISO>",
     "experiment": {
       "hypothesis": "...",
       "change_summary": "...",
       "files_modified": [...],
       "expected_score_delta": <number or null>
     },
     "evaluation": {
       "pass": bool,
       "score": <number or null>,
       "raw_stdout": "..."
     },
     "delta_score": <current_score - prev_score, or null>
   }
   ```

   `iteration-{NNNN}` = 4-digit zero-pad (e.g., `iteration-0001`, `iteration-0042`).

2. **Human-readable decision log**: append to same dir's `decision-log.md`:

   ```markdown
   ## Iteration {N} — <ISO>

   - **Hypothesis**: ...
   - **Change**: ... ({files_modified count} files)
   - **Evaluation**: pass={bool}, score={number or "N/A"}, delta={delta_score or "N/A"}
   - **Files**: {comma-separated paths}
   - **Verdict**: {KEEP|REVERT|INCONCLUSIVE based on delta_score}

   ```

3. **State JSON update**:
   - `iteration_count = N`
   - `passes += pass ? 1 : 0`
   - `failures += pass ? 0 : 1`
   - `last_evaluation = <evaluation obj>`

#### 2d. User Progress Report (every 3 iterations OR on first pass)

Emit short progress to user:

```
Iteration {N}/{max_iter} (경과 {elapsed} / 마감 {remaining})
- Pass: {passes} | Fail: {failures} | 마지막 score: {score}
- 마지막 가설: "{hypothesis}"
- Verdict: {KEEP|REVERT|INCONCLUSIVE}
```

#### 2e. Stop Condition Check

- **Deadline reached** → Phase 3 immediately. `stop_reason = "max_runtime_reached"`.
- **Max iterations reached** → Phase 3 immediately. `stop_reason = "max_iterations_reached"`.
- **5 consecutive passes**: `AskUserQuestion` "5회 연속 pass — 종료할까요, 계속 정제할까요?". On end-choice → `stop_reason = "user_satisfied"`.
- **User cancel**: `stop_reason = "user_cancelled"`.

If no stop condition met → `iteration_count += 1`, return to Phase 2 start.

---

## Phase 3: Termination + Summary

1. State JSON: `active: false`, `stop_reason`, `completed_at` recorded.

2. **Summary report**: `.omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}/summary.md`:

   ```markdown
   # Autoresearch Run Summary

   - Run ID: ${RUN_ID}
   - Mission: ${MISSION_SLUG}
   - Duration: {elapsed}
   - Total iterations: {N}
   - Passes: {passes}
   - Failures: {failures}
   - Stop reason: {stop_reason}
   - Best iteration: #{best_N} (score={best_score})

   ## Best Iteration
   - Hypothesis: ...
   - Change: ...
   - Files: ...

   ## All Iterations (overview)
   | Iter | Pass | Score | Delta | Verdict |
   |------|------|-------|-------|---------|
   | 1 | ✓/✗ | ... | ... | ... |
   | ... |

   ## 다음 단계 권장
   - Best iteration 의 변경을 채택할지 검토: `cat evaluations/iteration-{best_N}.json`
   - 결정 로그 정독: `cat decision-log.md`
   - 추가 run: `/autoresearch-loop --mission ${mission_path} --evaluator "..." --max-runtime 2h`
   - 주기적 재실행: `/loop 1d /autoresearch-loop --mission ${mission_path} --evaluator "..."`
   ```

3. **Final user output**:

   ```
   /autoresearch-loop 완료
   - Run: ${RUN_ID}
   - 종료 사유: {stop_reason}
   - Iterations: {N} (pass {passes}, fail {failures})
   - Best score: {best_score} @ iteration #{best_N}
   - Summary: .omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}/summary.md
   - Decision log: .omc/autoresearch/${MISSION_SLUG}/runs/${RUN_ID}/decision-log.md
   ```

---

## Cron / Periodic Re-execution Integration

Upstream recommends "Claude Code native cron" integration. Local equivalent: built-in `/loop` or `/schedule`:

- **In-session periodic**: `/loop 1h /autoresearch-loop --mission ${path} --evaluator "..." --max-runtime 45m` — start a 45-min run every hour.
- **Out-of-session cron**: `/schedule` skill registers a remote routine (`/schedule create --cron "0 */6 * * *" --prompt "/autoresearch-loop --mission ${path} --evaluator '...'"`).

Recommended cron policy (upstream contract preserved):
- One mission per schedule.
- Preserve mission/evaluator contract (new runs append with new run-id; do NOT overwrite prior evaluations).
- Only use new `mission_slug` when mission or evaluator changes.

---

## Guardrails

- All Read/Write inside `$CWD/.omc/autoresearch/` + `$CWD/.omc/state/sessions/${SESSION_ID}/` (preamble enforced). Other file modifications limited to experiment agent (Phase 2a), bounded to mission scope.
- NEVER directly inject user input into the shell for evaluator command — Phase 0 dry-run prints the full command for user review.
- If evaluator command contains mutation operations (rm, drop, push, etc.), warn + confirm with user.
- Phase 2a experiment agent touching out-of-scope files (`.git/`, `~/.ssh/`, other project dirs) → immediate stop + reject. Experiments restricted to mission's working scope.
- 5 consecutive evaluator parse failures → force terminate (infinite loop prevention), `stop_reason = "evaluator_persistent_failure"`.
- Cancel handling per preamble (jumps to Phase 3).
- Multi-mission orchestration forbidden (v1 contract). If another mission's `/autoresearch-loop` is already running, notify user and ask which to stop.

---

## Verification

- After invocation, `.omc/autoresearch/${MISSION_SLUG}/mission.md` and `evaluator.json` exist.
- Each iteration writes `runs/${RUN_ID}/evaluations/iteration-NNNN.json` and appends `decision-log.md`.
- If evaluator violates `{"pass": bool}` contract → immediate error stop.
- Non-passing iteration does NOT stop the loop (advances to next iteration).
- On max-runtime reached → stops precisely with `stop_reason = "max_runtime_reached"`.
- On termination, `summary.md` and state JSON `active: false` are both recorded.
- Multi-mission concurrent run → warning is emitted.
