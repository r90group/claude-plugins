# Windows half of check-old-mcp.sh: finds old Habitat MCP entries with
# PowerShell, because Git for Windows has no jq. Prints "user=<0|1>
# project=<0|1>". The rule matches the uninstaller (scripts/uninstall.ps1): a
# habitat or apollo server that runs a local command (no "url"), for the
# plugin's Habitat (HABITAT_API_URL starts with $env:HABITAT_HOOK_ORIGIN, or
# names none). Reads only; a file it can't parse counts as having no old entry.
#
# Inputs: $env:HABITAT_HOOK_USER_FILE (~/.claude.json, user scope and every
# project's local scope), $env:HABITAT_HOOK_PROJECT_FILE (this project's
# .mcp.json) and $env:HABITAT_HOOK_ORIGIN.

function Read-JsonOrNull([string]$path) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
  try {
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    return $text | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Test-OldIn($holder) {
  if ($holder -isnot [System.Management.Automation.PSCustomObject]) { return $false }
  if (-not $holder.PSObject.Properties["mcpServers"]) { return $false }
  $servers = $holder.mcpServers
  if ($servers -isnot [System.Management.Automation.PSCustomObject]) { return $false }
  foreach ($name in @("habitat", "apollo")) {
    $prop = $servers.PSObject.Properties[$name]
    if (-not $prop) { continue }
    $entry = $prop.Value
    if ($entry -isnot [System.Management.Automation.PSCustomObject]) { continue }
    if ($entry.PSObject.Properties["url"] -and $null -ne $entry.url) { continue }
    $type = if ($entry.PSObject.Properties["type"] -and $null -ne $entry.type) { $entry.type } else { "stdio" }
    if ($type -ne "stdio") { continue }
    $url = ""
    if ($entry.PSObject.Properties["env"] -and $entry.env -is [System.Management.Automation.PSCustomObject]) {
      foreach ($key in @("HABITAT_API_URL", "APOLLO_API_URL")) {
        if ($entry.env.PSObject.Properties[$key] -and $entry.env.$key) { $url = [string]$entry.env.$key; break }
      }
    }
    if (-not $env:HABITAT_HOOK_ORIGIN -or $url -eq "" -or $url.StartsWith($env:HABITAT_HOOK_ORIGIN)) { return $true }
  }
  return $false
}

$inUser = 0
$user = Read-JsonOrNull $env:HABITAT_HOOK_USER_FILE
if ($user) {
  if (Test-OldIn $user) { $inUser = 1 }
  elseif ($user.PSObject.Properties["projects"] -and $user.projects -is [System.Management.Automation.PSCustomObject]) {
    foreach ($project in $user.projects.PSObject.Properties) {
      if (Test-OldIn $project.Value) { $inUser = 1; break }
    }
  }
}

$inProject = 0
$projectConfig = Read-JsonOrNull $env:HABITAT_HOOK_PROJECT_FILE
if ($projectConfig -and (Test-OldIn $projectConfig)) { $inProject = 1 }

Write-Output "user=$inUser project=$inProject"
