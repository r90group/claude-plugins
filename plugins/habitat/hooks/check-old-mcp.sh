#!/usr/bin/env bash
# At session start, finds the old local Habitat MCP server (@adminifi/habitat-mcp,
# formerly apollo-mcp) if it is still configured. It runs pinned to whatever
# version was installed, beside this plugin's hosted server, so Claude sees two
# copies of every Habitat tool.
#
# An old entry is what the uninstaller removes: a server named habitat or
# apollo that runs a local command (no "url"), for this plugin's Habitat (its
# HABITAT_API_URL is Apollo's, or it names none). Hosted entries and entries
# for another Habitat are fine. Looks in
# ~/.claude.json (user scope and every project's local scope) and this
# project's .mcp.json. Reads the JSON with jq on macOS and Linux, and with
# PowerShell (find-old-mcp.ps1) on Windows, where Git Bash has no jq.
#
# The hook never edits config itself. It tells the user, and gives Claude the
# exact uninstall command to offer; Claude runs it only after the user agrees.
# Written for bash 3.2 (macOS) and Git Bash. Always exits 0 so a session never
# fails to start. Quiet in sessions nobody is attending (claude -p, the SDK):
# there is no one to ask, and their output may be parsed.
set -u
[ "${CLAUDE_CODE_SESSION_ATTENDED:-1}" = 0 ] && exit 0
case "${CLAUDE_CODE_ENTRYPOINT:-}" in sdk-*) exit 0 ;; esac
ORIGIN="https://apollo.adminifi.com"
CREDENTIALS_URL="${ORIGIN}/settings?tab=credentials"
hook_dir=$(cd "$(dirname "$0")" && pwd)
user_file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_file="$project_dir/.mcp.json"
windows=false
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows=true ;; esac

# Cheap first pass: no habitat or apollo key in either file means nothing to
# do, without starting jq or PowerShell.
candidate() { [ -r "$1" ] && grep -Eq '"(habitat|apollo)"[[:space:]]*:' "$1"; }
candidate "$user_file" || candidate "$project_file" || exit 0

# A JSON string literal for $1. Hook output is built here rather than with jq,
# which Windows doesn't have. One character at a time, because ${s//…/…}
# treats backslashes differently in bash 3.2 (macOS) and bash 5.
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

# A warning with the manual steps, for when the config can't be read here.
manual_warning() {
  if $windows; then how="irm ${ORIGIN}/uninstall/ps1 | iex in PowerShell"; else how="install jq, then run curl -fsSL ${ORIGIN}/uninstall | bash"; fi
  printf '{"systemMessage": %s}\n' "$(json_string "The old local Habitat MCP server may still be configured. To remove it so only the Habitat plugin's server runs, ${how}, then revoke its old token in Habitat under Settings, API credentials.")"
}

in_user=false
in_project=false
if $windows; then
  ps=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || command -v powershell.exe 2>/dev/null)
  if [ -z "$ps" ]; then manual_warning; exit 0; fi
  script=$(cygpath -w "$hook_dir/find-old-mcp.ps1" 2>/dev/null || printf '%s' "$hook_dir/find-old-mcp.ps1")
  script=${script//\'/\'\'}
  found=$(HABITAT_HOOK_ORIGIN=$ORIGIN HABITAT_HOOK_USER_FILE=$(cygpath -w "$user_file" 2>/dev/null || printf '%s' "$user_file") \
    HABITAT_HOOK_PROJECT_FILE=$(cygpath -w "$project_file" 2>/dev/null || printf '%s' "$project_file") \
    "$ps" -NoProfile -NonInteractive -Command "iex ([IO.File]::ReadAllText('${script}'))" 2>/dev/null | tr -d '\r')
  case "$found" in
    *user=1*) in_user=true ;;
  esac
  case "$found" in
    *project=1*) in_project=true ;;
  esac
  case "$found" in
    *user=*) ;;
    *) grep -Eqs '@adminifi/(habitat|apollo)-mcp|"(habitat|apollo)-mcp"|(habitat|apollo)[/\\]mcp[/\\]server\.mjs' "$user_file" "$project_file" && manual_warning; exit 0 ;;
  esac
elif command -v jq >/dev/null 2>&1; then
  OLD_ENTRY='def old_entry: (.key == "habitat" or .key == "apollo") and (.value | type == "object") and (.value.url == null) and ((.value.type // "stdio") == "stdio") and ($origin == "" or ((.value.env | if type == "object" then (.HABITAT_API_URL // .APOLLO_API_URL // "") else "" end) | tostring | . == "" or startswith($origin)));
def hits: if (.mcpServers | type) == "object" then [.mcpServers | to_entries[] | select(old_entry)] | length else 0 end;'
  [ -r "$user_file" ] && jq -e --arg origin "$ORIGIN" "$OLD_ENTRY"' (hits + ([(.projects // {} | if type == "object" then .[] else empty end) | if type == "object" then hits else 0 end] | add // 0)) > 0' "$user_file" >/dev/null 2>&1 && in_user=true
  [ -r "$project_file" ] && jq -e --arg origin "$ORIGIN" "$OLD_ENTRY"' hits > 0' "$project_file" >/dev/null 2>&1 && in_project=true
else
  grep -Eqs '@adminifi/(habitat|apollo)-mcp|"(habitat|apollo)-mcp"|(habitat|apollo)[/\\]mcp[/\\]server\.mjs' "$user_file" "$project_file" && manual_warning
  exit 0
fi
if ! $in_user && ! $in_project; then exit 0; fi

if $in_user && $in_project; then where="your Claude Code config and this project's .mcp.json"
elif $in_project; then where="this project's .mcp.json"
else where="your Claude Code config"; fi

# The uninstaller asks nothing when these are set: remove what it finds, and
# either clean this project's .mcp.json or skip that question. The variables
# are set by the shell that runs the command (Git Bash on Windows) and passed
# down to PowerShell, so the command has no nested quoting.
if $in_project; then
  if $windows; then scope_dir=$(cygpath -w "$project_dir" 2>/dev/null || printf '%s' "$project_dir"); else scope_dir=$project_dir; fi
  scope="APOLLO_SCOPE_DIR=$(printf '%q' "$scope_dir")"
else
  scope="APOLLO_SCOPE_GLOBAL=1"
fi
if $windows; then
  command="APOLLO_UNINSTALL_CONFIRM=Y HABITAT_UNINSTALL_ORIGIN=${ORIGIN} ${scope} $(basename "${ps%.exe}") -NoProfile -Command 'irm ${ORIGIN}/uninstall/ps1 | iex'"
else
  command="curl -fsSL ${ORIGIN}/uninstall | APOLLO_UNINSTALL_CONFIRM=Y HABITAT_UNINSTALL_ORIGIN=${ORIGIN} ${scope} bash"
fi
also_project=""
$in_project && also_project=" and from this project's .mcp.json"

user_message="The old local Habitat MCP server is still in ${where}. It runs beside the Habitat plugin's server, so every Habitat tool shows up twice. Claude will offer to remove it."

context="The Habitat plugin found the old local Habitat MCP server (@adminifi/habitat-mcp) still configured in ${where}. It runs beside the plugin's hosted server, so every Habitat tool appears twice, and the old copy is pinned to an outdated version.

At the start of your first reply, before anything else, tell the user this in one or two sentences and ask whether to remove it now. Use your question tool if you have one (AskUserQuestion in Claude Code), with \"Remove it now\" as the recommended option and \"Not now\" as the other. If this session can't ask the user (a non-interactive run), only mention it and don't run anything.

If they agree, run exactly this command with your Bash tool (Git Bash on Windows):

${command}

It runs Habitat's uninstaller without prompts. It removes habitat and apollo entries for ${ORIGIN} that run a local command, from ~/.claude.json (user scope and every project's local scope)${also_project}, and deletes the old server's files unless an entry for another Habitat still uses them. It leaves hosted entries alone, including this plugin's server. If it can't read a config file it stops before removing anything and says so; pass that on. Report what its output says it removed. Then tell the user two things: restart Claude Code so the old server stops, and revoke the old server's API token in Habitat under Settings, API credentials (${CREDENTIALS_URL}).

If they decline, don't bring it up again this session. Then carry on with whatever the user asked."

printf '{"systemMessage": %s, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": %s}}\n' \
  "$(json_string "$user_message")" "$(json_string "$context")"
exit 0
