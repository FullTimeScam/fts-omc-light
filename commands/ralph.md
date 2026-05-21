---
description: "OMC `$ralph` port — PRD-driven 8-phase loop (per-story implement → verify → reviewer → deslop)"
---

# /ralph

First action: `Read ~/.claude/commands/_shared/preamble.md` and apply all its rules. Korean output, .omc/ path discipline, cancel/context guards, external-plugin policy. Local port removes upstream OMC's Stop-hook / MCP / `state_write` dependencies — replaced by Claude Code built-ins and local JSON files.

## Pre-flight (mandatory first output)

1. **Isolation recommendation**: emit this notice:

   > ⚠️ Ralph는 코드를 자동으로 작성·수정합니다. 운영 환경에 영향을 줄 수 있으니 **격리된 git worktree** 또는 별도 디렉터리에서 실행을 권장합니다. 현재 디렉터리: `$CWD`

   Then `AskUserQuestion` `[현재 디렉터리에서 진행, 새 worktree 만들기 안내, 취소]`.
   - "새 worktree 만들기 안내" → show this command and exit:
     ```
     git worktree add -b ralph-$(date +%Y%m%d-%H%M%S) ../ralph-isolated
     cd ../ralph-isolated
     /ralph "<원래 인수>"
     ```
   - "취소" → exit immediately.
   - "진행" → continue.

2. **Argument parsing** (`$ARGUMENTS`):
   - `--no-deslop` → `deslop=false` (default `true`, matches upstream)
   - `--critic=architect|critic|codex` → `critic_mode` (default `architect`)
   - `--max-iterations=N` → `MAX_ITER` (default `30`)
   - `--auto` → suppress /goal pairing notice (user already in /goal)
   - Remaining text → `TASK_DESCRIPTION`

3. Apply preamble's session-ID resolution.

4. **/goal pairing notice**: if `--auto` not set and prd.json is being newly created, emit:

   > Ralph는 한 번 호출하면 한 사이클을 실행합니다. 모든 user story가 완료될 때까지 **자동 반복**하려면 이 커맨드를 끝낸 뒤 아래 두 줄을 순서대로 입력하세요.
   >
   > ```
   > /goal "prd.json의 모든 user story가 passes=true이고 reviewer 승인 + deslop 통과"
   > /ralph "{TASK_DESCRIPTION}" --auto
   > ```
   >
   > `/goal` 이 매 turn 종료 조건을 평가하고 거짓이면 다음 turn 에 `/ralph` 를 자동 재호출합니다. 참이 되면 자동 종료.

---

## Phase 1: PRD Setup

`PRD_PATH = .omc/state/sessions/${SESSION_ID}/prd.json`.

1. Check existence: `Bash: test -f "$PRD_PATH"`.

### Case A: New — interactive collection

2. **Parent dir**: `Bash: mkdir -p ".omc/state/sessions/${SESSION_ID}"`.

3. **Collect user stories** via repeated `AskUserQuestion`:

   First prompt:
   > 작업을 user story 단위로 쪼개겠습니다. 첫 번째 story 제목을 입력하세요. (한 줄, 예: "사용자 로그인 API 구현")

   Per story:
   - Title (free response)
   - Priority: `[high, medium, low]`
   - Acceptance criteria: at least 2, verifiable concrete only. **Forbidden phrases**: "잘 동작한다", "사용자가 만족한다", "직관적이다". **Required style**: "GET /api/login 호출 시 200 응답", "테스트 `test_login` 통과", "ruff 0 에러".

   After each story → `AskUserQuestion` `[다음 story 추가, 모두 입력 완료]`.

   **Scaffold rejection**: if generic "잘 동작한다"-class criteria are entered, re-ask until replaced with task-specific criteria (OMC `Step 1` principle).

4. **Write prd.json**:

   ```json
   {
     "version": "1.0",
     "session_id": "${SESSION_ID}",
     "task_description": "${TASK_DESCRIPTION}",
     "created_at": "<now ISO>",
     "deslop": <true|false>,
     "critic_mode": "<architect|critic|codex>",
     "max_iterations": <MAX_ITER>,
     "iteration_count": 0,
     "stories": [
       {
         "id": "S1",
         "title": "...",
         "priority": "high|medium|low",
         "acceptance_criteria": ["...", "..."],
         "passes": false,
         "evidence": [],
         "attempts": 0,
         "last_attempt_at": null
       }
     ],
     "reviewer_status": {
       "approved": false,
       "round": 0,
       "last_verdict": null,
       "last_review_at": null
     },
     "deslop_status": {
       "completed": false,
       "last_run_at": null
     },
     "completed": false
   }
   ```

5. **Initialize progress.txt**: Write `.omc/state/sessions/${SESSION_ID}/progress.txt` with header only.

### Case B: Existing — load + validate

2. Read `PRD_PATH`.
3. If `iteration_count ≥ max_iterations`, emit and exit:
   > ⚠️ 반복 횟수가 상한({max_iterations})에 도달했습니다. 진행 상황을 검토하세요. 강제 종료합니다.

4. If `iteration_count` is a non-zero multiple of 5, user checkpoint:
   > 반복 {iteration_count}회차입니다. 진행 상황 요약: {완료 story수}/{전체 story수}. 계속할까요?

   `AskUserQuestion` `[계속, 일시 중단, 강제 종료]`. "일시 중단" = leave prd.json + exit, "강제 종료" = mark `completed=true` + exit.

5. **Context guard** per preamble.

---

## Phase 2: Pick Next Story

Sort prd.json `stories` where `passes=false` by **priority (high→medium→low) → registration order**. First item = `CURRENT_STORY`.

All `passes=true` → jump to Phase 6 (reviewer).

---

## Phase 3: Implement

1. **Scope judgment** from `CURRENT_STORY.acceptance_criteria` + codebase exploration:
   - **Trivial** (single file, 1–2 line change) → direct Edit/Write in this session
   - **Scoped** (2–5 files) → direct, but note before/after diff
   - **Complex** (multi-system, 5+ files, architectural) → call executor persona via `Task(subagent_type="general-purpose")`

2. **Executor persona** (Complex only):

   ```
   You are in EXECUTOR mode. Respond in Korean (summary of work). Role: implementation agent that translates spec into precise code changes.
   Principles:
   - Smallest effective diff — small precise change >> large clever change
   - Match existing codebase patterns. No unnecessary abstractions.
   - LSP 0 errors on all modified files
   - Strip console.log / TODO / debugger residues
   - On 3 failed attempts at the same issue, escalate to architect persona (stop implementing, hand over full context)
   Current story:
     - title: {CURRENT_STORY.title}
     - acceptance criteria: {CURRENT_STORY.acceptance_criteria}
   Working directory: ${CWD}
   Stay inside the change scope. Return: changed-files list + change summary + verification commands (tests/build/lint).
   ```

3. After applying changes: `CURRENT_STORY.attempts += 1`, `last_attempt_at = <now>` → write prd.json.

---

## Phase 4: Acceptance Criteria Verification

For each `CURRENT_STORY.acceptance_criteria` entry, **gather fresh evidence** (do not trust cached / remembered results).

- Code behavior: run test command via Bash (e.g., `pytest tests/test_login.py -v`, `npm test -- --testPathPattern=auth`)
- Build / typecheck: project's existing commands (`npm run typecheck`, `cargo check`)
- Lint: `ruff check`, `eslint`, project's default tooling

Append to `evidence[]`: `{criterion, command, exit_code, stdout_tail, passed}`. If any `passed=false`:

1. Analyze cause.
2. If `CURRENT_STORY.attempts < 3` → return to Phase 3 (retry).
3. If `CURRENT_STORY.attempts ≥ 3` → escalate to architect persona:

   ```
   You are in ARCHITECT mode. Respond in Korean. Role: READ-ONLY code analysis / debugging / architecture guidance.
   Principles:
   - Every finding cites file:line + actual code evidence
   - Diagnose root cause, not symptoms
   - Concrete, actionable recommendations (no vague "consider refactoring")
   - Tradeoffs explicit per recommendation
   - No Write/Edit (READ-ONLY)
   Current failure context:
     - story: {CURRENT_STORY.title}
     - attempts: {CURRENT_STORY.attempts}
     - last failure evidence: {last evidence}
   Output structure: summary → analysis (citations) → root cause → prioritized recommendations → tradeoff table → file:line refs.
   ```

   Show architect output to user, then `AskUserQuestion` `[권장안 적용해서 재시도, 이 story 보류, 중단]`.

---

## Phase 5: Mark Complete

When all acceptance criteria pass:

1. `CURRENT_STORY.passes = true`, `last_attempt_at = <now>`
2. `iteration_count += 1`
3. Write prd.json
4. Append one line to progress.txt: `[<now>] S{n} "{title}" passed (criteria: {count}, attempts: {attempts})`
5. Return to Phase 2 (pick next story).

---

## Phase 6: Reviewer Verification

Reached when all stories `passes=true`. Runs once per cycle.

**Reviewer selection**:
- `critic_mode=architect` (default): architect persona above. READ-ONLY verification.
- `critic_mode=critic`: critic persona below.
- `critic_mode=codex`: codex persona below.

**Invocation**: `Task(subagent_type="general-purpose", prompt="<selected persona + changed-files list + prd.json copy>")`.

### Critic persona

```
You are in CRITIC mode. Respond in Korean. Role: final quality gate for plans/code/analyses. Responsible for not letting defects through.
Principles:
- Every claim cross-referenced against actual codebase (file:line citations required)
- Evaluate what is *missing* (not just errors in what's present)
- Mentally simulate every task implementation
- Extract and pressure-test assumptions
- Pre-mortem + dependency audit
- Code review: security / onboarding / operator lens. Plan review: implementer / stakeholder / skeptic lens.
Severity:
- CRITICAL: execution-blocking (file:line evidence required)
- MAJOR: significant rework required (evidence required)
- MINOR: suboptimal but operational
Verdict: REJECT | REVISE | ACCEPT-WITH-RESERVATIONS | ACCEPT
Review target:
  - prd.json: {prd copy}
  - changed files: {file list}
Output: verdict + findings list (with severity) + file:line evidence + recommended actions.
```

### Codex persona

```
You are in CODEX mode. Respond in Korean. Role: Ralph verification critic. Seek simpler / faster / more maintainable alternatives.
Review:
1. Acceptance criteria satisfaction (cite evidence per criterion)
2. Optimality eval ("is there a simpler / faster / more maintainable approach achieving the same AC?")
3. Modified files + related code in full scope (side-effects, regression risk)
Verdict: ACCEPT | REJECT_WITH_BETTER_ALTERNATIVE | REVISE
Changed files: {file list}
prd.json: {prd copy}
Output: verdict + better alternative (code sketch if applicable) + regression risks.
```

### Reviewer result handling

- **ACCEPT (or ACCEPT-WITH-RESERVATIONS)**: update `reviewer_status.approved=true`, `last_verdict=ACCEPT...`, `last_review_at=<now>`. Advance to Phase 7 IMMEDIATELY (do not stop to report — OMC Step 7 boulder principle).
- **REVISE**: convert review findings to new stories (append to `stories[]`, `passes=false`), set `reviewer_status.approved=false`, `iteration_count += 1`. Return to Phase 2.
- **REJECT / REJECT_WITH_BETTER_ALTERNATIVE**: show full verdict to user, then `AskUserQuestion` `[지적 사항을 story로 추가하고 계속, 작업 중단, reviewer 변경 후 재시도]`.

---

## Phase 7: Mandatory Deslop Pass

Condition: `deslop=true` (default) AND reviewer ACCEPT just occurred.

Invocation: `Task(subagent_type="general-purpose", prompt="<deslop persona + changed-files list>")`.

### Deslop (ai-slop-cleaner) persona

```
You are the AI-SLOP-CLEANER skill. Respond in Korean (summary). Goal: remove bloat / duplication / weak abstractions in AI-generated code while preserving intended behavior.
Apply: deslop / anti-slop requests, noisy or repetitive code cleanup.
Skip: feature additions, broad redesigns.
6-step workflow:
1. Lock behavior — add regression tests before changes
2. Cleanup plan — bounded smell list within scope
3. Smell classification — duplication / dead code / unnecessary abstraction / boundary violation / missing tests
4. One smell per pass — dead code → duplication → naming → tests, verify each pass
5. Quality gates — tests green, lint/typecheck clean
6. Report — files changed, simplifications, verification status, remaining risks
Constraints:
- Deletion > addition
- Reuse existing patterns, avoid new dependencies
- Diffs small and revertible
- "Concise and evidence-dense"
Target files (this cycle's changes only): {file list}
Output: post-change diff summary + regression test results + remaining risks.
```

### Result handling

- New file changes from deslop → run Phase 7.6 (regression re-verification).
- Update `deslop_status.completed=true`, `last_run_at=<now>`.

`deslop=false` → skip both Phase 7 and 7.6, jump to Phase 8.

---

## Phase 7.6: Regression Re-verification

After deslop touched files, **re-run every story's acceptance criteria verification commands** (same as Phase 4 evidence gathering).

- All pass → Phase 8.
- Regression → append regression as new high-priority story (`priority=high`, `passes=false`), set `reviewer_status.approved=false`, `deslop_status.completed=false`, return to Phase 2.

---

## Phase 8: Completion

When all verification / deslop / regression pass:

1. `completed=true`, write prd.json.
2. Append final line to progress.txt: `[<now>] CYCLE COMPLETE — stories: {n}, reviewer: {critic_mode}, deslop: {bool}`
3. Emit to user:

   ```
   ✅ Ralph 사이클 완료.

   - 처리된 user story: {n}개 (전체 통과)
   - reviewer: {critic_mode} ACCEPT
   - deslop: {수행됨/생략됨}
   - 변경 파일: {list}
   - 상태 파일: .omc/state/sessions/${SESSION_ID}/prd.json
   - 진행 기록: .omc/state/sessions/${SESSION_ID}/progress.txt

   /goal 을 활성화했다면 이 시점에서 자동 종료됩니다.
   ```

4. If `--auto` is active, emit a single explicit termination signal line (`RALPH_DONE`) so /goal evaluator can precisely judge completion.

---

## Guardrails

- Read/Write inside `$CWD` only (preamble enforced). No `.omc/` external paths, no home dir, no other projects.
- Cancel handling per preamble (also marks prd.json `completed: false, aborted_at: <now>`).
- On authentication failure / external API 401/403, immediately stop and notify user (equivalent to OMC `persistent-mode.mjs` auth guard).
- Before processing the 5th story in a single cycle, `AskUserQuestion` checkpoint to confirm continued intent.
- Context guard per preamble.

## Verification

- After invocation, `.omc/state/sessions/${CLAUDE_SESSION_ID}/prd.json` is created/updated.
- `.omc/state/sessions/${CLAUDE_SESSION_ID}/progress.txt` contains line-level progress records.
- Reviewer personas (architect/critic/codex) respond in Korean with file:line citations.
- Deslop touches only changed-file scope (verify diff bounded).
- `--auto` + /goal combo: cycle completion correctly triggers /goal termination.
