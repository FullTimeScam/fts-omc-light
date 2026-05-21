# fts-omc-light

OMC ([`Yeachan-Heo/oh-my-claudecode`](https://github.com/Yeachan-Heo/oh-my-claudecode), MIT) 의 핵심 5개 스킬을 **Claude Code 빌트인 기능만으로** 재구현한 경량 슬래시 커맨드 포트.

외부 OMC 플러그인 설치 없이 OMC 의 동작 ~95% 를 그대로 받을 수 있도록 만들었습니다. 보안 정책상 외부 의존성을 최소화해야 하는 환경에서 유용합니다.

---

## 무엇이 들어있나

| 슬래시 | 매핑된 OMC 스킬 | 용도 |
|---|---|---|
| `/deep-interview` | `$deep-interview` | Socratic 인터뷰 + 모호성 점수 게이트로 모호한 아이디어를 명확한 spec 으로 결정화 |
| `/plan-consensus` | `$plan --consensus` | Planner/Architect/Critic 합의 루프로 spec → 합의 plan (RALPLAN-DR + ADR) |
| `/ralph` | `$ralph` | PRD 기반 8단계 실행 루프 (스토리별 구현 → 검증 → reviewer → deslop) |
| `/team-dispatch` | `$team` | 빌트인 Agent Teams 활용 N 개 teammate 병렬 dispatch (staged pipeline) |
| `/autoresearch-loop` | `$autoresearch` | mission + evaluator 기반 stateful 미션 개선 루프 |

추가로 `_shared/preamble.md` — 5개 커맨드가 공통으로 따르는 규칙 (출력 언어, 경로 규율, cancel/context guard, 외부 플러그인 정책, AskUserQuestion 패턴, Critical Adherence Rules) 을 단일 파일로 추출.

---

## 요구사항

- **Claude Code v2.1.32 이상** (`/team-dispatch` 의 Agent Teams 기능)
- **macOS / Linux / WSL** (bash + cp/mkdir 만 사용)
- **Opus 모델 권장** (모호성 채점, 합의 루프, reviewer 페르소나 정확도)

---

## 설치

```bash
git clone https://github.com/FullTimeScam/fts-omc-light.git
cd fts-omc-light
./install.sh
```

설치 스크립트는:
- `~/.claude/commands/` 에 5개 `.md` 파일과 `_shared/preamble.md` 복사
- 멱등 (재실행 안전 — 동일 파일은 건너뜀)
- 기존 파일이 다르면 `.bak-<timestamp>` 로 백업 후 덮어쓰기
- `~/.claude/settings.json` 등 다른 파일은 건드리지 않음

---

## 수동 설정 (필수/권장)

설치 스크립트는 파일만 복사합니다. 다음은 사용자가 직접:

### 1. `/team-dispatch` 사용 시 — Agent Teams 활성화 (필수)

`~/.claude/settings.json` 에 다음 추가:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "in-process"
}
```

추가 후 Claude Code 세션 재시작.

이 설정이 없으면 `/team-dispatch` 가 폴백 모드 (병렬 Task spawn, coordination 없음) 로 동작합니다.

### 2. 모호성 채점 정확도 — Opus 권장

Sonnet 도 동작하지만 채점 일관성이 떨어집니다. `/deep-interview` 와 `/plan-consensus` 는 Opus 세션에서 가장 잘 작동합니다.

### 3. Plan Mode 활성 시 동작 — 인지만 하면 됨

Claude Code Plan Mode (`"defaultMode": "plan"`) 가 활성이면:
- `.omc/specs/` 와 `.omc/state/` 쓰기가 차단되고 spec 이 `~/.claude/plans/` 의 자동 슬러그 파일로 리다이렉트됨
- 이는 Claude Code 자체 동작이며 정상입니다
- 커맨드들은 Plan Mode 를 자동 감지하고 read-only 흐름으로 진행

### 4. 모호성 임계값 변경 (선택)

기본 임계값은 `0.05` (사용자 선호; upstream OMC default 는 `0.2`).

Claude Code 의 settings.json schema 가 `omc` 네임스페이스를 거부하므로 직접 spec 수정으로만 가능:

```bash
sed -i.bak 's/Default `0\.05`/Default `0.20`/' ~/.claude/commands/deep-interview.md
```

---

## 사용

```bash
# 1) 모호한 아이디어를 spec 으로
/deep-interview "사용자 인증 시스템을 만들고 싶어"
# → .omc/specs/deep-interview-<slug>.md

# 2) spec 을 합의 plan 으로 정제
/plan-consensus .omc/specs/deep-interview-<slug>.md
# → .omc/plans/plan-consensus-<slug>.md

# 3) plan 을 실행 (단일 세션)
/ralph "plan 파일: .omc/plans/plan-consensus-<slug>.md 의 모든 AC 통과"
# → .omc/state/sessions/<id>/prd.json + progress.txt

# 또는 (3') 병렬 실행
/team-dispatch .omc/plans/plan-consensus-<slug>.md
# → ~/.claude/teams/<slug>/ + .omc/handoffs/team-*.md

# autoresearch (별도 surface, mission + evaluator stateful 루프)
/autoresearch-loop --mission .omc/specs/<mission>.md --evaluator "pytest tests/" --max-runtime 2h
# → .omc/autoresearch/<mission>/runs/<run-id>/
```

플래그:
- `/deep-interview --quick|--standard|--deep` (라운드 hard cap 10/20/30)
- `/deep-interview --autoresearch` (autoresearch 셋업 모드)
- `/plan-consensus --deliberate` (pre-mortem + 확장 테스트 계획 강제, auth/migration 등 자동 발동)
- `/plan-consensus --interactive` (초안 검토 + 최종 승인 게이트)
- `/ralph --critic=architect|critic|codex` (reviewer 선택)
- `/ralph --no-deslop` (ai-slop-cleaner 패스 생략)
- `/team-dispatch N:agent-type` (워커 수 + 타입 명시)
- `/team-dispatch --ralph` (전체 파이프라인을 ralph 로 래핑)

---

## 출력 위치

모든 산출물은 작업 디렉터리의 `.omc/` 트리 안에:

```
.omc/
├── specs/
│   └── deep-interview-{slug}.md
├── plans/
│   └── plan-consensus-{slug}.md
├── state/sessions/{session-id}/
│   ├── deep-interview-{slug}.json
│   ├── plan-consensus-{slug}.json
│   ├── plan-consensus-{slug}/iteration_{N}_{role}.md
│   ├── prd.json                 (ralph)
│   └── progress.txt             (ralph)
├── handoffs/
│   └── team-{stage}.md          (team-dispatch)
└── autoresearch/{mission-slug}/
    ├── mission.md
    ├── evaluator.json
    └── runs/{run-id}/
        ├── evaluations/iteration-NNNN.json
        ├── decision-log.md
        └── summary.md
```

Plan Mode 활성 시엔 `.omc/specs/` 쓰기가 Claude Code 의 `~/.claude/plans/` (또는 `plansDirectory` 설정값) 으로 리다이렉트됩니다.

---

## 충실도

OMC 원본 대비 **94.73%** 동작 의미 충실도 (정적 분석, 카테고리×가중치 채점).
스킬별:
- `/deep-interview`: 98.35%
- `/ralph`: 99.00%
- `/plan-consensus`: 89.50% (Consensus mode 만 단독 포팅)
- `/team-dispatch`: 79.50% (Codex/Gemini CLI workers, Runtime V2, dynamic scaling 등 고급 기능 미이식)
- `/autoresearch-loop`: 100.00%
- autopilot 등가 체인 (`/plan-consensus → /ralph`): 83.33%

토큰 효율: OMC 원본 총 38,703 토큰 → 본 포트 24,725 토큰 (**0.639x, -36%**).

상세 비교는 [ATTRIBUTION.md](./ATTRIBUTION.md) 참조.

---

## 의도적 차이 (감점 아님)

- `Skill("oh-my-claudecode:*")` 직접 호출 0건 — 빌트인 `Task(subagent_type="general-purpose")` + 페르소나 프롬프트 주입으로 대체
- OMC 전용 서브에이전트 (`oh-my-claudecode:executor/architect/critic/...`) → 동등 페르소나 프롬프트로 재구현
- MCP `state_write/state_read` → 로컬 JSON 파일 (`.omc/state/sessions/{id}/`)
- 사용자 가시 출력은 한국어, 내부 인스트럭션은 영어 (토큰 효율)

---

## 제거

```bash
./uninstall.sh
```

`~/.claude/commands/` 의 5개 파일 + `_shared/preamble.md` 만 `.removed-<timestamp>` 접미사로 안전 보관. settings.json 의 Agent Teams 설정은 건드리지 않습니다.

---

## 라이선스

MIT — [LICENSE](./LICENSE) 참조.
Upstream OMC ([Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)) 도 MIT 라이선스로 ATTRIBUTION 만 보존하면 자유롭게 재배포·재구현 가능합니다.

---

## 출처 + 감사

상세 출처·차이·이식 내역은 [ATTRIBUTION.md](./ATTRIBUTION.md) 참조.

Upstream OMC 의 저자 [@Yeachan-Heo](https://github.com/Yeachan-Heo) 에게 감사합니다.
