# Enable Copilot code review for AL pull requests

AL-Go can review AL changes and post findings as pull request comments. The AL-Go-owned review engine installs the [BCQuality](https://github.com/microsoft/BCQuality) marketplace plugin, filters its skills and knowledge to the configured policy, and runs when a non-draft pull request targeting a branch in `CICDPullRequestBranches` is opened, reopened, synchronized, or marked ready for review. The default target branch is `main`.

## Prerequisites

Before enabling the reviewer:

1. Allow Copilot CLI requests billed to the organization in the GitHub organization Copilot policies.
1. Ensure the organization Actions policy allows reusable workflows from `microsoft/AL-Go`.
1. Ensure the organization and repository Actions policies allow the workflow's `GITHUB_TOKEN` to request `pull-requests: write` and `issues: write`.

Reviews consume organization AI credits. No personal access token or additional repository secret is required.

## Enable the reviewer

Add the following repository-level setting to `.github/AL-Go-Settings.json`:

```json
{
  "CodeReviewAgent": {
    "enabled": true,
    "model": "gpt-5.6-sol",
    "leafModel": "gpt-5.6-luna"
  }
}
```

Run the **Update AL-Go System Files** workflow to add the `CopilotPRReview.yaml` and `CopilotPRReviewRunner.yaml` workflows. Subsequent eligible pull requests targeting a branch configured in `CICDPullRequestBranches` will be reviewed automatically.

`model` controls final self-review and consolidation, while `leafModel` controls the isolated review processes. The values shown above are the defaults, so you can omit them when you only need to enable the reviewer.

The setting must be enabled at repository level. Project settings do not enable or disable the reviewer.

## How the workflows protect pull requests

The integration uses two workflows:

1. **Copilot PR Review** runs without write permissions and signals that an eligible pull request event occurred.
1. **Copilot PR Review Runner** runs from the trusted base branch, independently validates the setting and pull request, and calls the reusable AL-Go review workflow.

The reusable workflow supports ephemeral GitHub-hosted runners. It runs the model in a read-only job and installs BCQuality into Copilot's default plugin directory for that disposable runner. A separate job receives permission to publish the generated findings. This prevents untrusted pull request code from running in a job that can modify the pull request.

## Disable the reviewer

Set `CodeReviewAgent.enabled` to `false` and run **Update AL-Go System Files**. The reviewer workflows are removed from the repository.

______________________________________________________________________

[back](../README.md)
