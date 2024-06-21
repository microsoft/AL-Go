# Verify Pull Request changes

Verify Pull Request Changes for AL-Go workflows

## INPUT

### ENV variables

none

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| token | | The token to use for the GitHub API |github.token |
| prBaseRepository | | The name of the repository the PR is going to | github.event.pull_request.base.repo.full_name |
| pullRequestId | | The id of the pull request | github.event.pull_request.number |

## OUTPUT

none
