Param(
    [Parameter(HelpMessage = "Project folder", Mandatory = $false)]
    [string] $project = ""
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
Import-Module (Join-Path $PSScriptRoot '..\TelemetryHelper.psm1' -Resolve)
DownloadAndImportBcContainerHelper

if ($project -eq ".") { $project = "" }
$baseFolder = $ENV:GITHUB_WORKSPACE
$projectPath = Join-Path $baseFolder $project

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
$settings = AnalyzeRepo -settings $settings -baseFolder $baseFolder -project $project -doNotCheckArtifactSetting

$containerName = $env:containerName
if (-not $containerName) {
    throw "containerName environment variable is not set. Ensure SetupBuildEnvironment ran successfully."
}

$credential = New-Object pscredential 'admin', (ConvertTo-SecureString -String $env:containerPassword -AsPlainText -Force)
$tenant = "default"

$buildArtifactFolder = Join-Path $projectPath ".buildartifacts"
$testResultsFile = Join-Path $projectPath "TestResults.xml"
$bcptTestResultsFile = Join-Path $projectPath "bcptTestResults.json"

# Clean up previous test results
$allTestResults = Join-Path $projectPath "testresults*.xml"
if (Test-Path $allTestResults) {
    Remove-Item $allTestResults -Force
}

# Check for ImportTestData script override
$scriptOverrides = Get-ScriptOverrides -ALGoFolderName $ALGoFolderName -OverrideScriptNames @("ImportTestDataInBcContainer")

# Import test data if config packages are configured
$importTestData = $scriptOverrides.ContainsKey('ImportTestDataInBcContainer')
if (-not $importTestData) {
    if (($settings.configPackages) -or ($settings.Keys | Where-Object { $_ -like 'configPackages.*' })) {
        $importTestData = $true
    }
}

if ($importTestData) {
    OutputGroupStart -Message "Importing test data"

    if ($scriptOverrides.ContainsKey('ImportTestDataInBcContainer')) {
        $importScriptBlock = $scriptOverrides['ImportTestDataInBcContainer']
    }
    else {
        $importScriptBlock = {
            Param([Hashtable]$parameters)
            $country = Get-BcContainerCountry -containerOrImageName $parameters.containerName
            $prop = "configPackages.$country"
            if ($settings.Keys -notcontains $prop) {
                $prop = "configPackages"
            }
            if ($settings."$prop") {
                Write-Host "Importing config packages from $prop"
                $settings."$prop" | ForEach-Object {
                    $configPackage = $_.Split(',')[0].Replace('{COUNTRY}',$country)
                    $packageId = $_.Split(',')[1]
                    UploadImportAndApply-ConfigPackageInBcContainer `
                        -containerName $parameters.containerName `
                        -companyName $settings.companyName `
                        -Credential $parameters.credential `
                        -Tenant $parameters.tenant `
                        -ConfigPackage $configPackage `
                        -PackageId $packageId
                }
            }
        }
    }

    if (-not $settings.enableTaskScheduler) {
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
            Write-Host "Enabling Task Scheduler to load configuration packages"
            Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "EnableTaskScheduler" -KeyValue "True" -WarningAction SilentlyContinue
            Set-NAVServerInstance -ServerInstance $ServerInstance -Restart
            while (Get-NavTenant $serverInstance | Where-Object { $_.State -eq "Mounting" }) {
                Start-Sleep -Seconds 1
            }
        }
    }

    Invoke-Command -ScriptBlock $importScriptBlock -ArgumentList @{
        "containerName" = $containerName
        "tenant"        = $tenant
        "credential"    = $credential
    }

    if (-not $settings.enableTaskScheduler) {
        Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {
            Write-Host "Disabling Task Scheduler again"
            Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "EnableTaskScheduler" -KeyValue "False" -WarningAction SilentlyContinue
            Set-NAVServerInstance -ServerInstance $ServerInstance -Restart
            while (Get-NavTenant $serverInstance | Where-Object { $_.State -eq "Mounting" }) {
                Start-Sleep -Seconds 1
            }
        }
    }
    OutputGroupEnd
}

# Backup databases if restoreDatabases is configured
if ($settings.restoreDatabases) {
    OutputGroupStart -Message "Backing up databases"
    Backup-BcContainerDatabases -containerName $containerName
    OutputGroupEnd
}

$allPassed = $true

# Run unit tests
if (-not $settings.doNotRunTests) {
    $testFolders = $settings.testFolders
    if ($testFolders) {
        OutputGroupStart -Message "Running tests"

        $testFolders | ForEach-Object {
            $testFolder = Join-Path $projectPath $_
            $appJson = [System.IO.File]::ReadAllLines((Join-Path $testFolder "app.json")) | ConvertFrom-Json
            $testAppId = $appJson.Id

            Write-Host "Running tests for $($appJson.Name) ($testAppId)"

            $disabledTests = @()
            Get-ChildItem -Path $testFolder -Filter "disabledTests.json" -Recurse | ForEach-Object {
                $disabledTestsStr = Get-Content $_.FullName -Raw -Encoding utf8
                Write-Host "Disabled Tests:`n$disabledTestsStr"
                $disabledTests += ($disabledTestsStr | ConvertFrom-Json)
            }

            if ($settings.restoreDatabases -contains 'BeforeEachTestApp') {
                Write-Host "Restoring databases before test app"
                Restore-DatabasesInBcContainer -containerName $containerName
            }

            $testParams = @{
                "containerName"         = $containerName
                "tenant"                = $tenant
                "credential"            = $credential
                "companyName"           = $settings.companyName
                "extensionId"           = $testAppId
                "disabledTests"         = $disabledTests
                "AzureDevOps"           = "no"
                "GitHubActions"         = "$(if($settings.treatTestFailuresAsWarnings){'warning'}else{'error'})"
                "detailed"              = $true
                "returnTrueIfAllPassed" = $true
                "JUnitResultFileName"   = $testResultsFile
                "AppendToJUnitResultFile" = $true
            }

            if (-not (Run-TestsInBcContainer @testParams)) {
                $allPassed = $false
            }
        }
        OutputGroupEnd
    }
}

# Run BCPT tests
if (-not $settings.doNotRunBcptTests -and $settings.bcptTestFolders) {
    OutputGroupStart -Message "Running BCPT tests"

    if ($settings.restoreDatabases -contains 'BeforeBcpTests') {
        Write-Host "Restoring databases before BCPT tests"
        Restore-DatabasesInBcContainer -containerName $containerName
    }

    $settings.bcptTestFolders | ForEach-Object {
        $bcptTestFolder = Join-Path $projectPath $_
        $bcptSuiteFile = Join-Path $bcptTestFolder "bcptSuite.json"
        if (Test-Path $bcptSuiteFile) {
            if ($settings.restoreDatabases -contains 'BeforeEachBcptTestApp') {
                Write-Host "Restoring databases before each BCPT test app"
                Restore-DatabasesInBcContainer -containerName $containerName
            }

            $bcptParams = @{
                "containerName"  = $containerName
                "tenant"         = $tenant
                "credential"     = $credential
                "companyName"    = $settings.companyName
                "connectFromHost" = $true
                "BCPTsuite"      = [System.IO.File]::ReadAllLines($bcptSuiteFile) | ConvertFrom-Json
            }
            $result = Run-BCPTTestsInBcContainer @bcptParams
            $result | ConvertTo-Json -Depth 99 | Set-Content $bcptTestResultsFile
        }
    }
    OutputGroupEnd
}

# Copy test results to build artifacts folder
if (Test-Path $testResultsFile) {
    Copy-Item -Path $testResultsFile -Destination $buildArtifactFolder -Force
}
if (Test-Path $bcptTestResultsFile) {
    Copy-Item -Path $bcptTestResultsFile -Destination $buildArtifactFolder -Force
}

# Fail if tests did not pass and not treating as warnings
if (-not $allPassed -and -not $settings.treatTestFailuresAsWarnings) {
    throw "There are test failures!"
}
