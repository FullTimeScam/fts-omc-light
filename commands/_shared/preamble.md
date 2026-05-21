# OMC Local Port — Shared Preamble

Applied across `/deep-interview`, `/plan-consensus`, `/ralph`, `/team-dispatch`, `/autoresearch-loop`. Each command's first action MUST be `Read ~/.claude/commands/_shared/preamble.md` and apply these rules as the operating context.

## Critical Adherence Rules (MANDATORY — never override for brevity)

These rules apply across all commands. The model MUST NOT optimize them away even if a task seems simple, or a mode flag (`--quick`) suggests brevity, or a runtime mode (Plan Mode) seems to make them moot. Empirical past failures (2026-05-22 deep-interview smoke test) showed these are the most-violated invariants — they need explicit enforcement.

1. **First-action discipline**: When a command begins with `Read ~/.claude/commands/_shared/preamble.md`, this MUST be the literal first tool call. Do NOT skip it on the assumption "I already know the preamble from training / earlier turn / prior invocation". Each invocation requires the explicit Read so subsequent tool-result tracking confirms it ran. Skipping this Read is a primary cause of preamble rules being silently dropped.

2. **AskUserQuestion atomicity**: Each `AskUserQuestion` call MUST contain **exactly 1 question** in its `questions` array. Never batch multiple decisions into one call, even when several decisions are needed in a row — split them across rounds or sequential calls. Batching is explicitly forbidden because it (a) produces shallow answers, (b) breaks per-dimension scoring in deep-interview, (c) violates the upstream OMC "one question at a time" rule shown as the first "Bad" example in every interview-style command. The temptation to batch is highest in `--quick` mode — resist it.

3. **Mode-agnostic gates**: Phase numbering, blocking gates (Phase 0 threshold resolution, Round 0 topology enumeration, mandatory state writes, Phase 5 handoff bridges, etc.) apply regardless of `--quick` / `--standard` / `--deep` mode flags. Mode flags ONLY affect soft warning / hard cap round thresholds. They NEVER make a structural step optional. "It's quick, the task is simple, I can skip Round 0" is a wrong reasoning chain that has actually occurred — do not repeat it.

4. **Plan Mode interaction**: When Claude Code Plan Mode is active (detectable via prior turn context, the inability to Write outside the plan file, or a `<system-reminder>` mentioning plan mode), the command MUST:
   - Emit this notice once after Phase 0 threshold output:
     > ⚠️ Plan Mode 활성 감지됨. `.omc/state/` 와 `.omc/specs/` mutation 이 차단됩니다. 상태 영속성·재개 기능이 비활성화되며 spec 은 plan 파일로 리다이렉트됩니다. 완전한 워크플로우를 원하시면 ExitPlanMode 후 재실행 권장.
   - Continue with read-only flow (skip every `Write` to `.omc/`, do not call `Bash mkdir`).
   - Still emit ALL `AskUserQuestion` gates including Round 0 topology confirmation, per-round answer collection, soft-limit checks, and Phase 5 execution bridge. These are read-only interactions and remain mandatory.
   - On Phase 4 spec crystallization, write the spec body into the plan file instead of `.omc/specs/`. Phase 5 bridge options are still emitted to the user as text before `ExitPlanMode`.

## Output Language

All user-facing output MUST be in Korean: announcements, `AskUserQuestion` question text and option labels, progress reports, error messages, final summaries.

Internal instructions, persona prompts to subagents, JSON keys, and code blocks are in English for token efficiency. Subagent persona prompts include a "Respond in Korean" line so their outputs land in Korean.

## Session ID Resolution

`SESSION_ID = $CLAUDE_SESSION_ID`. If empty, ask via `AskUserQuestion` with question "세션 ID를 감지하지 못했습니다. 임의 UUID로 진행할까요?" and options `[진행, 취소]`. On `진행`, generate via Bash `uuidgen`.

## State / Artifact Path Discipline

- All Read/Write restricted to `$CWD/.omc/`. Reject any path outside.
- Final artifacts: `.omc/specs/`, `.omc/plans/`, `.omc/autoresearch/<mission-slug>/`.
- Ephemeral state: `.omc/state/sessions/${SESSION_ID}/`.
- Persona scratchpads: `.omc/state/sessions/${SESSION_ID}/<command>-<slug>/`.

## Cancel Handling

If user says any of `취소 / stop / 중단 / abort` at any phase: stop immediately, set `active: false` + `aborted_at: <ISO>` in the active state JSON, then report cancellation in Korean.

## Context Guard

- If estimated context usage > 75%: ask via `AskUserQuestion` `[계속, 일시 중단]` before next major step. On `일시 중단`, write state JSON and exit.
- If > 90%: force pause, save state, exit with a Korean summary.

## External Plugin Policy

This local port forbids `Skill("oh-my-claudecode:*")` calls (security policy: external OMC plugin not installed). All OMC functionality is reimplemented via Claude Code built-ins or sibling local slash commands. Where original OMC used `oh-my-claudecode:<agent>` subagents (executor / architect / critic / etc.), use `Task(subagent_type="general-purpose")` with the English persona prompt and a `Respond in Korean` directive.

Mapping table (informational, used by `/deep-interview` Phase 5 and similar handoff bridges):
- OMC `plan` (consensus) → local `/plan-consensus`
- OMC `team` → local `/team-dispatch`
- OMC `autoresearch` → local `/autoresearch-loop`
- OMC `autopilot` (full pipeline) → local chain `/plan-consensus → /ralph`
- OMC `explore` → built-in `Task(subagent_type="Explore")`

## AskUserQuestion Pattern

- **Exactly 1 question per call** (see Critical Adherence Rule #2 — non-negotiable).
- 2–4 contextually relevant options + free-text fallback (UI provides "Other" automatically).
- Question text and option labels in Korean.
- Use `multiSelect: true` only when options are not mutually exclusive.

## Opus Recommendation

Ambiguity scoring (deep-interview), Planner/Architect/Critic personas (plan-consensus, ralph), and reviewer modes work best in Opus. Non-Opus sessions: warn user with `AskUserQuestion` "이 워크플로우의 평가 정확도는 Opus 세션에서 가장 높습니다. 진행할까요?" and options `[Opus로 재시작, 현재 모델로 진행]`. On `재시작`, exit immediately.

## State JSON Skeleton (boilerplate referenced by each command)

```json
{
  "active": true,
  "current_phase": "<command-id>",
  "state": {
    "<command-specific fields>": "...",
    "threshold": "<if applicable>",
    "threshold_source": "<if applicable>"
  }
}
```

Always preserve `threshold_source` next to `threshold` when applicable. Always include `aborted_at` and `completion` fields on terminal write.

## Tool Loading

Commands that need deferred tools (`TeamCreate`, `Monitor`, `TaskCreate`, etc.) must call `ToolSearch("select:<name>[,<name>...]")` before first use. Do not invoke deferred tools by name without loading their schemas.

## Subagent Output Norm

When spawning a persona via `Task(subagent_type="general-purpose")`, the persona prompt MUST:
1. Begin with `You are now in <NAME> persona/mode.`
2. Include `Respond in Korean.` as a separate line.
3. Define role, principles, output structure in English.
4. Reference input data with placeholders like `{spec_path}`, `{file_list}`.

## Verification Discipline

Verification commands run via Bash MUST capture: command, exit code, stdout tail (last 500 chars), passed boolean. Persist as `evidence[]` entries in state JSON. Never trust cached memory of prior runs — re-run on every verification round.
