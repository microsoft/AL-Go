[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock parameters must match the authentication command')]
param()

Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force -DisableNameChecking
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'Authenticate action' {
    BeforeAll {
        $scriptRoot = Join-Path $PSScriptRoot '../Actions/Authenticate' -Resolve
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'authenticateScriptPath', Justification = 'Used in the action callback and tests')]
        $authenticateScriptPath = Join-Path $scriptRoot 'Authenticate.ps1'
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'wrapperPath', Justification = 'Used in the tests')]
        $wrapperPath = Join-Path $scriptRoot '../Invoke-AlGoAction.ps1' -Resolve
        $savedEnvironment = @{}
        foreach ($name in @('BcContainerHelperPath', 'Settings', 'GITHUB_WORKSPACE', 'GITHUB_OUTPUT', 'GITHUB_STEP_SUMMARY', 'RUNNER_TEMP')) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }

        function New-BcAuthContext {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stub for the mocked authentication command')]
            param([switch] $includeDeviceLogin, [TimeSpan] $deviceLoginTimeout)
            throw 'Authentication must be mocked'
        }
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'adminParameters', Justification = 'Splatted in the action callback and tests')]
        $adminParameters = @{ secretNames = 'adminCenterApiCredentials'; authType = 'AdminCenter' }
        $env:Settings = '{"adminCenterApiCredentialsSecretName":"CustomAdminCredentials"}'
        $env:GITHUB_WORKSPACE = $TestDrive
        $env:RUNNER_TEMP = $TestDrive
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'
        $env:GITHUB_STEP_SUMMARY = Join-Path $TestDrive 'summary.md'
        $env:BcContainerHelperPath = Join-Path $TestDrive 'BcContainerHelper.ps1'
        $helperLoadedPath = Join-Path $TestDrive 'helper-loaded.txt'
        if (Test-Path $helperLoadedPath) {
            Remove-Item -Path $helperLoadedPath
        }
        Set-Content -Path $env:GITHUB_OUTPUT -Value '' -Encoding UTF8
        Set-Content -Path $env:GITHUB_STEP_SUMMARY -Value 'Existing summary' -Encoding UTF8
        Set-Content -Path $env:BcContainerHelperPath -Encoding UTF8 -Value @'
param([switch] $ExportTelemetryFunctions, [string] $bcContainerHelperConfigFile)
if (-not $ExportTelemetryFunctions) { throw 'Expected telemetry functions to be exported' }
if (-not (Test-Path $bcContainerHelperConfigFile)) { throw 'Expected settings to be passed to BcContainerHelper' }
OutputDebug 'Packaged logging dependency is available'
Invoke-CommandWithRetry -ScriptBlock { 'Packaged retry dependency is available' } | Out-Null
Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE 'helper-loaded.txt') -Value 'loaded' -Encoding UTF8
'@
        Mock Write-Host {}
        Mock New-BcAuthContext {
            @{
                message = 'Sign in at https://aka.ms/devicelogin using code ABCD-EFGH.'
                deviceCode = 'test-device-code'
            }
        }
    }

    AfterAll {
        foreach ($name in $savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
        }
    }

    It 'Matches the standard action wrapper, environment inputs and output contract' {
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName 'Authenticate.ps1'
        YamlTest -scriptRoot $scriptRoot -actionName 'Authenticate' -actionScript $actionScript -outputs @{
            deviceCode = 'Device code used to complete authentication in a subsequent job'
        }
    }

    It 'Loads packaged dependencies through the wrapper and returns a device code without waiting' {
        & $wrapperPath -ActionName 'Authenticate' -SkipTelemetry -Action {
            & $authenticateScriptPath -secrets '{}' @adminParameters
        }

        Should -Invoke New-BcAuthContext -Times 1 -Exactly -ParameterFilter {
            $includeDeviceLogin -and $deviceLoginTimeout -eq [TimeSpan]::Zero
        }
        Test-Path $helperLoadedPath | Should -BeTrue
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be 'deviceCode=test-device-code'
        $summary = (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Replace("`r", '').TrimEnd()
        $summary | Should -Be "Existing summary`nAL-Go needs access to the Business Central Admin Center Api and could not locate a secret called CustomAdminCredentials (https://aka.ms/ALGoSettings#AdminCenterApiCredentialsSecretName)`n`nSign in at https://aka.ms/devicelogin using code ABCD-EFGH."
        $summary | Should -Not -Match 'test-device-code'
    }

    It 'Preserves the configured admin secret name without exposing or executing its value' {
        $secretJson = @{ adminCenterApiCredentials = 'test''; throw "not data"; # $(throw "not data")' } | ConvertTo-Json -Compress
        & $authenticateScriptPath -secrets $secretJson @adminParameters

        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { "$Object" -like '*not data*' }
        Test-Path $helperLoadedPath | Should -BeFalse
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Replace("`r", '').TrimEnd() |
            Should -Be "Existing summary`nAdmin Center Api Credentials was provided in a secret called CustomAdminCredentials. Using this information for authentication."
    }

    It 'Selects <expectedName> for publishing with sparse or competing secrets' -TestCases @(
        @{ secretJson = '{"Sandbox-AuthContext":"first","Sandbox_AuthContext":"second","AuthContext":"third"}'; expectedName = 'Sandbox-AuthContext' }
        @{ secretJson = '{"Sandbox_AuthContext":"second","AuthContext":"third"}'; expectedName = 'Sandbox_AuthContext' }
        @{ secretJson = '{"AuthContext":"third"}'; expectedName = 'AuthContext' }
        @{ secretJson = '{"Sandbox-AuthContext":"","Sandbox_AuthContext":null,"AuthContext":"third"}'; expectedName = 'AuthContext' }
    ) {
        param($secretJson, $expectedName)
        & $authenticateScriptPath -secrets $secretJson -secretNames 'Sandbox-AuthContext,Sandbox_AuthContext,AuthContext' -authType Environment -environmentName 'Sandbox'

        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        Test-Path $helperLoadedPath | Should -BeFalse
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Replace("`r", '').TrimEnd() |
            Should -Be "Existing summary`nAuthContext was provided in a secret called $expectedName. Using this information for authentication."
    }

    It 'Initiates login for <environmentName> when relevant secrets are absent or empty' -TestCases @(
        @{ environmentName = ''; secretJson = '{"adminCenterApiCredentials":""}' }
        @{ environmentName = ''; secretJson = '{"AuthContext":"environment-only"}' }
        @{ environmentName = 'Sandbox'; secretJson = '{}' }
        @{ environmentName = 'Sandbox'; secretJson = '{"Sandbox-AuthContext":null,"Sandbox_AuthContext":"","AuthContext":""}' }
    ) {
        param($environmentName, $secretJson)
        if ($environmentName) {
            & $authenticateScriptPath -secrets $secretJson -secretNames 'Sandbox-AuthContext,Sandbox_AuthContext,AuthContext' -authType Environment -environmentName $environmentName
        }
        else {
            & $authenticateScriptPath -secrets $secretJson @adminParameters
        }

        Should -Invoke New-BcAuthContext -Times 1 -Exactly
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be 'deviceCode=test-device-code'
        $summary = Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw
        if ($environmentName) {
            $summary | Should -Match 'Business Central Environment Sandbox and could not locate a secret called Sandbox-AuthContext or Sandbox_AuthContext or AuthContext'
        }
        else {
            $summary | Should -Match 'Business Central Admin Center Api and could not locate a secret called CustomAdminCredentials'
        }
        $summary | Should -Match 'Sign in at https://aka.ms/devicelogin using code ABCD-EFGH.'
    }

    It 'Reports invalid secret JSON without including its content' -TestCases @(
        @{ secretJson = '{"AuthContext":not-a-secret-value}' }
        @{ secretJson = '["not-a-secret-value"]' }
        @{ secretJson = '"not-a-secret-value"' }
        @{ secretJson = 'null' }
    ) {
        param($secretJson)
        { & $authenticateScriptPath -secrets $secretJson @adminParameters } | Should -Throw 'Authentication secrets must be *JSON object from ReadSecrets.'
        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { "$Object" -like '*not-a-secret-value*' }
        Test-Path $helperLoadedPath | Should -BeFalse
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
    }

    It 'Reports <label> device-login results without publishing success' -TestCases @(
        @{ label = 'null'; result = $null }
        @{ label = 'empty'; result = @{} }
        @{ label = 'missing code'; result = @{ message = 'Sign in' } }
        @{ label = 'missing instructions'; result = @{ deviceCode = 'test-device-code' } }
        @{ label = 'blank code'; result = @{ deviceCode = ' '; message = 'Sign in' } }
    ) {
        param($label, $result)
        Mock New-BcAuthContext { $result }
        { & $authenticateScriptPath -secrets '{}' @adminParameters } | Should -Throw 'Device login did not return a device code and sign-in instructions.'
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Trim() | Should -Be 'Existing summary'
    }

    It 'Accepts an authentication result represented as a PowerShell object' {
        Mock New-BcAuthContext { [PSCustomObject]@{ deviceCode = 'test-device-code'; message = 'Sign in' } }
        & $authenticateScriptPath -secrets '{}' @adminParameters
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be 'deviceCode=test-device-code'
    }

    It 'Propagates authentication failures without publishing a device code or success summary' {
        Mock New-BcAuthContext { throw 'Device login failed' }
        { & $authenticateScriptPath -secrets '{}' @adminParameters } | Should -Throw '*Device login failed*'
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Trim() | Should -Be 'Existing summary'
    }

    It 'Honors caller-defined priority <names> rather than JSON order or built-in names' -TestCases @(
        @{ names = 'Second,First'; expectedName = 'Second' }
        @{ names = 'First,Second'; expectedName = 'First' }
        @{ names = ' Missing, Second , First '; expectedName = 'Second' }
    ) {
        param($names, $expectedName)
        & $authenticateScriptPath -secrets '{"First":"one","Second":"two","AuthContext":"three"}' -secretNames $names -authType Environment -environmentName Sandbox

        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        Test-Path $helperLoadedPath | Should -BeFalse
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Replace("`r", '').TrimEnd() |
            Should -Be "Existing summary`nAuthContext was provided in a secret called $expectedName. Using this information for authentication."
    }

    It 'Does not use unrequested fallback keys and lists all requested candidates in order' {
        & $authenticateScriptPath -secrets '{"AuthContext":"unrequested"}' -secretNames ' Second,First ' -authType Environment -environmentName Sandbox

        Should -Invoke New-BcAuthContext -Times 1 -Exactly
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Replace("`r", '').TrimEnd() |
            Should -Be "Existing summary`nAL-Go needs access to the Business Central Environment Sandbox and could not locate a secret called Second or First`n`nSign in at https://aka.ms/devicelogin using code ABCD-EFGH."
    }

    It 'Displays configured and custom admin candidates in the supplied order' {
        & $authenticateScriptPath -secrets '{}' -secretNames 'Alternative,adminCenterApiCredentials' -authType AdminCenter

        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw) |
            Should -Match 'could not locate a secret called Alternative or CustomAdminCredentials'
    }

    It 'Reports a custom selected admin key by its own name' {
        & $authenticateScriptPath -secrets '{"Alternative":"value","adminCenterApiCredentials":"other"}' -secretNames 'Alternative,adminCenterApiCredentials' -authType AdminCenter

        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        (Get-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Raw).Replace("`r", '').TrimEnd() |
            Should -Be "Existing summary`nAdmin Center Api Credentials was provided in a secret called Alternative. Using this information for authentication."
    }

    It 'Rejects empty entries in the candidate list "<names>"' -TestCases @(
        @{ names = ' ' }
        @{ names = ',First' }
        @{ names = 'First,,Second' }
        @{ names = 'First, ' }
    ) {
        param($names)
        { & $authenticateScriptPath -secrets '{}' -secretNames $names -authType AdminCenter } |
            Should -Throw 'secretNames must contain a comma-separated list of non-empty secret keys.'
        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        Test-Path $helperLoadedPath | Should -BeFalse
    }

    It 'Rejects inconsistent authentication targets instead of inferring a mode' -TestCases @(
        @{ authType = 'Environment'; environmentName = ''; expectedError = 'environmentName is required for Environment authentication.' }
        @{ authType = 'Environment'; environmentName = ' '; expectedError = 'environmentName is required for Environment authentication.' }
        @{ authType = 'AdminCenter'; environmentName = 'Sandbox'; expectedError = 'environmentName must be empty for AdminCenter authentication.' }
    ) {
        param($authType, $environmentName, $expectedError)
        { & $authenticateScriptPath -secrets '{}' -secretNames 'AuthContext' -authType $authType -environmentName $environmentName } |
            Should -Throw $expectedError
        Should -Invoke New-BcAuthContext -Times 0 -Exactly
        Test-Path $helperLoadedPath | Should -BeFalse
        (Get-Content -Path $env:GITHUB_OUTPUT -Encoding UTF8 -Raw).Trim() | Should -Be ''
    }
}

Describe 'Authentication workflow integration' {
    It 'Uses a single authentication action in <template> / <workflow>' -TestCases @(
        @{ template = 'Per Tenant Extension'; workflow = 'CreateOnlineDevelopmentEnvironment' }
        @{ template = 'AppSource App'; workflow = 'CreateOnlineDevelopmentEnvironment' }
        @{ template = 'Per Tenant Extension'; workflow = 'PublishToEnvironment' }
        @{ template = 'AppSource App'; workflow = 'PublishToEnvironment' }
    ) {
        param($template, $workflow)
        $content = Get-Content -Path (Join-Path $PSScriptRoot "../Templates/$template/.github/workflows/$workflow.yaml") -Encoding UTF8 -Raw
        $blocks = [regex]::Matches($content, '(?ms)^      - name: [^\r\n]+\r?\n        id: [Aa]uthenticate\r?\n.*?(?=\r?\n\r?\n|\z)')
        $blocks.Count | Should -Be 1
        $authentication = $blocks[0].Value
        $authentication | Should -Match 'uses: microsoft/AL-Go-Actions/Authenticate@main'
        $authentication | Should -Match ([regex]::Escape('secrets: ${{ steps.ReadSecrets.outputs.Secrets }}'))
        $authentication | Should -Not -Match '\brun:'
        $content | Should -Not -Match 'DownloadAndImportBcContainerHelper|deviceLoginMessage|raw.githubusercontent.com'
        if ($workflow -eq 'PublishToEnvironment') {
            $authentication | Should -Match 'authType: Environment'
            $authentication | Should -Match ([regex]::Escape('secretNames: ''${{ steps.envName.outputs.envName }}-AuthContext,${{ steps.envName.outputs.envName }}_AuthContext,AuthContext'''))
            $authentication | Should -Match ([regex]::Escape('if: steps.DetermineDeploymentEnvironments.outputs.UnknownEnvironment == 1'))
            $authentication | Should -Match ([regex]::Escape('environmentName: ${{ steps.envName.outputs.envName }}'))
            $content | Should -Match ([regex]::Escape('deviceCode: ${{ steps.Authenticate.outputs.deviceCode }}'))
        }
        else {
            $authentication | Should -Match 'authType: AdminCenter'
            $authentication | Should -Match 'secretNames: adminCenterApiCredentials'
            $authentication | Should -Not -Match '\bif:|\benvironmentName:'
            $content | Should -Match ([regex]::Escape('deviceCode: ${{ steps.authenticate.outputs.deviceCode }}'))
        }
    }
}
