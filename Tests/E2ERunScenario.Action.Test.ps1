Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "E2ERunScenario Action Tests" {
    BeforeAll {
        $actionName = "E2ERunScenario"
        $scriptRoot = Join-Path $PSScriptRoot "..\.github\actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        # The dispatcher dot-sources e2eTests/scenarios/<scenario>/runtest.ps1 relative to the
        # current directory. We stub that scenario script so that, instead of executing a real end
        # to end scenario, it captures the parameters it was called with. This lets us assert on
        # the exact parameters the dispatcher forwards to the scenario script.
        $script:workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:scenarioName = 'TestScenario'
        $scenarioRoot = Join-Path $script:workDir "e2eTests/scenarios/$($script:scenarioName)"
        New-Item -Path $scenarioRoot -ItemType Directory -Force | Out-Null

        $scenarioStub = @(
            'param('
            '    [switch] $github,'
            '    [switch] $linux,'
            '    [string] $githubOwner,'
            '    [string] $repoName,'
            '    [string] $e2eAppId,'
            '    [string] $e2eAppKey,'
            '    [string] $algoauthapp,'
            '    [string] $pteTemplate,'
            '    [string] $appSourceTemplate,'
            '    [string] $adminCenterApiCredentials,'
            '    [string] $azureCredentials,'
            '    [string] $githubPackagesToken'
            ')'
            '$captured = @{}'
            'foreach ($key in $PSBoundParameters.Keys) { $captured[$key] = [string]$PSBoundParameters[$key] }'
            '$captured | ConvertTo-Json | Set-Content -Path $env:E2E_CAPTURE_FILE -Encoding UTF8'
        )
        $scenarioStub -join "`n" | Set-Content -Path (Join-Path $scenarioRoot 'runtest.ps1') -Encoding UTF8

        # Minimal set of mandatory parameters required by the dispatcher.
        $script:baseParams = @{
            scenario                  = $script:scenarioName
            githubOwner               = 'testowner'
            repoName                  = 'testrepo'
            e2eAppId                  = 'testappid'
            e2eAppKey                 = 'testappkey'
            algoAuthApp               = 'testalgoauthapp'
            pteTemplate               = 'testptetemplate'
            appSourceTemplate         = 'testappsourcetemplate'
            adminCenterApiCredentials = 'testadmincreds'
            azureCredentials          = 'testazurecreds'
            githubPackagesToken       = 'testpackagestoken'
        }

        function Invoke-Dispatcher {
            param([hashtable] $Parameters)
            $script:captureFile = Join-Path $script:workDir ("capture_" + [guid]::NewGuid().ToString("N") + ".json")
            $previousCapture = $env:E2E_CAPTURE_FILE
            try {
                $env:E2E_CAPTURE_FILE = $script:captureFile
                Push-Location $script:workDir
                try {
                    E2ERunScenario @Parameters
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

    It 'Runs the scenario runtest.ps1 and forwards the expected parameters' {
        $captured = Invoke-Dispatcher -Parameters $script:baseParams.Clone()

        $captured.github | Should -Be 'True'
        $captured.githubOwner | Should -Be 'testowner'
        $captured.repoName | Should -Be 'testrepo'
        $captured.e2eAppId | Should -Be 'testappid'
        $captured.e2eAppKey | Should -Be 'testappkey'
        # $algoAuthApp is forwarded as the lower-cased 'algoauthapp' parameter
        $captured.algoauthapp | Should -Be 'testalgoauthapp'
        $captured.pteTemplate | Should -Be 'testptetemplate'
        $captured.appSourceTemplate | Should -Be 'testappsourcetemplate'
        $captured.adminCenterApiCredentials | Should -Be 'testadmincreds'
        $captured.azureCredentials | Should -Be 'testazurecreds'
        $captured.githubPackagesToken | Should -Be 'testpackagestoken'
    }

    It 'Only forwards the linux switch when linux is requested' {
        $withLinux = $script:baseParams.Clone()
        $withLinux['linux'] = $true
        $capturedWithLinux = Invoke-Dispatcher -Parameters $withLinux
        ($capturedWithLinux.PSObject.Properties.Name -contains 'linux') | Should -BeTrue
        $capturedWithLinux.linux | Should -Be 'True'

        $withoutLinux = $script:baseParams.Clone()
        $withoutLinux['linux'] = $false
        $capturedWithoutLinux = Invoke-Dispatcher -Parameters $withoutLinux
        ($capturedWithoutLinux.PSObject.Properties.Name -contains 'linux') | Should -BeFalse
    }

    It 'Runs the runtest.ps1 of the requested scenario' {
        # A second scenario stub writes a marker so we can prove the dispatcher resolved the path
        # from the -scenario parameter rather than a hard-coded scenario name.
        $otherScenario = 'OtherScenario'
        $otherRoot = Join-Path $script:workDir "e2eTests/scenarios/$otherScenario"
        New-Item -Path $otherRoot -ItemType Directory -Force | Out-Null
        @(
            'param([switch] $github, [switch] $linux, [string] $githubOwner, [string] $repoName, [string] $e2eAppId, [string] $e2eAppKey, [string] $algoauthapp, [string] $pteTemplate, [string] $appSourceTemplate, [string] $adminCenterApiCredentials, [string] $azureCredentials, [string] $githubPackagesToken)'
            '@{ scenario = ''OtherScenario'' } | ConvertTo-Json | Set-Content -Path $env:E2E_CAPTURE_FILE -Encoding UTF8'
        ) -join "`n" | Set-Content -Path (Join-Path $otherRoot 'runtest.ps1') -Encoding UTF8

        $params = $script:baseParams.Clone()
        $params['scenario'] = $otherScenario
        $captured = Invoke-Dispatcher -Parameters $params
        $captured.scenario | Should -Be 'OtherScenario'
    }
}
