Param(
    [Parameter(HelpMessage = "The repository of the action", Mandatory = $false)]
    [string] $actionsRepo,
    [Parameter(HelpMessage = "The ref of the action", Mandatory = $false)]
    [string] $actionsRef
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-TestRepoHelper.ps1" -Resolve)

if ($actionsRepo -eq 'microsoft/AL-Go-Actions') {
    Write-Host "Using AL-Go for GitHub $actionsRef"
    $verstr = $actionsRef
}
elseif ($actionsRepo -eq 'microsoft/AL-Go') {
    Write-Host "Using AL-Go for GitHub Preview ($actionsRef)"
    $verstr = "p"
}
else {
    Write-Host "Using direct AL-Go development ($($actionsRepo)@$actionsRef)"
    $verstr = "d"
}

Write-Big -str "a$verstr"

# Test the AL-Go repository is set up correctly
TestALGoRepository

# Test the prerequisites for the test runner
TestRunnerPrerequisites

# Create a json object that contains an entry for the workflowstarttime
$scopeJson = @{
    "workflowStartTime" = [DateTime]::UtcNow
} | ConvertTo-Json -Compress

Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "telemetryScopeJson=$scopeJson"
