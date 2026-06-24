---
on:
  workflow_dispatch:

permissions:
  contents: read
  issues: read
  pull-requests: read

safe-outputs:
  add-comment:
    allowed-repos: [microsoft/AL-Go]

tools:
  github:
---

# Comment on Release Notes PRs

When a new version of AL-Go is released, notify contributors whose PRs modify RELEASENOTES.md that they need to update their release notes placement.

## Task

1. Read RELEASENOTES.md to find the current version (the first `## vX.Y` heading)
2. Find all open pull requests that modify RELEASENOTES.md
3. For each PR that modifies RELEASENOTES.md:
   - Check if there's already a comment containing "Release Notes Update Required" and the current version
   - If no such comment exists, add a new comment with the message below

## Comment Template

Use this exact format for the comment:

### 📦 Release Notes Update Required

AL-Go **{version}** has been released, and your changes to RELEASENOTES.md appear to be under that version's section.

**Action needed:** Please move your release notes entry to **above** the `## {version}` heading so it will be included in the next release.

<details>
<summary>Example</summary>

```markdown
## Changes to be included in the next release

- Your change here ✅

## {version}

- Already released changes
```

</details>

Thank you for contributing to AL-Go! 🙏

## Summary

After processing all PRs, report:
- How many PRs were found that modify RELEASENOTES.md
- How many comments were added
- How many were skipped (already had comments for this version)
