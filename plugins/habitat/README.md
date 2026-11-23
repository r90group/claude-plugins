# Habitat plugin for Claude Code

Connects Claude Code to Habitat's hosted MCP server
(`https://apollo.adminifi.com/api/mcp`, OAuth sign-in) and adds the
`spec-research` and `technical-spec` launcher skills. Tools and skill instructions are served by
Habitat, so they change on every Habitat deploy; the plugin itself pins no
version, so every commit to this marketplace reaches everyone through
auto-update. See ADR 0025.

## Use

- **Draft a spec:** ask Claude Code to "write a spec" or "draft a spec for
  [client]". The `spec-research` launcher fetches the current skill from
  Habitat and follows it.
- **Technical spec:** open the spec's **Technical spec** tab in Habitat, copy
  the prompt, and paste it into Claude Code in the product's checkout.

## Rollout (organization)

An Owner of R90's Claude organization pushes it once, so nobody installs
anything:

- claude.ai **Organization settings → Plugins & skills**: add the
  `r90group/habitat` repository as a marketplace (it holds
  `.claude-plugin/marketplace.json`), enable `habitat@r90`, auto-update on.
- Or the same in managed settings:

```json
{
  "extraKnownMarketplaces": {
    "r90": { "source": { "source": "github", "repo": "r90group/habitat" }, "autoUpdate": true }
  },
  "enabledPlugins": { "habitat@r90": true }
}
```

## Install

One command installs the plugin, enables it, turns on auto-update and signs
you in to Habitat in the browser. Safe to run again.

```
curl -fsSL https://apollo.adminifi.com/install | bash
```

On Windows: `irm https://apollo.adminifi.com/install/ps1 | iex`.

It needs git read access to `r90group/habitat` (`gh auth login`, then
`gh auth setup-git`). The marketplace is a sparse clone: only
`.claude-plugin/` and `plugins/`, not the app.

Sign-in uses a public OAuth client registered on Apollo's Supabase Auth for
Claude Code (PKCE, no secret, callback `http://localhost:47615/callback`). Its
id is pinned in `.claude-plugin/plugin.json` and listed in Apollo's
`HABITAT_OAUTH_CLIENT_IDS`; register it with
`node scripts/claude-oauth-client.mjs create-claude-code --tenant apollo`.
Writes are made as you, with your permissions. To sign in again:
`claude mcp login plugin:habitat:habitat`, or `/mcp` in Claude Code.

## Moving off the old local server

The install command replaces the old local server (`@adminifi/habitat-mcp`,
formerly `apollo-mcp`): it runs Habitat's uninstaller when it finds the old
server's files or a `habitat`/`apollo` entry that runs a local command, in
user scope, every project's local scope and the current directory's
`.mcp.json`. Hosted entries stay. Revoke the old token afterwards in Habitat
under **Settings → API credentials**.

The plugin also checks at startup, for an old entry the installer couldn't
see (another project's `.mcp.json`), and Claude offers to remove it.

It also checks that the r90 marketplace auto-updates. The installer turns
auto-update on only where it can edit settings (jq on macOS and Linux); when
it's off, Claude offers to turn it on by editing `~/.claude/settings.json`.

Permission rules or hooks that name `mcp__habitat__*` need the plugin's names,
`mcp__plugin_habitat_habitat__*`.

## Other agents

Cursor and other agents don't load Claude Code plugins. Add the MCP server
`https://apollo.adminifi.com/api/mcp` in the agent's MCP settings; the prompt
Habitat gives you calls `get_skill` directly, so no skill install is needed.
