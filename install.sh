#!/usr/bin/env bash
# Fallback installer for pr-review-lenses (copies the agents directly).
# The recommended install is the native Copilot CLI plugin - see README.
#
# Usage:
#   ./install.sh              # install to ~/.copilot/agents (user-level, all repos)
#   ./install.sh --repo       # install to ./.github/agents (current repo only)
#
# Or straight from GitHub (clones to a temp dir, installs, cleans up):
#   curl -fsSL https://raw.githubusercontent.com/costajohnt/pr-review-lenses/main/install.sh | bash
#
# Env:
#   REF=<tag|branch>   ref to clone in the curl | bash path (default: main)
#   FORCE=1            overwrite agents that already exist in the target dir

set -euo pipefail

REPO_URL="https://github.com/costajohnt/pr-review-lenses.git"
REF="${REF:-main}"
PLUGIN_SUBDIR="plugins/pr-review-toolkit/agents"

# Pick the target directory.
if [ "${1:-}" = "--repo" ]; then
  DEST="$(pwd)/.github/agents"
else
  DEST="${HOME}/.copilot/agents"
fi

# Find the agents source. If this script sits in a clone, use it. Otherwise
# (curl | bash) clone the repo to a temp dir first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
TMP=""
trap '[ -z "${TMP}" ] || rm -rf "${TMP}"' EXIT
if [ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/${PLUGIN_SUBDIR}" ]; then
  SRC="${SCRIPT_DIR}/${PLUGIN_SUBDIR}"
else
  TMP="$(mktemp -d)"
  echo "Fetching pr-review-lenses (${REF})..."
  # Errors stay on stderr so a bad ref or no network fails loudly.
  git clone --quiet --depth 1 --branch "${REF}" "${REPO_URL}" "${TMP}/repo"
  SRC="${TMP}/repo/${PLUGIN_SUBDIR}"
fi

agents=("${SRC}"/*.agent.md)

# Never clobber user-authored agents of the same name without FORCE=1.
existing=""
for f in "${agents[@]}"; do
  [ -e "${DEST}/$(basename "$f")" ] && existing="${existing} $(basename "$f" .agent.md)"
done
if [ -n "${existing}" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "Refusing to overwrite existing agents in ${DEST}:${existing}" >&2
  echo "Re-run with FORCE=1 to replace them." >&2
  exit 1
fi

mkdir -p "${DEST}"
cp "${agents[@]}" "${DEST}/"

echo "Installed ${#agents[@]} agents to ${DEST}:"
for f in "${agents[@]}"; do echo "  - $(basename "$f" .agent.md)"; done

echo
echo "Done. In Copilot CLI, run  /agent  to pick one, or:"
echo "  copilot --agent review-pr -p \"Review this branch against main\""
