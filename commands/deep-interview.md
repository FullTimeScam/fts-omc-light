---
description: "OMC `$deep-interview` port — Socratic interview with mathematical ambiguity gating before execution approval"
---

# /deep-interview

First action: `Read ~/.claude/commands/_shared/preamble.md` and apply all its rules. This includes the Korean-output requirement, session ID handling, .omc/ path discipline, cancel/context guards, and the external plugin policy that replaces `Skill("oh-my-claudecode:*")` with sibling local slash commands and built-in subagents.

This command is a faithful local port of OMC (`Yeachan-Heo/oh-my-claudecode`, MIT) `skills/deep-interview/SKILL.md`. Mapping is documented in the shared preamble.

## Pre-flight (mandatory first output)

0. **Plan Mode detection** (per shared-preamble Critical Adherence Rule #4): if Plan Mode is active (detect via prior turn context, inability to write outside the plan file, or a `<system-reminder>` mentioning plan mode), emit this notice immediately AFTER the Phase 0 threshold line and continue with the read-only flow described in the preamble. Phase 4 spec body redirects to the plan file; Phase 5 `AskUserQuestion` execution bridge MUST still be emitted before any `ExitPlanMode` call. Do not silently skip state JSON / spec writes — emit the notice so the user understands persistence is disabled.

1. **Argument parsing** from `$ARGUMENTS`:
   - `--quick` → `mode=quick`, hard cap=10 rounds, soft warning=5 rounds
   - `--standard` (default) → `mode=standard`, hard cap=20 rounds, soft warning=10 rounds
   - `--deep` → `mode=deep`, hard cap=30 rounds, soft warning=15 rounds
   - `--autoresearch` → `autoresearch=true` (auto-spawn built-in Explore subagent in Phase 1)
   - Remaining text → `initial_idea`

2. **Slug**: kebab-case first 6 words of `initial_idea` → `SLUG`. Transliterate Korean to English where needed.

3. Apply preamble session-ID resolution and Opus recommendation.

---

## Phase 0: Resolve Ambiguity Threshold (blocking gate)

Complete before Phase 1, brownfield exploration, state write, Round 0, or any ambiguity scoring. Do not proceed if threshold and source are unknown.

**Precedence (project overrides user)**:

1. Project: `./.claude/settings.json` → `omc.deepInterview.ambiguityThreshold` (Read; skip if file or key missing)
2. User: `~/.claude/settings.json` → same key (Read; skip if missing)
3. Default `0.05` (사용자 선호; upstream OMC default 는 `0.2`)

Key paths are identical to upstream OMC. Both files are local — no external network calls.

**Note on settings.json schema**: Claude Code's settings.json schema validator rejects unknown top-level keys including `omc`. The Read above will still find the key if present (validator only blocks Write), but inserting it via Claude Code's Edit tool is blocked. To override the default, edit this spec's Default value directly OR use a raw text editor bypass on settings.json.

Bind `RESOLVED_THRESHOLD`, `RESOLVED_THRESHOLD_PERCENT`, `RESOLVED_THRESHOLD_SOURCE`. Source value is one of `./.claude/settings.json`, `~/.claude/settings.json`, or `default`.

**Required first user-visible line** (do not advance to next Phase before emitting):

```
Deep Interview 임계값: {RESOLVED_THRESHOLD_PERCENT} (출처: {RESOLVED_THRESHOLD_SOURCE})
```

Preserve `threshold` and `threshold_source` together in every subsequent state write and the final spec metadata.

---

## Phase 1: Initialize

1. Parse `initial_idea` from `$ARGUMENTS`.

2. **Greenfield vs brownfield detection**:
   - `Task(subagent_type="Explore", prompt="Check whether cwd has source code / manifests / git history, and judge whether the user idea '{initial_idea}' references modifying or extending existing code. Report one line.")`
   - If source files exist AND idea references existing code → `type=brownfield`
   - Otherwise → `type=greenfield`

3. **Brownfield context gathering** (when `type=brownfield`):
   - `Task(subagent_type="Explore", prompt="Map codebase areas relevant to the idea — file tree, core manifests (package.json/pyproject.toml/go.mod/etc.), README, entry-point files in related directories")` → store as `CODEBASE_CONTEXT`. Summarize as cited paths/symbols/patterns, not raw dumps.
   - Consult accumulated local planning assets: `Bash: ls .omc/specs/deep-*.md .omc/plans/*.md 2>/dev/null`, then Read the 1–3 most topically relevant to `initial_idea` (each summary ≤ 200 tokens). Extract only durable domain facts, prior decisions, constraints, unresolved gaps — to avoid re-asking facts crystallized by earlier deep-interview/plan sessions.
   - Brownfield confirmation questions MUST cite codebase evidence (file path, symbol, pattern) so user does not rediscover what the code already reveals.

3.5. Verify Phase 0 threshold resolution complete. If any of `RESOLVED_THRESHOLD`, `RESOLVED_THRESHOLD_PERCENT`, `RESOLVED_THRESHOLD_SOURCE` missing → return to Phase 0. No hardcoded fallback.

3.6. **Oversized initial-context normalization**: inspect `initial_idea` plus any pasted artifacts, logs, transcripts, file excerpts for prompt-budget risk (roughly >500 words or likely to crowd downstream prompts).
   - If pressured, produce a concise prompt-safe Korean summary preserving user intent, decisions, constraints, unknowns, cited files/symbols, explicit non-goals. Store as `INITIAL_CONTEXT_SUMMARY`.
   - Treat the summary as the canonical `initial_idea`. Raw oversized material is external advisory context only — never paste into question generation, scoring, spec, or handoff prompts.
   - Block ambiguity scoring, weakest-dimension selection, brownfield exploration until summary exists.

3.7. **Artifact path discipline** (preamble enforced):
   - Final spec: exactly `.omc/specs/deep-interview-${SLUG}.md`
   - Ephemeral: `.omc/state/sessions/${SESSION_ID}/` or in-memory state JSON only.

4. **State file**: `Bash: mkdir -p .omc/state/sessions/${SESSION_ID}`, then Write `.omc/state/sessions/${SESSION_ID}/deep-interview-${SLUG}.json`:

   ```json
   {
     "active": true,
     "current_phase": "deep-interview",
     "state": {
       "interview_id": "<uuid or SESSION_ID-SLUG>",
       "type": "greenfield|brownfield",
       "mode": "quick|standard|deep",
       "initial_idea": "<prompt-safe initial context summary or user input>",
       "initial_context_summary": "<summary if oversized, else null>",
       "rounds": [],
       "current_ambiguity": 1.0,
       "threshold": <RESOLVED_THRESHOLD>,
       "threshold_source": "<RESOLVED_THRESHOLD_SOURCE>",
       "codebase_context": null,
       "topology": {
         "status": "pending|confirmed|legacy_missing",
         "confirmed_at": null,
         "components": [],
         "deferrals": [],
         "last_targeted_component_id": null
       },
       "challenge_modes_used": [],
       "ontology_snapshots": []
     }
   }
   ```

5. **Interview announcement**: first line MUST be the Phase 0 threshold marker. Order and inclusion are mandatory.

   > Deep Interview 임계값: {RESOLVED_THRESHOLD_PERCENT} (출처: {RESOLVED_THRESHOLD_SOURCE})
   >
   > Deep Interview를 시작합니다. 아이디어를 명확히 파악하기 위해 타깃 질문을 드리고, 답변 후 명료도 점수를 보여드립니다. 모호성이 {RESOLVED_THRESHOLD_PERCENT} 이하로 떨어지면 실행 단계로 진행합니다.
   >
   > **아이디어:** "{initial_idea}"
   > **프로젝트 유형:** {greenfield|brownfield}
   > **현재 모호성:** 100% (아직 시작 전)

---

## Round 0: Topology Enumeration Gate (one-time, pre-scoring)

**🚫 MUST NOT SKIP — applies even in `--quick` mode for simple-looking tasks.** Past failure (2026-05-22 smoke test): the model decided "task is simple, skip Round 0" and bypassed this gate. This is wrong. Round 0 is a hard blocking gate per shared-preamble Critical Adherence Rule #3 (mode-agnostic gates). The single confirmation question takes <30 seconds even for a 1-component task and produces the locked-topology state that downstream scoring depends on. Bypassing it breaks: (a) multi-component aggregation math, (b) `topology.last_targeted_component_id` rotation, (c) spec `## Topology` section, (d) resume capability.

Run exactly once after Phase 1 init, before any Phase 2 ambiguity scoring. Goal: lock the *shape* of user scope before depth-first Socratic questioning can overfit to the most-described component.

1. **Enumerate candidate top-level components** from prompt-safe initial idea + brownfield context:
   - Top-level verbs/nouns/workstreams/surfaces/integrations/deliverables that can succeed or fail independently.
   - Prefer 1–6. If > 6 candidates, group siblings at the highest useful level and record rationale.
   - Implementation tasks, fields, sub-features are NOT top-level components unless user framed them as independent outcomes.

2. **One confirmation question before Round 1**:

   ```
   Round 0 | 토폴로지 확인 | 모호성: 아직 미채점

   이 요구사항을 {N}개 최상위 컴포넌트로 읽었습니다:
   1. {component_name}: {one_sentence_description}
   2. ...

   토폴로지가 맞나요? 추가·제거·병합·분리·명시적 보류가 필요한가요?
   ```

   `AskUserQuestion` options: `[맞다 — 진행, 추가/제거/병합/분리, 일부 보류, 기타]`. Round 0 is the only pre-scoring question — preserves one-question-per-round rule.

3. **Lock topology to state** after answer. Normalize component list + confirmation timestamp:

   ```json
   {
     "topology": {
       "status": "confirmed",
       "confirmed_at": "<ISO-8601 timestamp>",
       "components": [
         {
           "id": "component-slug",
           "name": "Component Name",
           "description": "Confirmed top-level outcome",
           "status": "active|deferred",
           "evidence": ["initial prompt phrase or brownfield citation"],
           "clarity_scores": {
             "goal": null,
             "constraints": null,
             "criteria": null,
             "context": null
           },
           "weakest_dimension": null
         }
       ],
       "deferrals": [
         {
           "component_id": "component-slug",
           "reason": "User-confirmed deferral reason",
           "confirmed_at": "<ISO-8601 timestamp>"
         }
       ],
       "last_targeted_component_id": null
     }
   }
   ```

4. **Legacy state migration**: when resuming a deep-interview state file lacking `topology`, treat as `"status": "legacy_missing"`. If no final `spec_path` yet, run Round 0 before next scoring pass and continue with existing transcript. If final spec already exists, do not rewrite history — note in handoff that "topology was not captured for this legacy interview".

5. **Single-component pass-through**: if user confirms one active component, Phase 2 proceeds normally with `topology.components[0]` carried into scoring and spec output.

6. **Multi-component fixture shape**: for an initial idea like "CSV ingest + normalization + detailed reviewer UI with inline comments + audit-ready export", Round 0 must surface all four — `Ingestion`, `Normalization`, `Review UI`, `Export`. The detailed `Review UI` must not collapse or stand in for less-detailed siblings. Phase 2 must keep asking until every active component has sufficient goal/constraint/criteria clarity. Phase 4 spec `## Topology` must cover each confirmed component or list explicit user-confirmed deferrals.

---

## Phase 2: Interview Loop

Rounds start at 1. Repeat 2a–2f sequentially until `current_ambiguity ≤ RESOLVED_THRESHOLD` OR user exits early.

### 2a. Generate Next Question

Build the question-generation prompt with:
- Prompt-safe initial-context summary (if created), else original user idea
- Prior Q&A rounds trimmed/summarized to fit prompt budget (preserve decisions, constraints, unresolved gaps, ontology changes)
- Current per-dimension clarity scores (which is weakest?)
- Challenge mode (if activated — see Phase 3)
- Brownfield codebase context (if applicable, summarized to cited paths/symbols/patterns, not raw dumps)
- Locked topology from Round 0: active components, deferred components, prior per-component scores, `last_targeted_component_id`

If any prompt input is too large, summarize first and continue from summary. Do not issue the next `AskUserQuestion`, score ambiguity, or hand off to execution from an over-budget raw transcript.

**Dimension weights (greenfield)**: Goal 40% · Constraint 30% · Success Criteria 30%
**Dimension weights (brownfield)**: Goal 35% · Constraint 25% · Success Criteria 25% · Context 15%

**Ambiguity formula**
```
greenfield:  ambiguity = 1 - (goal*0.40 + constraints*0.30 + criteria*0.30)
brownfield:  ambiguity = 1 - (goal*0.35 + constraints*0.25 + criteria*0.25 + context*0.15)
```

**Question targeting strategy**:
- Identify the (active component × dimension) pair with the LOWEST clarity score across locked topology
- When N > 1 active components are similarly weak, rotate across them rather than repeating. Update `topology.last_targeted_component_id` after each question
- Generate a question that specifically improves that component's weakest dimension
- Just before the question, state in one sentence why this (component/dimension) pair is the current bottleneck to reducing ambiguity
- Questions must expose ASSUMPTIONS, not gather feature lists
- If scope is still conceptually fuzzy (entities keep shifting, user names symptoms, core noun unstable), switch to an ontology-style question that asks what the thing fundamentally IS before returning to feature/detail questions

**Question styles by dimension** (presented to user in Korean):

| Dimension | Style | Example |
|---|---|---|
| Goal Clarity | "정확히 무엇이 일어나는가?" | "'작업 관리'라고 했을 때 사용자가 가장 먼저 취하는 구체 액션은 무엇인가요?" |
| Constraint Clarity | "경계는 무엇인가?" | "오프라인에서도 동작해야 하나요, 아니면 인터넷 연결을 가정하나요?" |
| Success Criteria | "어떻게 동작 여부를 알 수 있는가?" | "완성품을 보여드리면 '이거 맞다' 라고 말하게 만드는 것이 무엇인가요?" |
| Context (brownfield) | "어떻게 끼워 맞추는가?" | "`src/auth/` 에서 JWT + passport 패턴을 찾았는데, 이 피처가 그 경로를 확장하나요, 의도적으로 분기하나요?" |
| Scope-fuzzy / ontology | "이 핵심은 정말 무엇인가?" | "지난 라운드에서 Tasks, Projects, Workspaces를 언급하셨는데, 어떤 것이 핵심 엔티티이고 어떤 것이 보조 뷰/컨테이너인가요?" |

### 2b. Emit the Question

**🚫 EXACTLY 1 question per `AskUserQuestion` call.** `questions` array length MUST be 1. Even if the round needs to clarify multiple dimensions (e.g., runtime + storage + commands + install location), split them into separate rounds — never batch into a single AskUserQuestion. Past failure (2026-05-22 smoke test): Round 1 emitted 4 questions and Round 2 emitted 3 questions in single AskUserQuestion calls. This is the first "Bad" example in this very command's Examples section. The temptation to batch is highest in `--quick` mode — resist it; spec design assumes per-question scoring resolution.

Use `AskUserQuestion`. Include this one-line header first:

```
Round {n} | 컴포넌트: {target_component_name} | 타깃: {weakest_dimension} | 왜 지금: {one_sentence_targeting_rationale} | 모호성: {score}%

{question}
```

Options: 2–4 contextually relevant choices + "기타" (free-text always available). Discrete choices score more reliably than flat free-text.

### 2c. Score Ambiguity

After receiving the user's answer, do internal evaluation (do not expose raw evaluator output to user). Use Opus equivalent (temperature 0.1 spirit) for scoring consistency.

**Scoring inputs**:
- Original idea OR prompt-safe initial-context summary
- Transcript (or prompt-safe transcript summary)
- Locked topology (`state.topology.components` + `state.topology.deferrals`)

**Scoring procedure**:

1. **Score every active component on every dimension independently, 0.0–1.0**. Do not drop sibling components because one component is already clear. Deferred components are excluded from ambiguity math but remain listed in topology and final spec.
   - **Goal Clarity**: Is the primary objective unambiguous? Statable in one sentence without qualifiers? Can you name key entities (nouns) and relationships (verbs) without ambiguity?
   - **Constraint Clarity**: Are boundaries, limits, non-goals clear?
   - **Success Criteria Clarity**: Could you write a test that verifies success now? Are acceptance criteria concrete?
   - **Context Clarity** (brownfield only): Do we understand existing system well enough to modify safely? Do identified entities map cleanly to existing codebase structures?

2. **Attach per-dimension**:
   - `score`: float (0.0–1.0)
   - `justification`: one-sentence rationale
   - `gap`: what is still unclear if score < 0.9

3. **Also identify**:
   - `weakest_component_id`: lowest-clarity active component after rotation
   - `weakest_dimension`: single lowest-confidence dimension for that component this round
   - `weakest_dimension_rationale`: one sentence on why this (component/dimension) pair is the next-question's highest-leverage target
   - `component_scores`: object keyed by component id, with per-dimension scores + gaps

4. **Multi-component aggregation** (CRITICAL — NOT average):
   - Compute each component's `ambiguity` with the formula above.
   - Overall `current_ambiguity` = **maximum** of active components (or coverage-weighted weakest). The most ambiguous component must drag down the gate — averaging would let clear components hide weak siblings.
   - Single active component → its `ambiguity` is the overall.

5. **Ontology extraction**: identify all key entities (nouns) in the answer. For Round 2+, inject into scoring prompt:

   > "Previous round's entities: {prior_entities_json from state.ontology_snapshots[-1]}. REUSE these entity names where the concept is the same. Only introduce new names for genuinely new concepts."

   Each entity:
   - `name`: entity name (e.g. "User", "Order", "PaymentMethod")
   - `type`: "core domain" | "supporting" | "external system"
   - `fields`: array of key attributes mentioned
   - `relationships`: array (e.g., "User has many Orders")

**Ontology stability calculation**:
- **Round 1 special case**: skip comparison. All entities are "new". `stability_ratio = N/A`. Zero entities in any round → `stability_ratio = N/A` (no div-by-zero).
- **Round 2+**: compare with prior round's entity list:
  - `stable_entities`: same name in both rounds
  - `changed_entities`: different name but same type AND ≥50% field overlap (renamed, not new+removed)
  - `new_entities`: in this round only, no name/fuzzy match to prior
  - `removed_entities`: in prior round, no match to current
  - `stability_ratio = (stable + changed) / total_entities` (0.0–1.0, 1.0 = fully converged)

Renamed entities count toward stability — name shift while concept persists is convergence evidence, not instability. Two entities with different names but same type and ≥50% field overlap = "changed", not (removed + added).

**Show your work**: before reporting stability numbers, briefly list which entities were matched (by name or fuzzy) and which are new/removed. Lets user sanity-check matching.

Persist `state.ontology_snapshots[]` with (entities + stability_ratio + matching_reasoning).

### 2d. Progress Report

Output the following table to user (Context row only for brownfield):

```
Round {n} 완료.

| 차원              | 점수  | 가중치 | 가중점수    | 갭                 |
|-------------------|-------|--------|-------------|--------------------|
| 목표 명료도       | ...   | 40%    | ...         | {gap 또는 "Clear"} |
| 제약 명료도       | ...   | 30%    | ...         | {gap 또는 "Clear"} |
| 성공 기준         | ...   | 30%    | ...         | {gap 또는 "Clear"} |
| 컨텍스트 명료도   | ...   | 15%    | ...         | {gap 또는 "Clear"} |   ← brownfield 만
| **모호성**        |       |        | **{score}%** | |

**토폴로지:** 타깃 {target_component_name} | 활성 {n} / 보류 {m} | 다음 로테이션 이후: {last_targeted_component_id}

**온톨로지:** 엔티티 {e}개 | 안정 비율 {ratio} | 신규 {new} | 변경 {changed} | 안정 {stable}

**다음 타깃:** {target_component_name} / {weakest_dimension} — {weakest_dimension_rationale}

{score ≤ threshold ? "명료도 임계값 도달! 진행 준비 완료." : "다음 질문은 {weakest_dimension} 에 집중합니다."}
```

### 2e. Update State

Read → modify → Write `.omc/state/sessions/${SESSION_ID}/deep-interview-${SLUG}.json`:
- Append `rounds[]` with `{round, target_component_id, dimension, question, answer, scores, ambiguity, ontology_snapshot}`
- Update `current_ambiguity`
- Update per-component `topology.components[].clarity_scores`, `topology.components[].weakest_dimension`
- Update `topology.last_targeted_component_id`
- Append `ontology_snapshots[]` with this round's snapshot

### 2f. Soft Limits / Termination

- **Round 3+**: if user signals stop ("충분", "그만", "그냥 진행", "build it"), offer early exit. If ambiguity > threshold, show risk transparently:

   > "현재 모호성 {score}% (임계값: {RESOLVED_THRESHOLD_PERCENT}). 여전히 불명확한 영역:
   >   - {dimension}: {score} ({gap})
   > 진행하면 재작업이 필요할 수 있습니다. 그래도 진행하시겠습니까?"

   `AskUserQuestion`: `[지금 spec 으로 동결, 한 라운드 더, 챌린지 모드 강제 발동, 취소]`.

- **Soft warning round reached** (per mode: quick=5, standard=10, deep=15): "라운드 {n} 도달. 모호성 {score}%. 계속할까요, 지금 spec 으로 동결할까요?" confirmation.
- **Hard cap reached** (per mode: quick=10, standard=20, deep=30): force-advance to Phase 4 with status=`BELOW_THRESHOLD_HARD_CAP`.
- **Ambiguity stalls** (`current_ambiguity` within ±0.05 across last 3 rounds): force Ontologist mode next round (if unused; otherwise proceed normally).
- **All dimensions ≥ 0.9**: jump to Phase 4 spec crystallization immediately even if round minimum not met.
- **Codebase exploration fails**: proceed as greenfield, note limitation.

When `current_ambiguity ≤ RESOLVED_THRESHOLD` → advance to Phase 4 with status=`PASSED`.

---

## Phase 3: Challenge Agent Modes (question-prompt injection)

At specific round thresholds, shift question-generation perspective. **This is prompt injection into the same agent, NOT spawning a new agent.** Each mode used exactly **once** per interview; record in `state.challenge_modes_used`.

### Round 4+: Contrarian Mode

Inject into question-generation prompt:

> You are now in CONTRARIAN mode. Your next question must challenge the user's core assumption. Ask "What if the opposite were true?" or "What if this constraint doesn't actually exist?" Goal: test whether the user's framing is correct or just habitual.

### Round 6+: Simplifier Mode

Inject:

> You are now in SIMPLIFIER mode. Your next question should probe whether complexity can be removed. Ask "What's the simplest version that's still valuable?" or "Which of these constraints are actually necessary vs assumed?" Goal: find the minimal viable specification.

### Round 8+ (ambiguity > 0.3): Ontologist Mode

Inject:

> You are now in ONTOLOGIST mode. High ambiguity after 8 rounds suggests we may be addressing symptoms rather than the core problem. Tracked entities so far: {current_entities_summary from latest ontology snapshot}. Ask "What IS this, really?" or "Looking at these entities, which is the CORE concept and which are merely supporting?" Goal: find the essence by examining the ontology.

Each mode used exactly once → revert to normal Socratic questioning. Track usage in state to prevent repetition.

---

## Phase 4: Crystallize Spec

Trigger: `current_ambiguity ≤ RESOLVED_THRESHOLD` OR hard cap OR user early exit.

1. `Bash: mkdir -p .omc/specs`
2. **Generate spec body**: fill the markdown template below using the prompt-safe transcript and Write to `.omc/specs/deep-interview-${SLUG}.md`. If full transcript or initial context is too large, include summary + all concrete decisions, acceptance criteria, unresolved gaps, ontology snapshots — never overflow with raw oversized context.
3. First output after spec write:

   ```
   Spec 작성 완료 → .omc/specs/deep-interview-${SLUG}.md
   최종 모호성: {current_ambiguity*100}%
   라운드: {rounds.length}
   상태: PASSED | BELOW_THRESHOLD_EARLY_EXIT | BELOW_THRESHOLD_HARD_CAP
   ```

### Spec template

```markdown
# Deep Interview Spec: {title}

## Metadata
- Interview ID: {interview_id}
- Rounds: {rounds.length}
- Final Ambiguity Score: {current_ambiguity*100}%
- Type: {greenfield|brownfield}
- Mode: {quick|standard|deep}
- Generated: {now ISO}
- Threshold: {threshold}
- Threshold Source: {threshold_source}
- Initial Context Summarized: {yes|no}
- Status: {PASSED | BELOW_THRESHOLD_EARLY_EXIT | BELOW_THRESHOLD_HARD_CAP}

## 명료도 분해 (Clarity Breakdown)
| 차원 | 점수 | 가중치 | 가중점수 |
|------|------|--------|----------|
| 목표 명료도 | {s} | {w} | {s*w} |
| 제약 명료도 | {s} | {w} | {s*w} |
| 성공 기준 | {s} | {w} | {s*w} |
| 컨텍스트 명료도 | {s} | {w} | {s*w} |
| **총 명료도** | | | **{total}** |
| **모호성** | | | **{1-total}** |

## Topology
Round 0 확정 최상위 컴포넌트 전체 등재. 활성 컴포넌트엔 커버리지 노트, 보류 컴포넌트엔 사용자 확인 보류 사유·타임스탬프 포함.

| Component | Status | Description | Coverage / Deferral Note |
|-----------|--------|-------------|--------------------------|
| {component.name} | {active|deferred} | {component.description} | {covered acceptance criteria 또는 deferral reason} |

## Goal
{모든 활성 토폴로지 컴포넌트를 포함한 명료한 목표 진술}

## Constraints
- {제약 1}
- {제약 2}

## Non-Goals
- {명시적으로 제외된 범위 1}
- {명시적으로 제외된 범위 2}

## Acceptance Criteria
- [ ] {검증 가능한 기준 1}
- [ ] {검증 가능한 기준 2}

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| {가정} | {어떻게 도전했는지} | {무엇이 결정됐는지} |

## Technical Context
{brownfield: 관련 코드베이스 발견; greenfield: 기술 선택과 제약}

## Ontology (Key Entities)
FINAL 라운드 온톨로지 추출에서 채움 (결정화 시점 재생성 아님).

| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| {entity.name} | {entity.type} | {entity.fields} | {entity.relationships} |

## Ontology Convergence
state.ontology_snapshots 데이터로 라운드별 엔티티 안정화 표시.

| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | {n} | {n} | - | - | - |
| 2 | {n} | {new} | {changed} | {stable} | {ratio}% |
| ... | ... | ... | ... | ... | ... |
| {final} | {n} | {new} | {changed} | {stable} | {ratio}% |

## Interview Transcript
<details>
<summary>전체 Q&A ({rounds.length} 라운드)</summary>

### Round 1
**Q:** {question}
**A:** {answer}
**Ambiguity:** {score}% (Goal: {g}, Constraints: {c}, Criteria: {cr})

...
</details>
```

---

## Phase 5: Execution Bridge

**🚫 MANDATORY — do not jump to ExitPlanMode / end-of-turn / direct implementation before this Phase emits an `AskUserQuestion` with execution options.** Past failure (2026-05-22 smoke test): the command wrote the spec/plan and went straight to ExitPlanMode without ever presenting Phase 5 options. The `AskUserQuestion` here is read-only and remains mandatory in Plan Mode too — the user's explicit selection is what authorizes downstream execution.

After spec write, mark `pending approval` and present execution options via `AskUserQuestion`. Until user selects an execution option, deep-interview MUST NOT run mutation shell commands, edit source files, commit, push, open PRs, invoke execution skills, or delegate implementation.

**`--autoresearch` mode branch**: if interview started with `--autoresearch`, present only this option (skip standard options):

> ```
> 다음을 새 입력으로 실행하세요:
> /autoresearch-loop --mission .omc/specs/deep-interview-${SLUG}.md --evaluator "<인터뷰 중 확정한 evaluator command>" --max-runtime 2h
> ```
> Autoresearch is a single-mission stateful loop and is the final execution surface for this path. Do not proceed with standard plan/ralph/team options afterward.

**Standard options** (non-autoresearch):

> Spec 이 완성되었습니다 (모호성: {score}%). 다음 단계는 어떻게 진행할까요?

Options (slash commands cannot invoke other slash commands directly, so the user must trigger as new input):

1. **plan 정제 (권장)** — `/plan-consensus`:
   > ```
   > 다음을 새 입력으로 실행하세요:
   > /plan-consensus .omc/specs/deep-interview-${SLUG}.md
   > ```
   > Planner/Architect/Critic consensus loop (max 5 iter) → spec → consensus plan with RALPLAN-DR + ADR. Add `--deliberate` for high-risk (auth/migration/etc.).

2. **ralph 로 실행** — `/ralph`:
   > ```
   > 다음을 새 입력으로 실행하세요:
   > /ralph "spec 파일: .omc/specs/deep-interview-${SLUG}.md 의 모든 Acceptance Criteria 를 통과시켜라"
   > ```

3. **autopilot 등가 체인 (plan + ralph)** — `/plan-consensus` then `/ralph`:
   > ```
   > 다음을 순서대로 실행하세요:
   > 1) /plan-consensus .omc/specs/deep-interview-${SLUG}.md
   > 2) /ralph "plan 파일: .omc/plans/plan-consensus-${SLUG}.md 의 모든 Acceptance Criteria 를 통과시켜라"
   > ```
   > Equivalent to OMC autopilot's Phase 0–4 (expansion/planning/execution/QA). Phase 0 replaced by spec, Phase 1 by plan-consensus, Phase 2–4 absorbed by ralph's reviewer/codex/deslop cycles.

4. **team 으로 병렬 실행** — `/team-dispatch`:
   > ```
   > 다음을 새 입력으로 실행하세요:
   > /team-dispatch .omc/specs/deep-interview-${SLUG}.md
   > ```
   > Or after plan-consensus: `/team-dispatch .omc/plans/plan-consensus-${SLUG}.md`. Built-in TeamCreate spawns N teammates in parallel, runs staged pipeline (team-plan → exec → verify → fix).

5. **추가 정제** — return to Phase 2 interview loop (continue rounds at current ambiguity).

**Important**: never jump to direct implementation before an execution option is explicitly chosen. If oversized initial context was summarized, pass the spec + prompt-safe summary forward — never the raw original.

### Approval-Gated Refinement Path (recommended diagram)

```
Stage 1: Deep Interview        Stage 2: plan 정제 (권장)         Stage 3: 별도 승인
┌─────────────────────┐    ┌───────────────────────────┐    ┌──────────────────────┐
│ Socratic Q&A        │    │ Planner 플랜 생성          │    │ 사용자가 실행 여부/   │
│ 모호성 채점          │───>│ Architect 리뷰            │───>│ 방식 선택            │
│ 챌린지 모드          │    │ Critic 검증               │    │ team/ralph 등        │
│ Spec 결정화          │    │ 합의 도달 시까지 루프      │    │ 자동 핸드오프 금지    │
│ Gate: ≤{임계값} 모호성  │    │ ADR + RALPLAN-DR 요약    │    │                      │
└─────────────────────┘    └───────────────────────────┘    └──────────────────────┘
Output: spec.md            Output: consensus-plan.md        Output: pending approval
```

Each stage provides a different quality gate:
1. **Deep Interview**: *clarity* — does the user know what they want?
2. **plan 정제**: *feasibility* — is the approach architecturally sound?
3. **별도 승인**: *consent* — does the user explicitly choose an execution path?

---

## Examples

### Good

**Weakest-dimension targeting** (user-facing in Korean):
```
Scores: Goal=0.9, Constraints=0.4, Criteria=0.7
다음 질문은 Constraints (최저 0.4) 를 타깃:
"'모바일에서 동작' 이라고 하셨는데 네이티브 앱인가요, 반응형 웹인가요, PWA 인가요?
지원해야 할 특정 디바이스나 OS 버전이 있나요?"
```
Good: weakest dim identified, bottleneck reason stated, specific improving question, no topic batching.

**Gathering codebase facts before asking**:
```
[Explore subagent spawn: "find authentication implementation"]
[receives: "passport.js JWT in src/auth/"]

질문: "Explore 에서 `src/auth/` 의 passport.js JWT 인증을 찾았습니다.
이 새 피처는 기존 auth 미들웨어를 확장할까요, 별도 인증 흐름을 만들까요?"
```
Good: explored first, cited repo evidence, informed confirmation question. Never asks what code already reveals.

**Contrarian activation**:
```
Round 5 | Contrarian Mode | Ambiguity: 42%

이 시스템이 10,000 명 동시 사용자를 지원해야 한다고 하셨습니다. 만약 100 명만 처리하면 된다면요?
아키텍처가 근본적으로 바뀔까요, 아니면 10K 라는 숫자가 측정된 요구사항이 아니라 가정인가요?
```
Good: challenges a specific assumption (scale) that could dramatically simplify the solution.

**Early exit + warning**:
```
사용자: "충분합니다, 그냥 만드세요"
시스템: "현재 모호성 35% (임계값: 20%). 여전히 불명확한 영역:
  - Success Criteria: 0.5 (검색 랭킹 알고리즘 동작 검증 방법?)
  - Constraints: 0.6 (성능 목표 미정의)

진행 시 재작업 가능성. 그래도 진행하시겠습니까?"
  [네, 진행] [2~3개 질문 더] [취소]
```
Good: respects user's stop intent while transparently showing risk.

**Ontology convergence tracking**:
```
Round 3 entities: User, Task, Project (stability: N/A → 67%)
Round 4 entities: User, Task, Project, Tag (stability: 75% — 3 stable, 1 new)
Round 5 entities: User, Task, Project, Tag (stability: 100% — all 4 stable)

"온톨로지 수렴 — 같은 4개 엔티티가 2 연속 라운드 동안 변화 없이 등장. 도메인 모델 안정."
```
Good: round-over-round entity tracking with visible convergence. Stability ratio rising = mathematical evidence of model solidifying.

**Ontology-style question for scope-fuzzy tasks**:
```
Round 6 | 타깃: 목표 명료도 | 왜 지금: core entity unstable across rounds — feature questions would compound ambiguity | 모호성: 38%

"지난 라운드에서 이것을 워크플로우라고도, 인박스라고도, 플래너라고도 묘사하셨습니다. 어떤 것이 이 제품이 본질적으로 IS 인 것이고, 어떤 것이 보조 메타포/뷰인가요?"
```
Good: stabilize core noun before drilling into features when scope is fuzzy.

### Bad

**Batching multiple questions**:
```
"타깃 청중은? 그리고 기술 스택은? 인증은 어떻게? 배포 타깃은?"
```
Bad: 4 questions at once → shallow answers, inaccurate scoring.

**Asking about codebase facts**:
```
"프로젝트는 어떤 DB 를 사용하나요?"
```
Bad: should have spawned Explore subagent. Never ask what the code already reveals.

**Proceeding despite high ambiguity**:
```
"모호성이 45% 지만 5라운드 했으니 빌드 시작하죠"
```
Bad: 45% means half the requirements unclear. The mathematical gate exists exactly to prevent this.

---

## Escalation / Stop Conditions

- **Hard cap reached**: proceed with current clarity, note risk
- **Soft warning reached**: ask user whether to continue
- **Early exit (Round 3+)**: allow with warning if ambiguity > threshold
- **User says stop/취소/중단**: stop immediately, save state for resume (preamble enforced)
- **Ambiguity stalls** (3 rounds within ±0.05): force Ontologist next round (if unused)
- **All dimensions ≥ 0.9**: skip to spec crystallization
- **Codebase exploration fails**: proceed as greenfield, note limitation

---

## Final Checklist

- [ ] Phase 0 completed before Phase 1: both settings files were read, threshold resolved, first user-visible line was `Deep Interview 임계값: {percent} (출처: {source})`
- [ ] State includes both `threshold` and `threshold_source`, final spec metadata records both
- [ ] Interview completed (ambiguity ≤ threshold OR user early exit OR hard cap)
- [ ] Oversized initial context/history summarized before scoring/question/spec/handoff
- [ ] Ambiguity score displayed after every round
- [ ] Every round explicitly names weakest dimension and why it's the next target
- [ ] Challenge modes activated at correct thresholds (4, 6, 8), used once each, recorded in `state.challenge_modes_used`
- [ ] Spec file at exactly `.omc/specs/deep-interview-${SLUG}.md`; ephemerals stayed under `.omc/state/`
- [ ] Spec includes: topology, goal, constraints, acceptance criteria, clarity breakdown, transcript
- [ ] Execution bridge presented via AskUserQuestion
- [ ] No direct implementation without explicit execution selection
- [ ] Brownfield confirmation questions cite repo evidence (file/path/pattern) before asking user to decide
- [ ] Scope-fuzzy tasks can trigger ontology-style questioning to stabilize core entity before feature elaboration
- [ ] Round 0 topology gate completed before scoring, `topology.confirmed_at` persisted
- [ ] Per-round report includes Topology target/coverage + Ontology row (entity count + stability ratio)
- [ ] Multi-component interview rotates targeting across active components when N > 1
- [ ] Spec `## Topology` includes confirmed active components and user-confirmed deferrals
- [ ] Spec includes `## Ontology (Key Entities)` table and `## Ontology Convergence` section
- [ ] Multi-component aggregation uses max / coverage-weighted weakest (NOT average — most ambiguous component drags the gate)

---

## Advanced / Configuration

### Settings

`./.claude/settings.json` (project, higher precedence) or `~/.claude/settings.json` (user):

```json
{
  "omc": {
    "deepInterview": {
      "ambiguityThreshold": 0.05,
      "maxRounds": 20,
      "softWarningRounds": 10,
      "minRoundsBeforeExit": 3,
      "enableChallengeAgents": true,
      "autoExecuteOnComplete": false,
      "defaultExecutionMode": null,
      "scoringModel": "opus"
    }
  }
}
```

Local port actively reads `ambiguityThreshold` only. Other keys are forward-compat placeholders. Mode caps are governed by `--quick|--standard|--deep` flag precedence.

⚠️ Claude Code 의 settings.json schema 가 `omc` 네임스페이스를 거부하므로 Edit 도구로는 위 키를 settings.json 에 추가할 수 없음. 직접 default 를 바꾸려면 본 spec 의 Phase 0 default 값을 수정 (현재 `0.05`).

### Resume

On interrupt, re-invoke `/deep-interview` to resume from last completed round via `.omc/state/sessions/${SESSION_ID}/deep-interview-${SLUG}.json`. Legacy state without topology field → Round 0 migration (see Round 0 section item 4).

### Brownfield vs Greenfield Weights

| Dimension | Greenfield | Brownfield |
|-----------|-----------|------------|
| Goal Clarity | 40% | 35% |
| Constraint Clarity | 30% | 25% |
| Success Criteria | 30% | 25% |
| Context Clarity | N/A | 15% |

Brownfield adds Context Clarity because safe modification requires system understanding.

### Challenge Agent Modes

| Mode | Activates | Purpose | Prompt Injection |
|------|-----------|---------|------------------|
| Contrarian | Round 4+ | Challenge assumptions | "What if the opposite were true?" |
| Simplifier | Round 6+ | Remove complexity | "What's the simplest version?" |
| Ontologist | Round 8+ (if ambiguity > 0.3) | Find essence | "What IS this, really?" |

Each used exactly once → normal Socratic resumes. Tracked in state to prevent repetition.

### Ambiguity Score Interpretation

| Range | Meaning | Action |
|-------|---------|--------|
| 0.0–0.1 | Crystal clear | Proceed immediately |
| ≤ threshold | Clear enough | Proceed |
| Above threshold + minor gap | Some gaps | Continue interviewing |
| Moderate | Significant gaps | Focus on weakest dimensions |
| High | Very unclear | May need reframing (Ontologist) |
| Extreme | Almost nothing known | Early stages, continue |

---

## Verification

- After invocation, `.omc/state/sessions/${SESSION_ID}/deep-interview-${SLUG}.json` is created/updated.
- On ambiguity threshold pass, `.omc/specs/deep-interview-${SLUG}.md` is created.
- Each challenge mode invoked at most once, recorded in `state.challenge_modes_used`.
- Multi-component overall ambiguity is computed as max/coverage-weighted weakest, not average.
- Phase 5 option selection prints local slash-command instructions for the user to invoke; no direct implementation jump (sibling commands: `/plan-consensus`, `/ralph`, `/team-dispatch`, `/autoresearch-loop`).
