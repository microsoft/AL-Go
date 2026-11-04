Param(
    [Parameter(HelpMessage = "Build version to find artifacts for", Mandatory = $true)]
    [string] $buildVersion,
    [Parameter(HelpMessage = "The GitHub token", Mandatory = $true)]
    [string] $GITHUB_TOKEN,
    [Parameter(HelpMessage = "The GhTokenWorkflow or the GitHub token (based on UseGhTokenWorkflow for PR/Commit)", Mandatory = $true)]
    [string] $TOKENFORPUSH,
    [Parameter(HelpMessage = "Json structure containing projects to search for", Mandatory = $true)]
    [string] $ProjectsJson
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

Write-Host "Get settings from env"
$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable

# Get projects
$projects = $ProjectsJson | ConvertFrom-Json
Write-Host "projects:"
$projects | ForEach-Object { Write-Host "- $_" }
if ($settings.type -eq "PTE" -and $settings.powerPlatformSolutionFolder -ne "") {
    Write-Host "PowerPlatformSolution:"
    Write-Host "- $($settings.powerPlatformSolutionFolder)"
    $projects += @($settings.powerPlatformSolutionFolder)
}
$include = @()
$sha = ''
$headers = @{
    "Authorization" = "token $GITHUB_TOKEN"
    "X-GitHub-Api-Version" = "2022-11-28"
    "Accept" = "application/vnd.github+json; charset=utf-8"
}
$refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
$buildVersion = "$buildVersion"
$projects | ForEach-Object {
    $thisProject = $_
    if ($thisProject -and ($thisProject -ne '.')) {
        $project = $thisProject.Replace('\','_').Replace('/','_')
    }
    else {
        $project = $settings.repoName
    }
    Write-Host "Analyzing artifacts for project $project"
    # Find the workflow run with the artifacts of the project and read the artifacts of that run.
    # Release artifacts (Apps, PowerPlatformSolution) are searched first, test artifacts only for projects without release artifacts.
    $allArtifacts = @()
    foreach ($artifactMasks in @(@('Apps', 'PowerPlatformSolution'), @('*TestApps'))) {
        $workflowRunId = 0
        if ($buildVersion -eq "latest") {
            $artifactsVersionFilter = '*'
            $workflowRunId, $workflowRunSha = FindLatestSuccessfulCICDRun -repository $ENV:GITHUB_REPOSITORY -branch $ENV:GITHUB_REF_NAME -token $GITHUB_TOKEN -retention 90 -api_url $ENV:GITHUB_API_URL -artifactProject $project -artifactMasks $artifactMasks
        }
        else {
            $artifactsVersionFilter = $buildVersion
            foreach ($artifactMask in $artifactMasks) {
                $artifactName = "$project-$refname-$($artifactMask.TrimStart('*'))-$buildVersion"
                Write-Host "Search for $artifactName"
                $namedArtifacts = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/actions/artifacts?name=$([Uri]::EscapeDataString($artifactName))&per_page=100"
                $namedArtifact = @($namedArtifacts.artifacts | Where-Object { !$_.expired }) | Select-Object -First 1
                if ($namedArtifact) {
                    $workflowRunId = $namedArtifact.workflow_run.id
                    break
                }
            }
        }
        if ($workflowRunId) {
            Write-Host "Using artifacts from CI/CD run $workflowRunId"
            $allArtifacts = @(GetArtifactsFromWorkflowRun -workflowRun $workflowRunId -token $GITHUB_TOKEN -api_url $ENV:GITHUB_API_URL -repository $ENV:GITHUB_REPOSITORY -mask '*' -projects $project -version $artifactsVersionFilter)
            break
        }
    }
    Write-Host "Artifacts count: $($allArtifacts.Count)"
    if ($buildVersion -eq "latest") {
        Write-Host "Grab latest"
        $artifact = $allArtifacts | Where-Object { $_.name -like "$project-$refname-Apps-*.*.*.*" -or $_.name -like "$project-$refname-PowerPlatformSolution-*.*.*.*" } | Select-Object -First 1
    }
    else {
        Write-Host "Search for $project-$refname-Apps-$buildVersion or $project-$refname-PowerPlatformSolution-$buildVersion"
        $artifact = $allArtifacts | Where-Object { $_.name -eq "$project-$refname-Apps-$buildVersion" -or $_.name -eq "$project-$refname-PowerPlatformSolution-$buildVersion" } | Select-Object -First 1
    }
    if ($artifact) {
        $startIndex = $artifact.name.LastIndexOf('-') + 1
        $artifactsVersion = $artifact.name.SubString($startIndex)
    }
    else {
        # No release artifacts (Apps or PowerPlatformSolution) were found for this project.
        # This can happen when a project contains only test apps - in that case, skip the project
        # rather than failing the release, as test apps are not part of the release.
        if ($allArtifacts | Where-Object { $_.name -like "$project-$refname-*TestApps-*.*.*.*" }) {
            Write-Host "::Warning::No release artifacts found for project $project, only test artifacts are available. Skipping project for release."
            return
        }
        throw "No artifacts found for this project"
    }
    if ($sha) {
        if ($artifact.workflow_run.head_sha -ne $sha) {
            throw "The build selected for release doesn't contain all projects. Please rebuild all projects by manually running the CI/CD workflow and recreate the release."
        }
    }
    else {
        $sha = $artifact.workflow_run.head_sha
    }
    Write-host "Looking for $project-$refname-Apps-$artifactsVersion or $project-$refname-TestApps-$artifactsVersion or $project-$refname-Dependencies-$artifactsVersion or $project-$refname-PowerPlatformSolution-$artifactsVersion"
    $allArtifacts | Where-Object { ($_.name -like "$project-$refname-Apps-$artifactsVersion" -or $_.name -like "$project-$refname-TestApps-$artifactsVersion" -or $_.name -like "$project-$refname-Dependencies-$artifactsVersion" -or $_.name -like "$project-$refname-PowerPlatformSolution-$artifactsVersion") } | ForEach-Object {
        $atype = $_.name.SubString(0,$_.name.Length-$artifactsVersion.Length-1)
        $atype = $atype.SubString($atype.LastIndexOf('-')+1)
        $include += $( [ordered]@{ "name" = $_.name; "url" = $_.archive_download_url; "atype" = $atype; "project" = $thisproject } )
    }
    if ($include.Count -eq 0) {
        throw "No artifacts found for version $artifactsVersion"
    }
}
if ($include.Count -eq 0 -or -not $sha) {
    throw "No release artifacts found for any project. Ensure that at least one project produces release artifacts (Apps or PowerPlatformSolution) before creating a release."
}
$artifacts = @{ "include" = $include }
$artifactsJson = $artifacts | ConvertTo-Json -compress
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "artifacts=$artifactsJson"
Write-Host "artifacts=$artifactsJson"
Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "commitish=$sha"
Write-Host "commitish=$sha"
if ("$GITHUB_TOKEN" -eq "$TOKENFORPUSH") {
    # See https://github.blog/changelog/2023-11-02-github-actions-enforcing-workflow-scope-when-creating-a-release/
    $latestCommit = (Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/branches/$($ENV:GITHUB_REF_NAME)").commit.sha
    if ($latestCommit -ne $sha) {
        if ($buildVersion -eq 'latest') {
            throw "The $($ENV:GITHUB_REF_NAME) branch has changed since the last successful build. To prevent this error, either enable 'Use GhTokenWorkflow for PR/Commit' when you start the workflow, or first run the CI/CD pipeline to create a fresh build before rerunning the workflow."
        }
        else {
            throw "You’re attempting to create a release from a build that isn’t the most recent one. Enable the 'Use GhTokenWorkflow for PR/Commit' option when you run the workflow, to achieve this."
        }
    }
}
