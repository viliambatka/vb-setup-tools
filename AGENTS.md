# Agent Instructions (vb-setup-tools)

## Development workflow — standing instruction (2026-10-01)

- Use trunk-based development in this repository and its submodules until the user explicitly
  instructs otherwise. Develop and commit directly on `main` in small, validated increments.
- Feature branches and pull requests are optional and used when the user requests them.
  This standing instruction replaces earlier mandatory branch/PR rules for repository development.
- Review diffs and run checks appropriate to each change before committing. Preserve unrelated
  work, secrets protection, and runtime safety/approval boundaries.
- Commit submodule changes within each submodule first, then commit updated pointers in the parent.
- Follow the user's publication instructions for remote pushes; never force-push without explicit
  authorization.
