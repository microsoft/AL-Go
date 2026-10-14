# Enable Copilot code review for AL pull requests

AL-Go can review AL changes and post findings as pull request comments. The AL-Go-owned review engine installs the [BCQuality](https://github.com/microsoft/BCQuality) marketplace plugin, filters its skills and knowledge to the configured policy, and runs when a non-draft pull request targeting a branch in `CICDPullRequestBranches` is opened, reopened, synchronized, or marked ready for review. The default target branch is `main`.

## Prerequisites

Before enabling the reviewer:

1. Allow Copilot CLI requests billed to the organization in the GitHub organization Copilot policies.
1. Ensure the organization and repository Actions policies allow the workflow's `GITHUB_TOKEN` to request `pull-requests: write` and `issues: write`.

Reviews consume organization AI credits. No personal access token or additional repository secret is required when using the public BCQuality marketplace.

If the review policy points to a private BCQuality marketplace repository, add a `BCQUALITY_TOKEN` repository secret containing a token with read access to that repository. The trusted runner passes it only to non-default marketplace installation; the default `microsoft/BCQuality` marketplace always uses unauthenticated access. The token is not available to pull request code or the model execution step.

## Enable the reviewer

Add the following repository-level setting to `.github/AL-Go-Settings.json`:

```json
{
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

`model` controls final self-review and consolidation, while `leafModel` controls the isolated review processes. `excludedOwners` contains GitHub login names whose pull requests should not be reviewed. The owner list is empty by default.

The setting must be enabled at repository level. Project settings do not enable or disable the reviewer.

## How the workflows protect pull requests

The integration uses two workflows:

1. **Copilot PR Review** runs without write permissions and uploads the pull request event metadata.
1. **Copilot PR Review Runner** runs from the trusted base branch, downloads that metadata, applies the trusted repository settings, validates the pull request, generates findings, and publishes them.

The trusted runner supports ephemeral GitHub-hosted runners, runs the model in a read-only job, and installs BCQuality into Copilot's default plugin directory for that disposable runner. A separate job receives permission to publish the generated findings. This prevents untrusted pull request code from running in a job that can modify the pull request.

## Disable the reviewer

Set `CodeReviewAgent.enabled` to `false` and run **Update AL-Go System Files**. The reviewer workflows are removed from the repository.

______________________________________________________________________

[back](../README.md)
