Param(
    [Parameter(HelpMessage = "Folder containing error logs and SARIF output", Mandatory = $false)]
    [string] $errorLogsFolder = "ErrorLogs"
)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "ProcessALCodeAnalysisLogs.psm1" -Resolve) -Force -DisableNameChecking

$errorLogsFolderPath = Join-Path $ENV:GITHUB_WORKSPACE $errorLogsFolder

$sarifPath = Join-Path -Path $PSScriptRoot -ChildPath ".\baseSarif.json" -Resolve
$sarif = $null
if (Test-Path $sarifPath) {
    $sarif = Get-Content -Path $sarifPath -Raw | ConvertFrom-Json
} else {
    OutputError -message "Base SARIF file not found at $sarifPath"
}

<#
    .SYNOPSIS
    Generates SARIF JSON.
    .DESCRIPTION
    Generates SARIF JSON from a error log file and adds both rules and results to the base sarif object.
    Rules and results are de-duplicated.
    .PARAMETER errorLogContent
    The contents of the error log file to process.
#>
function GenerateSARIFJson {
    param(
        [Parameter(HelpMessage = "The contents of the error log file to process.", Mandatory = $true)]
        [PSCustomObject] $errorLogContent,
        [Parameter(HelpMessage = "The base SARIF object to add results to.", Mandatory = $false)]
        [PSCustomObject] $sarif = $null
    )

    foreach ($issue in $errorLogContent.issues) {
        # Skip issues without locations as GitHub expects at least one location
        if (($issue.PSObject.Properties.Name -notcontains "locations" ) -or ($issue.locations.Count -eq 0) -or $issue.PSObject.Properties.Name -notcontains "ruleId") {
            continue
        }

        $newResult = $null
        $relativePath = Get-FileFromAbsolutePath -AbsolutePath $issue.locations[0].analysisTarget[0].uri
        $message = Get-IssueMessage -issue $issue
        $issueSeverity = Get-IssueSeverity -issue $issue

        # Skip issues if we cannot find a message
        if ($null -eq $message) {
            OutputDebug -message "Could not extract message from issue: $($issue | ConvertTo-Json -Depth 10 -Compress)"
            continue
        }

        # Skip issues if we cannot find the file in the workspace
        if ($null -eq $relativePath) {
            OutputDebug -message "Could not find file for issue: $($issue | ConvertTo-Json -Depth 10 -Compress)"
            continue
        }

        # Check if result already exists in the sarif object
        $existingResults = $sarif.runs[0].results | Where-Object {
            $_.ruleId -eq $issue.ruleId -and
            $_.message.text -eq $message -and
            $_.level -eq ($issueSeverity).ToLower() -and
            ($_.locations[0].physicalLocation.artifactLocation.uri -eq $relativePath) -and
            ($_.locations[0].physicalLocation.region | ConvertTo-Json) -eq ($issue.locations[0].analysisTarget[0].region | ConvertTo-Json)
        }

        if ($existingResults) {
            # Skip if existing
            continue
        }

        # Add rule to the sarif object if not already added
        if (-not ($sarif.runs[0].tool.driver.rules | Where-Object { $_.id -eq $issue.ruleId })) {
            $fullMessage = $message
            if ($issue.PSObject.Properties.Name -contains "fullMessage") {
                $fullMessage = $issue.fullMessage
            }
            $fullMessage = "$($issue.ruleId): $fullMessage"

            # Use only full message for rules if possible. The messages from the AL compiler look like this:
            # "shortMessage": "Variable 'InvalidDate' is unused in 'CustomerListExtTwo'.",
            # "fullMessage": "Do not declare variables that are unused."
            # So if shortMessage is used, the rule description will not be generic, but specific to a certain alert result.
            $sarif.runs[0].tool.driver.rules += @{
                id = $issue.ruleId
                shortDescription = @{ text = $fullMessage }
                fullDescription = @{ text = $fullMessage }
                helpUri = $issue.properties.helpLink
                properties = @{
                    category = $issue.properties.category
                    severity = $issueSeverity
                }
            }
        }

        # Create new result
        $newResult = @{
            ruleId = $issue.ruleId
            message = @{ text = $message }
            locations = @(@{
                physicalLocation = @{
                    artifactLocation = @{ uri = $relativePath }
                    region = $issue.locations[0].analysisTarget[0].region
                }
            })
            level = ($issueSeverity).ToLower()
        }

        # Add the new result if it was created
        if ($null -ne $newResult) {
            $sarif.runs[0].results += $newResult
        }
    }
}

try {
    if ((Test-Path $errorLogsFolderPath -PathType Container) -and ($null -ne $sarif)){
        $errorLogFiles = @(Get-ChildItem -Path $errorLogsFolderPath -Filter "*.errorLog.json" -File -Recurse)
        Write-Host "Found $($errorLogFiles.Count) error log files in $errorLogsFolderPath"
        $errorLogFiles | ForEach-Object {
            OutputDebug -message "Found error log file: $($_.FullName)"
            $fileName = $_.Name
            try {
                $errorLogContent = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
                GenerateSARIFJson -errorLogContent $errorLogContent -sarif $sarif
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
        OutputWarning -message "ErrorLogs $errorLogsFolder folder not found. You can manually inspect your artifacts for AL code alerts."
    }
}
catch {
    OutputWarning -message "Unexpected error processing AL code analysis results. You can manually inspect your artifacts for AL code alerts."
    OutputDebug -message "Error: $_"
    Trace-Exception -ActionName "ProcessALCodeAnalysisLogs" -ErrorRecord $_
}
