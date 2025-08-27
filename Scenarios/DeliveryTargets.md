# DeliveryTargets and NuGet/GitHub Packages in AL-Go

AL-Go for GitHub supports continuous delivery to multiple targets, including NuGet feeds and GitHub Packages. This document provides comprehensive guidance on how to set up and configure delivery targets for your Business Central apps, particularly focusing on Per-Tenant Extensions (PTEs).

## Table of Contents

- [Overview](#overview)
- [DeliveryTargets Concept](#deliverytargets-concept)
- [GitHub Packages Setup](#github-packages-setup)
- [NuGet Feed Setup](#nuget-feed-setup)
- [Configuration Examples](#configuration-examples)
- [Troubleshooting](#troubleshooting)
- [Advanced Scenarios](#advanced-scenarios)
- [Important Notes](#important-notes)

## Overview

AL-Go for GitHub provides experimental support for delivering your Business Central apps to NuGet feeds and GitHub Packages. This enables you to:

- **Automate app distribution**: Automatically publish your apps to package repositories after successful builds
- **Manage dependencies**: Use published packages as dependencies in other projects
- **Enable partner collaboration**: Share your apps with partners through package feeds
- **Implement CI/CD best practices**: Integrate package delivery into your continuous integration pipeline

> [!IMPORTANT]
> **Experimental Feature**: NuGet and GitHub Packages delivery is currently experimental. While the functionality is stable and has been used in production by several partners, the package structure and configuration options may change in future versions.

## DeliveryTargets Concept

DeliveryTargets in AL-Go define where and how your built applications should be delivered after a successful build. Each delivery target is configured through:

1. **Context Secret**: A secret named `<DeliveryTarget>Context` containing connection information
1. **Delivery Script**: An optional PowerShell script named `DeliverTo<DeliveryTarget>.ps1` for custom delivery logic
1. **Settings**: Optional configuration in AL-Go settings files

### Supported Delivery Targets

| Target | Purpose | Context Secret | Status |
|--------|---------|----------------|--------|
| GitHubPackages | GitHub Packages NuGet feed | `GitHubPackagesContext` | ✅ Experimental |
| NuGet | Custom NuGet feed | `NuGetContext` | ✅ Experimental |
| Storage | Azure Storage Account | `StorageContext` | ✅ Stable |
| AppSource | Microsoft AppSource | `AppSourceContext` | ✅ Stable |

## GitHub Packages Setup

GitHub Packages provides a free NuGet feed for each GitHub organization. This is the recommended approach for most scenarios.

### Step 1: Create Personal Access Token

1. Navigate to [GitHub Personal Access Tokens](https://github.com/settings/tokens/new)
1. Create a **Classic Personal Access Token** (Fine-grained tokens don't support packages yet)
1. Select the following scopes:
   - `write:packages` - Required for publishing packages
   - `read:packages` - Required for consuming packages
   - `repo` - Required if your repositories are private

### Step 2: Create GitHubPackagesContext Secret

Create an organizational secret named `GitHubPackagesContext` with the following compressed JSON format:

```json
{"token":"ghp_<your_token>","serverUrl":"https://nuget.pkg.github.com/<your_org>/index.json"}
```

Replace:

- `<your_token>` with your personal access token
- `<your_org>` with your GitHub organization name

> [!TIP]
> Use the BcContainerHelper function `New-ALGoNuGetContext` to create a correctly formatted JSON structure.

> [!WARNING]
> The secret must be in compressed JSON format (single line). Multi-line JSON will break AL-Go functionality as curly brackets will be masked in logs.

### Step 3: Configure Repository Settings (Optional)

You can control delivery behavior by adding settings to your AL-Go settings file. For detailed information about DeliveryTarget settings, see [DeliverTo<deliveryTarget>](https://aka.ms/algosettings#deliverto).

```json
{
  "DeliverToGitHubPackages": {
    "ContinuousDelivery": true,
    "Branches": ["main", "release/*"]
  }
}
```

### Step 4: Verify Setup

After creating the secret, run your CI/CD workflow. You should see a "Deliver to GitHubPackages" job in the workflow summary.

## NuGet Feed Setup

For custom NuGet feeds (e.g., Azure DevOps Artifacts, private NuGet servers), use the NuGetContext secret.

### Step 1: Create NuGetContext Secret

Create a secret named `NuGetContext` with the following format:

> [!NOTE]
> Replace `<YOUR_NUGET_TOKEN>`, `<your_org>`, `<your_project>`, and `<your_feed>` with your actual values.

```json
{"token":"<YOUR_NUGET_TOKEN>","serverUrl":"https://pkgs.dev.azure.com/<your_org>/<your_project>/_packaging/<your_feed>/nuget/v3/index.json"}
```

Common NuGet feed URLs:

- **Azure DevOps**: `https://pkgs.dev.azure.com/<org>/<project>/_packaging/<feedName>/nuget/v3/index.json`
- **GitHub Packages**: `https://nuget.pkg.github.com/<org>/index.json`
- **NuGet.org**: `https://api.nuget.org/v3/index.json`

### Step 2: Configure Dependency Resolution (Optional)

Unlike GitHub Packages, NuGet feeds configured with `NuGetContext` are not automatically used for dependency resolution. To use your custom feed for dependencies, add it to [trustedNuGetFeeds](https://aka.ms/algosettings#trustedNuGetFeeds):

```json
{
  "trustedNuGetFeeds": [
    {
      "url": "https://pkgs.dev.azure.com/<your_org>/<your_project>/_packaging/<your_feed>/nuget/v3/index.json",
      "authTokenSecret": "NuGetContext",
      "patterns": ["*"]
    }
  ]
}
```

## Configuration Examples

### Example 1: GitHub Packages for PTE Organization

**Use Case**: A company developing Per-Tenant Extensions (PTEs) wants to automatically publish apps to GitHub Packages for internal distribution and dependency management.

**Organizational Secret**: `GitHubPackagesContext`

```json
{"token":"ghp_<your_token>","serverUrl":"https://nuget.pkg.github.com/contoso/index.json"}
```

**AL-Go-Settings.json** (optional):

```json
{
  "DeliverToGitHubPackages": {
    "ContinuousDelivery": true,
    "Branches": ["main"]
  }
}
```

### Example 2: Azure DevOps Artifacts for PTE Development

**Use Case**: A partner company with existing Azure DevOps infrastructure wants to deliver PTEs to their existing Azure DevOps Artifacts feed for controlled distribution.

**Repository Secret**: `NuGetContext`

```json
{"token":"<YOUR_AZURE_DEVOPS_TOKEN>","serverUrl":"https://pkgs.dev.azure.com/contoso/BusinessCentral/_packaging/BC-Apps/nuget/v3/index.json"}
```

**AL-Go-Settings.json**:

```json
{
  "trustedNuGetFeeds": [
    {
      "url": "https://pkgs.dev.azure.com/contoso/BusinessCentral/_packaging/BC-Apps/nuget/v3/index.json",
      "authTokenSecret": "NuGetContext",
      "patterns": ["Contoso.*"]
    }
  ]
}
```

### Example 3: Multi-Environment PTE Setup

**Use Case**: A PTE development team that wants to publish development builds to GitHub Packages and production releases to a private NuGet feed.

**AL-Go-Settings.json**:

```json
{
  "DeliverToGitHubPackages": {
    "ContinuousDelivery": true,
    "Branches": ["main", "develop"]
  },
  "environments": [
    {
      "name": "PRODUCTION",
      "DeliverToNuGet": {
        "ContinuousDelivery": true,
        "Branches": ["main"]
      }
    }
  ]
}
```

## Troubleshooting

### Common Issues

#### 1. Missing Context Secret

**Error**: `Secret 'GitHubPackagesContext' not found`
**Solution**: Ensure the secret is created at the organization level (or repository level) and is accessible to your repository.

#### 2. Authentication Failed

**Error**: `401 Unauthorized` when publishing packages
**Solution**:

- Verify your personal access token has the correct scopes
- Check if your token has expired
- Ensure your token has access to the target organization

#### 3. Package Not Found During Dependency Resolution

**Error**: Unable to find package during build
**Solution**:

- Verify the package was published successfully
- Check that dependency resolution is configured correctly
- Ensure the package name and version match your app.json dependencies

#### 4. Curly Brackets Masked in Logs

**Error**: Seeing `***` instead of JSON in logs
**Solution**: Ensure your JSON secrets are compressed (single line) without formatting.

### Debugging Steps

1. **Check Workflow Logs**: Look for the "Deliver to [Target]" job in your CI/CD workflow
1. **Verify Package Publication**: Check your organization's packages page
1. **Test Dependency Resolution**: Look for "Resolving Dependencies" and "installing app dependencies" in build logs
1. **Validate Secret Format**: Use `New-ALGoNuGetContext` to generate correctly formatted secrets

## Advanced Scenarios

### Custom Delivery Scripts

For advanced scenarios, you can create custom delivery scripts:

1. Create a PowerShell script named `DeliverTo<TargetName>.ps1` in your `.github` folder
1. Create a context secret named `<TargetName>Context`
1. AL-Go will automatically detect and use your custom delivery target

Example custom delivery script:

```powershell
# .github/DeliverToCustomFeed.ps1
Param(
    [Parameter(Mandatory = $true)]
    [HashTable] $parameters
)

# Extract parameters
$project = $parameters.project
$projectName = $parameters.projectName
$type = $parameters.type
$appsFolder = $parameters.appsFolder
$testAppsFolder = $parameters.testAppsFolder
$dependenciesFolder = $parameters.dependenciesFolder
$appsFolders = $parameters.appsFolders
$testAppsFolders = $parameters.testAppsFolders
$dependenciesFolders = $parameters.dependenciesFolders

# Custom delivery logic here
Write-Host "Delivering project '$project' (type: $type) to custom feed"
if ($appsFolder) {
    Write-Host "Apps folder: $appsFolder"
    # Process apps in $appsFolder
}
```

#### Supported Parameters

Your custom delivery script receives a hash table with the following parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `project` | string | Project path (escaped for artifact naming) |
| `projectName` | string | Project name (sanitized for use in paths) |
| `type` | string | Delivery type: "CD" (Continuous Delivery) or "Release" |
| `appsFolder` | string | Path to folder containing app files (.app) |
| `testAppsFolder` | string | Path to folder containing test app files (if available) |
| `dependenciesFolder` | string | Path to folder containing dependency files (if available) |
| `appsFolders` | string[] | Array of paths to all apps folders from different build modes |
| `testAppsFolders` | string[] | Array of paths to all test app folders from different build modes |
| `dependenciesFolders` | string[] | Array of paths to all dependency folders from different build modes |

> **Note:** The folder parameters (`*Folder`) may be `$null` if no artifacts of that type were found. The plural versions (`*Folders`) contain arrays of all matching folders across different build modes.

### Branch-Specific Delivery

Configure different delivery targets for different branches:

```json
{
  "DeliverToGitHubPackages": {
    "ContinuousDelivery": true,
    "Branches": ["develop", "feature/*"]
  },
  "DeliverToNuGet": {
    "ContinuousDelivery": true,
    "Branches": ["main"]
  }
}
```

### Multiple Feed Configuration

You can configure multiple trusted NuGet feeds for dependency resolution:

```json
{
  "trustedNuGetFeeds": [
    {
      "url": "https://nuget.pkg.github.com/contoso/index.json",
      "authTokenSecret": "GitHubPackagesContext",
      "patterns": ["Contoso.*"]
    },
    {
      "url": "https://pkgs.dev.azure.com/contoso/BC/_packaging/External/nuget/v3/index.json",
      "authTokenSecret": "AzureDevOpsContext",
      "patterns": ["External.*"]
    }
  ]
}
```

## Important Notes

### Security Considerations

- **Use appropriate token scopes**: Only grant necessary permissions to your tokens
- **Organization vs Repository secrets**: Use organization secrets for shared configurations
- **Token expiration**: Regularly rotate your personal access tokens
- **Compressed JSON**: Always use compressed JSON format for secrets to avoid masking issues

### Limitations

- **Fine-grained tokens**: GitHub Packages doesn't support fine-grained personal access tokens yet
- **Package visibility**: GitHub Packages inherit repository visibility settings
- **Retention policies**: Consider package retention policies for your feeds
- **Version conflicts**: Be mindful of version conflicts when using multiple feeds

### Best Practices

1. **Use semantic versioning**: Follow semantic versioning for your packages
1. **Test in isolation**: Test delivery configuration in a separate repository first
1. **Monitor package sizes**: Be aware of package size limits
1. **Document dependencies**: Clearly document your app dependencies
1. **Regular cleanup**: Implement package cleanup policies

## Next Steps

- [Learn more about AL-Go Settings](https://aka.ms/algosettings)
- [Explore Continuous Delivery options](../Workshop/ContinuousDelivery.md)
- [Set up dependencies between repositories](../Workshop/Dependencies2.md)
- [Understand AL-Go Secrets](https://aka.ms/algosecrets)
