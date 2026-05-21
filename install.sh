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
# Writes:
#   - ~/.claude/commands/{deep-interview,plan-consensus,ralph,team-dispatch,autoresearch-loop}.md
#   - ~/.claude/commands/_shared/preamble.md
#   - ~/.claude/settings.json (only env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS + teammateMode keys;
#     other keys preserved; backup created before any modification)
#
# Honors $CLAUDE_CONFIG_DIR if set (replaces $HOME/.claude).
# Idempotent: skips identical files, backs up changed ones with timestamp suffix.
# To skip the Agent Teams auto-config step, set FTS_NO_AGENT_TEAMS_CONFIG=1.

set -euo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET_DIR="$CONFIG_DIR/commands"
SETTINGS_FILE="$CONFIG_DIR/settings.json"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPO_RAW="${FTS_OMC_LIGHT_REPO:-https://raw.githubusercontent.com/FullTimeScam/fts-omc-light/master}"

COMMANDS=(
  "deep-interview.md"
  "plan-consensus.md"
  "ralph.md"
  "team-dispatch.md"
  "autoresearch-loop.md"
)

# ─────────────────────────────────────────────────────────────
# Mode detection: local if BASH_SOURCE points to a real file next to a commands/ dir
# ─────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────
# File install helpers
# ─────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────
# Agent Teams auto-config (settings.json)
# Adds env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1" and teammateMode="in-process"
# while preserving every other key. Backs up before writing.
#
# Failure modes (all fall through to manual instruction at end):
#   - FTS_NO_AGENT_TEAMS_CONFIG=1 set → user opted out
#   - python3 not available
#   - existing settings.json has invalid JSON
#   - write permission denied
# ─────────────────────────────────────────────────────────────

AGENT_TEAMS_STATUS="UNKNOWN"
AGENT_TEAMS_DETAIL=""

configure_agent_teams() {
  if [ "${FTS_NO_AGENT_TEAMS_CONFIG:-0}" = "1" ]; then
    AGENT_TEAMS_STATUS="OPTED_OUT"
    AGENT_TEAMS_DETAIL="FTS_NO_AGENT_TEAMS_CONFIG=1"
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    AGENT_TEAMS_STATUS="NO_PYTHON"
    AGENT_TEAMS_DETAIL="python3 명령을 찾을 수 없음"
    return
  fi

  mkdir -p "$CONFIG_DIR"

  local result
  result=$(python3 - "$SETTINGS_FILE" "$TIMESTAMP" <<'PYEOF'
import json
import os
import shutil
import sys

path, ts = sys.argv[1], sys.argv[2]

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            print("INVALID_JSON")
            sys.exit(0)
    except (json.JSONDecodeError, OSError):
        print("INVALID_JSON")
        sys.exit(0)
else:
    data = {}

env = data.get("env") if isinstance(data.get("env"), dict) else {}
already_set = (
    env.get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") == "1"
    and data.get("teammateMode") == "in-process"
)

if already_set:
    print("ALREADY_SET")
    sys.exit(0)

if os.path.exists(path):
    try:
        shutil.copy2(path, f"{path}.bak-{ts}")
    except OSError as e:
        print(f"BACKUP_FAILED:{e}")
        sys.exit(0)

if not isinstance(data.get("env"), dict):
    data["env"] = {}
data["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
data["teammateMode"] = "in-process"

try:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
except OSError as e:
    print(f"WRITE_FAILED:{e}")
    sys.exit(0)

print("UPDATED")
PYEOF
) || result="EXEC_FAILED"

  case "$result" in
    ALREADY_SET)
      AGENT_TEAMS_STATUS="ALREADY_SET"
      ;;
    UPDATED)
      AGENT_TEAMS_STATUS="UPDATED"
      ;;
    INVALID_JSON)
      AGENT_TEAMS_STATUS="INVALID_JSON"
      AGENT_TEAMS_DETAIL="$SETTINGS_FILE 가 유효한 JSON 이 아님"
      ;;
    BACKUP_FAILED:*|WRITE_FAILED:*|EXEC_FAILED)
      AGENT_TEAMS_STATUS="WRITE_ERROR"
      AGENT_TEAMS_DETAIL="${result#*:}"
      ;;
    *)
      AGENT_TEAMS_STATUS="UNKNOWN"
      AGENT_TEAMS_DETAIL="$result"
      ;;
  esac
}

echo ""
echo "⚙ Agent Teams 자동 설정 (settings.json)..."
configure_agent_teams

case "$AGENT_TEAMS_STATUS" in
  ALREADY_SET)
    echo "  = 이미 활성화됨 (env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 + teammateMode=in-process)"
    ;;
  UPDATED)
    echo "  + env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = \"1\""
    echo "  + teammateMode = \"in-process\""
    if [ -f "$SETTINGS_FILE.bak-$TIMESTAMP" ]; then
      echo "  ✓ $SETTINGS_FILE 갱신 (백업: settings.json.bak-$TIMESTAMP)"
    else
      echo "  ✓ $SETTINGS_FILE 신규 생성"
    fi
    echo "  ! 변경 사항 반영을 위해 Claude Code 세션 재시작 필요"
    ;;
  *)
    echo "  ✗ 자동 설정 실패 ($AGENT_TEAMS_STATUS${AGENT_TEAMS_DETAIL:+: $AGENT_TEAMS_DETAIL})"
    echo "    /team-dispatch 를 사용하려면 $SETTINGS_FILE 에 다음 두 키를 수동으로 추가하세요:"
    echo ""
    echo "      \"env\": { \"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\": \"1\" },"
    echo "      \"teammateMode\": \"in-process\""
    echo ""
    echo "    추가 후 Claude Code 세션을 재시작하세요."
    echo "    (다른 네 명령어는 이 설정 없이도 정상 동작합니다.)"
    ;;
esac

cat <<'EOF'

✓ 설치 완료.

────────────────────────────────────────────────────────
권장 / 참고 사항
────────────────────────────────────────────────────────

[권장] 모호성 채점·합의 루프 정확도
  Opus 모델 사용 (Sonnet 도 동작하지만 정확도 ↓).

[참고] Plan Mode 활성 시
  Plan Mode 가 활성이면 .omc/specs/ 와 .omc/state/ 쓰기가
  차단되고 spec 이 ~/.claude/plans/ 의 auto-slug 파일로
  리다이렉트됩니다. 정상 동작입니다.

────────────────────────────────────────────────────────
사용 예
────────────────────────────────────────────────────────

  /deep-interview "vague idea"
  /plan-consensus path/to/spec.md
  /ralph "task description"
  /team-dispatch path/to/plan.md
  /autoresearch-loop --mission path/to/mission.md --evaluator "command"

자세한 사용법: https://github.com/FullTimeScam/fts-omc-light
EOF
