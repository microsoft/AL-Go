Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "E2ERunTest Action Tests" {
    BeforeAll {
        $actionName = "E2ERunTest"
        $scriptRoot = Join-Path $PSScriptRoot "..\.github\actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        # The dispatcher dot-sources e2eTests/Test-AL-Go.ps1 and e2eTests/Test-AL-Go-Upgrade.ps1
        # relative to the current directory. We stub both scripts so that, instead of executing a
        # real end to end test, they capture the parameters they were called with. This lets us
        # assert on the exact parameters the dispatcher forwards to each target script.
        $script:workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $stubRoot = Join-Path $script:workDir 'e2eTests'
        New-Item -Path $stubRoot -ItemType Directory -Force | Out-Null

        $captureLines = @(
            '$captured = @{ ''__target'' = ''__TARGET__'' }'
            'foreach ($key in $PSBoundParameters.Keys) { $captured[$key] = [string]$PSBoundParameters[$key] }'
            '$captured | ConvertTo-Json | Set-Content -Path $env:E2E_CAPTURE_FILE -Encoding UTF8'
        )

        $testStub = @(
            'param('
            '    [switch] $github,'
            '    [string] $githubOwner,'
            '    [string] $repoName,'
            '    [string] $e2eAppId,'
            '    [string] $e2eAppKey,'
            '    [string] $algoauthapp,'
            '    [string] $template,'
            '    [string] $adminCenterApiCredentials,'
            '    [switch] $multiProject,'
            '    [switch] $appSourceApp,'
            '    [switch] $linux,'
            '    [switch] $useCompilerFolder,'
            '    [switch] $private'
            ')'
        ) + ($captureLines -replace '__TARGET__', 'test')
        $testStub -join "`n" | Set-Content -Path (Join-Path $stubRoot 'Test-AL-Go.ps1') -Encoding UTF8

        $upgradeStub = @(
            'param('
            '    [switch] $github,'
            '    [string] $githubOwner,'
            '    [string] $repoName,'
            '    [string] $e2eAppId,'
            '    [string] $e2eAppKey,'
            '    [string] $algoauthapp,'
            '    [string] $template,'
            '    [switch] $appSourceApp,'
            '    [string] $release,'
            '    [string] $contentPath,'
            '    [switch] $private'
            ')'
        ) + ($captureLines -replace '__TARGET__', 'upgrade')
        $upgradeStub -join "`n" | Set-Content -Path (Join-Path $stubRoot 'Test-AL-Go-Upgrade.ps1') -Encoding UTF8

        # Minimal set of mandatory parameters required by the dispatcher.
        $script:baseParams = @{
            githubOwner = 'testowner'
            repoName    = 'testrepo'
            e2eAppId    = 'testappid'
            e2eAppKey   = 'testappkey'
            algoAuthApp = 'testalgoauthapp'
            template    = 'testtemplate'
        }

        function Invoke-Dispatcher {
            param([hashtable] $Parameters)
            $script:captureFile = Join-Path $script:workDir ("capture_" + [guid]::NewGuid().ToString("N") + ".json")
            $previousCapture = $env:E2E_CAPTURE_FILE
            try {
                $env:E2E_CAPTURE_FILE = $script:captureFile
                Push-Location $script:workDir
                try {
                    E2ERunTest @Parameters
                }
                finally {
                    Pop-Location
                }
            }
            finally {
                $env:E2E_CAPTURE_FILE = $previousCapture
            }
            return (Get-Content -Path $script:captureFile -Raw | ConvertFrom-Json)
        }
    }

    BeforeEach {
        # (Re)define the action as a function so it can be called directly.
        Invoke-Expression $actionScript
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    Context 'test branch' {
        It 'Routes to Test-AL-Go.ps1 and forwards the expected parameters' {
            $params = $script:baseParams.Clone()
            $params['testType'] = 'test'
            $params['adminCenterApiCredentials'] = 'testadmincreds'
            $params['multiProject'] = $true
            $params['appSource'] = $true
            $params['linux'] = $true
            $params['useCompilerFolder'] = $true

            $captured = Invoke-Dispatcher -Parameters $params

            $captured.__target | Should -Be 'test'
            $captured.github | Should -Be 'True'
            $captured.githubOwner | Should -Be 'testowner'
            $captured.repoName | Should -Be 'testrepo'
            $captured.e2eAppId | Should -Be 'testappid'
            $captured.e2eAppKey | Should -Be 'testappkey'
            # $algoAuthApp is forwarded as the lower-cased 'algoauthapp' parameter
            $captured.algoauthapp | Should -Be 'testalgoauthapp'
            $captured.template | Should -Be 'testtemplate'
            $captured.adminCenterApiCredentials | Should -Be 'testadmincreds'
            $captured.multiProject | Should -Be 'True'
            $captured.linux | Should -Be 'True'
            $captured.useCompilerFolder | Should -Be 'True'
            # $appSource is forwarded as the target's 'appSourceApp' parameter
            $captured.appSourceApp | Should -Be 'True'
        }

        It 'Defaults to the test branch when no testType is supplied' {
            $captured = Invoke-Dispatcher -Parameters $script:baseParams.Clone()
            $captured.__target | Should -Be 'test'
        }

        It 'Only forwards the private switch when private is requested' {
            $withPrivate = $script:baseParams.Clone()
            $withPrivate['private'] = $true
            $capturedWithPrivate = Invoke-Dispatcher -Parameters $withPrivate
            ($capturedWithPrivate.PSObject.Properties.Name -contains 'private') | Should -BeTrue
            $capturedWithPrivate.private | Should -Be 'True'

            $withoutPrivate = $script:baseParams.Clone()
            $withoutPrivate['private'] = $false
            $capturedWithoutPrivate = Invoke-Dispatcher -Parameters $withoutPrivate
            ($capturedWithoutPrivate.PSObject.Properties.Name -contains 'private') | Should -BeFalse
        }

        It 'Does not forward upgrade-only parameters' {
            $captured = Invoke-Dispatcher -Parameters $script:baseParams.Clone()
            ($captured.PSObject.Properties.Name -contains 'release') | Should -BeFalse
            ($captured.PSObject.Properties.Name -contains 'contentPath') | Should -BeFalse
        }
    }

    Context 'upgrade branch' {
        It 'Routes to Test-AL-Go-Upgrade.ps1 and forwards the expected parameters' {
            $params = $script:baseParams.Clone()
            $params['testType'] = 'upgrade'
            $params['appSource'] = $true
            $params['release'] = 'v2.2'
            $params['contentPath'] = 'pte'

            $captured = Invoke-Dispatcher -Parameters $params

            $captured.__target | Should -Be 'upgrade'
            $captured.github | Should -Be 'True'
            $captured.githubOwner | Should -Be 'testowner'
            $captured.repoName | Should -Be 'testrepo'
            $captured.e2eAppId | Should -Be 'testappid'
            $captured.e2eAppKey | Should -Be 'testappkey'
            $captured.algoauthapp | Should -Be 'testalgoauthapp'
            $captured.template | Should -Be 'testtemplate'
            $captured.release | Should -Be 'v2.2'
            $captured.contentPath | Should -Be 'pte'
            $captured.appSourceApp | Should -Be 'True'
        }

        It 'Does not forward test-only parameters' {
            $params = $script:baseParams.Clone()
            $params['testType'] = 'upgrade'
            $captured = Invoke-Dispatcher -Parameters $params
            ($captured.PSObject.Properties.Name -contains 'multiProject') | Should -BeFalse
            ($captured.PSObject.Properties.Name -contains 'linux') | Should -BeFalse
            ($captured.PSObject.Properties.Name -contains 'useCompilerFolder') | Should -BeFalse
        }

        It 'Only forwards the private switch when private is requested' {
            $params = $script:baseParams.Clone()
            $params['testType'] = 'upgrade'
            $params['private'] = $true
            $captured = Invoke-Dispatcher -Parameters $params
            $captured.private | Should -Be 'True'
        }
    }
}
