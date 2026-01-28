# Download External Project Dependencies

Downloads external project dependencies from URLs specified in installApps and installTestApps settings.

This action resolves secret placeholders in URLs (e.g., `${{ secrets.MySecret }}`), downloads app files from those URLs to a temporary location, and outputs paths to the downloaded files.

## INPUT

### ENV variables

| Name | Description |
| :-- | :-- |
| Settings | env.Settings must be set by a prior call to the ReadSettings Action |
| Secrets | env.Secrets must be read by a prior call to the ReadSecrets Action |

### Parameters

| Name | Required | Description | Default value |
| :-- | :-: | :-- | :-- |
| shell | | The shell (powershell or pwsh) in which the PowerShell script in this action should run | powershell |
| installAppsJson | | A path to a JSON-formatted list of apps to install | '' |
| installTestAppsJson | | A path to a JSON-formatted list of test apps to install | '' |

## OUTPUT

### OUTPUT variables

| Name | Description |
| :-- | :-- |
| DownloadedApps | A path to a JSON-formatted list of apps to install (with URLs resolved and downloaded) |
| DownloadedTestApps | A path to a JSON-formatted list of test apps to install (with URLs resolved and downloaded) |
