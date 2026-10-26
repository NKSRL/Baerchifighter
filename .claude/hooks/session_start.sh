#!/bin/bash
# SessionStart-Hook: stellt in Cloud-Sitzungen die Luau-CLI bereit (luau-bin/, steht in .gitignore).
# Auf dem Laptop/Heim-PC (Windows) tut er nichts; dort liegt luau-bin/ von Hand (siehe CLAUDE.md).
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ ! -x luau-bin/luau ] || [ ! -x luau-bin/luau-compile ]; then
  mkdir -p luau-bin
  curl -sSL --retry 3 -o luau-bin/luau-ubuntu.zip \
    https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip
  (cd luau-bin && unzip -oq luau-ubuntu.zip && rm -f luau-ubuntu.zip && chmod +x luau luau-compile luau-analyze luau-ast 2>/dev/null || true)
fi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export LUAU=\"$PWD/luau-bin/luau\"" >> "$CLAUDE_ENV_FILE"
  echo "export PATH=\"$PWD/luau-bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
echo "Luau-CLI bereit (luau-bin/). Pruefen: python tools/check_all.py"
