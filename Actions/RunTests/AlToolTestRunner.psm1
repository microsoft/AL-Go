<#
.SYNOPSIS
    Executes tests with AlTool and produces JUnit XML compatible with AL-Go AnalyzeTests.

.DESCRIPTION
    This is the default RunTests executor when no RunTestsInBcContainer override is supplied.
    BcContainerHelper provides app metadata, container configuration, company discovery, and test
    enumeration; AlTool executes each codeunit in a separate session. Methods without a result are
    retried once, and the final outcomes are written as JUnit.
#>

$ErrorActionPreference = "Stop"

$script:AlToolPackageId = "Microsoft.Dynamics.BusinessCentral.Development.Tools"

<#
.SYNOPSIS
    Invokes a native executable and returns normalized output with its exit code.
.DESCRIPTION
    Captures native stderr without terminating under Windows PowerShell 5 and restores the caller's
    error preference after invocation. Command resolution and invocation failures remain terminating.
.PARAMETER FilePath
    The native executable name or path.
.PARAMETER ArgumentList
    Arguments passed to the native executable.
.OUTPUTS
    [pscustomobject] with string-array Output and integer ExitCode properties.
#>
function Invoke-AlNativeCommand {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [string[]] $ArgumentList = @()
    )

    $nativeCommand = Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop
    $errorBeforeInvocation = if ($Error.Count -gt 0) { $Error[0] } else { $null }
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $nativeCommand.Source @ArgumentList 2>&1
        [int] $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $originalErrorActionPreference
    }

    $invocationErrors = @()
    foreach ($errorRecord in $Error) {
        if ($null -ne $errorBeforeInvocation -and [object]::ReferenceEquals($errorRecord, $errorBeforeInvocation)) {
            break
        }
        if ($errorRecord.FullyQualifiedErrorId -notin @("NativeCommandError", "NativeCommandErrorMessage")) {
            $invocationErrors += $errorRecord
        }
    }
    if ($invocationErrors.Count -gt 0) {
        throw $invocationErrors[0]
    }

    [string[]] $outputLines = @($output | ForEach-Object { "$_" })
    return [PSCustomObject]@{
        Output   = $outputLines
        ExitCode = $exitCode
    }
}

<#
.SYNOPSIS
    Ensures the `al` CLI is available on PATH, installing the prerelease dotnet global tool.
.DESCRIPTION
    Installs the AL developer tools when unavailable. A named mutex prevents concurrent jobs from
    modifying the shared tool store at the same time.
.OUTPUTS
    [string] The resolved `al` version string.
#>
function Install-AlTool {
    param(
        [switch] $Force
    )

    $toolsPath = Join-Path $env:USERPROFILE ".dotnet\tools"
    if ($env:HOME -and -not $env:USERPROFILE) {
        $toolsPath = Join-Path $env:HOME ".dotnet/tools"
    }
    if (($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $toolsPath) {
        $env:PATH = "$env:PATH$([System.IO.Path]::PathSeparator)$toolsPath"
    }

    # Serialize install/update across processes with a named mutex and re-check availability after
    # acquiring it (another job may have just installed it).
    $mutex = New-Object System.Threading.Mutex($false, "Global\AL-Go-AlTool-Install")
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne([TimeSpan]::FromMinutes(10)) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }

        $alAvailable = $null -ne (Get-Command al -ErrorAction SilentlyContinue)

        if (-not $alAvailable) {
            Write-Host "Installing '$script:AlToolPackageId' (prerelease) as a dotnet global tool..."
            $installResult = Invoke-AlNativeCommand -FilePath "dotnet" -ArgumentList @(
                "tool", "install", $script:AlToolPackageId, "--global", "--prerelease"
            )
            $installResult.Output | ForEach-Object { Write-Host $_ }
            if ($installResult.ExitCode -ne 0) {
                # A concurrent job may have installed it first; treat as success if `al` now resolves,
                # otherwise fall back to an update.
                if ($null -eq (Get-Command al -ErrorAction SilentlyContinue)) {
                    $updateResult = Invoke-AlNativeCommand -FilePath "dotnet" -ArgumentList @(
                        "tool", "update", $script:AlToolPackageId, "--global", "--prerelease"
                    )
                    $updateResult.Output | ForEach-Object { Write-Host $_ }
                    if ($updateResult.ExitCode -ne 0) {
                        throw "Failed to install or update '$script:AlToolPackageId'. The fallback dotnet tool update exited with code $($updateResult.ExitCode). Output: $($updateResult.Output -join [Environment]::NewLine)"
                    }
                }
            }
        }
        elseif ($Force) {
            # Explicit opt-in moves to the newest prerelease once, under the mutex.
            try {
                $updateResult = Invoke-AlNativeCommand -FilePath "dotnet" -ArgumentList @(
                    "tool", "update", $script:AlToolPackageId, "--global", "--prerelease"
                )
                $updateResult.Output | ForEach-Object { Write-Host $_ }
                if ($updateResult.ExitCode -ne 0) {
                    Write-Host "WARNING: 'al' update check exited with code $($updateResult.ExitCode). Using existing version."
                }
            }
            catch {
                Write-Host "WARNING: 'al' update check failed ($($_.Exception.Message)). Using existing version."
            }
        }
    }
    finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }

    if (-not (Get-Command al -ErrorAction SilentlyContinue)) {
        throw "The 'al' CLI is not available after installation. Ensure '$toolsPath' is on PATH and that the runner can reach nuget.org."
    }

    $versionResult = Invoke-AlNativeCommand -FilePath "al" -ArgumentList @("--version")
    if ($versionResult.ExitCode -ne 0) {
        throw "Failed to run 'al --version'. The command exited with code $($versionResult.ExitCode). Output: $($versionResult.Output -join [Environment]::NewLine)"
    }
    if ($versionResult.Output.Count -eq 0) {
        throw "Failed to run 'al --version'. The command returned no output."
    }
    $version = $versionResult.Output[0]
    Write-Host "Using al CLI version: $version"
    return "$version"
}

<#
.SYNOPSIS
    Resolves the on-prem connection settings (server URL, instance, dev-service port) for a container.
.DESCRIPTION
    Reads the container server configuration required by AlTool and falls back to conventional
    defaults when it is unavailable.
.PARAMETER ContainerName
    The name of the build container.
.OUTPUTS
    [hashtable] @{ Server; ServerInstance; Port }
#>
function Get-AlToolConnection {
    param(
        [Parameter(Mandatory = $true)][string] $ContainerName
    )

    $server = "http://$ContainerName"
    $instance = "BC"
    $port = 7049

    try {
        $config = Get-BcContainerServerConfiguration -ContainerName $ContainerName
        if ($config) {
            if ($config.ServerInstance) { $instance = "$($config.ServerInstance)" }
            if ($config.DeveloperServicesPort) { $port = [int]$config.DeveloperServicesPort }
        }
    }
    catch {
        Write-Host "WARNING: Could not read server configuration for '$ContainerName' ($($_.Exception.Message)). Falling back to $server/${instance}:$port."
    }

    return @{ Server = $server; ServerInstance = $instance; Port = $port }
}

<#
.SYNOPSIS
    Creates the temporary AL project used to connect AlTool to the container.
.PARAMETER ContainerName
    The name of the build container.
.PARAMETER Tenant
    The tenant to connect to.
.PARAMETER Connection
    The connection hashtable produced by Get-AlToolConnection.
.OUTPUTS
    [string] Path to the generated project folder.
#>
function New-AlToolProject {
    param(
        [Parameter(Mandatory = $true)][string] $ContainerName,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [Parameter(Mandatory = $true)][hashtable] $Connection
    )

    $projectRoot = Join-Path ([System.IO.Path]::GetTempPath()) "altool-project-$ContainerName"
    $vscodeDir = Join-Path $projectRoot ".vscode"
    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null

    $appJson = [ordered]@{
        id        = [System.Guid]::NewGuid().ToString()
        name      = "AlToolTestDriver"
        publisher = "AL-Go"
        version   = "1.0.0.0"
        platform  = "1.0.0.0"
        runtime   = "15.0"
    }
    $appJson | ConvertTo-Json | Set-Content -Path (Join-Path $projectRoot "app.json") -Encoding UTF8

    $launch = [ordered]@{
        version        = "0.2.0"
        configurations = @(
            [ordered]@{
                name              = "altool"
                type              = "al"
                request           = "launch"
                server            = $Connection.Server
                serverInstance    = $Connection.ServerInstance
                port              = $Connection.Port
                tenant            = $Tenant
                authentication    = "UserPassword"
                environmentType   = "OnPrem"
                startupObjectId   = 22
                startupObjectType = "Page"
                schemaUpdateMode  = "Synchronize"
            }
        )
    }
    $launch | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $vscodeDir "launch.json") -Encoding UTF8

    return $projectRoot
}

<#
.SYNOPSIS
    Resolves the company `al runtests` should target.
.DESCRIPTION
    Uses an explicitly requested company or selects a container company, preferring an evaluation
    company.
.PARAMETER ContainerName
    The name of the build container.
.PARAMETER Tenant
    The tenant to connect to.
.PARAMETER CompanyName
    The company name requested by the caller (optional).
.OUTPUTS
    [string] Company name, or empty string if none could be resolved.
#>
function Get-AlToolCompany {
    param(
        [Parameter(Mandatory = $true)][string] $ContainerName,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [string] $CompanyName = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($CompanyName)) {
        return $CompanyName
    }

    try {
        $companies = @(Get-CompanyInBcContainer -containerName $ContainerName -tenant $Tenant)
        if ($companies.Count -gt 0) {
            $preferred = $companies | Where-Object { $_.evaluationCompany -eq $true } | Select-Object -First 1
            $company = if ($preferred) { $preferred.companyName } else { $companies[0].companyName }
            return "$company"
        }
    }
    catch {
        Write-Host "WARNING: Could not enumerate companies for '$ContainerName' ($($_.Exception.Message))."
    }
    return ""
}

<#
.SYNOPSIS
    Builds case-insensitive disabled-method and disabled-codeunit lookups.
.DESCRIPTION
    A `*` method disables the complete codeunit instead of a method named `*`.
.PARAMETER DisabledTests
    Array of disabled-test entries.
.OUTPUTS
    [hashtable] @{ Methods = <set of "<codeunitname>::<method>">; Codeunits = <set of "<codeunitname>"> }
#>
function Get-DisabledTestKeySet {
    param(
        [array] $DisabledTests = @()
    )

    $methodSet = @{}
    $codeunitSet = @{}
    foreach ($entry in $DisabledTests) {
        if (-not $entry) { continue }
        $cuName = "$($entry.codeunitName)".ToLowerInvariant()
        $methods = @()
        if ($entry.PSObject.Properties['method'] -and $entry.method) { $methods = @($entry.method) }
        foreach ($m in $methods) {
            if ("$m" -eq '*') {
                $codeunitSet[$cuName] = $true
            }
            else {
                $methodSet["$cuName::$("$m".ToLowerInvariant())"] = $true
            }
        }
    }
    return @{ Methods = $methodSet; Codeunits = $codeunitSet }
}

<#
.SYNOPSIS
    Enumerates enabled test methods for an app in the container.
.DESCRIPTION
    Removes configured disabled methods and codeunits before AlTool execution.
.PARAMETER Parameters
    Hashtable with containerName, tenant, credential, extensionId and optionally testType and
    disabledTests.
.OUTPUTS
    [object[]] Codeunit objects with .Id, .Name, .Tests (enabled method name array).
#>
function Get-AlToolTestCodeunits {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Parameters
    )

    $getTestsParams = @{
        containerName = $Parameters.containerName
        tenant        = if ($Parameters.ContainsKey("tenant") -and $Parameters.tenant) { $Parameters.tenant } else { "default" }
        credential    = $Parameters.credential
        extensionId   = $Parameters.extensionId
        ignoreGroups  = $true
    }
    if ($Parameters.ContainsKey("testType") -and $Parameters.testType) {
        $getTestsParams.testType = $Parameters.testType
    }

    $codeunits = @(Get-TestsFromBcContainer @getTestsParams)

    $disabledMethods = @{}
    $disabledCodeunits = @{}
    if ($Parameters.ContainsKey("disabledTests") -and $Parameters.disabledTests) {
        $lookup = Get-DisabledTestKeySet -DisabledTests @($Parameters.disabledTests)
        $disabledMethods = $lookup.Methods
        $disabledCodeunits = $lookup.Codeunits
    }

    $result = @()
    $disabledCount = 0
    foreach ($cu in $codeunits) {
        $cuNameLower = "$($cu.Name)".ToLowerInvariant()
        $methods = @($cu.Tests | ForEach-Object { "$_" })

        if ($disabledCodeunits.ContainsKey($cuNameLower)) {
            $disabledCount += $methods.Count
            continue
        }

        if ($disabledMethods.Count -gt 0) {
            $enabled = @($methods | Where-Object { -not $disabledMethods.ContainsKey("$cuNameLower::$("$_".ToLowerInvariant())") })
            $disabledCount += ($methods.Count - $enabled.Count)
            $methods = $enabled
        }
        if ($methods.Count -gt 0) {
            $result += [PSCustomObject]@{ Id = $cu.Id; Name = $cu.Name; Tests = $methods }
        }
    }

    if ($disabledCount -gt 0) {
        Write-Host "Excluded $disabledCount disabled test method(s) from altool enumeration."
    }
    return @($result)
}

<#
.SYNOPSIS
    Parses the `Results:` block of a single `al runtests` invocation into per-method outcomes.
.DESCRIPTION
    Drops the phantom `OnRun` trigger entry and the trailing empty-named aggregate entry. Captures
    the failure message (lines up to `AL Callstack:`) and callstack (following lines) for failures.
.PARAMETER OutputLines
    The lines of `al runtests --raw` output.
.OUTPUTS
    [hashtable] method name -> @{ Outcome (Pass/Fail/Skip); Ms; Message; Stacktrace }
#>
function ConvertFrom-AlRunTestsOutput {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]] $OutputLines
    )

    $results = @{}
    $resultLineRegex = '^\s*(PASS|FAIL|SKIP)\s+(.*?)\s*\((\d+)ms\)\s*$'

    $startIdx = -1
    for ($i = 0; $i -lt $OutputLines.Count; $i++) {
        if ($OutputLines[$i] -match '^\s*Results:\s*$') { $startIdx = $i + 1; break }
    }
    if ($startIdx -lt 0) { return $results }

    $i = $startIdx
    while ($i -lt $OutputLines.Count) {
        $line = $OutputLines[$i]
        $m = [regex]::Match($line, $resultLineRegex)
        if (-not $m.Success) { $i++; continue }

        $outcome = switch ($m.Groups[1].Value) { 'PASS' { 'Pass' } 'FAIL' { 'Fail' } 'SKIP' { 'Skip' } }
        $name = $m.Groups[2].Value.Trim()
        $ms = [int]$m.Groups[3].Value

        if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'OnRun') { $i++; continue }

        $message = ''
        $stackText = ''
        if ($outcome -eq 'Fail') {
            $msgLines = @()
            $stackLines = @()
            $inStack = $false
            $j = $i + 1
            while ($j -lt $OutputLines.Count) {
                $next = $OutputLines[$j]
                if ([regex]::IsMatch($next, $resultLineRegex)) { break }
                if ($next -match '^\s*AL Callstack:\s*$') { $inStack = $true; $j++; continue }
                if ($inStack) {
                    if ($next.Trim().Length -gt 0) { $stackLines += $next.Trim() }
                }
                else {
                    if ($next.Trim().Length -gt 0) { $msgLines += $next.Trim() }
                }
                $j++
            }
            $message = ($msgLines -join ' ').Trim()
            $stackText = ($stackLines -join ';')
            $i = $j
        }
        else {
            $i++
        }

        $results[$name] = @{ Outcome = $outcome; Ms = $ms; Message = $message; Stacktrace = $stackText }
    }

    return $results
}

<#
.SYNOPSIS
    Runs `al runtests` for one codeunit and returns the parsed per-method results plus raw output.
.PARAMETER CodeunitId
    The codeunit id to run.
.PARAMETER Methods
    The test method names to run.
.PARAMETER ProjectPath
    The throw-away AL project folder.
.PARAMETER Company
    The company to run against.
.PARAMETER Tenant
    The tenant to connect to.
.PARAMETER Connection
    The connection hashtable produced by Get-AlToolConnection.
.OUTPUTS
    [hashtable] @{ Results (method->outcome map); ElapsedSec; Raw; Connected (bool); ExitCode (int) }
#>
function Invoke-AlRunTestsForCodeunit {
    param(
        [Parameter(Mandatory = $true)][string] $CodeunitId,
        [Parameter(Mandatory = $true)][string[]] $Methods,
        [Parameter(Mandatory = $true)][string] $ProjectPath,
        [Parameter(Mandatory = $true)][string] $Company,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [Parameter(Mandatory = $true)][hashtable] $Connection
    )

    # Use textual output because ConvertFrom-AlRunTestsOutput parses the Results block.
    $alArgs = @(
        'runtests', $CodeunitId,
        '--project', $ProjectPath,
        '--company', $Company,
        '--server', $Connection.Server,
        '--serverinstance', $Connection.ServerInstance,
        '--port', "$($Connection.Port)",
        '--environmenttype', 'OnPrem',
        '--authentication', 'UserPassword',
        '--tenant', $Tenant,
        '--raw',
        '--testmethods'
    ) + $Methods

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $nativeResult = Invoke-AlNativeCommand -FilePath "al" -ArgumentList $alArgs
    }
    finally {
        $sw.Stop()
    }

    $lines = @($nativeResult.Output)
    $connected = ($lines | Where-Object { $_ -match 'Test run completed:' }).Count -gt 0
    $parsed = ConvertFrom-AlRunTestsOutput -OutputLines $lines

    if ($connected -and $parsed.Count -eq 0 -and $Methods.Count -gt 0) {
        Write-Host "::warning::al runtests connected for codeunit $CodeunitId but produced no parseable results. Raw output follows (possible output-format change):"
        Write-Host ($lines -join "`n")
    }

    return @{
        Results    = $parsed
        ElapsedSec = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
        Raw        = ($lines -join "`n")
        Connected  = $connected
        ExitCode   = [int] $nativeResult.ExitCode
    }
}

<#
.SYNOPSIS
    Appends an AL-Go AnalyzeTests-compatible JUnit <testsuite> for one codeunit to the given
    <testsuites> document.
.PARAMETER Doc
    The JUnit XmlDocument being built.
.PARAMETER TestSuitesNode
    The root <testsuites> element to append to.
.PARAMETER Codeunit
    The codeunit object (.Id, .Name).
.PARAMETER RequestedMethods
    The method names that were requested for this codeunit.
.PARAMETER MethodResults
    The parsed per-method result map for this codeunit.
.PARAMETER ExtensionId
    The extension (app) id.
.PARAMETER AppName
    The app name.
.PARAMETER Hostname
    The runner host name.
.PARAMETER ElapsedSec
    The elapsed time (seconds) attributed to this codeunit.
.OUTPUTS
    [int] Number of failing methods in this codeunit.
#>
function Add-JUnitTestSuite {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument] $Doc,
        [Parameter(Mandatory = $true)][System.Xml.XmlElement] $TestSuitesNode,
        [Parameter(Mandatory = $true)] $Codeunit,
        [Parameter(Mandatory = $true)][string[]] $RequestedMethods,
        [Parameter(Mandatory = $true)][hashtable] $MethodResults,
        [Parameter(Mandatory = $true)][string] $ExtensionId,
        [Parameter(Mandatory = $true)][string] $AppName,
        [Parameter(Mandatory = $true)][string] $Hostname,
        [Parameter(Mandatory = $true)][double] $ElapsedSec
    )

    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    $suiteName = "$($Codeunit.Id) $($Codeunit.Name)"

    $suite = $Doc.CreateElement("testsuite")
    $suite.SetAttribute("name", $suiteName)
    $suite.SetAttribute("timestamp", (Get-Date -Format s))
    $suite.SetAttribute("hostname", $Hostname)

    $props = $Doc.CreateElement("properties")
    $suite.AppendChild($props) | Out-Null
    $extProp = $Doc.CreateElement("property")
    $extProp.SetAttribute("name", "extensionid")
    $extProp.SetAttribute("value", $ExtensionId)
    $props.AppendChild($extProp) | Out-Null
    if ($AppName) {
        $appProp = $Doc.CreateElement("property")
        $appProp.SetAttribute("name", "appName")
        $appProp.SetAttribute("value", $AppName)
        $props.AppendChild($appProp) | Out-Null
    }

    $failed = 0
    $skipped = 0
    foreach ($method in $RequestedMethods) {
        $res = $MethodResults[$method]

        $tc = $Doc.CreateElement("testcase")
        $tc.SetAttribute("classname", $suiteName)
        $tc.SetAttribute("name", $method)

        if ($null -eq $res) {
            # Missing results remain failures in the final JUnit output.
            $tc.SetAttribute("time", "0")
            $failure = $Doc.CreateElement("failure")
            $failure.SetAttribute("message", "No result produced by al runtests")
            $failure.InnerText = ""
            $tc.AppendChild($failure) | Out-Null
            $failed++
        }
        else {
            $tc.SetAttribute("time", ([Math]::Round($res.Ms / 1000.0, 3)).ToString($ci))
            switch ($res.Outcome) {
                'Fail' {
                    $failure = $Doc.CreateElement("failure")
                    $failure.SetAttribute("message", "$($res.Message)")
                    $failure.InnerText = "$($res.Stacktrace)".Replace(";", "`n")
                    $tc.AppendChild($failure) | Out-Null
                    $failed++
                }
                'Skip' {
                    $sk = $Doc.CreateElement("skipped")
                    $tc.AppendChild($sk) | Out-Null
                    $skipped++
                }
            }
        }
        $suite.AppendChild($tc) | Out-Null
    }

    $suite.SetAttribute("tests", "$($RequestedMethods.Count)")
    $suite.SetAttribute("errors", "0")
    $suite.SetAttribute("failures", "$failed")
    $suite.SetAttribute("skipped", "$skipped")
    $suite.SetAttribute("time", ([Math]::Round($ElapsedSec, 3)).ToString($ci))

    $TestSuitesNode.AppendChild($suite) | Out-Null
    return $failed
}

function Merge-MissingAlTestResults {
    param(
        [Parameter(Mandatory = $true)][hashtable] $PrimaryResults,
        [Parameter(Mandatory = $true)][hashtable] $RetryResults
    )

    foreach ($methodName in $RetryResults.Keys) {
        if (-not $PrimaryResults.ContainsKey($methodName)) {
            $PrimaryResults[$methodName] = $RetryResults[$methodName]
        }
    }
    return $PrimaryResults
}

<#
.SYNOPSIS
    Runs all of a single app's test codeunits through `al runtests` and writes a JUnit results file.
.DESCRIPTION
    Runs each codeunit in a separate session, retries methods without a result once, and appends
    JUnit output compatible with AL-Go AnalyzeTests.
.PARAMETER Parameters
    Test parameters containing containerName, credential, extensionId, and optional runner settings.
.OUTPUTS
    [bool] $true if all executed methods passed; $false otherwise.
#>
function Invoke-AlToolTestRun {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Parameters
    )

    Install-AlTool | Out-Null

    $containerName = $Parameters.containerName
    $tenant = if ($Parameters.ContainsKey("tenant") -and $Parameters.tenant) { "$($Parameters.tenant)" } else { "default" }
    $extensionId = "$($Parameters.extensionId)"
    $appName = if ($Parameters.ContainsKey("appName")) { "$($Parameters.appName)" } else { "" }
    $companyName = if ($Parameters.ContainsKey("companyName")) { "$($Parameters.companyName)" } else { "" }

    if ([string]::IsNullOrWhiteSpace($extensionId)) {
        throw "Invoke-AlToolTestRun requires 'extensionId' in parameters."
    }

    # Set credentials inside the guarded scope so they are always removed after the run.
    if ($Parameters.credential -isnot [System.Management.Automation.PSCredential]) {
        throw "Invoke-AlToolTestRun requires a PSCredential in parameters.credential."
    }

    try {
        $env:BC_SERVER_USERNAME = $Parameters.credential.UserName
        $env:BC_SERVER_PASSWORD = $Parameters.credential.GetNetworkCredential().Password

        $connection = Get-AlToolConnection -ContainerName $containerName
        $projectPath = New-AlToolProject -ContainerName $containerName -Tenant $tenant -Connection $connection
        $company = Get-AlToolCompany -ContainerName $containerName -Tenant $tenant -CompanyName $companyName
        if ([string]::IsNullOrWhiteSpace($company)) {
            throw "Could not resolve a company to run tests against in container '$containerName'."
        }

        Write-Host "altool run: app='$appName' extensionId=$extensionId company='$company' server='$($connection.Server)' instance='$($connection.ServerInstance)' port=$($connection.Port) tenant='$tenant'"

        $codeunits = @(Get-AlToolTestCodeunits -Parameters $Parameters)
        Write-Host "Enumerated $($codeunits.Count) test codeunit(s) for app '$appName'."
        if ($codeunits.Count -eq 0) {
            Write-Host "No test codeunits to run for app '$appName'; nothing to do."
            return $true
        }

        $hostname = [System.Net.Dns]::GetHostName()

        # Multiple test apps append to the same result file.
        $junitFile = if ($Parameters.ContainsKey("JUnitResultFileName")) { $Parameters.JUnitResultFileName } else { "" }
        $doc = New-Object System.Xml.XmlDocument
        $suites = $null
        if (-not [string]::IsNullOrWhiteSpace($junitFile) -and (Test-Path $junitFile)) {
            try {
                $doc.Load($junitFile)
                $suites = $doc.DocumentElement
                if (-not $suites -or $suites.LocalName -ne 'testsuites') { $suites = $null; $doc = New-Object System.Xml.XmlDocument }
            }
            catch {
                Write-Host "WARNING: Could not load existing JUnit file '$junitFile' ($($_.Exception.Message)); starting fresh."
                $doc = New-Object System.Xml.XmlDocument
                $suites = $null
            }
        }
        if (-not $suites) {
            $doc.AppendChild($doc.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
            $suites = $doc.CreateElement("testsuites")
            $doc.AppendChild($suites) | Out-Null
        }

        $allPassed = $true
        $merged = @{}
        $totalElapsed = 0.0

        # Run each codeunit in a fresh session.
        foreach ($cu in $codeunits) {
            $cid = "$($cu.Id)"
            $methods = @($cu.Tests | ForEach-Object { "$_" })
            $run = Invoke-AlRunTestsForCodeunit -CodeunitId $cid -Methods $methods `
                -ProjectPath $projectPath -Company $company -Tenant $tenant -Connection $connection
            $totalElapsed += [double]$run.ElapsedSec
            if (-not $run.Connected) {
                Write-Host "::warning::al runtests did not complete for codeunit $cid ('$($cu.Name)') in app '$appName'. Raw output:"
                Write-Host $run.Raw
            }
            $merged[$cid] = $run.Results
        }

        # Retry only unreported methods; existing outcomes are final.
        $isoGroups = @()
        foreach ($cu in $codeunits) {
            $cid = "$($cu.Id)"
            $requested = @($cu.Tests | ForEach-Object { "$_" })
            $cuResults = $merged[$cid]
            $retryMethods = @($requested | Where-Object {
                    (-not $cuResults) -or (-not $cuResults.ContainsKey($_))
                })
            if ($retryMethods.Count -gt 0) {
                $isoGroups += @{ Id = $cid; Methods = $retryMethods; Name = $cu.Name }
            }
        }
        if ($isoGroups.Count -gt 0) {
            Write-Host ("rerun pass: {0} codeunit(s) with unreported method(s) (each in its own session)" -f $isoGroups.Count)
            foreach ($g in $isoGroups) {
                $iso = Invoke-AlRunTestsForCodeunit -CodeunitId $g.Id -Methods $g.Methods `
                    -ProjectPath $projectPath -Company $company -Tenant $tenant -Connection $connection
                $totalElapsed += [double]$iso.ElapsedSec
                if (-not $merged.ContainsKey($g.Id)) { $merged[$g.Id] = @{} }
                Merge-MissingAlTestResults -PrimaryResults $merged[$g.Id] -RetryResults $iso.Results | Out-Null
            }
        }

        # Attribute the app duration across codeunits using method durations as weights.
        $cuMsShare = @{}
        $grandMs = 0.0
        foreach ($cu in $codeunits) {
            $cuResults = $merged["$($cu.Id)"]
            $ms = 0.0
            if ($cuResults) { foreach ($mName in $cuResults.Keys) { $ms += [double]$cuResults[$mName].Ms } }
            $cuMsShare["$($cu.Id)"] = $ms
            $grandMs += $ms
        }

        $idx = 0
        foreach ($cu in $codeunits) {
            $idx++
            $methods = @($cu.Tests | ForEach-Object { "$_" })
            $cuResults = $merged["$($cu.Id)"]
            if ($null -eq $cuResults) { $cuResults = @{} }

            if ($grandMs -gt 0) {
                $suiteSec = $totalElapsed * ($cuMsShare["$($cu.Id)"] / $grandMs)
            }
            elseif ($codeunits.Count -gt 0) {
                $suiteSec = $totalElapsed / $codeunits.Count
            }
            else {
                $suiteSec = 0.0
            }

            $failed = Add-JUnitTestSuite -Doc $doc -TestSuitesNode $suites -Codeunit $cu `
                -RequestedMethods $methods -MethodResults $cuResults -ExtensionId $extensionId `
                -AppName $appName -Hostname $hostname -ElapsedSec $suiteSec

            if ($failed -gt 0) { $allPassed = $false }

            Write-Host ("[{0}/{1}] cu {2} '{3}' -> {4} failed of {5} method(s)" -f `
                    $idx, $codeunits.Count, $cu.Id, $cu.Name, $failed, $methods.Count)
        }
        Write-Host ("Run for app '{0}': {1} codeunit(s) in {2}s real al wall-clock." -f `
                $appName, $codeunits.Count, [Math]::Round($totalElapsed, 2))

        if (-not [string]::IsNullOrWhiteSpace($junitFile)) {
            $dir = [System.IO.Path]::GetDirectoryName($junitFile)
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $doc.Save($junitFile)
            Write-Host "Wrote JUnit results for app '$appName' to $junitFile"
        }
        else {
            Write-Host "WARNING: No JUnitResultFileName in parameters; results not persisted for app '$appName'."
        }

        return $allPassed
    }
    finally {
        # Do not retain container credentials after the run.
        Remove-Item Env:\BC_SERVER_USERNAME -ErrorAction SilentlyContinue
        Remove-Item Env:\BC_SERVER_PASSWORD -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Install-AlTool, Get-AlToolConnection, New-AlToolProject, Get-AlToolCompany, `
    Get-DisabledTestKeySet, Get-AlToolTestCodeunits, ConvertFrom-AlRunTestsOutput, `
    Invoke-AlRunTestsForCodeunit, Add-JUnitTestSuite, Invoke-AlToolTestRun
