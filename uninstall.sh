#!/usr/bin/env bash
# fts-omc-light uninstaller
# Renames installed files with .removed-<timestamp> suffix (safe — easy to restore).
# Does not touch user's settings.json or any other files.

set -euo pipefail

TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

COMMANDS=(
  "deep-interview.md"
  "plan-consensus.md"
  "ralph.md"
  "team-dispatch.md"
  "autoresearch-loop.md"
)

echo "fts-omc-light 제거를 시작합니다."
echo "대상: $TARGET_DIR/"
echo ""

remove_one() {
  local dest="$1"
  local name="$2"

  if [ -f "$dest" ]; then
    mv "$dest" "$dest.removed-$TIMESTAMP"
    echo "  - $name → $name.removed-$TIMESTAMP"
  else
    echo "  · $name (이미 없음)"
  fi
}

for cmd in "${COMMANDS[@]}"; do
  remove_one "$TARGET_DIR/$cmd" "$cmd"
done

remove_one \
  "$TARGET_DIR/_shared/preamble.md" \
  "_shared/preamble.md"

rmdir "$TARGET_DIR/_shared" 2>/dev/null && echo "  - _shared/ (빈 디렉터리 제거)" || true

cat <<EOF

✓ 제거 완료.

.removed-$TIMESTAMP 접미사 파일들은 안전 백업입니다.
복원하려면 접미사를 제거하세요. 완전 삭제는 수동으로:

  find $TARGET_DIR -name '*.removed-*' -delete

settings.json 의 Agent Teams 설정은 건드리지 않았습니다.
필요 시 수동으로 제거하세요.
EOF
