# TRASER PreCompileApp Override Implementation
# Removes internalsVisibleTo from app.json before compilation.

Param(
    [hashtable]$parameters
)

$project = $parameters.project
$projectFolder = Join-Path $ENV:GITHUB_WORKSPACE $project

$appJsonFiles = Get-ChildItem -Path $projectFolder -Filter "app.json" -Recurse
foreach ($appJsonFile in $appJsonFiles) {
    $appInfo = Get-Content -Encoding UTF8 $appJsonFile.FullName | ConvertFrom-Json
    if ($appInfo.PSObject.Properties.Name -match 'internalsVisibleTo') {
        $appInfo.PSObject.Properties.Remove('internalsVisibleTo')
        $appInfo | ConvertTo-Json -Depth 100 | Set-Content -Encoding UTF8 $appJsonFile.FullName
        Write-Host "Removed internalsVisibleTo from $($appInfo.name)"
    }
}
