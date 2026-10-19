# Enable Copilot code review for AL pull requests

AL-Go can review AL changes and post findings as pull request comments. The AL-Go-owned `SetupBCQuality` action installs the [BCQuality](https://github.com/microsoft/BCQuality) marketplace plugin and filters its skills and knowledge to the configured policy. The prepared plugin is then consumed by the `ReviewAgent` action. Reviews run when a non-draft pull request targeting a branch in `CodeReviewAgent.branches` is opened, reopened, synchronized, or marked ready for review. The default target branch is `main`.

## Prerequisites

Before enabling the reviewer:

1. Allow Copilot CLI requests billed to the organization in the GitHub organization Copilot policies.
1. Ensure the organization and repository Actions policies allow the workflow's `GITHUB_TOKEN` to request `pull-requests: write` and `issues: write`.

Reviews consume organization AI credits. No personal access token or additional repository secret is required when using the public BCQuality marketplace.

If the `BCQuality` setting points to a private marketplace repository, add a `BCQUALITY_TOKEN` repository secret containing a token with read access to that repository. The trusted runner passes it only to non-default marketplace installation; the default `microsoft/BCQuality` marketplace always uses unauthenticated access. The token is not available to pull request code or the model execution step.

## Enable the reviewer

Add the following repository-level setting to `.github/AL-Go-Settings.json`:

```json
{
  "CodeReviewAgent": {
    "enabled": true,
    "branches": [
      "main"
    ],
    "excludedAuthors": [
      "dependabot[bot]"
    ]
  }
}
```

Run the **Update AL-Go System Files** workflow to add the review workflows. Subsequent eligible pull requests targeting a branch configured in `CodeReviewAgent.branches` will be reviewed automatically.

BCQuality defaults to the trusted `microsoft/BCQuality` marketplace release, retains all content layers, and supplies the internal AL review context. Advanced filtering remains available through `BCQuality.enabledLayers`, `disabledSkills`, and `knowledge`. An empty `enabledLayers` list retains Microsoft, community, and custom content; an explicit list retains only those layers. `CodeReviewAgent.branches` controls the target branches reviewed independently of pull request build branches. Its empty default means `main`; an explicit list replaces that fallback and uses ordered GitHub Actions branch patterns, including `!` exclusions. The trusted runner checks the authoritative pull request base branch against these patterns before review. `model` controls final self-review and consolidation, while `leafModel` controls the isolated review processes. `excludedAuthors` contains GitHub login names whose pull requests should not be reviewed. The author list is empty by default.

Both settings are populated by default. `CodeReviewAgent` must be enabled at repository level; project settings do not enable or disable the reviewer.

## How the workflows protect pull requests

The integration uses two workflows:

1. **Copilot PR Review** runs without write permissions and uploads the pull request event metadata.
1. **Copilot PR Review Runner** runs from the trusted base branch and treats that metadata only as a pull request number hint. It retrieves the workflow run and pull request from GitHub, validates the head repository, branch, commit and pull request association, and uses the authoritative author, draft state and base branch. The trusted repository setting must explicitly enable review before findings can be generated or published.

The trusted runner supports ephemeral GitHub-hosted runners, even when repository build jobs use self-hosted runners. It installs the pinned Copilot CLI, invokes the AL-Go `SetupBCQuality` action in a secret-scoped step, passes only the prepared plugin path to `ReviewAgent`, runs the model in a separate read-only step, and publishes the generated findings from a separate job. This prevents the model and untrusted pull request code from receiving the private marketplace token or permission to modify the pull request.

Each completed intake run has an independent review concurrency group, so pull requests sharing a source branch do not cancel one another. Reviews of older commits are not automatically cancelled by newer intake runs. Publication is serialized per pull request so overlapping reviews cannot race existing-comment deduplication.

`SetupBCQuality` defaults to PowerShell 7 (`pwsh`), which the BCQuality indexing tools require. Review diagnostics record the action repository and requested ref separately. A full commit SHA is recorded when the action is SHA-pinned; for mutable branch/tag references, the commit is unknown (`null`) rather than incorrectly treating the ref or the reviewed repository's checkout as the action commit.

Review generation requires the `microsoft/skills/review/al-code-review.md` super-skill and its layer to remain enabled and present in the filtered plugin. Invalid filtering configurations fail before any review leaves start. To disable automated review entirely, set `CodeReviewAgent.enabled` to `false` instead.

## Review execution and artifacts

Root and leaf model processes can read the sanitized review data and create or edit only their designated report file. Both patch-based and create/edit tools are available for model compatibility; shell commands, URL access, delegation, and automatic temporary-directory access remain unavailable. Copilot output is logged with workflow-command parsing suspended. Windows npm installations launch through Node rather than a batch shim.

Review artifacts retain the generated task context after publication. Regional deduplication preserves case-sensitive fixes, deletion anchors retain their old/new line distinction, and per-file diffs treat filenames literally so Git pathspec characters cannot include another file's changes in inline-comment coordinates.

## Disable the reviewer

Set `CodeReviewAgent.enabled` to `false` and run **Update AL-Go System Files**. The reviewer workflows are removed from the repository.

______________________________________________________________________

[back](../../README.md)
