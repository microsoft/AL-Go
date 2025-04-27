Param(
    [Parameter(HelpMessage="Build version to find artifacts for", Mandatory=$true)]
    [string] $buildVersion,
    [Parameter(HelpMessage="The GitHub token", Mandatory=$true)]
    [string] $GITHUB_TOKEN,
    [Parameter(HelpMessage="The GhTokenWorkflow or the GitHub token (based on UseGhTokenWorkflow for PR/Commit)", Mandatory=$true)]
    [string] $TOKENFORPUSH,
    [Parameter(HelpMessage="Json structure containing projects to search for", Mandatory=$true)]
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
$allArtifacts = @()
$page = 1
$headers = @{
  "Authorization" = "token $GITHUB_TOKEN"
  "X-GitHub-Api-Version" = "2022-11-28"
  "Accept" = "application/vnd.github+json; charset=utf-8"
}
do {
  $repoArtifacts = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "$($ENV:GITHUB_API_URL)/repos/$($ENV:GITHUB_REPOSITORY)/actions/artifacts?per_page=100&page=$page"
  $allArtifacts += $repoArtifacts.Artifacts | Where-Object { !$_.expired }
  $page++
}
while ($repoArtifacts.Artifacts.Count -gt 0)
Write-Host "Repo Artifacts count: $($repoArtifacts.total_count)"
Write-Host "Downloaded Artifacts count: $($allArtifacts.Count)"
$projects | ForEach-Object {
  $thisProject = $_
  if ($thisProject -and ($thisProject -ne '.')) {
    $project = $thisProject.Replace('\','_').Replace('/','_')
  }
  else {
    $project = $settings.repoName
  }
  $refname = "$ENV:GITHUB_REF_NAME".Replace('/','_')
  Write-Host "Analyzing artifacts for project $project"
  $buildVersion = "$buildVersion"
  if ($buildVersion -eq "latest") {
    Write-Host "Grab latest"
    $artifact = $allArtifacts | Where-Object { $_.name -like "$project-$refname-Apps-*.*.*.*" -or $_.name -like "$project-$refname-PowerPlatformSolution-*.*.*.*" } | Select-Object -First 1
  }
  else {
    Write-Host "Search for $project-$refname-Apps-$buildVersion or $project-$refname-PowerPlatformSolution-$buildVersion"
    $artifact = $allArtifacts | Where-Object { $_.name -eq "$project-$refname-Apps-$buildVersion"-or $_.name -eq "$project-$refname-PowerPlatformSolution-$buildVersion" } | Select-Object -First 1
  }
  if ($artifact) {
    $startIndex = $artifact.name.LastIndexOf('-') + 1
    $artifactsVersion = $artifact.name.SubString($startIndex)
  }
  else {
    Write-Host "::Error::No artifacts found for this project"
    exit 1
  }
  if ($sha) {
    if ($artifact.workflow_run.head_sha -ne $sha) {
      Write-Host "::Error::The build selected for release doesn't contain all projects. Please rebuild all projects by manually running the CI/CD workflow and recreate the release."
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
    Write-Host "::Error::No artifacts found for version $artifactsVersion"
    exit 1
  }
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
      Write-Host "::ERROR::There has been changes to the $($ENV:GITHUB_REF_NAME) branch since the last successful build. Please run the CI/CD workflow to create the release or check the 'Use GhTokenWorkflow for PR/Commit' option when running the workflow."
    }
    else {
      Write-Host "::ERROR::You are trying to create a release from a version which is not the latest build. Please check the 'Use GhTokenWorkflow for PR/Commit' option when running the workflow."
    }
    exit 1
  }
}
