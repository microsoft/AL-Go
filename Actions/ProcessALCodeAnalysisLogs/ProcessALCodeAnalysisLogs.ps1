Param(
    [Parameter(HelpMessage = "Folder containing error logs and SARIF output", Mandatory = $false)]
    [string] $errorLogsFolder = "ErrorLogs"
)

$errorLogsFolderPath = Join-Path $ENV:GITHUB_WORKSPACE "ErrorLogs"

$sarifPath = Join-Path -Path $PSScriptRoot -ChildPath ".\baseSarif.json" -Resolve
$sarif = $null
if (Test-Path $sarifPath) {
    $sarif = Get-Content -Path $sarifPath -Raw | ConvertFrom-Json
} else {
    OutputError -message "Base SARIF file not found at $sarifPath"
}

function GenerateSARIFJson {
    param(
        [PSCustomObject] $errorLogContent
    )

    foreach ($issue in $errorLogContent.issues) {
        # Add rule if not already added
        if (-not ($sarif.runs[0].tool.driver.rules | Where-Object { $_.id -eq $issue.ruleId })) {
            $sarif.runs[0].tool.driver.rules += @{
                id = $issue.ruleId
                shortDescription = @{ text = $issue.fullMessage }
                fullDescription = @{ text = $issue.fullMessage }
                helpUri = $issue.properties.helpLink
                properties = @{
                    category = $issue.properties.category
                    severity = $issue.properties.severity
                }
            }
        }

        # Convert absolute path to relative path from repository root
        $absolutePath = $issue.locations[0].analysisTarget[0].uri
        $workspacePath = $ENV:GITHUB_WORKSPACE
        $relativePath = $absolutePath.Replace($workspacePath, '').TrimStart('\').Replace('\', '/')

        # Add result
        $sarif.runs[0].results += @{
            ruleId = $issue.ruleId
            message = @{ text = $issue.shortMessage }
            locations = @(@{
                physicalLocation = @{
                    artifactLocation = @{ uri = $relativePath }
                    region = $issue.locations[0].analysisTarget[0].region
                }
            })
            level = ($issue.properties.severity).ToLower()
        }
    }
}

try {
    if (Test-Path $errorLogsFolderPath -PathType Container -and $sarif -neq $null){
        $errorLogFiles = @(Get-ChildItem -Path $errorLogsFolderPath -Filter "*.errorLog.json" -File -Recurse)
        Write-Host "Found $($errorLogFiles.Count) error log files in $errorLogsFolderPath"
        $errorLogFiles | ForEach-Object {
            OutputDebug -message "Found error log file: $($_.FullName)"
            $fileName = $_.Name
            try {
                $errorLogContent = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
                GenerateSARIFJson -errorLogContent $errorLogContent
            }
            catch {
                OutputWarning "Failed to process $fileName. AL code alerts might not appear in GitHub. You can manually inspect your artifacts for AL code alerts"
                OutputDebug -message "Error: $_"
            }
        }

        $sarifJson = $sarif | ConvertTo-Json -Depth 10 -Compress
        OutputDebug -message $sarifJson
        Set-Content -Path "$errorLogsFolderPath/output.sarif.json" -Value $sarifJson
    }
    else {
        OutputWarning -message "ErrorLogs folder not found. You can manually inspect your artifacts for AL code alerts."
    }
}
catch {
    OutputWarning -message "Unexpected error processing AL code analysis results. You can manually inspect your artifacts for AL code alerts."
    OutputDebug -message "Error: $_"
}
