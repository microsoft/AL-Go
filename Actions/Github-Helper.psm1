function InvokeWebRequest {
    Param(
        [Hashtable] $headers,
        [string] $method,
        [string] $body,
        [string] $outFile,
        [string] $uri,
        [switch] $retry
    )

    try {
        $params = @{ "UseBasicParsing" = $true }
        if ($headers) {
            $params += @{ "headers" = $headers }
        }
        if ($method) {
            $params += @{ "method" = $method }
        }
        if ($body) {
            $params += @{ "body" = $body }
        }
        if ($outfile) {
            $params += @{ "outfile" = $outfile }
        }
        Invoke-WebRequest  @params -Uri $uri
    }
    catch {
        if ($retry) {
            Start-Sleep -Seconds 60
            try {
                Invoke-WebRequest  @params -Uri $uri
                return
            }
            catch {}
        }
        $errorRecord = $_
        $exception = $_.Exception
        $message = $exception.Message
        try {
            if ($errorRecord.ErrorDetails) {
                $errorDetails = $errorRecord.ErrorDetails | ConvertFrom-Json 
                $errorDetails.psObject.Properties.name | ForEach-Object {
                    $message += " $($errorDetails."$_")"
                }
            }
        }
        catch {}
        Write-Host "::Error::$message"
        throw $message
    }
}

function Get-dependencies {
    Param(
        $probingPathsJson,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE ".dependencies"),
        [string] $mask = "Apps"
    )

    if (!(Test-Path $saveToPath)) {
        New-Item $saveToPath -ItemType Directory | Out-Null
    }

    Write-Host "Downloading all $mask artifacts from probing paths"
    $downloadedList = @()
    $probingPathsJson | ForEach-Object {
        $dependency = $_
        $projects = $dependency.projects
        $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")
        if ($dependency.release_status -eq "latestBuild") {
            $artifacts = GetArtifacts -token $dependency.authTokenSecret -api_url $api_url -repository $repository -mask $mask -projects $projects -version $dependency.version -branch $dependency.branch
            if ($artifacts) {
                $artifacts | ForEach-Object {
                    $download = DownloadArtifact -path $saveToPath -token $dependency.authTokenSecret -artifact $_
                    if ($download) {
                        $downloadedList += $download
                    }
                    else {
                        Write-Host -ForegroundColor Red "Unable to download artifact $_"
                    }
                }
            }
            else {
                Write-Host -ForegroundColor Red "Could not find any $mask artifacts for projects $projects, version $($dependency.version)"
            }
        }
        elseif ($dependency.release_status -eq "include") {
            # folders have been included
        }
        else {
            $releases = GetReleases -api_url $api_url -token $dependency.authTokenSecret -repository $repository
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
                
            $download = DownloadRelease -token $dependency.authTokenSecret -projects $projects -api_url $api_url -repository $repository -path $saveToPath -release $release -mask $mask
            if ($download) {
                $downloadedList += $download
            }
        }
    }
    
    return $downloadedList;
}

function CmdDo {
    Param(
        [string] $command = "",
        [string] $arguments = "",
        [switch] $silent,
        [switch] $returnValue
    )

    $oldNoColor = "$env:NO_COLOR"
    $env:NO_COLOR = "Y"
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $result = $true
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.WorkingDirectory = Get-Location
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
    
        $outtask = $p.StandardOutput.ReadToEndAsync()
        $errtask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit();

        $message = $outtask.Result
        $err = $errtask.Result

        if ("$err" -ne "") {
            $message += "$err"
        }
        
        $message = $message.Trim()

        if ($p.ExitCode -eq 0) {
            if (!$silent) {
                Write-Host $message
            }
            if ($returnValue) {
                $message.Replace("`r","").Split("`n")
            }
        }
        else {
            $message += "`n`nExitCode: "+$p.ExitCode + "`nCommandline: $command $arguments"
            throw $message
        }
    }
    finally {
    #    [Console]::OutputEncoding = $oldEncoding
        $env:NO_COLOR = $oldNoColor
    }
}

function invoke-gh {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    $arguments = "$command "
    $remaining | ForEach-Object {
        if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
            $arguments += """$($_.Replace('"','\"'))"" "
        }
        else {
            $arguments += "$_ "
        }
    }
    cmdDo -command gh -arguments $arguments -silent:$silent -returnValue:$returnValue
}

function invoke-git {
    Param(
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    $arguments = "$command "
    $remaining | ForEach-Object {
        if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
            $arguments += """$($_.Replace('"','\"'))"" "
        }
        else {
            $arguments += "$_ "
        }
    }
    cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue
}

function SemVerObjToSemVerStr {
    Param(
        $semVerObj
    )

    try {
        $str = "$($semVerObj.Prefix)$($semVerObj.Major).$($semVerObj.Minor).$($semVerObj.Patch)"
        for ($i=0; $i -lt 5; $i++) {
            $seg = $semVerObj."Addt$i"
            if ($seg -eq 'zzz') { break }
            if ($i -eq 0) { $str += "-$($seg)" } else { $str += ".$($seg)" }
        }
        $str
    }
    catch {
        throw "'$SemVerObj' cannot be recognized as a semantic version object (internal error)"
    }
}

function SemVerStrToSemVerObj {
    Param(
        [string] $semVerStr
    )

    $obj = New-Object PSCustomObject
    try {
        $prefix = ''
        $verstr = $semVerStr
        if ($semVerStr -like 'v*') {
            $prefix = 'v'
            $verStr = $semVerStr.Substring(1)
        }
        $version = [System.Version]"$($verStr.split('-')[0])"
        if ($version.Revision -ne -1) { throw "not semver" }
        $obj | Add-Member -MemberType NoteProperty -Name "Prefix" -Value $prefix
        $obj | Add-Member -MemberType NoteProperty -Name "Major" -Value ([int]$version.Major)
        $obj | Add-Member -MemberType NoteProperty -Name "Minor" -Value ([int]$version.Minor)
        $obj | Add-Member -MemberType NoteProperty -Name "Patch" -Value ([int]$version.Build)
        0..4 | ForEach-Object {
            $obj | Add-Member -MemberType NoteProperty -Name "Addt$_" -Value 'zzz'
        }
        $idx = $verStr.IndexOf('-')
        if ($idx -gt 0) {
            $segments = $verStr.SubString($idx+1).Split('.')
            if ($segments.Count -ge 5) {
                throw "max. 5 segments"
            }
            0..($segments.Count-1) | ForEach-Object {
                $result = 0
                if ([int]::TryParse($segments[$_], [ref] $result)) {
                    $obj."Addt$_" = [int]$result
                }
                else {
                    if ($segments[$_] -ge 'zzz') {
                        throw "Unsupported segment"
                    }
                    $obj."Addt$_" = $segments[$_]
                }
            }
        }
        $newStr = SemVerObjToSemVerStr -semVerObj $obj
        if ($newStr -cne $semVerStr) {
            throw "Not equal"
        }
    }
    catch {
        throw "'$semVerStr' cannot be recognized as a semantic version string (https://semver.org)"
    }
    $obj
}

function GetReleases {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )

    Write-Host "Analyzing releases $api_url/repos/$repository/releases"
    $releases = @(InvokeWebRequest -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases" | ConvertFrom-Json)
    if ($releases.Count -gt 1) {
        # Sort by SemVer tag
        try {
            $sortedReleases = $releases.tag_name | 
                ForEach-Object { SemVerStrToSemVerObj -semVerStr $_ } | 
                Sort-Object -Property Major,Minor,Patch,Addt0,Addt1,Addt2,Addt3,Addt4 -Descending | 
                ForEach-Object { SemVerObjToSemVerStr -semVerObj $_ } | ForEach-Object {
                    $tag_name = $_
                    $releases | Where-Object { $_.tag_name -eq $tag_name }
                }
            $sortedReleases
        }
        catch {
            Write-Host -ForegroundColor red "Some of the release tags cannot be recognized as a semantic version string (https://semver.org)"
            Write-Host -ForegroundColor red "Using default GitHub sorting for releases"
            $releases
        }
    }
    else {
        $releases
    }
}

function GetHeader {
    param (
        [string] $token,
        [string] $accept = "application/vnd.github.v3+json"
    )
    $headers = @{ "Accept" = $accept }
    if (![string]::IsNullOrEmpty($token)) {
        $headers["Authorization"] = "token $token"
    }

    return $headers
}

function GetReleaseNotes {
    Param(
        [string] $token,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $tag_name,
        [string] $previous_tag_name
    )
    
    Write-Host "Generating release note $api_url/repos/$repository/releases/generate-notes"

    $postParams = @{
        tag_name = $tag_name;
    }

    if (-not [string]::IsNullOrEmpty($previous_tag_name)) {
        $postParams["previous_tag_name"] = $previous_tag_name
    }

    InvokeWebRequest -Headers (GetHeader -token $token) -Method POST -Body ($postParams | ConvertTo-Json) -Uri "$api_url/repos/$repository/releases/generate-notes" 
}

function GetLatestRelease {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY
    )
    
    Write-Host "Getting the latest release from $api_url/repos/$repository/releases/latest"
    try {
        InvokeWebRequest -Headers (GetHeader -token $token) -Uri "$api_url/repos/$repository/releases/latest" | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function DownloadRelease {
    Param(
        [string] $token,
        [string] $projects = "*",
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $path,
        [string] $mask = "Apps",
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "Downloading release $($release.Name), projects $projects, type $mask"
    if ([string]::IsNullOrEmpty($token)) {
        $authstatus = (invoke-gh -silent -returnValue auth status --show-token) -join " "
        $token = $authStatus.SubString($authstatus.IndexOf('Token: ')+7).Trim()
    }
    $headers = @{ 
        "Accept"        = "application/octet-stream"
        "Authorization" = "token $token"
    }
    $projects.Split(',') | ForEach-Object {
        $project = $_.Replace('\','_')
        Write-Host "project '$project'"
        
        $release.assets | Where-Object { $_.name -like "$project*-$mask-*.zip" } | ForEach-Object {
            $uri = "$api_url/repos/$repository/releases/assets/$($_.id)"
            Write-Host $uri
            $filename = Join-Path $path $_.name
            InvokeWebRequest -Headers $headers -Uri $uri -OutFile $filename 
            return $filename
        }
    }
}       

function CheckRateLimit {
    Param(
        [string] $token
    )

    $headers = GetHeader -token $token
    $rate = (InvokeWebRequest -Headers $headers -Uri "https://api.github.com/rate_limit").Content | ConvertFrom-Json
    $rate | ConvertTo-Json -Depth 99 | Out-Host
    $rate = $rate.rate
    $percent = [int]($rate.remaining*100/$rate.limit)
    Write-Host "$($rate.remaining) API calls remaining out of $($rate.limit) ($percent%)"
    if ($percent -lt 10) {
        $resetTimeStamp = ([datetime] '1970-01-01Z').AddSeconds($rate.reset)
        $waitTime = $resetTimeStamp.Subtract([datetime]::Now)
        Write-Host "Less than 10% API calls left, waiting for $($waitTime.TotalSeconds) seconds for limits to reset."
        Start-Sleep -seconds $waitTime.TotalSeconds+1
    }
}


function GetArtifacts {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $mask = "Apps",
        [string] $branch = "main",
        [string] $projects,
        [string] $version
    )

    $headers = GetHeader -token $token
    $allArtifacts = @()
    $per_page = 100
    $page = 1
    if ($version -eq 'latest') { $version = '*' }
    Write-Host "Analyzing artifacts"
    do {
        $uri = "$api_url/repos/$repository/actions/artifacts?per_page=$($per_page)&page=$($page)"
        Write-Host $uri
        $artifacts = InvokeWebRequest -UseBasicParsing -Headers $headers -Uri $uri | ConvertFrom-Json
        $page++
        $allArtifacts += @($artifacts.artifacts | Where-Object { $_.name -like "*-$branch-$mask-$version" })
        $result = @()
        $allArtifactsFound = $true
        $projects.Split(',') | ForEach-Object {
            $project = $_.Replace('\','_')
            $projectArtifact = $allArtifacts | Where-Object { $_.name -like "$project-$branch-$mask-$version" } | Select-Object -First 1
            if ($projectArtifact) {
                $result += @($projectArtifact)
            }
            else {
                $allArtifactsFound = $false
                $result = @()
            }
        }
    } while (!$allArtifactsFound -and $artifacts.total_count -gt $page*$per_page)
    $result
}

function DownloadArtifact {
    Param(
        [string] $token,
        [string] $path,
        $artifact
    )

    Write-Host "Downloading artifact $($artifact.Name)"
    Write-Host $artifact.archive_download_url
    if ([string]::IsNullOrEmpty($token)) {
        $authstatus = (invoke-gh -silent -returnValue auth status --show-token) -join " "
        $token = $authStatus.SubString($authstatus.IndexOf('Token: ')+7).Trim()
    }
    $headers = @{ 
        "Authorization" = "token $token"
        "Accept"        = "application/vnd.github.v3+json"
    }
    $outFile = Join-Path $path "$($artifact.Name).zip"
    InvokeWebRequest -Headers $headers -Uri $artifact.archive_download_url -OutFile $outFile
    $outFile
}    
