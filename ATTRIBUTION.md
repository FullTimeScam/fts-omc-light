# Attribution

## Upstream

This project is a derivative work of **[`Yeachan-Heo/oh-my-claudecode`](https://github.com/Yeachan-Heo/oh-my-claudecode)** (OMC), licensed under MIT.

OMC is a comprehensive multi-agent orchestration package for Claude Code. We re-implement a subset of its core skills as local slash commands (`~/.claude/commands/*.md`) to avoid installing the OMC npm package while preserving its key behaviors.

## What was ported

| Local file | OMC source (path in upstream repo) |
|---|---|
| `commands/deep-interview.md` | `skills/deep-interview/SKILL.md` |
| `commands/plan-consensus.md` | `skills/plan/SKILL.md` (Consensus mode only) |
| `commands/ralph.md` | `skills/ralph/SKILL.md` |
| `commands/team-dispatch.md` | `skills/team/SKILL.md` |
| `commands/autoresearch-loop.md` | `skills/autoresearch/SKILL.md` |
| `commands/_shared/preamble.md` | Synthesized — common rules across the 5 above |

## Fidelity measurement

Static analysis (category × weight scoring) measured 2026-05-22:

| Skill | Fidelity | Notes |
|---|---:|---|
| `/deep-interview` | 98.35% | Phase 0~5 + Round 0 + challenge modes + spec template all preserved |
| `/ralph` | 99.00% | PRD loop + reviewer + deslop + regression all preserved |
| `/plan-consensus` | 89.50% | Consensus mode 100% fidelity; Interview/Direct/Review modes intentionally not ported (covered by other surfaces) |
| `/team-dispatch` | 79.50% | Core staged pipeline preserved; CLI workers (Codex/Gemini), Runtime V2, dynamic scaling, per-role routing not ported |
| `/autoresearch-loop` | 100.00% | Upstream was 90-line contract spec; we provide full implementation while preserving the contract |
| `autopilot` chain | 83.33% | No standalone file — equivalent to `/plan-consensus → /ralph` chain |
| `explore` | 100.00% | Both use Claude Code built-in `Task(subagent_type="Explore")` |
| **Suite weighted** | **94.73%** | Weights: deep-interview 40%, plan 15%, ralph 15%, team 10%, autoresearch 10%, autopilot 5%, explore 5% |

Token efficiency: 38,703 tokens (OMC originals) → 24,725 tokens (this port, including shared preamble) = **0.639x (36% smaller)**.

## Intentional differences from upstream

These are by design (security policy or local environment constraints), not gaps:

1. **No external plugin calls**: `Skill("oh-my-claudecode:*")` invocations are forbidden. Replaced with built-in `Task(subagent_type="general-purpose")` + English persona prompts. Persona content preserved.
2. **No OMC-specific subagents**: `oh-my-claudecode:executor`, `:architect`, `:critic`, etc. → equivalent persona prompts injected into `general-purpose` subagent calls.
3. **No MCP state tools**: Upstream `state_write` / `state_read` MCP tools → local JSON files in `.omc/state/sessions/{session-id}/`.
4. **Korean output, English internals**: User-facing strings (announcements, AskUserQuestion text, progress reports) are Korean. Internal instructions and persona prompts are English. Each persona includes a "Respond in Korean" directive.
5. **Shared preamble**: Common rules (path discipline, cancel handling, context guard, plugin policy, AskUserQuestion atomicity, Plan Mode interaction) are extracted to `_shared/preamble.md` and loaded as the first action of every command. Upstream has these rules inline per skill.
6. **Compressed team worker preamble**: `team-dispatch` worker preamble shortened from ~800 tokens (verbose Korean) to ~300 tokens (English 6-step protocol). All 6 protocol steps + BLOCKED/ERRORS/RULES preserved.
7. **Default ambiguity threshold 0.05**: Upstream OMC default is `0.2`. Local port defaults to `0.05` (stricter). Override by editing the spec body — Claude Code's settings.json schema rejects `omc.*` namespace so settings-based override is blocked in this environment.

## What was NOT ported

These OMC features are out of scope for the local port:

- **OMC npm package install** — full plugin with custom MCP servers, agent definitions, hooks
- **Codex CLI / Gemini CLI workers** (`/team-dispatch` only spawns Claude teammates)
- **Runtime V2 event-driven team monitoring** (`/team-dispatch` uses polling + SendMessage)
- **Dynamic team scaling** (mid-session scale_up/scale_down)
- **Per-role provider/model routing config** (`omc.jsonc` style)
- **Git worktree integration for team workers** (mentioned in `/ralph` only as a safety prompt)
- **Optional company-context MCP call** (Phase 4 step 0 in upstream deep-interview)
- **Native plugin invocation guard** (irrelevant — this port is invoked as `/deep-interview` natively, not via plugin path)

## Adherence rule additions (not in upstream)

These were added after empirical testing revealed adherence failures:

- **Critical Adherence Rules** in `_shared/preamble.md` (4 MANDATORY rules):
  1. First-action discipline (always Read preamble explicitly)
  2. AskUserQuestion atomicity (exactly 1 question per call — no batching)
  3. Mode-agnostic gates (`--quick` does not make Phase 0 / Round 0 optional)
  4. Plan Mode interaction (emit notice, continue read-only, still emit user gates)
- **🚫 banners** in `deep-interview.md` at Round 0, Phase 2b, Phase 5 with explicit past-failure citations to prevent model self-optimization that bypasses spec.

## License

Both upstream OMC and this port are MIT licensed. Redistribution, modification, and commercial use are allowed with attribution preservation.

Upstream copyright: see [Yeachan-Heo/oh-my-claudecode/LICENSE](https://github.com/Yeachan-Heo/oh-my-claudecode/blob/main/LICENSE).
This port copyright: see [LICENSE](./LICENSE).

## Thanks

To [@Yeachan-Heo](https://github.com/Yeachan-Heo) for OMC's design and the rigor of its skill specs. The fidelity score reflects how carefully the upstream behaviors were specified — easy to port because each phase, formula, and gate was unambiguous.
