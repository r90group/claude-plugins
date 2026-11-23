---
name: spec-research
description: "Researches and drafts a Habitat spec with cited hard/soft requirements, user stories and open questions, using the current spec-research skill from Habitat. Use for \"write a spec\", \"spec research\" or \"draft a spec for [client]\"."
license: Proprietary (R90)
compatibility: "Needs the habitat MCP server from this plugin, signed in (run /mcp once to sign in)."
---

# Spec research (launcher)

The instructions live in Habitat, so they change with every Habitat deploy
without reinstalling anything.

1. Call the Habitat `get_skill` tool with `{"name": "spec-research"}`. In this
   plugin it is `mcp__plugin_habitat_habitat__get_skill`.
2. It returns `files`: `SKILL.md` first, then its `references/…` files. Follow
   `SKILL.md`; when it links a reference, read that file from the same
   response. Don't fetch them again.
3. When a step needs another Habitat skill (`spec-unslop` for the readability
   pass, `link-specs` for references to other specs), fetch it once with
   `get_skill` and use it the same way. To run one of its scripts
   (`scripts/check_prose.py`, `scripts/check_patch.py`), write the file from
   the response to a scratch folder and run it with `python3` from there.
4. If the Habitat tools are missing or answer 401, tell the person to run
   `/mcp`, choose **plugin:habitat:habitat** and sign in, then stop.
