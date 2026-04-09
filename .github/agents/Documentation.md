# Documentation Rules

## Important (Should Flag)

1. **Missing RELEASENOTES update**: User-facing changes without a release note entry
1. **Missing documentation for new settings**: New or changed AL-Go settings must be documented in `Scenarios/settings.md` (including purpose, type, default/required status, and which templates/workflows honor them) and represented in the settings schema (`Actions/.Modules/settings.schema.json`) with matching descriptions and correct metadata (`type`, `enum`, `default`, `required`).
1. **Missing documentation for new functions**: New public functions (exported from modules or used as entry points) should include comment-based help (e.g., `.SYNOPSIS`, `.DESCRIPTION`, parameter help) and be described in relevant markdown documentation when they are part of the public surface.
1. **Missing documentation for new workflows or user-facing behaviors**: New or significantly changed workflows/templates in `Templates/` must have corresponding scenario documentation (or updates) in `Scenarios/`, and new user-facing commands or actions must be documented in scenarios or `README.md`.
