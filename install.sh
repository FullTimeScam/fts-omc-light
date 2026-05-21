#!/usr/bin/env bash
# fts-omc-light installer
# Copies OMC port slash commands to ~/.claude/commands/ (or $CLAUDE_CONFIG_DIR/commands/).
# Idempotent: skips identical files, backs up changed ones with timestamp suffix.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

COMMANDS=(
  "deep-interview.md"
  "plan-consensus.md"
  "ralph.md"
  "team-dispatch.md"
  "autoresearch-loop.md"
)

echo "fts-omc-light 설치를 시작합니다."
echo "소스: $SCRIPT_DIR/commands/"
echo "대상: $TARGET_DIR/"
echo ""

mkdir -p "$TARGET_DIR" "$TARGET_DIR/_shared"

install_one() {
  local src="$1"
  local dest="$2"
  local name="$3"

  if [ ! -f "$src" ]; then
    echo "  ✗ 소스 파일 누락: $src" >&2
    exit 1
  fi

  if [ -f "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      echo "  = $name (동일, 건너뜀)"
      return
    fi
    cp "$dest" "$dest.bak-$TIMESTAMP"
    cp "$src" "$dest"
    echo "  ↻ $name (변경됨 — 기존: $name.bak-$TIMESTAMP)"
  else
    cp "$src" "$dest"
    echo "  + $name (신규)"
  fi
}

for cmd in "${COMMANDS[@]}"; do
  install_one "$SCRIPT_DIR/commands/$cmd" "$TARGET_DIR/$cmd" "$cmd"
done

install_one \
  "$SCRIPT_DIR/commands/_shared/preamble.md" \
  "$TARGET_DIR/_shared/preamble.md" \
  "_shared/preamble.md"

cat <<'EOF'

✓ 파일 설치 완료.

────────────────────────────────────────────────────────
다음 수동 단계가 필요할 수 있습니다:
────────────────────────────────────────────────────────

[필수 — /team-dispatch 사용 시]
  ~/.claude/settings.json 에 다음 추가:

    "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
    "teammateMode": "in-process"

  추가 후 Claude Code 세션 재시작.

[권장 — 모호성 채점·합의 루프 정확도]
  Opus 모델 사용 (Sonnet 도 동작하지만 정확도 ↓).

[참고 — Plan Mode 활성 시]
  Plan Mode 가 활성이면 .omc/specs/ 와 .omc/state/ 쓰기가
  차단되고 spec 이 ~/.claude/plans/ 의 auto-slug 파일로
  리다이렉트됩니다. 정상 동작입니다.

────────────────────────────────────────────────────────
사용 예:
────────────────────────────────────────────────────────

  /deep-interview "vague idea"
  /plan-consensus path/to/spec.md
  /ralph "task description"
  /team-dispatch path/to/plan.md
  /autoresearch-loop --mission path/to/mission.md --evaluator "command"

자세한 사용법: README.md 참조.
EOF
