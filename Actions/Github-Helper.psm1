function Get-dependencies {
    Param(
        [string] $token,
        $probingPathsJson,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE "dependencies")
    )

    Write-Host "Getting all the artifacts from probing paths"
    $downloadedList = @()
    $probingPathsJson | 
        ForEach-Object {
            $dependency = $_
            Write-Host "Getting releases from $($dependency.repo)"
            $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")

            if ($dependency.release_status -eq "latestBuild") {

                # TODO it should check the branch and limit to a certain branch
                $artifacts = GetArtifacts -token $token -api_url $api_url -repository $repository 
                if ($dependency.version -ne "latest") {
                    $artifacts = $artifacts | Where-Object { ($_.tag_name -eq $dependency.version) }
                }    
                
                $artifact = $artifacts | Select-Object -First 1
                if (!($artifact)) {
                    throw "Could not find any artifacts that matches the criteria."
                }

                DownloadArtifact -path $saveToPath -token $dependency.authTokenSecret -artifact $artifact
            }
            else {
                $releases = GetReleases -api_url $api_url -token $token -repository $repository
                if ($dependency.version -ne "latest") {
                    $releases = $releases | Where-Object { ($_.tag_name -eq $dependency.version) }
                }

                switch ($dependency.release_status) {
                    "release" { $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft ) } | Select-Object -First 1 }
                    "prerelease" { $release = $releases | Where-Object { ($_.prerelease ) } | Select-Object -First 1 }
                    "draft" { $release = $releases | Where-Object { ($_.draft ) } | Select-Object -First 1 }
                    Default { throw "Invalid release status '$($dependency.release_status)' is encountered." }
                }

                if (!($release)) {
                    throw "Could not find a release that matches the criteria."
                }
                
                $projects = $dependency.projects
                if ([string]::IsNullOrEmpty($dependency.projects)) {
                    $projects = "*"
                }

                $downloadedList += DownloadRelease -token $dependency.authTokenSecret -projects $projects -api_url $api_url -repository $repository -path $saveToPath -release $release
            }
        }
    
    return $downloadedList;
}

function GetReleases {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing releases"
    Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases" | ConvertFrom-Json
}

function GetHeader {
    param (
        [string] $token,
        [string] $accept = "application/json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "token $token"
    }

    return $headers
}

function DownloadRelease {
    Param(
        [string] $token,
        [string] $projects = "*",
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $path,
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "Downloading release $($release.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/octet-stream"
    }
    $projects.Split(',') | ForEach-Object {
        $project = $_
        Write-Host "project '$project'"
        $release.assets | ForEach-Object { Write-Host $_.name }
        
        $release.assets | Where-Object { $_.name -like "$project-Apps-*.zip" } | ForEach-Object {
            Write-Host "$api_url/repos/$repository/releases/assets/$($_.id)"
            $filename = Join-Path $path $_.name
            Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $_.browser_download_url -OutFile $filename 
            return $filename
        }
    }
}       

function GetArtifacts {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing artifacts"
    $artifacts = Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/actions/artifacts" | ConvertFrom-Json
    $artifacts.artifacts | Where-Object { $_.name -like "*-Apps-*" }
}

function GetArtifact {
    Param(
        [string] $token,
        $artifactsUrl
    )
    Write-Host "Analyzing artifact ($artifactsUrl)"
    $artifacts = Invoke-WebRequest -UseBasicParsing -Headers (GetHeader -token $token) -Uri $artifactsUrl | ConvertFrom-Json
    $artifacts.artifacts | Where-Object { $_.name -like "*-Apps-*" }
}

function DownloadArtifact {
    Param(
        [string] $token,
        [string] $path,
        $artifact
    )

    Write-Host "Downloading artifact $($artifact.Name)"
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.v3+json"
    }
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $artifact.archive_download_url -OutFile (Join-Path $path "$($artifact.Name).zip")
}    
