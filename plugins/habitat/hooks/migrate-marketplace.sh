#!/usr/bin/env bash
# At session start, moves the r90 marketplace off the private app repo
# (r90group/habitat) to the public plugin repo (r90group/claude-plugins), so
# people without access to the app repo can install and update the plugin.
# Machines that installed from the app repo get this hook through auto-update
# from it, and from then on update from the public repo. Nobody has to act.
#
# It rewrites the r90 source in the two places Claude Code keeps it, the user
# settings (extraKnownMarketplaces.r90) and plugins/known_marketplaces.json,
# then replaces the marketplace's clone of the old repo with one of the new.
# Removing and re-adding the marketplace would do the same, but it uninstalls
# the plugin and deletes its stored secrets, including the Habitat sign-in.
# The installed plugin keeps running from its cache throughout.
#
# Edits JSON with jq, else python3 (not macOS, where it may be a stub that
# opens an install dialog), else JavaScript for Automation (macOS), else
# PowerShell (Windows). Without any of them it does nothing. A marketplace
# from managed or organization settings isn't in these files and is left
# alone. Safe to run in every session: once moved, it finds nothing to do.
# Written for bash 3.2 (macOS) and Git Bash. Always exits 0 and prints nothing.
set -u
NEW_REPO="r90group/claude-plugins"
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config/settings.json"
known="$config/plugins/known_marketplaces.json"

windows=false macos=false
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows=true ;; Darwin) macos=true ;; esac

# The old source: the app repo as a github repo, or as a git URL (https or ssh).
is_old_url() {
  local u
  u=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  u=${u%/}; u=${u%.git}
  case "$u" in r90group/habitat|*/r90group/habitat|*:r90group/habitat) return 0 ;; esac
  return 1
}

# Rewrites the marketplace entry at the dotted path $2 in file $1 when its
# source is the old repo, keeping everything else. Exit 0 only when it changed
# the file. The file is written in place (cat >), so a symlinked settings file
# stays a symlink.
move_entry() {
  local file=$1 keypath=$2 out
  [ -r "$file" ] && grep -qi 'r90group/habitat' "$file" || return 1
  out=$(mktemp) || return 1
  if command -v jq >/dev/null 2>&1; then
    # No regex: some jq 1.6 builds have none.
    jq --arg new "$NEW_REPO" --arg path "$keypath" '
      def norm: ascii_downcase | rtrimstr("/") | rtrimstr(".git");
      def old: type == "object" and (
        ((.repo // "") | tostring | norm) == "r90group/habitat"
        or ((.url // "") | tostring | norm | (endswith("/r90group/habitat") or endswith(":r90group/habitat"))));
      ($path | split(".")) as $p
      | if (getpath($p) | type) == "object" and (getpath($p).source | old)
        then setpath($p + ["source"]; {source: "github", repo: $new}) else empty end' "$file" >"$out" 2>/dev/null
  elif ! $macos && ! $windows && command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import json, sys
path, new, out = sys.argv[1], sys.argv[3], sys.argv[4]
with open(path, encoding="utf-8") as f: data = json.load(f)
entry = data
for key in sys.argv[2].split("."):
    entry = entry.get(key) if isinstance(entry, dict) else None
src = entry.get("source") if isinstance(entry, dict) else None
def norm(s): s = str(s).lower().rstrip("/"); return s[:-4] if s.endswith(".git") else s
if isinstance(src, dict) and (norm(src.get("repo", "")) == "r90group/habitat" or norm(src.get("url", "")).endswith(("/r90group/habitat", ":r90group/habitat"))):
    entry["source"] = {"source": "github", "repo": new}
    with open(out, "w", encoding="utf-8") as f: json.dump(data, f, indent=2); f.write("\n")
' "$file" "$keypath" "$NEW_REPO" "$out" 2>/dev/null
  elif $macos && command -v osascript >/dev/null 2>&1; then
    osascript -l JavaScript - "$file" "$keypath" "$NEW_REPO" "$out" >/dev/null 2>&1 <<'JXA'
ObjC.import("Foundation");
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  if (!text) return;
  const data = JSON.parse(text.js);
  let entry = data;
  for (const key of argv[1].split(".")) entry = entry && typeof entry === "object" ? entry[key] : undefined;
  const src = entry && typeof entry === "object" ? entry.source : undefined;
  const norm = (s) => String(s || "").toLowerCase().replace(/\/$/, "").replace(/\.git$/, "");
  if (!src || typeof src !== "object") return;
  const url = norm(src.url);
  if (norm(src.repo) !== "r90group/habitat" && !url.endsWith("/r90group/habitat") && !url.endsWith(":r90group/habitat")) return;
  entry.source = { source: "github", repo: argv[2] };
  $(JSON.stringify(data, null, 2) + "\n").writeToFileAtomicallyEncodingError(argv[3], true, $.NSUTF8StringEncoding, null);
}
JXA
  elif $windows; then
    local ps
    ps=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || command -v powershell.exe 2>/dev/null)
    [ -n "$ps" ] || { rm -f "$out"; return 1; }
    # UTF-8 without a BOM, date strings kept as written: what Claude Code reads.
    HABITAT_HOOK_FILE=$(cygpath -w "$file" 2>/dev/null || printf '%s' "$file") HABITAT_HOOK_OUT=$(cygpath -w "$out" 2>/dev/null || printf '%s' "$out") \
      HABITAT_HOOK_PATH=$keypath HABITAT_HOOK_REPO=$NEW_REPO "$ps" -NoProfile -NonInteractive -Command '
try {
  $text = [IO.File]::ReadAllText($env:HABITAT_HOOK_FILE, [Text.Encoding]::UTF8)
  $data = if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")) { $text | ConvertFrom-Json -DateKind String } else { $text | ConvertFrom-Json }
  $entry = $data
  foreach ($key in $env:HABITAT_HOOK_PATH.Split(".")) { if ($entry -is [System.Management.Automation.PSCustomObject]) { $entry = $entry.$key } else { $entry = $null } }
  if ($entry -isnot [System.Management.Automation.PSCustomObject]) { return }
  $src = $entry.source
  if ($src -isnot [System.Management.Automation.PSCustomObject]) { return }
  function Norm($s) { $s = "$s".ToLowerInvariant().TrimEnd("/"); if ($s.EndsWith(".git")) { $s = $s.Substring(0, $s.Length - 4) }; $s }
  $url = Norm $src.url
  if ((Norm $src.repo) -ne "r90group/habitat" -and -not $url.EndsWith("/r90group/habitat") -and -not $url.EndsWith(":r90group/habitat")) { return }
  $entry.source = [PSCustomObject]@{ source = "github"; repo = $env:HABITAT_HOOK_REPO }
  [IO.File]::WriteAllText($env:HABITAT_HOOK_OUT, ($data | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding $false))
} catch {}' >/dev/null 2>&1
  fi
  if [ -s "$out" ]; then
    cat "$out" >"$file" && rm -f "$out" && return 0
  fi
  rm -f "$out"
  return 1
}

move_entry "$settings" "extraKnownMarketplaces.r90" || true
move_entry "$known" "r90" || true

# The clone still pulls from the old repo when its origin says so (just moved,
# or a clone a racing update re-created). Replace it with a clone of the new
# repo; the path is Claude Code's own, so only a folder under its marketplaces
# directory is removed. If the clone can't be made now (offline), the folder
# stays missing and the marketplace's next update clones it.
clone="$config/plugins/marketplaces/r90"
origin=$(git -C "$clone" remote get-url origin 2>/dev/null) || exit 0
is_old_url "$origin" || exit 0
grep -qi "$NEW_REPO" "$known" 2>/dev/null || exit 0
rm -rf "$clone"
command -v claude >/dev/null 2>&1 && claude plugin marketplace update r90 >/dev/null 2>&1 </dev/null
exit 0
