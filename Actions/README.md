# AL-Go Actions

This repository contains a set of GitHub actions used by the AL-Go for GitHub templates.

Please go to https://aka.ms/AL-Go to learn more.

## Actions

| Name | Description |
| :-- | :-- |
| [Add existing app](AddExistingApp) | Add an existing app to an AL-Go for GitHub repository |
| [Analyze Tests](AnalyzeTests) | Analyze results of tests from the RunPipeline action |
| [Calculate Artifact Names](CalculateArtifactNames) | Calculate Artifact Names for AL-Go workflows |
| [Check for updates](CheckForUpdates) | Check for updates to AL-Go system files and perform the update if requested |
| [Create a new app](CreateApp) | Create a new app and add it to an AL-Go repository |
| [Create Development Environment](CreateDevelopmentEnvironment) | Create an online development environment |
| [Creates release notes](CreateReleaseNotes) | Creates release notes for a release, based on a given tag and the tag from the latest release |
| [Deliver](Deliver) | Deliver App to deliveryTarget (AppSource, Storage, or...) |
| [Deploy](Deploy) | Deploy Apps to online environment |
| [Determine artifactUrl](DetermineArtifactUrl) | Determines the artifactUrl to use for a given project |
| [Determine projects to build](DetermineProjectsToBuild) | Scans for AL-Go projects and determines which one to build |
| [Download project dependencies](DownloadProjectDependencies) | Downloads artifacts from AL-Go projects, that are dependencies of a given AL-Go project |
| [Increment version number](IncrementVersionNumber) | Increment version number in AL-Go repository |
| [Pipeline Cleanup](PipelineCleanup) | Perform cleanup after running pipeline in AL-Go repository |
| [Read secrets](ReadSecrets) | Read secrets from GitHub secrets or Azure Keyvault for AL-Go workflows |
| [Read settings](ReadSettings) | Read settings for AL-Go workflows |
| [Run pipeline](RunPipeline) | Run pipeline in AL-Go repository |
| [Sign](Sign) | Sign apps with a certificate stored in Azure Key Vault |
| [Verify Pull Request changes](VerifyPRChanges) | Verify Pull Request Changes for AL-Go workflows |
| [Initialize workflow](WorkflowInitialize) | Initialize a workflow |
| [PostProcess action](WorkflowPostProcess) | Finalize a workflow |

## Contributing

Please read [this](https://github.com/microsoft/AL-Go/blob/main/Scenarios/Contribute.md) description on how to contribute to AL-Go for GitHub.

We do not accept Pull Requests on the Actions repository directly.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
