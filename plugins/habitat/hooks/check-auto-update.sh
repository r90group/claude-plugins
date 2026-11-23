#!/usr/bin/env bash
# At session start, checks that the r90 marketplace auto-updates. The plugin
# pins no version, so auto-update is how Habitat's skills and server settings
# reach everyone; without it the plugin stays on the commit it was installed
# at. Claude Code turns auto-update on only for Anthropic's marketplaces, and
# the installer turns it on for r90 only when it can edit settings (jq on
# macOS and Linux), so a machine without jq can be left behind silently.
#
# Reads extraKnownMarketplaces.r90.autoUpdate from the user settings file, the
# entry `claude plugin marketplace add` writes, with jq, else plutil (macOS),
# else python3 (Linux, not macOS: there it may be a stub that opens an install
# dialog), else PowerShell (Windows). No r90 entry there means the marketplace
# came from managed or organization settings, which this can't see: quiet.
# Quiet too when nothing can read the file.
#
# The hook never edits settings itself. It tells the user and asks Claude to
# offer turning it on; Claude edits the file only after the user agrees.
# Written for bash 3.2 (macOS) and Git Bash. Always exits 0 so a session never
# fails to start. Quiet in sessions nobody is attending (claude -p, the SDK).
set -u
[ "${CLAUDE_CODE_SESSION_ATTENDED:-1}" = 0 ] && exit 0
case "${CLAUDE_CODE_ENTRYPOINT:-}" in sdk-*) exit 0 ;; esac
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

# Cheap first pass: no r90 key at all means nothing to check.
[ -r "$settings" ] && grep -q '"r90"[[:space:]]*:' "$settings" || exit 0

windows=false
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows=true ;; Darwin) macos=true ;; esac

# Prints on, off or absent (no r90 entry); nothing when the file can't be read.
read_state() {
  if command -v jq >/dev/null 2>&1; then
    jq -r 'if (.extraKnownMarketplaces.r90 | type) != "object" then "absent" elif .extraKnownMarketplaces.r90.autoUpdate == true then "on" else "off" end' "$settings" 2>/dev/null
  elif [ "${macos:-false}" = true ] && command -v plutil >/dev/null 2>&1; then
    plutil -extract extraKnownMarketplaces.r90 json -o /dev/null "$settings" >/dev/null 2>&1 || { echo absent; return; }
    [ "$(plutil -extract extraKnownMarketplaces.r90.autoUpdate json -o - "$settings" 2>/dev/null | tr -d "[:space:]")" = true ] && echo on || echo off
  elif ! $windows && [ "${macos:-false}" != true ] && command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8")).get("extraKnownMarketplaces", {})
m = m.get("r90") if isinstance(m, dict) else None
print("absent" if not isinstance(m, dict) else "on" if m.get("autoUpdate") is True else "off")
' "$settings" 2>/dev/null
  elif $windows; then
    ps=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || command -v powershell.exe 2>/dev/null)
    [ -n "$ps" ] || return
    HABITAT_HOOK_SETTINGS=$(cygpath -w "$settings" 2>/dev/null || printf '%s' "$settings") "$ps" -NoProfile -NonInteractive -Command '
try {
  $m = ([IO.File]::ReadAllText($env:HABITAT_HOOK_SETTINGS, [Text.Encoding]::UTF8) | ConvertFrom-Json).extraKnownMarketplaces.r90
  if ($m -isnot [System.Management.Automation.PSCustomObject]) { "absent" } elseif ($m.autoUpdate -eq $true) { "on" } else { "off" }
} catch {}' 2>/dev/null | tr -d '\r'
  fi
}

[ "$(read_state)" = off ] || exit 0

shown=$settings
$windows && shown=$(cygpath -w "$settings" 2>/dev/null || printf '%s' "$settings")

# A JSON string literal for $1, without jq (Windows has none). One character
# at a time, because ${s//…/…} treats backslashes differently in bash 3.2 and 5.
json_string() {
  local s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in
      '\') out+='\\' ;;
      '"') out+='\"' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *) out+=$c ;;
    esac
  done
  printf '"%s"' "$out"
}

user_message="The Habitat plugin isn't set to auto-update, so it stays on the version you installed. Claude will offer to turn auto-update on."

context="The Habitat plugin's marketplace (r90) has auto-update turned off in ${shown}, so the plugin stays on the version that was installed and misses Habitat's updates.

At the start of your first reply, before anything else, tell the user this in one sentence and ask whether to turn auto-update on. Use your question tool if you have one (AskUserQuestion in Claude Code), with \"Turn it on\" as the recommended option and \"Not now\" as the other; if another Habitat notice also asks a question, ask both together. If this session can't ask the user (a non-interactive run), only mention it.

If they agree, open ${shown} with your file tools (no jq or other shell tools needed) and set extraKnownMarketplaces.r90.autoUpdate to true, changing nothing else in the file. If the change is refused, tell them they can do it in Claude Code instead: /plugin, then Marketplaces, then r90, then Enable auto-update. Tell them it takes effect from the next Claude Code start.

If they decline, don't bring it up again this session. Then carry on with whatever the user asked."

printf '{"systemMessage": %s, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": %s}}\n' \
  "$(json_string "$user_message")" "$(json_string "$context")"
exit 0
