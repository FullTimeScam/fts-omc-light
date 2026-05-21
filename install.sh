#!/usr/bin/env bash
# fts-omc-light installer
# Two modes (auto-detected):
#   1. One-line install (recommended):
#        curl -fsSL https://raw.githubusercontent.com/FullTimeScam/fts-omc-light/master/install.sh | bash
#      Downloads command files directly from GitHub. No clone, no leftover directory.
#   2. From local clone (for users who want to inspect first):
#        git clone https://github.com/FullTimeScam/fts-omc-light.git
#        cd fts-omc-light
#        ./install.sh
#      Uses the local commands/ directory.
#
# Both modes write to ~/.claude/commands/ (or $CLAUDE_CONFIG_DIR/commands/).
# Idempotent: skips identical files, backs up changed ones with timestamp suffix.
# Touches nothing else (no settings.json modification, no other directories).

set -euo pipefail

TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPO_RAW="${FTS_OMC_LIGHT_REPO:-https://raw.githubusercontent.com/FullTimeScam/fts-omc-light/master}"

COMMANDS=(
  "deep-interview.md"
  "plan-consensus.md"
  "ralph.md"
  "team-dispatch.md"
  "autoresearch-loop.md"
)

# Mode detection: local if BASH_SOURCE points to a real file next to a commands/ dir
MODE="remote"
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  CANDIDATE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || CANDIDATE=""
  if [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE/commands" ]; then
    MODE="local"
    SCRIPT_DIR="$CANDIDATE"
  fi
fi

if [ "$MODE" = "local" ]; then
  echo "fts-omc-light 설치를 시작합니다 (로컬 클론 모드)."
  echo "소스: $SCRIPT_DIR/commands/"
else
  echo "fts-omc-light 설치를 시작합니다 (원격 다운로드 모드)."
  echo "소스: $REPO_RAW/commands/"
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "✗ curl 또는 wget 이 필요합니다." >&2
    exit 1
  fi
fi
echo "대상: $TARGET_DIR/"
echo ""

mkdir -p "$TARGET_DIR" "$TARGET_DIR/_shared"

fetch_to() {
  local relpath="$1"
  local outpath="$2"
  if [ "$MODE" = "local" ]; then
    cp "$SCRIPT_DIR/commands/$relpath" "$outpath"
  else
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$REPO_RAW/commands/$relpath" -o "$outpath" || return 1
    else
      wget -q "$REPO_RAW/commands/$relpath" -O "$outpath" || return 1
    fi
  fi
}

install_one() {
  local relpath="$1"
  local dest="$2"
  local name="$3"

  local tmp
  tmp=$(mktemp)
  if ! fetch_to "$relpath" "$tmp"; then
    echo "  ✗ 다운로드 실패: $name"
    rm -f "$tmp"
    exit 1
  fi
  if [ ! -s "$tmp" ]; then
    echo "  ✗ 빈 파일: $name"
    rm -f "$tmp"
    exit 1
  fi

  if [ -f "$dest" ]; then
    if cmp -s "$tmp" "$dest"; then
      echo "  = $name (동일, 건너뜀)"
      rm -f "$tmp"
      return
    fi
    cp "$dest" "$dest.bak-$TIMESTAMP"
    mv "$tmp" "$dest"
    echo "  ↻ $name (변경됨 — 기존: $name.bak-$TIMESTAMP)"
  else
    mv "$tmp" "$dest"
    echo "  + $name (신규)"
  fi
}

for cmd in "${COMMANDS[@]}"; do
  install_one "$cmd" "$TARGET_DIR/$cmd" "$cmd"
done

install_one \
  "_shared/preamble.md" \
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

자세한 사용법: https://github.com/FullTimeScam/fts-omc-light
EOF
