function GetExtendedErrorMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingEmptyCatchBlock", "", Justification="We want to ignore errors")]
    Param(
        $errorRecord
    )

    $exception = $errorRecord.Exception
    $message = $exception.Message

    try {
        $errorDetails = $errorRecord.ErrorDetails | ConvertFrom-Json
        $message += " $($errorDetails.error)`n$($errorDetails.error_description)"
    }
    catch {
        # ignore errors
    }
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
        }
        catch {
            # ignore errors
        }
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
        catch {
            # ignore errors
        }
    }
    catch{
        # ignore errors
    }
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
        try {
            $result = Invoke-WebRequest  @params -Uri $uri
        }
        catch [System.Net.WebException] {
            $response = $_.Exception.Response
            $responseUri = $response.ResponseUri.AbsoluteUri
            if ($response.StatusCode -eq 404 -and $responseUri -ne $uri) {
                Write-Host "::Warning::Repository ($uri) was renamed or moved, please update your references with the new name. Trying $responseUri, as suggested by GitHub."
                $result = Invoke-WebRequest @params -Uri $responseUri
            }
            else {
                throw
            }
        }
        $result
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
            catch {
                Write-Host "Retry failed as well"
            }
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

function GetDependencies {
    Param(
        $probingPathsJson,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $saveToPath = (Join-Path $ENV:GITHUB_WORKSPACE ".dependencies")
    )

    if (!(Test-Path $saveToPath)) {
        New-Item $saveToPath -ItemType Directory | Out-Null
    }

    $downloadedList = @()
    foreach($mask in 'Apps','TestApps') {
        foreach($dependency in $probingPathsJson) {
            $projects = $dependency.projects
            $buildMode = $dependency.buildMode

            # change the mask to include the build mode
            if($buildMode -ne "Default") {
                $mask = "$buildMode$mask"
            }

            Write-Host "Locating $mask artifacts for projects: $projects"

            if ($dependency.release_status -eq "thisBuild") {
                $missingProjects = @()
                foreach($project in $projects.Split(',')) {
                    $project = $project.Replace('\','_').Replace('/','_') # sanitize project name

                    $downloadName = Join-Path $saveToPath "thisbuild-$project-$($mask)"

                    if (Test-Path $downloadName -PathType Container) {
                        $folder = Get-Item $downloadName
                        Get-ChildItem -Path $folder | ForEach-Object {
                            if ($mask -like '*TestApps') {
                                $downloadedList += @("($($_.FullName))")
                            }
                            else {
                                $downloadedList += @($_.FullName)
                            }
                            Write-Host "$($_.FullName) found from previous job"
                        }
                    }
                    elseif ($mask -notlike '*TestApps') {
                        Write-Host "$project not built, downloading from artifacts"
                        $missingProjects += @($project)
                    }
                }
                if ($missingProjects) {
                    $dependency.release_status = 'latestBuild'
                    $dependency.branch = $dependency.baseBranch
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
                            if ($mask -like '*TestApps') {
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
                    if ($mask -like '*TestApps') {
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingEmptyCatchBlock", "", Justification="We want to ignore errors")]
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

    Process {
        $arguments = "$command "
        foreach($parameter in $remaining) {
            if ("$parameter".IndexOf(" ") -ge 0 -or "$parameter".IndexOf('"') -ge 0) {
                if ($parameter.length -gt 15000) {
                    $parameter = "$($parameter.Substring(0,15000))...`n`n**Truncated due to size limits!**"
                }
                $arguments += """$($parameter.Replace('"','\"'))"" "
            }
            else {
                $arguments += "$parameter "
            }
        }
        cmdDo -command gh -arguments $arguments -silent:$silent -returnValue:$returnValue -inputStr $inputStr
    }
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

    Process {
        $arguments = "$command "
        foreach($parameter in $remaining) {
            if ("$parameter".IndexOf(" ") -ge 0 -or "$parameter".IndexOf('"') -ge 0) {
                $arguments += """$($parameter.Replace('"','\"'))"" "
            }
            else {
                $arguments += "$parameter "
            }
        }
        cmdDo -command git -arguments $arguments -silent:$silent -returnValue:$returnValue -inputStr $inputStr
    }
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

    Process {
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

    Process {
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
        [string] $accept = "application/vnd.github+json",
        [string] $apiVersion = "2022-11-28"
    )
    $headers = @{
        "Accept" = $accept
        "X-GitHub-Api-Version" = $apiVersion
    }
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
        [string] $previous_tag_name,
        [string] $target_commitish
    )

    Write-Host "Generating release note $api_url/repos/$repository/releases/generate-notes"

    $postParams = @{
        tag_name = $tag_name;
    }

    if ($previous_tag_name) {
        $postParams["previous_tag_name"] = $previous_tag_name
    }
    if ($target_commitish) {
        $postParams["target_commitish"] = $target_commitish
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
        $token = invoke-gh -silent -returnValue auth token
    }
    $headers = GetHeader -token $token -accept "application/octet-stream"
    foreach($project in $projects.Split(',')) {
        $project = $project.Replace('\','_').Replace('/','_')
        Write-Host "project '$project'"
        $assetPattern1 = "$project-*-$mask-*.zip"
        $assetPattern2 = "$project-$mask-*.zip"
        Write-Host "AssetPatterns: '$assetPattern1' | '$assetPattern2'"
        $assets = @($release.assets | Where-Object { $_.name -like $assetPattern1 -or $_.name -like $assetPattern2 })
        foreach($asset in $assets) {
            $uri = "$api_url/repos/$repository/releases/assets/$($asset.id)"
            Write-Host $uri
            $filename = Join-Path $path $asset.name
            InvokeWebRequest -Headers $headers -Uri $uri -OutFile $filename
            $filename
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

    Process {
        (Get-Content -Path $path -Encoding UTF8 -Raw).Replace("`r", "").TrimEnd("`n")
    }
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

    Process {
        $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if ($content -is [array]) {
            $content = $content -join "`n"
        }
        else {
            $content = "$content".Replace("`r", "")
        }
        [System.IO.File]::WriteAllText($path, "$content`n")
    }
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

    Process {
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
}

<#
    Gets the last successful CICD run ID for the specified repository and branch.

    If no successful CICD run is found, 0 is returned.
#>

function FindLatestSuccessfulCICDRun {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $api_url,
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $branch
    )

    $headers = GetHeader -token $token
    $lastSuccessfulCICDRun = 0
    $per_page = 100
    $page = 1

    # Get the latest CICD workflow run
    while($true) {
        $runsURI = "$api_url/repos/$repository/actions/runs?per_page=$per_page&page=$page&exclude_pull_requests=true&status=success&branch=$branch"
        Write-Host "- $runsURI"
        $workflowRuns = InvokeWebRequest -Headers $headers -Uri $runsURI | ConvertFrom-Json

        if($workflowRuns.workflow_runs.Count -eq 0) {
            # No more workflow runs, breaking out of the loop
            break
        }

        $CICDRuns = @($workflowRuns.workflow_runs | Where-Object { $_.name -eq ' CI/CD' })

        if ($CICDRuns.Count -gt 0) {
            $lastSuccessfulCICDRun = $CICDRuns[0].id
            Write-Host "Found last successful CICD run: $($LastSuccessfulCICDRun)"
            break
        }

        $page += 1
    }

    return $lastSuccessfulCICDRun
}

<#
    Gets the CICD run ID for the specified repository and branch, that built the specified project, mask and version.

    If no successful CICD run is found, 0 is returned.
#>
function FindCICDRunForVersion {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $api_url,
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $branch,
        [Parameter(Mandatory = $true)]
        [string] $project,
        [Parameter(Mandatory = $true)]
        [string] $mask,
        [Parameter(Mandatory = $true)]
        [string] $version
    )

    $headers = GetHeader -token $token
    $CICDRun = 0
    $per_page = 100
    $page = 1

    # Construct the project artifact name
    $artifactPattern = "$project-$branch-$mask-$version"
    $escapedArtifactPattern = [Uri]::EscapeDataString($artifactPattern)

    while ($true) {
        $uri = "$api_url/repos/$repository/actions/artifacts?per_page=$($per_page)&page=$($page)&name=$escapedArtifactPattern"
        Write-Host "- $uri"
        $artifacts = InvokeWebRequest -Headers $headers -Uri $uri | ConvertFrom-Json

        # If no artifacts are read, we are done
        if ($artifacts.artifacts.Count -eq 0) {
            break
        }

        foreach($artifact in $artifacts.artifacts) {
            if($artifact.expired) {
                Write-Host "Artifact $($artifact.name) (ID: $($artifact.id)) expired on $($artifact.expired_at)"
                continue
            }

            Write-Host "Found artifact $($artifact.name) in workflow run $($artifact.workflow_run.id))"

            # Get the workflow run
            $runsURI = "$api_url/repos/$repository/actions/runs/$($artifact.workflow_run.id)"
            Write-Host "- $runsURI"
            $workflowRun = InvokeWebRequest -Headers $headers -Uri $runsURI | ConvertFrom-Json

            if($workflowRun.name -ne ' CI/CD') {
                Write-Host "Workflow run $($workflowRun.id) (name: $($workflowRun.name)) is not a CI/CD run"
                continue
            }

            if($workflowRun.status -ne "completed") {
                Write-Host "Workflow run $($workflowRun.id) (name: $($workflowRun.name)) is not completed"
                continue
            }

            if($workflowRun.conclusion -ne "success") {
                Write-Host "Workflow run $($workflowRun.id) (name: $($workflowRun.name)) did not succeed"
                continue
            }

            $CICDRun = $workflowRun.id
            break
        }

        if ($CICDRun -ne 0) {
            # CICD run was found, breaking out of the loop
            Write-Host "Found CICD run $CICDRun that built version $version"
            break
        }

        $page += 1
    }

    return $CICDRun
}

<#
    Gets the project artifacts for the specified repository, branch, mask and version.

    The project artifacts are returned as an array of artifact objects.

    If the version is 'latest', the artifacts from the last successful CICD run are returned.
    Otherwise, the artifacts from the CICD run that built the specified project, mask and version are returned.
#>
function GetArtifacts {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $token,
        [Parameter(Mandatory = $true)]
        [string] $api_url,
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $mask,
        [Parameter(Mandatory = $true)]
        [string] $branch,
        [Parameter(Mandatory = $true)]
        [string] $projects,
        [Parameter(Mandatory = $true)]
        [string] $version
    )

    $headers = GetHeader -token $token
    if ($version -eq 'latest') { $version = '*' }

    # Get sanitized project names (the way they appear in the artifact names)
    $projects = @(@($projects.Split(',')) | ForEach-Object { $_.Replace('\','_').Replace('/','_') })

    $CICDrun = 0

    if($version -eq '*') {
        # For latest version, use the artifacts from the last successful CICD run
        $CICDrun = FindLatestSuccessfulCICDRun -token $token -api_url $api_url -repository $repository -branch $branch
    } else {
        # For specific version, find the corresponding CICD run based on the first project
        $CICDrun = FindCICDRunForVersion -token $token -api_url $api_url -repository $repository -branch $branch -project $project[0] -mask $mask -version $version
    }

    if ($CICDrun -eq 0) {
        Write-Host "No successful CICD runs found for branch $branch and version $version in repository $repository"
        return
    }

    Write-Host "Using CICD run $CICDrun to get artifacts for mask $maks and projects: $($projects -join ', ')"

    $foundProjects = @()
    $foundArtifacts = @()
    $page = 1

    # Get the artifacts from the found successful CICD run
    while($true) {
        $artifactsURI = "$api_url/repos/$repository/actions/runs/$CICDrun/artifacts?per_page=$per_page&page=$page"

        $artifacts = InvokeWebRequest -Headers $headers -Uri $artifactsURI | ConvertFrom-Json

        if($artifacts.artifacts.Count -eq 0) {
            Write-Host "No more artifacts found for CICD run $CICDrun"
            break
        }

        foreach($project in $projects) {
            $artifactPattern = "$project-$branch-$mask-$version"
            $matchingArtifacts = @($artifacts.artifacts | Where-Object { $_.name -like $artifactPattern })

            if ($matchingArtifacts.Count -eq 0) {
                continue
            }

            if ($matchingArtifacts.Count -gt 1) {
                Write-Host "::Warning:: Found more than one matching artifact for pattern $artifactPattern. Taking the first one: $($matchingArtifacts[0].name)"
            }

            if($matchingArtifacts[0].expired) {
                Write-Host "Artifact $($matchingArtifacts[0].name) (ID: $($matchingArtifacts[0].id)) expired on $($matchingArtifacts[0].expired_at)"
                continue
            }

            $foundArtifacts += $matchingArtifacts[0]
            $foundProjects += $project
        }

        # Remove found projects from the list of projects to find
        $projects = $projects | Where-Object { $foundProjects -notcontains $_ }

        if ($projects.Count -eq 0) {
            Write-Host "Found all project artifacts in CICD run $CICDrun for mask $mask"
            break
        }

        $page += 1
    }

    if ($projects.Count -gt 0) {
        Write-Host "::Warning:: Could not find non-expired artifacts for mask $mask and projects: $($projects -join ', ')"
    }

    return $foundArtifacts
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
        $token = invoke-gh -silent -returnValue auth token
    }
    $headers = GetHeader -token $token
    $outFile = Join-Path $path "$($artifact.Name).zip"
    InvokeWebRequest -Headers $headers -Uri $artifact.archive_download_url -OutFile $outFile
    $outFile
}
