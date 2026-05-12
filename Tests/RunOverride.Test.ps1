[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock/callback parameters must match function signatures')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

. (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)

Describe 'RunOverride action' {
    BeforeAll {
        # Trace-Information is from TelemetryHelper.psm1 which isn't loaded in tests
        function Trace-Information { param([string]$Message) }

        $script:RunOverrideScript = (Join-Path $PSScriptRoot "../Actions/RunOverride/RunOverride.ps1" -Resolve)
    }

    BeforeEach {
        $script:workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:workspace | Out-Null
        $script:projectPath = Join-Path $script:workspace 'project'
        New-Item -ItemType Directory -Path (Join-Path $script:projectPath '.AL-Go') | Out-Null
        $env:GITHUB_WORKSPACE = $script:workspace
    }

    AfterEach {
        $env:GITHUB_WORKSPACE = $null
    }

    It 'Is a silent no-op when the override script does not exist' {
        { & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson '{}' } | Should -Not -Throw
    }

    It 'Invokes the override script and forwards parameters as a hashtable' {
        $sentinelPath = Join-Path $script:workspace 'sentinel.json'
        Set-Content -Path (Join-Path $script:projectPath '.AL-Go/BuildInitialize.ps1') -Value @"
Param([Hashtable]`$parameters)
`$parameters | ConvertTo-Json -Depth 5 | Set-Content -Path '$sentinelPath' -Encoding UTF8
"@

        & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson '{"foo":"bar","nested":{"answer":42}}'

        Test-Path $sentinelPath | Should -BeTrue
        $payload = Get-Content -Path $sentinelPath -Encoding UTF8 -Raw | ConvertFrom-Json
        $payload.foo | Should -Be 'bar'
        $payload.nested.answer | Should -Be 42
    }

    It 'Throws a clear error when overrideName is not in the allow-list' {
        { & $script:RunOverrideScript -project 'project' -overrideName 'NotARealOverride' -parametersJson '{}' } |
            Should -Throw -ExpectedMessage "*'NotARealOverride'*not a recognized AL-Go override*"
    }

    It 'Throws when parametersJson is not valid JSON' {
        { & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson 'not-json' } |
            Should -Throw -ExpectedMessage "*Failed to parse parametersJson*"
    }

    It 'Throws when parametersJson is a JSON array (not an object)' {
        { & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson '[1,2,3]' } |
            Should -Throw -ExpectedMessage "*must deserialize to a JSON object*"
    }

    It 'Throws when parametersJson is a JSON scalar (not an object)' {
        { & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson '42' } |
            Should -Throw -ExpectedMessage "*must deserialize to a JSON object*"
    }

    It 'Auto-populates project in $parameters' {
        $sentinelPath = Join-Path $script:workspace 'auto.json'
        Set-Content -Path (Join-Path $script:projectPath '.AL-Go/BuildInitialize.ps1') -Value @"
Param([Hashtable]`$parameters)
`$parameters | ConvertTo-Json -Depth 5 | Set-Content -Path '$sentinelPath' -Encoding UTF8
"@

        & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson '{}'

        $payload = Get-Content -Path $sentinelPath -Encoding UTF8 -Raw | ConvertFrom-Json
        $payload.project | Should -Be 'project'
        $payload.PSObject.Properties.Name | Should -Not -Contain 'overrideName'
    }

    It 'Caller-supplied keys in parametersJson override auto-populated defaults' {
        $sentinelPath = Join-Path $script:workspace 'override.json'
        Set-Content -Path (Join-Path $script:projectPath '.AL-Go/BuildInitialize.ps1') -Value @"
Param([Hashtable]`$parameters)
`$parameters | ConvertTo-Json -Depth 5 | Set-Content -Path '$sentinelPath' -Encoding UTF8
"@

        & $script:RunOverrideScript -project 'project' -overrideName 'BuildInitialize' -parametersJson '{"project":"custom","extra":"value"}'

        $payload = Get-Content -Path $sentinelPath -Encoding UTF8 -Raw | ConvertFrom-Json
        $payload.project | Should -Be 'custom'
        $payload.extra | Should -Be 'value'
    }
}

Describe 'Invoke-ScriptOverride helper' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        function Trace-Information { param([string]$Message) }
    }

    It 'Does nothing when no override script exists' {
        $alGoFolder = Join-Path $TestDrive 'invoke-noop'
        New-Item -ItemType Directory -Path $alGoFolder | Out-Null

        { Invoke-ScriptOverride -ALGoFolderName $alGoFolder -OverrideName 'BuildInitialize' -Parameters @{} } | Should -Not -Throw
    }

    It 'Invokes the override script with the supplied hashtable' {
        $alGoFolder = Join-Path $TestDrive 'invoke-run'
        New-Item -ItemType Directory -Path $alGoFolder | Out-Null
        $sentinelPath = Join-Path $TestDrive 'invoke-run-sentinel.txt'
        Set-Content -Path (Join-Path $alGoFolder 'BuildInitialize.ps1') -Value @"
Param([Hashtable]`$parameters)
Set-Content -Path '$sentinelPath' -Value `$parameters.message -Encoding UTF8
"@

        Invoke-ScriptOverride -ALGoFolderName $alGoFolder -OverrideName 'BuildInitialize' -Parameters @{ message = 'hello' }

        Get-Content -Path $sentinelPath -Encoding UTF8 -Raw | Should -Match 'hello'
    }
}

Describe 'Invoke-ALGoOverride helper' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath "../Actions/AL-Go-Helper.ps1" -Resolve)
        function Trace-Information { param([string]$Message) }
    }

    BeforeEach {
        $script:workspace2 = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:workspace2 | Out-Null
        $script:projectPath2 = Join-Path $script:workspace2 'project'
        New-Item -ItemType Directory -Path (Join-Path $script:projectPath2 '.AL-Go') | Out-Null
        $env:GITHUB_WORKSPACE = $script:workspace2
    }

    AfterEach {
        $env:GITHUB_WORKSPACE = $null
    }

    It 'Throws when overrideName is not in the allow-list' {
        { Invoke-ALGoOverride -Project 'project' -OverrideName 'NotARealOverride' -Parameters @{} } |
            Should -Throw -ExpectedMessage "*'NotARealOverride'*not a recognized AL-Go override*"
    }

    It 'Resolves project path against GITHUB_WORKSPACE and invokes the override' {
        $sentinelPath = Join-Path $script:workspace2 'algo-sentinel.txt'
        Set-Content -Path (Join-Path $script:projectPath2 '.AL-Go/BuildInitialize.ps1') -Value @"
Param([Hashtable]`$parameters)
Set-Content -Path '$sentinelPath' -Value `$parameters.value -Encoding UTF8
"@

        Invoke-ALGoOverride -Project 'project' -OverrideName 'BuildInitialize' -Parameters @{ value = 'resolved' }

        Get-Content -Path $sentinelPath -Encoding UTF8 -Raw | Should -Match 'resolved'
    }

    It 'Is a silent no-op when the override script does not exist' {
        { Invoke-ALGoOverride -Project 'project' -OverrideName 'BuildInitialize' -Parameters @{} } | Should -Not -Throw
    }
}
