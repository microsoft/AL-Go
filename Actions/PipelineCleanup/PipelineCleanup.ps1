$ErrorActionPreference = "Stop"


. (Join-Path $PSScriptRoot "..\AL-Go-Helper.ps1")

$BcContainerHelperPath = DownloadAndImportBcContainerHelper

try {
    $containerName = "bc$env:GITHUB_RUN_ID"
    Remove-Bccontainer $containerName
}
finally {
    try {
        Remove-Module BcContainerHelper
        Remove-Item $bcContainerHelperPath -Recurse
    }
    catch {}
}
