[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'GitHub Secrets are transferred as plain text')]
Param(
    [Parameter(HelpMessage = "The GitHub actor running the action", Mandatory = $false)]
    [string] $actor,
    [Parameter(HelpMessage = "The GitHub token running the action", Mandatory = $false)]
    [string] $token,
    [Parameter(HelpMessage = "Specifies the parent telemetry scope for the telemetry signal", Mandatory = $false)]
    [string] $parentTelemetryScopeJson = '7b7d',
    [Parameter(HelpMessage = "Name of the online environment", Mandatory = $true)]
    [string] $environmentName,
    [Parameter(HelpMessage = "Project name if the repository is setup for multiple projects", Mandatory = $false)]
    [string] $project = '.',
    [Parameter(HelpMessage = "Admin center API credentials", Mandatory = $false)]
    [string] $adminCenterApiCredentials,
    [Parameter(HelpMessage = "Reuse environment if it exists", Mandatory = $false)]
    [bool] $reUseExistingEnvironment,
    [Parameter(HelpMessage = "Set the branch to update", Mandatory = $false)]
    [string] $updateBranch,
    [Parameter(HelpMessage = "Direct Commit (Y/N)", Mandatory = $false)]
    [bool] $directCommit
)

$telemetryScope = $null

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    $branch = ''
    if (!$directcommit) {
        # If not direct commit, create a new branch with name, relevant to the current date and base branch, and switch to it
        $branch = "create-development-environment/$updateBranch/$((Get-Date).ToUniversalTime().ToString(`"yyMMddHHmmss`"))" # e.g. create-development-environment/main/210101120000
    }
    $serverUrl = CloneIntoNewFolder -actor $actor -token $token -branch $branch
    $baseFolder = (Get-Location).Path
    DownloadAndImportBcContainerHelper -baseFolder $baseFolder

    import-module (Join-Path -path $PSScriptRoot -ChildPath "..\TelemetryHelper.psm1" -Resolve)
    $telemetryScope = CreateScope -eventId 'DO0073' -parentTelemetryScopeJson $parentTelemetryScopeJson

    $adminCenterApiCredentials = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminCenterApiCredentials))
    CreateDevEnv `
        -kind cloud `
        -caller GitHubActions `
        -environmentName $environmentName `
        -reUseExistingEnvironment:$reUseExistingEnvironment `
        -baseFolder $baseFolder `
        -project $project `
        -adminCenterApiCredentials ($adminCenterApiCredentials | ConvertFrom-Json | ConvertTo-HashTable)

    CommitFromNewFolder -serverUrl $serverUrl -commitMessage "Create a development environment $environmentName" -branch $branch

    TrackTrace -telemetryScope $telemetryScope
}
catch {
    if (Get-Module BcContainerHelper) {
        TrackException -telemetryScope $telemetryScope -errorRecord $_
    }
    throw
}
