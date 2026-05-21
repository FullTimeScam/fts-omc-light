---
description: "OMC `$team` reimplementation — built-in TeamCreate/TaskCreate/SendMessage for N parallel teammates (staged pipeline)"
---

# /team-dispatch

First action: `Read ~/.claude/commands/_shared/preamble.md` and apply all its rules. Korean output, .omc/ path discipline, cancel/context guards, external-plugin policy.

This command is a faithful reimplementation of OMC `skills/team/SKILL.md` within the security policy. Uses Claude Code built-in Team tools only (`TeamCreate`, `TaskCreate`, `TaskUpdate`, `TaskList`, `SendMessage`, `Monitor`, `TeamDelete`).

**Prerequisite**: Agent Teams must be active in-process (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: in-process` in `~/.claude/settings.json`). Re-verified in Phase 0.

## Pre-flight (mandatory first output)

1. **Agent Teams active check**: Read `~/.claude/settings.json`, verify BOTH:
   - `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (or set in shell env)
   - `teammateMode: "in-process"`

   If either missing, notify user:
   > Agent Teams 가 활성화돼 있지 않습니다. `/team-dispatch` 는 빌트인 Team 도구가 필요합니다. 다음 중 선택하세요:
   > [Agent Teams 활성화 안내, 폴백 — 병렬 Task spawn 으로 진행 (coordination 없음), 취소]

   "활성화 안내" → emit update-config skill guidance or manual setting steps and exit.

2. **Argument parsing** (`$ARGUMENTS`):
   - First positional: plan or spec file path (default: most recent `.omc/plans/plan-consensus-*.md` → `.omc/specs/deep-interview-*.md` fallback).
   - `N:agent-type` (e.g., `3:executor`, `5:debugger`) — N = worker count (1–20), agent-type = team-exec worker type. Omitted → derived from decomposition.
   - `--max-fix-loops N` (default 3) — max team-fix → exec → verify cycles after team-verify failure.
   - `--ralph` → wrap entire pipeline in ralph persistence loop (architect verify before completion on failure, restart cycle).

3. Apply preamble's session-ID resolution.

4. **Team slug**: from plan/spec filename, strip prefix and `.md` → `TEAM_SLUG`. Lowercase alphanumeric + hyphen. ≤ 40 chars.

5. **User-visible start message**:

   ```
   /team-dispatch 시작
   - Input: {plan_or_spec_path}
   - Team slug: {TEAM_SLUG}
   - Workers: {N or auto}, agent-type: {executor|...}
   - Ralph 래핑: {yes|no}
   - Max fix loops: {N}
   ```

---

## Required Tool Loading

Before phase execution, load deferred tools: `ToolSearch("select:TeamCreate,TaskCreate,TaskUpdate,TaskList,TaskGet,SendMessage,Monitor,TeamDelete")`. If any tool absent, terminate immediately (fallback mode in Phase 6).

---

## Phase 1: Input Parsing + State Init

1. Read plan/spec file. Secure sections:
   - Goal / Requirements Summary
   - Acceptance Criteria
   - Implementation Steps (if present)
   - Topology / Component split (deep-interview spec's `## Topology` or plan-consensus' RALPLAN-DR Options)

2. `Bash: mkdir -p .omc/state/sessions/${SESSION_ID} .omc/handoffs`.

3. **State file**: `.omc/state/sessions/${SESSION_ID}/team-dispatch-${TEAM_SLUG}.json`:

   ```json
   {
     "active": true,
     "current_phase": "team-plan",
     "state": {
       "team_name": "${TEAM_SLUG}",
       "input_path": "<plan or spec path>",
       "agent_count": <N or null>,
       "agent_types": "<executor|...>",
       "task": "<one-line summary from Goal>",
       "fix_loop_count": 0,
       "max_fix_loops": 3,
       "linked_ralph": false,
       "stage_history": "team-plan:<ISO>",
       "subtasks": [],
       "completion": null
     }
   }
   ```

---

## Phase 2: Decomposition (team-plan stage)

1. `Task(subagent_type="Explore", description="Team task decomposition", prompt=<decomposition_prompt>)`:

   > Read the input plan/spec and decompose into independently executable subtasks per these rules:
   >
   > 1. Each subtask scoped to **a file** or **a module** (avoid conflicts).
   > 2. Declare inter-subtask dependencies (`task_3` needs `task_1` → `blockedBy: [1]`).
   > 3. Each subtask: one-line `subject` + detailed `description` (execution + verification commands).
   > 4. 1–{N or auto-size between 2–10} subtasks. Too fine-grained → coordination overhead.
   > 5. Recommend appropriate `agent_type` per subtask (executor / debugger / designer / writer / test-engineer).
   >
   > Input:
   > ```
   > {input file content, prompt-safe summary if oversized}
   > ```
   >
   > Output: JSON array. Each element `{id, subject, description, agent_type, blocked_by}`.

2. Parse Explore result, persist as `subtasks[]` in state JSON.

3. **Handoff write**: `.omc/handoffs/team-plan.md`:

   ```markdown
   ## Handoff: team-plan → team-prd

   - **Decided**: {N}개 subtask 로 분해. 핵심 결정: {요약}
   - **Rejected**: {대안 분해 + 기각 사유}
   - **Risks**: {분해 시 식별된 위험}
   - **Files**: {예상 touched files}
   - **Remaining**: team-prd 에서 각 subtask 의 acceptance criteria 검증
   ```

4. Update state phase → `team-prd`.

---

## Phase 3: PRD Enrichment (team-prd stage)

For each subtask, verify acceptance criteria specified. For subtasks missing them, call `Task(subagent_type="general-purpose", description="PRD analyst", prompt=...)`:

> Write verifiable acceptance criteria and explicit non-goals for the subtask below. Respond in Korean.
> Subtask: {subtask json}
> Replace vague words with metrics (e.g., "fast" → "p99 < 200ms").
> Output JSON: `{acceptance_criteria: [...], non_goals: [...]}`.

Merge into each subtask in state. Write `.omc/handoffs/team-prd.md` handoff. State phase → `team-exec`.

---

## Phase 4: Team Creation (entering team-exec)

1. `TeamCreate`:

   ```json
   {
     "team_name": "${TEAM_SLUG}",
     "description": "<one-line task summary>"
   }
   ```

   Response includes `lead_agent_id`. Current session becomes `team-lead@${TEAM_SLUG}`.

2. For each subtask, `TaskCreate`:

   ```json
   {
     "subject": "<subtask.subject>",
     "description": "<subtask.description + acceptance_criteria + verification commands>",
     "activeForm": "<현재진행형 활성 폼>"
   }
   ```

3. Dependencies: for subtasks with deps, `TaskUpdate({"taskId": "N", "addBlockedBy": ["<dep_id>"]})`.

4. **Owner pre-assignment** (race-condition prevention — upstream explicit rule):
   - Worker names: `worker-1`, `worker-2`, ..., `worker-N`.
   - Round-robin assignment: `TaskUpdate({"taskId": "N", "owner": "worker-K"})`.

---

## Phase 5: Teammate Spawn (parallel)

Spawn N teammates **in parallel** (N Task tool calls in the same message). Never spawn sequentially.

Each spawn:

```json
{
  "subagent_type": "general-purpose",
  "team_name": "${TEAM_SLUG}",
  "name": "worker-K",
  "prompt": "<TEAM_WORKER_PREAMBLE + assigned task IDs>"
}
```

### TEAM_WORKER_PREAMBLE (compact)

```
You are worker "{name}" in team "{team}". Report to "team-lead".
출력은 한국어로 보고하세요.

PROTOCOL:
1. CLAIM: TaskList → pick first pending task with owner = "{name}". TaskUpdate {status: in_progress}.
2. WORK: Read/Write/Edit/Bash directly. No sub-agent spawn, no delegation.
3. COMPLETE: TaskUpdate {status: completed}.
4. REPORT: SendMessage to "team-lead": {type: "message", content: "Completed #ID: <요약>", summary: "Task #ID complete"}.
5. NEXT: TaskList re-check. More assigned → step 1. None → SendMessage "모든 할당 task 완료, 대기".
6. SHUTDOWN: on shutdown_request, respond {type: "shutdown_response", request_id: "<from request>", approve: true}.

BLOCKED: skip tasks with blockedBy until deps complete. Poll TaskList periodically.
ERRORS: on failure, SendMessage "FAILED #ID: <reason>" and leave status=in_progress for lead to reassign. Do NOT mark completed.

RULES:
- No sub-agent spawn. No Task tool.
- No orchestration slash commands (/team-dispatch, /ralph, /autopilot).
- No tmux pane/session commands.
- Absolute paths only.
- SendMessage type "message" only (no "broadcast" — too costly).

Assigned task IDs: {[K, K+N, K+2N, ...]}
```

---

## Phase 6: Monitor Loop (lead side)

1. `Monitor(team_name="${TEAM_SLUG}")` subscribes to inbound SendMessage stream.
2. Periodic `TaskList` for progress (Monitor notifies — do NOT sleep-poll).

Per inbound event:

- **task complete**: if dependent tasks exist, unblock via `TaskUpdate` `blockedBy` mutation + notify worker "task #X unblocked" via SendMessage.
- **idle**: if other pending tasks, reassign via `TaskUpdate({owner})` + SendMessage.
- **failed**: reassign failed task or retry. After 2 failures by same worker, stop assigning new tasks to it.
- **stuck worker detection**: in_progress with no messages > 5 min → SendMessage status check. > 10 min with no response → mark dead, reassign task.

### Fallback mode (Agent Teams inactive)

If Phase 0 user chose "폴백":
- Replace `TeamCreate` with N parallel `Task(subagent_type="general-purpose", ...)` spawned in the same message.
- Each Task receives its subtask + full spec context as prompt.
- No coordination. Lead manually synthesizes N returned results.
- Limitations: no dependency handling, no message-based unblocking. Independent tasks only.

---

## Phase 7: Verification (team-verify stage)

When all real tasks (non-internal) reach completed or failed:

1. **Collect results**: each worker's changed-files list + executed verification command output via SendMessage.
2. **Verifier execution**:
   - Run build + lint + tests via Bash.
   - Record results to `.omc/handoffs/team-verify.md`.
3. **Additional reviewers** (risk-based):
   - 20+ files changed OR architectural change → `Task(subagent_type="general-purpose", description="Code reviewer persona", ...)` for code-reviewer persona.
   - auth/crypto/secret changes → security-reviewer persona.

All verifier + reviewers PASS → Phase 9 (completion).
Any FAIL → Phase 8 (fix loop).

---

## Phase 8: Fix Loop (team-fix → team-exec → team-verify)

1. Derive fix tasks from verifier/reviewer rejection reasons. `TaskCreate` + owner assign for each.
2. Re-run Phase 5–7 cycle (spawning targets only new tasks).
3. Increment `fix_loop_count`. On `max_fix_loops` exceeded, force Phase 9 with status `BLOCKED`.

Update state phase per transition: `team-fix → team-exec → team-verify`, accumulate `stage_history`.

---

## Phase 9: Shutdown Protocol (BLOCKING — exact order required)

### Step 1: Completion verification
`TaskList` → all real tasks (excluding `_internal: true`) are completed or failed.

### Step 2: Send shutdown_request to each teammate

```json
{
  "type": "shutdown_request",
  "recipient": "worker-K",
  "content": "All work complete, shutting down team"
}
```

### Step 3: Wait for shutdown_response (BLOCKING)
- Per-worker timeout 30s.
- `approve: true` received → confirmed. Timeout → mark unresponsive.

### Step 4: TeamDelete (only after all workers confirmed/timed-out)

```json
{"team_name": "${TEAM_SLUG}"}
```

### Step 5: State cleanup

Update state JSON `active: false`, `completion: {status, completed_at, summary}`.

### Step 6: Final report

```
/team-dispatch 완료
- Team: ${TEAM_SLUG}
- 총 task: {total} / 완료: {completed} / 실패: {failed}
- Fix loops: {fix_loop_count} / {max_fix_loops}
- 변경 파일: {modified_files_count}
- Status: {COMPLETE | PARTIAL | BLOCKED}
- 다음 단계 (사용자 선택):
  - 결과 검토: cat .omc/handoffs/team-verify.md
  - 재시도 (실패 task 만): /team-dispatch --resume ${TEAM_SLUG}
  - PR 생성: gh pr create (현재 브랜치 기준)
```

---

## Ralph Wrapping (`--ralph`)

When `--ralph` is set, wrap the entire pipeline in `/ralph` persistence loop:

1. iteration 1 start — execute Phase 1–9.
2. Phase 7 verifier or architect rejection → increment iteration, re-enter Phase 5 (team-exec).
3. iteration exceeds hard cap (default 10) → status=`FAILED_MAX_ITER`.
4. Mark `state.linked_ralph = true`, `state.ralph_iteration = N`.

User notice:
> Ralph 모드 활성. iteration {n}/{max} 진행 중. 중단하려면 "취소" 또는 `/oh-my-claudecode:cancel` 등가로 즉시 stop 신호.

---

## Guardrails

- Read/Write restricted to `$CWD/.omc/` + `~/.claude/teams/${TEAM_SLUG}/` + `~/.claude/tasks/${TEAM_SLUG}/` (Claude Code's team-managed dirs).
- Before `TeamCreate`, check if same-slug team exists → if so, offer resume `AskUserQuestion: [기존 team 재개, 새 team 으로 진행 (slug 에 -2 suffix), 취소]`.
- `TeamDelete` ONLY after all workers shut down. Earlier invocation fails.
- Worker prompts MUST NOT contain secrets / credentials / tokens — stored in plaintext in config.json.
- Broadcast messages are expensive → never use. "message" DM type only.
- Cancel handling per preamble (also runs Phase 9 cancel path: shutdown_request → wait → TeamDelete).
- Worker spawn MUST be parallel (same-message N Task calls). Never sequential.
- `agent_count` range 1–20. > 20 requires user confirmation.

---

## Verification

- After invocation, `.omc/state/sessions/${SESSION_ID}/team-dispatch-${TEAM_SLUG}.json` is created/updated.
- `~/.claude/teams/${TEAM_SLUG}/config.json` exists after TeamCreate with members registered.
- All stage transitions recorded in `.omc/handoffs/team-{stage}.md`.
- On exit, `TeamDelete` invoked and team directory cleaned up.
- State JSON's `active: false` + `completion` object recorded at the end.
- Worker spawns verifiably parallel (one message with N Task calls) via timestamps.
- No Architect/Critic persona calls (out of scope for this command) — only worker tasks executed.
