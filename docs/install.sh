#!/bin/bash
# Lingo installer — https://getlingo.dev/
#   curl -fsSL https://getlingo.dev/install.sh | bash
#   curl -fsSL https://getlingo.dev/install.sh | bash -s -- uninstall
# Downloads Lingo.zip next to this script, installs it into /Applications (or ~/Applications) and starts it.
# Files fetched with curl carry no quarantine flag, so macOS opens the app without the "unidentified developer" prompt.
set -euo pipefail

APP="Lingo"
BID="com.serhii.Lingo"
MINOS="14.0"
BASE="${INSTALL_BASE_URL:-https://github.com/buhaenko/lingo/releases/latest/download}"   # where Lingo.zip lives

bold=$(tput bold 2>/dev/null || true); dim=$(tput dim 2>/dev/null || true); reset=$(tput sgr0 2>/dev/null || true)
say() { printf "%s\n" "$*"; }

if [ "$(uname)" != "Darwin" ]; then say "${APP} is a Mac app."; exit 1; fi
ver=$(sw_vers -productVersion)
if [ "$(printf '%s\n%s\n' "${MINOS}" "${ver}" | sort -V | head -1)" != "${MINOS}" ]; then
  say "${APP} needs macOS ${MINOS} or newer (you have ${ver})."; exit 1
fi

# where to install: /Applications if writable, otherwise ~/Applications
DEST="${INSTALL_DEST:-/Applications}"; [ -w "${DEST}" ] || { DEST="$HOME/Applications"; mkdir -p "${DEST}"; }

if [ "${1:-}" = "uninstall" ]; then
  if [ -n "${INSTALL_DEST:-}" ]; then
    rm -rf "${INSTALL_DEST}/${APP}.app"                       # only the given folder (used by tests)
  else
    pkill -x "${APP}" 2>/dev/null || true
    rm -rf "/Applications/${APP}.app" "$HOME/Applications/${APP}.app"
  fi
  if [ -z "${INSTALL_KEEP_DATA:-}" ]; then
    defaults delete "${BID}" 2>/dev/null || true
    rm -rf "$HOME/Library/Application Support/${APP}"
  fi
  say "${bold}${APP} removed.${reset}"; exit 0
fi

say "${bold}Installing ${APP}…${reset}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar "${BASE}/${APP}.zip" -o "$tmp/${APP}.zip"
ditto -x -k "$tmp/${APP}.zip" "$tmp"
[ -d "$tmp/${APP}.app" ] || { say "Download looks broken, please try again."; exit 1; }

[ -n "${INSTALL_DEST:-}" ] || { pkill -x "${APP}" 2>/dev/null || true; sleep 0.5; }
rm -rf "${DEST}/${APP}.app"
ditto "$tmp/${APP}.app" "${DEST}/${APP}.app"
xattr -dr com.apple.quarantine "${DEST}/${APP}.app" 2>/dev/null || true

[ -n "${INSTALL_NO_OPEN:-}" ] || open "${DEST}/${APP}.app"
say "${bold}✓ ${APP} is installed${reset} ${dim}(${DEST}/${APP}.app)${reset}"
say "${dim}It lives in your menu bar. Uninstall: curl -fsSL https://getlingo.dev/install.sh | bash -s -- uninstall${reset}"
