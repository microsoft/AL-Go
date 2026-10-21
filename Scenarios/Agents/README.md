# Agents

AI agents that integrate with AL-Go workflows to help with Business Central extension development. Follow each agent's setup guide for prerequisites, configuration, and details about how it runs.

## Available agents

| Agent and setup guide | Description | When it runs |
| --- | --- | --- |
| [Copilot code review](CopilotCodeReview.md) | Reviews AL changes using BCQuality skills and knowledge and posts findings as pull request comments. | When an eligible non-draft pull request targeting a configured branch is opened, reopened, updated, or marked ready for review. |

## Getting started

Copilot code review is available in both the PTE and AppSource templates and is **off by default**. To enable it, follow the [setup guide](CopilotCodeReview.md#enable-the-reviewer), configure the repository-level setting, and run **Update AL-Go System Files**.

Reviews consume organization AI credits and require the organization Copilot and repository Actions policies described in the [prerequisites](CopilotCodeReview.md#prerequisites).

______________________________________________________________________

[back](../../README.md)
