# fts-omc-light

Claude Code 에게 "대충 만들어줘" 같은 막연한 부탁을 던져도, 알아서 끝까지 캐묻고 검증하고 완성하도록 만드는 다섯 개의 슬래시 명령어 모음입니다.

설치하면 Claude Code 안에서 `/deep-interview`, `/plan-consensus`, `/ralph`, `/team-dispatch`, `/autoresearch-loop` 다섯 가지를 바로 쓸 수 있습니다.

---

## 설치

깃이 설치돼 있다면 (대부분의 macOS 에는 기본 설치):

```bash
git clone https://github.com/FullTimeScam/fts-omc-light.git
cd fts-omc-light
./install.sh
```

이게 전부입니다. Claude Code 를 다음에 열면 다섯 명령어를 바로 쓸 수 있습니다.

---

## 왜 만들었나

AI 에게 뭔가를 부탁했을 때 이런 경험, 익숙하지 않으세요?

- 절반만 만들어 놓고 "완료했습니다" 라고 끝내버림
- 내가 진짜 원한 게 아니라 비슷한 다른 걸 만들어줌
- "테스트도 통과해" 라고 했는데 실제로 확인 안 하고 끝남
- 큰 작업을 시켰더니 어디서부터 손대야 할지 헤매다가 시간만 씀

이 다섯 명령어는 그런 상황을 막으려고 만들어졌습니다. 각자 다른 단계에서 끼어들어서, AI 가 "대충" 끝내지 못하게 합니다.

원본은 [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) 라는 큰 패키지인데, 그 중 가장 핵심적인 다섯 가지만 떼어내서 **외부 패키지 설치 없이** 동작하도록 다시 만든 게 이 프로젝트입니다.

---

## 무엇이 들어있나

| 명령어 | 한 줄 요약 | 언제 쓰나 |
|---|---|---|
| `/deep-interview` | AI 가 당신의 아이디어를 점수 매기며 끝까지 캐묻습니다 | 막연한 아이디어를 명확한 명세로 만들고 싶을 때 |
| `/plan-consensus` | 세 명의 AI 가 계획을 짠 뒤 서로 까며 합의에 이릅니다 | "이 계획이 정말 옳을까?" 가 궁금할 때 |
| `/ralph` | "다 끝났습니다" 라고 거짓말 못 하게 매 단계를 증거로 확인합니다 | 한 번에 끝까지 가야 하는 작업일 때 |
| `/team-dispatch` | 여러 AI 가 팀을 이뤄 동시에 작업합니다 | 큰 작업을 빠르게 끝내고 싶을 때 |
| `/autoresearch-loop` | 평가 함수를 정해두면 합격할 때까지 AI 가 반복합니다 | "이 정도면 됐다" 의 기준이 명확할 때 |

---

## 어떻게 동작하나

가장 많이 쓰게 될 `/deep-interview` 를 예로 들면 이렇게 흘러갑니다.

당신:
```
/deep-interview "회의록 자동 정리하는 거 만들어줘"
```

AI:
> Deep Interview 임계값: 5% (현재 모호성: 100%)
>
> 이 아이디어를 4개 컴포넌트로 읽었습니다:
>   1. 회의 녹음 캡처
>   2. 음성→텍스트 변환
>   3. 요약 생성
>   4. 저장·공유
>
> 토폴로지가 맞나요?

당신이 답하면 AI 가 점수표를 보여주고, 점수가 가장 낮은 영역만 골라 다시 묻습니다. 이게 모호성이 5% 이하로 떨어질 때까지 반복됩니다. 떨어지면 명세 파일이 한 장으로 완성됩니다.

완성된 명세를 `/plan-consensus` 에 넘기면 계획이 만들어지고, 그 계획을 `/ralph` 에 넘기면 실제 코드가 만들어집니다. 마치 신입에게 일을 맡길 때처럼, 한 단계씩 또렷하게 확인하면서 진행하는 방식입니다.

---

설치 스크립트는:
- 명령어 파일들을 `~/.claude/commands/` 에 복사합니다
- 같은 이름의 파일이 이미 있는데 내용이 다르면, 기존 파일을 백업한 뒤 덮어씁니다
- 내용이 같으면 건너뜁니다 (그래서 여러 번 실행해도 안전합니다)
- 그 외 어떤 설정도 건드리지 않습니다

---

## 한 가지 수동 설정 (`/team-dispatch` 사용 시)

`/team-dispatch` 는 Claude Code 의 "Agent Teams" 라는 실험 기능을 씁니다. 이걸 켜려면 `~/.claude/settings.json` 파일을 열어서 다음 두 항목을 추가해야 합니다.

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "in-process"
}
```

추가 후 Claude Code 세션을 닫고 다시 여세요.

이 설정을 안 해도 다른 네 명령어는 정상 동작합니다. `/team-dispatch` 도 폴백 모드로는 돌아가지만, 팀원 AI 들이 서로 메시지를 주고받지 못하고 각자 작업만 하게 됩니다.

---

## 알아두면 좋은 것들

### 어떤 모델이 좋나
가능하면 **Opus** 를 권장합니다. 모호성 점수 매기기와 합의 루프의 정확도가 Sonnet 보다 눈에 띄게 좋습니다. Sonnet 으로도 동작은 합니다 — 단지 채점이 조금 더 들쭉날쭉할 수 있습니다.

### Plan Mode 와 같이 쓰면
Claude Code 의 Plan Mode 가 켜져 있으면 명세 파일이 평소 위치 (`.omc/specs/`) 대신 `~/.claude/plans/` 의 자동 생성 이름으로 옮겨갑니다. 정상 동작입니다 — 명령어들이 Plan Mode 를 감지해서 알아서 대응하니까 신경 쓰지 않아도 됩니다.

### 결과는 어디에 저장되나
모든 산출물은 현재 작업 폴더의 `.omc/` 안에 정리됩니다:

```
.omc/
├── specs/           ← /deep-interview 의 완성된 명세
├── plans/           ← /plan-consensus 의 합의 계획
├── state/sessions/  ← 진행 상태 (중단되면 여기서 재개됨)
├── handoffs/        ← /team-dispatch 의 단계별 인수인계
└── autoresearch/    ← /autoresearch-loop 의 실험 기록
```

### 기본 모호성 임계값을 바꾸고 싶다면
`/deep-interview` 는 기본적으로 모호성이 **5% 이하** 가 될 때까지 질문을 던집니다. 더 빨리 끝내고 싶으면 20% (원본 기본값) 으로 올리세요. 한 줄로 가능합니다:

```bash
sed -i.bak 's/Default `0\.05`/Default `0.20`/' ~/.claude/commands/deep-interview.md
```

---

## 실전 흐름 예시

다섯 명령어를 한 번에 엮어서 쓰면 이런 식이 됩니다:

```bash
# 1) 막연한 아이디어를 명세로
/deep-interview "회의록 자동 정리하는 거 만들어줘"

# 2) 명세를 합의된 계획으로
/plan-consensus .omc/specs/deep-interview-회의록정리.md

# 3) 계획을 실제 코드로 (한 명의 AI 가 끝까지)
/ralph "plan 파일: .omc/plans/plan-consensus-회의록정리.md 의 모든 AC 통과"

# 또는 (3') 여러 AI 가 병렬로
/team-dispatch .omc/plans/plan-consensus-회의록정리.md
```

별도 워크플로우로, "평가 함수가 통과할 때까지 무한 반복" 도 가능합니다:

```bash
/autoresearch-loop --mission .omc/specs/회의록정리.md --evaluator "pytest tests/"
```

각 명령어에 세부 옵션이 더 있습니다 (`--quick`, `--deliberate`, `--no-deslop` 등). 자세한 건 설치된 명령어 파일 (`~/.claude/commands/*.md`) 의 본문을 직접 참조하세요.

---

## 제거

`~/.claude/commands/` 에 설치된 다섯 파일을 안전하게 옮겨두려면:

```bash
curl -fsSL https://raw.githubusercontent.com/FullTimeScam/fts-omc-light/master/uninstall.sh | bash
```

또는 클론한 적이 있다면 `./uninstall.sh` 로도 됩니다.

설치된 파일들이 `.removed-<날짜시간>` 접미사로 옮겨집니다. 잘못 지웠다면 접미사만 떼어내면 복원됩니다. settings.json 의 Agent Teams 설정은 자동으로 건드리지 않으니, 필요하면 손으로 지우세요.

---

## 출처와 신뢰도

원본은 [Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (MIT 라이선스). 이 프로젝트는 그 중 다섯 개 핵심 기능을 떼어내서 외부 패키지 설치 없이 동작하도록 재구현한 것입니다.

원본 대비 **94.73% 의 동작 충실도** (정적 분석 기준 — 카테고리별 가중치 채점). 토큰 사용량은 원본의 **64%** 수준 (한국어로 번역하면 길어질 텐데, 영어 내부 인스트럭션 + 분량 압축으로 오히려 줄어들었습니다).

차이 항목과 의도적 변경 내역은 [ATTRIBUTION.md](./ATTRIBUTION.md) 에 정리돼 있습니다.

라이선스는 [MIT](./LICENSE) — 자유롭게 사용·수정·재배포 가능합니다.

원본을 만든 [@Yeachan-Heo](https://github.com/Yeachan-Heo) 에게 감사를 전합니다. 명세가 워낙 정성스럽게 쓰여 있었기에 이렇게 깔끔하게 떼어낼 수 있었습니다.
