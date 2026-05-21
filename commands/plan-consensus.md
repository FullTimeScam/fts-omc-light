---
description: "OMC `$plan --consensus` reimplementation — Planner/Architect/Critic consensus loop: spec → consensus plan (RALPLAN-DR + ADR)"
---

# /plan-consensus

First action: `Read ~/.claude/commands/_shared/preamble.md` and apply all its rules. Korean output, .omc/ path discipline, cancel/context guards, external-plugin policy (use `Task(subagent_type="general-purpose")` with English personas instead of `Skill("oh-my-claudecode:*")`).

This command is a faithful local reimplementation of OMC `skills/plan/SKILL.md` Consensus Mode within the security policy. All personas implemented as prompt-injected `Task(subagent_type="general-purpose")` calls.

## Pre-flight (mandatory first output)

1. Apply preamble's Opus recommendation (consensus loop benefits significantly from Opus).

2. **Argument parsing** (`$ARGUMENTS`):
   - First positional: spec file path (default: most recent `.omc/specs/deep-interview-*.md`).
   - `--max-iterations N` (default 5) — consensus loop hard cap.
   - `--interactive` (default false) — gate via `AskUserQuestion` at draft review and final approval.
   - `--deliberate` (default false) — high-risk mode. Forces pre-mortem (3 scenarios) + expanded test plan (unit/integration/e2e/observability). Auto-enabled when spec contains auth/security, data migration, destructive change, production incident, compliance/PII, or public API breakage patterns.
   - `--architect-provider <claude|skip>` (default claude) — `skip` omits Architect round (quality warning).
   - `--critic-provider <claude|skip>` (default claude).

3. Apply preamble's session-ID resolution.

4. **Slug**: strip `deep-interview-` or other prefix from input spec filename, drop `.md` → `SLUG`. New plan slug: `plan-consensus-${SLUG}`.

---

## Phase 0: Input Validation

1. Read spec file. On missing or corrupt → emit error and exit.
2. Verify spec contains `## Goal`, `## Constraints`, `## Acceptance Criteria`. On missing → warn user and confirm before proceeding.
3. Scan spec body for high-risk patterns → if matched, force `--deliberate` on:
   - "auth", "OAuth", "JWT", "credential", "secret", "encrypt", "password"
   - "migration", "DROP TABLE", "ALTER TABLE", "schema change"
   - "delete", "rm -rf", "destructive", "irreversible"
   - "production", "prod incident", "outage"
   - "PII", "compliance", "GDPR", "HIPAA"
   - "public API", "breaking change", "v2", "deprecation"

   On force-enable, emit one-line notice: `고위험 패턴 감지 ({matched}) → --deliberate 모드 자동 활성화`.

4. **State file**: `Bash: mkdir -p .omc/state/sessions/${SESSION_ID}`, then Write `.omc/state/sessions/${SESSION_ID}/plan-consensus-${SLUG}.json`:

   ```json
   {
     "active": true,
     "current_phase": "plan-consensus",
     "state": {
       "consensus_id": "${SESSION_ID}-${SLUG}",
       "spec_path": "<input spec path>",
       "plan_path": ".omc/plans/plan-consensus-${SLUG}.md",
       "mode": "short|deliberate",
       "interactive": true|false,
       "max_iterations": 5,
       "current_iteration": 0,
       "iterations": [],
       "status": "in_progress",
       "deliberate_triggered_by": ["matched patterns"]
     }
   }
   ```

5. **User-visible start message**:

   ```
   /plan-consensus 시작
   - Spec: {spec_path}
   - Plan 출력: .omc/plans/plan-consensus-${SLUG}.md
   - Mode: {short|deliberate}
   - Max iterations: {N}
   - Interactive: {yes|no}
   ```

---

## Phase 1: Consensus Loop

Start `current_iteration = 1`. Repeat while `current_iteration ≤ max_iterations` AND Critic has not approved.

Each iteration MUST run steps 1 → 2 → 3 → 4 **sequentially**. Never spawn Architect and Critic in parallel (upstream OMC explicit rule).

### Step 1: Planner

Iteration 1 input: full spec body + (if exists) 1 related prior plan from `.omc/plans/` + brownfield codebase context.

Iteration 2+ input: previous iteration's Planner draft + Architect review + Critic rejection + all accumulated improvement proposals.

Call `Task(subagent_type="general-purpose", description="Planner persona", prompt=<persona+context>)` with the persona prompt below:

> You are now in PLANNER persona. Respond in Korean. Based on the input spec and (if any) prior round Architect/Critic feedback, write an executable work plan.
>
> Plan MUST include:
>
> 1. **Requirements Summary** — compress spec's Goal/Constraints (2–3 sentences).
> 2. **RALPLAN-DR Summary**:
>    - **Principles** (3–5) — design principles this plan upholds.
>    - **Decision Drivers** (top 3) — key factors influencing decisions.
>    - **Viable Options** (≥2) — one-line approach + 3–5 pros / 3–5 cons each. If only one viable option remains, explicit **invalidation rationale** for rejected alternatives.
> 3. **Acceptance Criteria** — verifiable checklist (every criterion must pass "can it be judged ✓/✗?").
> 4. **Implementation Steps** — numbered steps scoped per file or component. Each cites (`file:line` or `component`).
> 5. **Risks and Mitigations** — known risks + concrete mitigations.
> 6. **Verification Steps** — commands to run on plan completion (tests/build/smoke).
>
> {if deliberate mode, also include:}
> 7. **Pre-Mortem** — 3 failure scenarios + early warning signal per scenario.
> 8. **Expanded Test Plan** — one line each for unit / integration / e2e / observability.
>
> {if iteration 2+, append:}
> Last round feedback:
> - Architect: {summary}
> - Critic rejection: {summary}
> - Improvement proposals: {list}
> Write a **revised plan** reflecting this feedback. At the end, briefly note which feedback was accepted and which was deliberately rejected (with reasons).
>
> Output format: single markdown document. Use code blocks and file references inline.

Save response as `iteration_${N}_planner.md` under `.omc/state/sessions/${SESSION_ID}/plan-consensus-${SLUG}/`.

### Step 2 (--interactive only): Draft Review Gate

If not `--interactive`, advance to Step 3 immediately.

If `--interactive`, `AskUserQuestion`:

> Iteration {N} Planner 초안 완료. RALPLAN-DR Principles/Drivers/Options 요약:
> - Principles: {list}
> - Decision Drivers: {list}
> - Top Option: {summary}
>
> 어떻게 진행할까요?

Options: `[리뷰로 진행 (Architect→Critic), 초안 수정 요청, 리뷰 건너뛰고 최종 승인으로]`.

- "초안 수정 요청" → free-text follow-up, then re-call Planner (Step 1 repeat, iteration count unchanged).
- "리뷰 건너뛰기" → jump to Step 5 (final approval).

### Step 3: Architect Review (sequential, before Critic)

Call `Task(subagent_type="general-purpose", description="Architect persona", prompt=<persona+planner_output>)`. **MUST receive this result before issuing Step 4 (Critic).** Never spawn Architect + Critic as parallel tool calls in the same message.

Persona prompt:

> You are now in ARCHITECT persona. Respond in Korean. Input is the Planner's plan draft. MUST evaluate:
>
> 1. **Steelman antithesis**: construct the strongest counter-argument against Planner's preferred option. Seriously defend "why this decision should be reversed".
> 2. **Tradeoff tension**: identify at least one meaningful trade-off (e.g., performance vs simplicity, scalability vs consistency, safety vs speed) and state which side the plan resolved it to.
> 3. **Synthesis path**: if possible, propose a third path combining Planner's option and the antithesis. If not, state "no synthesis path — keep Planner option".
> 4. **Architectural soundness check**: separation of concerns, data flow, failure boundaries, extension points, reversibility. Cite (`file:line` or `component`) per issue found.
> 5. {deliberate only} **Principle violation flagging**: list every RALPLAN-DR Principle the plan explicitly or implicitly violates.
>
> End with verdict:
> - **APPROVE** — proceed to Critic round
> - **REVISE** — specific change requests for Planner to incorporate next round
> - **REJECT** — fundamental architectural defect; restart from scratch
>
> Plan body:
> ```
> {planner_output}
> ```

Save response as `iteration_${N}_architect.md`. Record verdict in state JSON.

### Step 4: Critic Evaluation (sequential, after Architect)

Call `Task(subagent_type="general-purpose", description="Critic persona", prompt=<persona+planner_output+architect_review>)`.

Persona prompt:

> You are now in CRITIC persona. Respond in Korean. Input is the Planner's plan draft + Architect's review. MUST verify:
>
> 1. **Principle-Option consistency**: do the Plan's Principles align with the preferred Option? Cite contradictions.
> 2. **Fair alternative exploration**: are Viable Options seriously compared, or is only the preferred one explored in depth?
> 3. **Mitigation specificity**: does each risk have measurable, actionable mitigation? Vague words ("careful", "watch out") = immediate reject.
> 4. **Verifiable acceptance criteria**: is every criterion judgeable ✓/✗? Have ambiguous words ("fast", "safe") been replaced with metrics ("p99 < 200ms", "0 secret exposures")?
> 5. **Concrete verification steps**: is there a clear command + expected output combination that means "plan complete"?
> 6. {deliberate only} **Pre-mortem fidelity**: do the 3 scenarios cover meaningful failure modes? Superficial ("team misses deadline") = reject. **Expanded test plan fidelity**: does each of unit/integration/e2e/observability name concrete tools/scope/observable signals?
>
> If Architect's review raised items the Plan didn't address, also reject for those.
>
> End with verdict:
> - **APPROVE** — all criteria pass (optionally suggest minor improvements)
> - **REJECT** — specific rejection reasons (cite which criterion #N each violates)
>
> Plan body:
> ```
> {planner_output}
> ```
>
> Architect review:
> ```
> {architect_review}
> ```

Save response as `iteration_${N}_critic.md`. Record verdict in state JSON.

### Step 5: Consensus Check and Loop Control

- **Critic APPROVE** → consensus reached. Advance to Phase 2.
- **Critic REJECT + iteration < max_iterations** → next iteration (back to Step 1) with accumulated feedback passed to Planner.
- **Critic REJECT + iteration == max_iterations**:
  - `--interactive`: `AskUserQuestion`:
    > 최대 {max} iteration 도달, 전문가 합의 실패. 마지막 라운드의 best version 으로 진행할까요?
    > 옵션: `[best version 으로 진행, 추가 라운드 1회 허용, 이번 plan 폐기]`
  - Non-interactive: auto-proceed with best version, status = `BELOW_THRESHOLD_NO_CONSENSUS`.

At each iteration end, push to state JSON `iterations[]`:
```json
{
  "iteration": N,
  "planner_path": "iteration_N_planner.md",
  "architect_path": "iteration_N_architect.md",
  "architect_verdict": "APPROVE|REVISE|REJECT",
  "critic_path": "iteration_N_critic.md",
  "critic_verdict": "APPROVE|REJECT",
  "critic_rejection_reasons": [...],
  "timestamp": "<ISO>"
}
```

---

## Phase 2: Apply Improvements + ADR

After consensus (or best version adopted):

1. **Collect improvement proposals**: extract from every iteration's Architect/Critic responses items marked "improvement", "suggestion", "minor revision".
2. **Dedupe + categorize**: merge same-intent items. Categorize by area (requirements/risks/tests/observability/docs).
3. **Merge into final plan**: combine final Planner output with accepted improvements. Record rejected improvements with reasons in trailing changelog.

4. **Append ADR section**:

   ```markdown
   ## ADR (Architecture Decision Record)

   - **Decision**: one sentence. "Implement X via Y."
   - **Drivers**: top 3 (same as / abbreviated from RALPLAN-DR Decision Drivers).
   - **Alternatives considered**: each alternative one-line description + one-line invalidation reason.
   - **Why chosen**: how the selected option satisfies the drivers (2–3 sentences).
   - **Consequences**: positive/negative outcomes (each 2–3 items, inevitable results, not mere risks).
   - **Follow-ups**: items to address in subsequent plans.
   ```

5. **Write final plan** to `.omc/plans/plan-consensus-${SLUG}.md`. `Bash: mkdir -p .omc/plans` to ensure directory.

### Plan template

```markdown
# Plan: {title}

## Metadata
- Consensus ID: {consensus_id}
- Spec source: {spec_path}
- Mode: {short|deliberate}
- Iterations: {N}
- Status: PASSED | BELOW_THRESHOLD_NO_CONSENSUS | USER_BEST_VERSION
- Generated: {now ISO}
- Architect verdict (final): {APPROVE|REVISE|REJECT}
- Critic verdict (final): {APPROVE|REJECT}

## Requirements Summary
{2~3 문장}

## RALPLAN-DR Summary
### Principles
1. ...

### Decision Drivers
1. ...

### Viable Options
#### Option A: {name}
- Approach: ...
- Pros: ...
- Cons: ...

#### Option B: {name}
...

### Chosen Option
{name + one-sentence reason}

## Acceptance Criteria
- [ ] {testable criterion}

## Implementation Steps
1. {step} ({file:line})
2. ...

## Risks and Mitigations
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|

## Verification Steps
```bash
# concrete commands
```

{deliberate only}
## Pre-Mortem
### Scenario 1: ...
- Trigger:
- Early warning signal:

## Expanded Test Plan
- **Unit**: ...
- **Integration**: ...
- **E2E**: ...
- **Observability**: ...

## ADR (Architecture Decision Record)
- **Decision**: ...
- **Drivers**: ...
- **Alternatives considered**: ...
- **Why chosen**: ...
- **Consequences**: ...
- **Follow-ups**: ...

## Consensus Changelog
- Iteration 1: Planner → Architect ({verdict}) → Critic ({verdict})
- Iteration 2: ...
- 수용된 개선: {list}
- 거부된 개선: {list (사유 포함)}

## Status
**pending approval** — 사용자의 명시적 실행 선택 전까지 어떤 코드 변경도 일어나지 않는다.
```

6. After write, first output:

   ```
   Plan 작성 완료 → .omc/plans/plan-consensus-${SLUG}.md
   Iterations: {N}/{max}
   상태: {PASSED | BELOW_THRESHOLD_NO_CONSENSUS | USER_BEST_VERSION}
   ```

---

## Phase 3: pending approval + Execution Bridge

Mark plan as `pending approval`. Until user explicitly selects an execution option, do not run mutation shell commands, edit source, commit, push, open PRs, or auto-invoke other slash commands.

`--interactive` only: `AskUserQuestion`:

> Plan 이 합의됐습니다. 다음 단계는 어떻게 진행할까요?

Options (user triggers as new input):

1. **ralph 로 실행** (single-session sequential + reviewer/codex/deslop verification):
   > ```
   > 다음을 새 입력으로 실행하세요:
   > /ralph "plan 파일: .omc/plans/plan-consensus-${SLUG}.md 의 모든 Acceptance Criteria 를 통과시켜라"
   > ```

2. **team 으로 병렬 실행** (uses Agent Teams):
   > ```
   > 다음을 새 입력으로 실행하세요:
   > /team-dispatch .omc/plans/plan-consensus-${SLUG}.md
   > ```

3. **컨텍스트 정리 후 실행** (recommended if current session context > 50% used):
   > 새 세션을 열고 다음을 실행하세요:
   > ```
   > /ralph "plan 파일: .omc/plans/plan-consensus-${SLUG}.md"
   > ```

4. **수정 요청** — free-text follow-up → start new iteration (back to Phase 1 Step 1).
5. **거부** — discard plan, clean state, exit.

Non-interactive: emit all options at once and exit. Never auto-trigger.

---

## Guardrails

- Read/Write restricted to `$CWD/.omc/` (preamble enforced). No mutations outside.
- Architect and Critic Task calls MUST be sequential. Do not place both tool calls in the same message.
- Consensus loop hard cap = `--max-iterations` (default 5). Beyond cap → forced terminate to prevent infinite loop.
- Planner/Architect/Critic personas: `Task(subagent_type="general-purpose")` with prompt injection. No `Skill("oh-my-claudecode:*")`.
- Cancel handling per preamble.
- After plan write, never auto-trigger `/ralph` or `/team-dispatch`. Approval gate must not be bypassed.
- Context guard per preamble (75% / 90% thresholds).

---

## Verification

- After invocation, `.omc/state/sessions/${SESSION_ID}/plan-consensus-${SLUG}.json` is created/updated.
- On consensus (or best version), `.omc/plans/plan-consensus-${SLUG}.md` exists.
- Plan includes RALPLAN-DR Summary, ADR, Acceptance Criteria, Risks/Mitigations, Verification Steps.
- Deliberate mode → Pre-Mortem + Expanded Test Plan present.
- Architect and Critic calls verifiably sequential (state JSON iteration timestamps prove ordering).
- Stop occurs in pending-approval state; no auto code mutation or slash invocation.
