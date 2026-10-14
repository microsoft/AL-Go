# Enable Copilot code review for AL pull requests

AL-Go can review AL changes and post findings as pull request comments. The AL-Go-owned `ReviewAgent` action installs the [BCQuality](https://github.com/microsoft/BCQuality) marketplace plugin, filters its skills and knowledge to the configured policy, and runs when a non-draft pull request targeting a branch in `CICDPullRequestBranches` is opened, reopened, synchronized, or marked ready for review. The default target branch is `main`.

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
  "BCQuality": {
    "marketplaceRepo": "https://github.com/microsoft/BCQuality",
    "version": "1.7",
    "pluginVersion": "0.2.0",
    "enabledLayers": [
      "microsoft"
    ],
    "disabledSkills": [],
    "knowledge": {
      "allow": [
        "microsoft/knowledge/**"
      ],
      "deny": []
    },
    "taskContext": {
      "technologies": [
        "al"
      ],
      "countries": [
        "w1"
      ],
      "applicationArea": [
        "all"
      ]
    }
  },
  "CodeReviewAgent": {
    "enabled": true,
    "model": "gpt-5.6-sol",
    "leafModel": "gpt-5.6-luna",
    "excludedOwners": [
      "dependabot[bot]"
    ]
  }
}
```

Run the **Update AL-Go System Files** workflow to add the review workflows. Subsequent eligible pull requests targeting a branch configured in `CICDPullRequestBranches` will be reviewed automatically.

`BCQuality.marketplaceRepo`, `version`, and `pluginVersion` select and validate the plugin installation. `enabledLayers`, `disabledSkills`, and `knowledge` control the content retained for the review. `taskContext` supplies BCQuality's technology, country, application-area, and Business Central version dimensions. `CodeReviewAgent.model` controls final self-review and consolidation, while `CodeReviewAgent.leafModel` controls the isolated review processes. `excludedOwners` contains GitHub login names whose pull requests should not be reviewed. The owner list is empty by default.

Both settings are populated by default. `CodeReviewAgent` must be enabled at repository level; project settings do not enable or disable the reviewer.

## How the workflows protect pull requests

The integration uses two workflows:

1. **Copilot PR Review** runs without write permissions and uploads the pull request event metadata.
1. **Copilot PR Review Runner** runs from the trusted base branch, downloads that metadata, applies the trusted repository settings, validates the pull request, generates findings, and publishes them.

The trusted runner supports ephemeral GitHub-hosted runners and delegates its implementation to the AL-Go `ReviewAgent` action. It prepares BCQuality in a secret-scoped step, runs the model in a separate read-only step, and publishes the generated findings from a separate job. This prevents the model and untrusted pull request code from receiving the private marketplace token or permission to modify the pull request.

## Disable the reviewer

Set `CodeReviewAgent.enabled` to `false` and run **Update AL-Go System Files**. The reviewer workflows are removed from the repository.

______________________________________________________________________

[back](../README.md)
