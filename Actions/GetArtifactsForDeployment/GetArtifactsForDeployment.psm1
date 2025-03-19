<#
    .SYNOPSIS
    Incremental builds adds an annotation to PR builds, pointing to a last known good build.
    This function checks if this annotation exists on a given PR build,
    and returns the id of the last known good build if it does.
    .PARAMETER repository
    Repository to search in
    .PARAMETER checkSuiteId
    The check suite id of the PR build
    .PARAMETER token
    Auth token
#>
function FindPRRunAnnotationForIncrementalBuilds {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $checkSuiteId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token
    $lastKnownGoodBuildId = 0

    Write-Host "Finding PR run annotation for incremental builds in repository $repository"

    $checkRunsURI = "https://api.github.com/repos/$repository/check-suites/$checkSuiteId/check-runs"
    Write-Host "- $checkRunsURI"

    $checkRuns = (InvokeWebRequest -Headers $headers -Uri $checkRunsURI).Content | ConvertFrom-Json

    # Use the check-suits api to get all the annotations for a build
    $annotationsURI = ''
    if($checkRuns -and $checkRuns.total_count -gt 0) {
        $initializationCheckRun = $checkRuns.check_runs | Where-Object { $_.name -eq 'Initialization' }

        if($initializationCheckRun) {
            Write-Host "Found PR run annotation"
            $annotationsURI = $initializationCheckRun.output.annotations_url
        }
    }

    # If the initialization annotation exist, check if a message pointing to last good build exist.
    if($annotationsURI) {
        Write-Host "- $annotationsURI"
        $annotations = (InvokeWebRequest -Headers $headers -Uri $annotationsURI).Content | ConvertFrom-Json
        if($annotations -and $annotations.count -gt 0) {
            foreach($annotation in $annotations) {
                if($annotation.message -match "Last known good build: https://github.com/$repository/actions/runs/([0-9]{1,11})") {
                    Write-Host "Found PR run annotation message: $($annotation.message)"
                    $lastKnownGoodBuildId = $matches[1]
                    break
                }
            }
        }
    }

    return $lastKnownGoodBuildId
}

<#
    .SYNOPSIS
    Gets the last PR build run ID for the specified repository and branch.
    Successful PR runs are those that have a workflow run named 'Pull Request Build' and successfully built all the projects.

    If the latest PR build is not completed or successful, 0 is returned.
    .PARAMETER repository
    Repository to search in
    .PARAMETER commitSha
    The commit sha of the PR. Finds runs related to that sha
    .PARAMETER token
    Auth token
#>
function FindLatestPRRun {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $commitSha,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token
    $lastSuccessfulPRRun = 0
    $lastKnownGoodBuildId = 0
    $per_page = 100
    $page = 1

    Write-Host "Finding latest PR build run for commit sha $commitSha in repository $repository"

    while($true) {
        # Get all workflow runs for the given commit sha
        $runsURI = "https://api.github.com/repos/$repository/actions/runs?per_page=$per_page&page=$page&head_sha=$commitSha"
        Write-Host "- $runsURI"
        $workflowRuns = (InvokeWebRequest -Headers $headers -Uri $runsURI).Content | ConvertFrom-Json

        if($workflowRuns.workflow_runs.Count -eq 0) {
            # No more workflow runs, breaking out of the loop
            break
        }

        # Filter to only PR builds
        $PRRuns = @($workflowRuns.workflow_runs | Where-Object { $_.name -eq 'Pull Request Build' -and $_.event -in @('pull_request', 'pull_request_target') })

        if ($PRRuns.Count -gt 0) {
            $latestPrRun = $PRRuns[0]
            if ($latestPrRun.status -ne 'completed') {
                Write-Host "::error::Latest PR build run is not completed. ($($latestPrRun.html_url))"
                break
            }

            if ($latestPrRun.conclusion -ne 'success') {
                Write-Host "::error::Latest PR build run is not successful. ($($latestPrRun.html_url))"
                break
            }
            # We only care about the latest PR build. If it is not completed or not successful, we return 0
            $lastSuccessfulPRRun = $latestPrRun.id
            $lastKnownGoodBuildId = FindPRRunAnnotationForIncrementalBuilds -repository $repository -checkSuiteId $latestPrRun.check_suite_id -token $token
            break
        }

        if($lastSuccessfulPRRun -ne 0) {
            break
        }

        $page += 1
    }

    if($lastSuccessfulPRRun -ne 0) {
        Write-Host "Lastest PR build ($lastSuccessfulPRRun) was successful for branch $branch in repository $repository"
    } else {
        Write-Host "Lastest PR build ($lastSuccessfulPRRun) was not successful for branch $branch in repository $repository"
    }

    return $lastSuccessfulPRRun, $lastKnownGoodBuildId
}

<#
    .SYNOPSIS
    Downloads an artifact from a workflow run and unpacks it.
    .PARAMETER token
    Auth token
    .PARAMETER folder
    Folder to download the artifact to
    .PARAMETER artifact
    The artifact to download
#>
function DownloadAndUnpackArtifact {
    Param(
        [string] $token,
        [string] $folder,
        $artifact
    )

    if ([string]::IsNullOrEmpty($token)) {
        $token = invoke-gh -silent -returnValue auth token
    }
    $headers = GetHeaders -token $token

    $filename = "$folder.zip"
    InvokeWebRequest -Headers $headers -Uri $artifact.archive_download_url -OutFile $filename
    if (Test-Path $folder) {
        Remove-Item $folder -Recurse -Force
    }
    Expand-Archive -Path $filename -DestinationPath $folder
    Remove-Item $filename -Force
}

<#
    .SYNOPSIS
    Downloads artifacts from a PR build and related last known good build.
    Iterates through the last known good build, and only copies any apps not found in the PR build.

    Any apps copied from the last known good build, are copied to the related PR artifact folder, based on project and artifact type.
    In case a PR artifact folder does not exist for a specific app, it is created.
    This is necessary, since the deploy action expects artifacts to follow the PR naming convention when deploying from a PR.
    .PARAMETER token
    Auth token
    .PARAMETER path
    Path to the build artifacts folder
    .PARAMETER prArtifacts
    List of artifacts published by the PR build
    .PARAMETER lastKnownGoodBuildArtifacts
    List of artifacts published by the last known good build, linked from the PR build
    .PARAMETER prRunId
    Run id of the PR build
    .PARAMETER lastKnownGoodBuildRunId
    Run id of the last known good build
#>
function DownloadPRArtifacts {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $path,
        [Parameter(Mandatory = $true)]
        $prArtifacts,
        [Parameter(Mandatory = $false)]
        $lastKnownGoodBuildArtifacts,
        [Parameter(Mandatory = $true)]
        [string] $prRunId,
        [Parameter(Mandatory = $false)]
        [string] $lastKnownGoodBuildRunId
    )

    $prHeadRef = GetHeadRefFromRunId -repository $ENV:GITHUB_REPOSITORY -runId $prRunId -token $token
    if ($lastKnownGoodBuildRunId -ne 0) {
        $lastKnownGoodBuildHeadRef = GetHeadRefFromRunId -repository $ENV:GITHUB_REPOSITORY -runId $lastKnownGoodBuildRunId -token $token
    }

    $prArtifactSuffix = ''

    $projectArtifactTypeToFolderMap = @{}
    $appsBuiltInPr = [System.Collections.Generic.HashSet[string]]::new()
    # Get the artifacts from the PR
    foreach($artifact in $prArtifacts) {
        # PR artifacts are named project-branch-type-PRxx-date, but since both branch and project can contain '-' in the name, we can't split using dash.
        $projectSuffix = $artifact.Name -split "-$prHeadRef-" # (project, type-PRxx-date)
        $typeIdDate = $projectSuffix[1] -split '-' # (type, PRxx, date)
        $project = $projectSuffix[0]
        $artifactType = $typeIdDate[0]
        Write-Host "Downloading artifact $($artifact.Name)"
        if ($prArtifactSuffix -eq '') {
            $prArtifactSuffix = "$($typeIdDate[1])-$($typeIdDate[2])"
        }

        # Download and unpack the artifact
        $foldername = Join-Path $path $artifact.Name
        DownloadAndUnpackArtifact -token $token -folder $foldername -artifact $artifact

        # For each app in the artifact, save the name in a hashset so we know not to copy it from the last known good build
        (Get-ChildItem -Path $foldername -Filter "*_*_*.*.*.*.app") | ForEach-Object {
            $versionAndFileEnding = $_.Name.Split('_')[-1]
            $appName = $_.Name.Replace("_$versionAndFileEnding", "")
            $appsBuiltInPr.Add("$project|$appName") | Out-Null
            $projectArtifactTypeToFolderMap["$project|$artifactType"] = $foldername
        }
    }

    # Get the artifacts from the last known good build, referenced in the PR
    $tempPath = Join-Path $path "temp"
    if (!(Test-Path $tempPath)) {
        New-Item $tempPath -ItemType Directory | Out-Null
    }
    foreach($artifact in $lastKnownGoodBuildArtifacts) {
        # PR artifacts are named project-branch-type-version, but since both branch and project can contain '-' in the name, we can't split using dash.
        $projectSuffix = $artifact.Name -split "-$lastKnownGoodBuildHeadRef-" # (project, type-version)
        $typeVersion = $projectSuffix[1] -split '-' # (type, version)
        $project = $projectSuffix[0]
        $artifactType = $typeVersion[0]
        Write-Host "Downloading artifact $($artifact.Name)"

        # Download and unpack the artifact
        $foldername = Join-Path $tempPath $artifact.Name
        DownloadAndUnpackArtifact -token $token -folder $foldername -artifact $artifact

        # The deploy action will search for an artifact with the PR style artifact name, so we need to create a folder with that pattern.
        if (!($projectArtifactTypeToFolderMap.ContainsKey("$project|$artifactType"))) {
            $newFolderName = Join-Path $path "$project-$prHeadRef-$artifactType-$prArtifactSuffix"
            if (!(Test-Path $newFolderName)) {
                New-Item $newFolderName -ItemType Directory | Out-Null
            }
            $projectArtifactTypeToFolderMap["$project|$artifactType"] = $newFolderName
            Write-Host "Artifact not built in PR for project $project, creating folder $newFolderName to store downloaded artifacts"
        }

        # Go through each artifact in the last known good build and copy the files to the PR artifact folder, if it is not already included.
        (Get-ChildItem -Path $foldername -Filter "*_*_*.*.*.*.app") | ForEach-Object {
            $versionAndFileEnding = $_.Name.Split('_')[-1]
            $appName = $_.Name.Replace("_$versionAndFileEnding", "")
            # If the app was not built in the PR, we need to copy it from the last known good build
            if (!$appsBuiltInPr.Contains("$project|$appName")) {
                Write-Host "App $appName not found in PR artifacts, copying from last known good build"
                Copy-Item -Path $_.FullName -Destination $projectArtifactTypeToFolderMap["$project|$artifactType"]
            }
        }
    }
    # Cleanup temp folder
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Recurse -Force
    }
}

<#
    .SYNOPSIS
    Gets the latest commit sha for the specified PR id in the specified repository.
    .PARAMETER repository
    Repository to search in
    .PARAMETER prId
    The run id
    .PARAMETER token
    Auth token
#>
function GetLatestCommitShaFromPRId {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $prId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token

    $pullsURI = "https://api.github.com/repos/$repository/pulls/$prId"
    Write-Host "- $pullsURI"
    $pr = (InvokeWebRequest -Headers $headers -Uri $pullsURI).Content | ConvertFrom-Json

    return $pr.head.sha
}

<#
 .SYNOPSIS
  Gets the head ref for the specified run id in the specified repository.
 .PARAMETER repository
  Repository to search in
 .PARAMETER prId
  The run id
 .PARAMETER token
  Auth token
#>
function GetHeadRefFromRunId {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $runId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token

    $runsURI = "https://api.github.com/repos/$repository/actions/runs/$runId"
    Write-Host "- $runsURI"

    $run = (InvokeWebRequest -Headers $headers -Uri $runsURI).Content | ConvertFrom-Json

    return $run.head_branch
}
