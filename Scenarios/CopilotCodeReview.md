# Enable Copilot code review for AL pull requests

AL-Go can review AL changes and post findings as pull request comments. The AL-Go-owned review engine installs the [BCQuality](https://github.com/microsoft/BCQuality) marketplace plugin, filters its skills and knowledge to the configured policy, and runs when a non-draft pull request targeting a branch in `CICDPullRequestBranches` is opened, reopened, synchronized, or marked ready for review. The default target branch is `main`.

## Prerequisites

Before enabling the reviewer:

1. Allow Copilot CLI requests billed to the organization in the GitHub organization Copilot policies.
1. Ensure the organization Actions policy allows actions from `microsoft/AL-Go-Actions`.
1. Ensure the organization and repository Actions policies allow the workflow's `GITHUB_TOKEN` to request `pull-requests: write` and `issues: write`.

Reviews consume organization AI credits. No additional repository secret is
required when BCQuality is public.

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

Run the **Update AL-Go System Files** workflow to add the intake, runner, and
local reusable review workflows. Subsequent eligible pull requests targeting a
branch configured in `CICDPullRequestBranches` will be reviewed automatically.
Pull requests authored by GitHub bot accounts are skipped.

The setting must be enabled at repository level. Project settings do not enable or disable the reviewer.

## How the workflows protect pull requests

The integration uses two workflows:

1. **Copilot PR Review** runs without write permissions and signals that an eligible pull request event occurred.
1. **Copilot PR Review Runner** runs from the trusted base branch, independently validates the setting and pull request, and calls the generated local reusable review workflow.

The reusable workflow supports ephemeral GitHub-hosted runners and invokes the
versioned AL-Go review action. It runs the model in a read-only job and
installs BCQuality into Copilot's default plugin directory for that disposable
runner. A separate job receives permission to publish the generated findings.
This prevents untrusted pull request code from running in a job that can modify
the pull request.

## Private BCQuality repositories

If the configured BCQuality marketplace repository is private and cannot be
read with the workflow `GITHUB_TOKEN`, create a repository or organization
Actions secret named `bcqualityToken` containing a fine-grained token with
read access to that repository. The workflow passes it only to the setup
action, which provides authentication through temporary process-scoped Git
configuration and does not persist the credential.

## Disable the reviewer

Set `CodeReviewAgent.enabled` to `false` and run **Update AL-Go System Files**.
The reviewer workflows are removed from the repository.

______________________________________________________________________

[back](../README.md)
