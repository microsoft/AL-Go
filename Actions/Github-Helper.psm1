function GetExtendedErrorMessage {
    Param(
        $errorRecord
    )

    $exception = $errorRecord.Exception
    $message = $exception.Message

    try {
        $errorDetails = $errorRecord.ErrorDetails | ConvertFrom-Json
        $message += " $($errorDetails.error)`n$($errorDetails.error_description)"
    }
    catch {}
    try {
        if ($exception -is [System.Management.Automation.MethodInvocationException]) {
            $exception = $exception.InnerException
        }
        $webException = [System.Net.WebException]$exception
        $webResponse = $webException.Response
        try {
            if ($webResponse.StatusDescription) {
                $message += "`n$($webResponse.StatusDescription)"
            }
        } catch {}
        $reqstream = $webResponse.GetResponseStream()
        $sr = new-object System.IO.StreamReader $reqstream
        $result = $sr.ReadToEnd()
        try {
            $json = $result | ConvertFrom-Json
            $message += "`n$($json.Message)"
        }
        catch {
            $message += "`n$result"
        }
        try {
            $correlationX = $webResponse.GetResponseHeader('ms-correlation-x')
            if ($correlationX) {
                $message += " (ms-correlation-x = $correlationX)"
            }
        }
        catch {}
    }
    catch{}
    $message
}

function InvokeWebRequest {
    Param(
        [Hashtable] $headers,
        [string] $method,
        [string] $body,
        [string] $outFile,
        [string] $uri,
        [switch] $retry,
        [switch] $ignoreErrors
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
        $message = GetExtendedErrorMessage -errorRecord $_
        if ($retry) {
            Write-Host $message
            Write-Host "...retrying in 1 minute"
            Start-Sleep -Seconds 60
            try {
                Invoke-WebRequest  @params -Uri $uri
                return
            }
            catch {}
        }
        if ($ignoreErrors.IsPresent) {
            Write-Host $message
        }
        else {
            Write-Host "::Error::$message"
            throw $message
        }
    }
}

function Get-dependencies {
    Param(
        $probingPathsJson,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE ".dependencies")
    )

    if (!(Test-Path $saveToPath)) {
        New-Item $saveToPath -ItemType Directory | Out-Null
    }

    $downloadedList = @()
    'Apps','TestApps' | ForEach-Object {
        $mask = $_
        Write-Host "Locating all $mask artifacts from probing paths"
        $probingPathsJson | ForEach-Object {
            $dependency = $_
            $projects = $dependency.projects
            
            if ($dependency.release_status -eq "thisBuild") {
                $missingProjects = @()
                $projects.Split(',') | ForEach-Object {
                    $project = $_
                    $project = $project.Replace('\','_').Replace('/','_') # sanitize project name
                    
                    $downloadName = Join-Path $saveToPath "thisbuild-$project-$($mask)"
                    
                    if (Test-Path $downloadName -PathType Container) {
                        $folder = Get-Item $downloadName
                        Get-ChildItem -Path $folder | ForEach-Object {
                            if ($mask -eq 'TestApps') {
                                $downloadedList += @("($($_.FullName))")
                            }
                            else {
                                $downloadedList += @($_.FullName)
                            }
                            Write-Host "$($_.FullName) found from previous job"
                        }
                    }
                    elseif ($mask -ne 'TestApps') {
                        Write-Host "$_ not built, downloading from artifacts"
                        $missingProjects += @($_)
                    }
                }
                if ($missingProjects) {
                    $dependency.release_status = 'latestBuild'
                    $dependency.branch = "main"
                    $dependency.projects = $missingProjects -join ","
                }
            }
            $projects = $dependency.projects
            $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")
            if ($dependency.release_status -eq "latestBuild") {
                $artifacts = GetArtifacts -token $dependency.authTokenSecret -api_url $api_url -repository $repository -mask $mask -projects $projects -version $dependency.version -branch $dependency.branch
                if ($artifacts) {
                    $artifacts | ForEach-Object {
                        $download = DownloadArtifact -path $saveToPath -token $dependency.authTokenSecret -artifact $_
                        if ($download) {
                            if ($mask -eq 'TestApps') {
                                $downloadedList += @("($download)")
                            }
                            else {
                                $downloadedList += @($download)
                            }
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
            elseif ($dependency.release_status -ne "thisBuild" -and $dependency.release_status -ne "include") {
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
                    if ($mask -eq 'TestApps') {
                        $downloadedList += @("($download)")
                    }
                    else {
                        $downloadedList += @($download)
                    }
                }
            }
        }
    }
    return $downloadedList
}

function CmdDo {
    Param(
        [string] $command = "",
        [string] $arguments = "",
        [switch] $silent,
        [switch] $returnValue,
        [string] $inputStr = ""
    )

    $oldNoColor = "$env:NO_COLOR"
    $env:NO_COLOR = "Y"
    $oldEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    try {
        $result = $true
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        if ($inputStr) {
            $pinfo.RedirectStandardInput = $true
        }
        $pinfo.WorkingDirectory = Get-Location
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $pinfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        if ($inputStr) {
            $p.StandardInput.WriteLine($inputStr)
            $p.StandardInput.Close()
        }
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
        try { [Console]::OutputEncoding = $oldEncoding } catch {}
        $env:NO_COLOR = $oldNoColor
    }
}

function invoke-gh {
    Param(
        [parameter(mandatory = $false, ValueFromPipeline = $true)]
        [string] $inputStr = "",
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
    cmdDo -command gh -arguments $arguments -silent:$silent -returnValue:$returnValue -inputStr $inputStr
}

function invoke-git {
    Param(
        [parameter(mandatory = $false, ValueFromPipeline = $true)]
        [string] $inputStr = "",
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
    cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue -inputStr $inputStr
}

# Convert a semantic version object to a semantic version string
#
# The SemVer object has the following properties:
#   Prefix: 'v' or ''
#   Major: the major version number
#   Minor: the minor version number
#   Patch: the patch version number
#   Addt0: the first additional segment (zzz means not specified)
#   Addt1: the second additional segment (zzz means not specified)
#   Addt2: the third additional segment (zzz means not specified)
#   Addt3: the fourth additional segment (zzz means not specified)
#   Addt4: the fifth additional segment (zzz means not specified)
#
# Returns the SemVer string
#   #   [v]major.minor.patch[-addt0[.addt1[.addt2[.addt3[.addt4]]]]]
function SemVerObjToSemVerStr {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
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

# Convert a semantic version string to a semantic version object
# SemVer strings supported are defined under https://semver.org, additionally allowing a leading 'v' (as supported by GitHub semver sorting)
#
# The string has the following format:
#   if allowMajorMinorOnly is specified:
#     [v]major.minor.[patch[-addt0[.addt1[.addt2[.addt3[.addt4]]]]]]
#   else
#     [v]major.minor.patch[-addt0[.addt1[.addt2[.addt3[.addt4]]]]]
#
# Returns the SemVer object. The SemVer object has the following properties:
#   Prefix: 'v' or ''
#   Major: the major version number
#   Minor: the minor version number
#   Patch: the patch version number
#   Addt0: the first additional segment (zzz means not specified)
#   Addt1: the second additional segment (zzz means not specified)
#   Addt2: the third additional segment (zzz means not specified)
#   Addt3: the fourth additional segment (zzz means not specified)
#   Addt4: the fifth additional segment (zzz means not specified)

function SemVerStrToSemVerObj {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $semVerStr,
        [switch] $allowMajorMinorOnly
    )

    $obj = New-Object PSCustomObject
    try {
        # Only allowed prefix is a 'v'.
        # This is supported by GitHub when sorting tags
        $prefix = ''
        $verstr = $semVerStr
        if ($semVerStr -like 'v*') {
            $prefix = 'v'
            $verStr = $semVerStr.Substring(1)
        }
        # Next part is a version number with 2 or 3 segments
        # 2 segments are allowed only if $allowMajorMinorOnly is specified
        $version = [System.Version]"$($verStr.split('-')[0])"
        if ($version.Revision -ne -1) { throw "not semver" }
        if ($version.Build -eq -1) {
            if ($allowMajorMinorOnly) {
                $version = [System.Version]"$($version.Major).$($version.Minor).0"
                $idx = $semVerStr.IndexOf('-')
                if ($idx -eq -1) {
                    $semVerStr = "$semVerStr.0"
                }
                else {
                    $semVerstr = $semVerstr.insert($idx, '.0')
                }
            }
            else {
                throw "not semver"
            }
        }
        # Add properties to the object
        $obj | Add-Member -MemberType NoteProperty -Name "Prefix" -Value $prefix
        $obj | Add-Member -MemberType NoteProperty -Name "Major" -Value ([int]$version.Major)
        $obj | Add-Member -MemberType NoteProperty -Name "Minor" -Value ([int]$version.Minor)
        $obj | Add-Member -MemberType NoteProperty -Name "Patch" -Value ([int]$version.Build)
        0..4 | ForEach-Object {
            # default segments to 'zzz' for sorting of SemVer Objects to work as GitHub does
            $obj | Add-Member -MemberType NoteProperty -Name "Addt$_" -Value 'zzz'
        }
        $idx = $verStr.IndexOf('-')
        if ($idx -gt 0) {
            $segments = $verStr.SubString($idx+1).Split('.')
            if ($segments.Count -gt 5) {
                throw "max. 5 segments"
            }
            # Add all 5 segments to the object
            # If the segment is a number, it is converted to an integer
            # If the segment is a string, it cannot be -ge 'zzz' (would be sorted wrongly)
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
        # Check that the object can be converted back to the original string
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
            Write-Host "::Warning::Some of the release tags cannot be recognized as a semantic version string (https://semver.org). Using default GitHub sorting for releases, which will not work for release branches"
            $releases
        }
    }
    else {
        $releases
    }
}

function GetLatestRelease {
    Param(
        [string] $token,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository = $ENV:GITHUB_REPOSITORY,
        [string] $ref = $ENV:GITHUB_REFNAME
    )
    
    Write-Host "Getting the latest release from $api_url/repos/$repository/releases/latest - branch $ref"
    # Get all releases from GitHub, sorted by SemVer tag
    # If any release tag is not a valid SemVer tag, use default GitHub sorting and issue a warning
    # Default github sorting will return the latest historically created release as the latest release - not the highest version
    $releases = GetReleases -token $token -api_url $api_url -repository $repository

    # Get Latest release
    $latestRelease = $releases | Where-Object { -not ($_.prerelease -or $_.draft) } | Select-Object -First 1
    $releaseBranchPrefix = 'release/'
    if ($ref -like "$releaseBranchPrefix*") {
        # If release branch, get the latest release from that the release branch
        # This is given by the latest release with the same major.minor as the release branch
        $semVerObj = SemVerStrToSemVerObj -semVerStr $ref.SubString($releaseBranchPrefix.Length) -allowMajorMinorOnly
        $latestRelease = $releases | Where-Object {
            $releaseSemVerObj = SemVerStrToSemVerObj -semVerStr $_.tag_name
            $semVerObj.Major -eq $releaseSemVerObj.Major -and $semVerObj.Minor -eq $releaseSemVerObj.Minor
        } | Select-Object -First 1
    }
    $latestRelease
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
        $project = $_.Replace('\','_').Replace('/','_')
        Write-Host "project '$project'"
        
        $release.assets | Where-Object { $_.name -like "$project-*-$mask-*.zip" -or $_.name -like "$project-$mask-*.zip" } | ForEach-Object {
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
        [string] $token = ''
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
        Start-Sleep -seconds ($waitTime.TotalSeconds+1)
    }
}

# Get Content of UTF8 encoded file as a string with LF line endings
# No empty line at the end of the file
function Get-ContentLF {
    Param(
        [parameter(mandatory = $true, ValueFromPipeline = $false)]
        [string] $path
    )

    (Get-Content -Path $path -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n")
}

# Set-Content defaults to culture specific ANSI encoding, which is not what we want
# Set-Content defaults to environment specific line endings, which is not what we want
# This function forces UTF8 encoding and LF line endings
function Set-ContentLF {
    Param(
        [parameter(mandatory = $true, ValueFromPipeline = $false)]
        [string] $path,
        [parameter(mandatory = $true, ValueFromPipeline = $true)]
        $content
    )

    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
    if ($content -is [array]) {
        $content = $content -join "`n"
    }
    else {
        $content = "$content".Replace("`r", "")
    }
    [System.IO.File]::WriteAllText($path, "$content`n")
}

# Format Object to JSON and write to file with LF line endings and formatted as PowerShell 7 would do it
# PowerShell 5.1 formats JSON differently than PowerShell 7, so we need to use pwsh to format it
# PowerShell 5.1 format:
# {
#     "key":  "value"
# }
# PowerShell 7 format:
# {
#   "key": "value"
# }
function Set-JsonContentLF {
    Param(
        [parameter(mandatory = $true, ValueFromPipeline = $false)]
        [string] $path,
        [parameter(mandatory = $true, ValueFromPipeline = $true)]
        [object] $object
    )

    $object | ConvertTo-Json -Depth 99 | Set-ContentLF -path $path
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try {
            $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
            . pwsh (Join-Path $PSScriptRoot 'prettyfyjson.ps1') $path
        }
        catch {
            Write-Host "WARNING: pwsh (PowerShell 7) not installed, json will be formatted by PowerShell $($PSVersionTable.PSVersion)"
        }
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
        $artifactsJson = InvokeWebRequest -UseBasicParsing -Headers $headers -Uri $uri
        $artifacts = $artifactsJson | ConvertFrom-Json
        $page++
        $allArtifacts += @($artifacts.artifacts | Where-Object { $_.name -like "*-$branch-$mask-$version" })
        $result = @()
        $allArtifactsFound = $true
        $projects.Split(',') | ForEach-Object {
            $project = $_.Replace('\','_').Replace('/','_')
            Write-Host "project '$project'"
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
