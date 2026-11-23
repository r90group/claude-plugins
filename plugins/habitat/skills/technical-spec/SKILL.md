---
name: technical-spec
description: "Drafts or revises the technical spec (tech spec, design doc, ADRs) of a Habitat spec with its tech lead, using the current technical-spec skill from Habitat. Use only when the request names a Habitat spec, or a prompt says to call get_skill technical-spec."
license: Proprietary (R90)
compatibility: "Needs the habitat MCP server from this plugin, signed in (run /mcp once to sign in)."
---

# Technical spec (launcher)

The instructions live in Habitat, so they change without reinstalling anything.

1. Call the Habitat `get_skill` tool with `{"name": "technical-spec"}`. In this
   plugin it is `mcp__plugin_habitat_habitat__get_skill`.
2. It returns `files`: `SKILL.md` first, then its `references/…` files. Follow
   `SKILL.md`; when it links a reference, read that file from the same
   response. Don't fetch them again.
3. If the Habitat tools are missing or answer 401, tell the person to run
   `/mcp`, choose **plugin:habitat:habitat** and sign in, then stop.
