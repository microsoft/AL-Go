Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force

Describe "DetermineDeliveryTargets Action Test" {
    BeforeAll {
        $actionName = "DetermineDeliveryTargets"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    BeforeEach {
        $env:GITHUB_REF_NAME = "main"
        $env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_ENV = [System.IO.Path]::GetTempFileName()
        $env:GITHUB_WORKSPACE = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
        New-Item -Path $env:GITHUB_WORKSPACE -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $env:GITHUB_WORKSPACE '.github') -ItemType Directory | Out-Null
    }

    AfterEach {
        Remove-Item $env:GITHUB_OUTPUT
        Remove-Item $env:GITHUB_ENV
        Remove-Item $env:GITHUB_WORKSPACE -Recurse -Force
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $permissions = [ordered]@{
        }
        $outputs = [ordered]@{
            "DeliveryTargetsJson" = "An array of Delivery Targets in compressed JSON format"
            "ContextSecrets" = "A comma-separated list of Context Secret names used"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -permissions $permissions -outputs $outputs
    }

    # PTE with NuGetContext secret defined, should yield NuGet
    It 'Test calling action directly - PTE / Nuget' {
        $env:Settings = @{ "type" = "PTE" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = "xyz"; "GitHubPackagesContext" = ""; "StorageContext" = ""; "AppSourceContext" = "abc" } | ConvertTo-Json -Compress

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["NuGet"]'
    }

    # AppSource App with GitHubPackagesContext and AppSourceContext defined, but without AppSourceContinuousDelivery set, should yield GitHubPackages
    It 'Test calling action directly - AppSource App / GitHubPackages' {
        $env:Settings = @{ "type" = "AppSource App" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = ""; "GitHubPackagesContext" = "xyz"; "StorageContext" = ""; "AppSourceContext" = "abc" } | ConvertTo-Json -Compress

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["GitHubPackages"]'
    }

    # AppSource App with GitHubPackagesContext and AppSourceContext defined, with AppSourceContinuousDelivery set, should yield GitHubPackages and AppSource
    It 'Test calling action directly - AppSource App / GitHubPackages + CD' {
        $env:Settings = @{ "type" = "AppSource App" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = "xyz"; "GitHubPackagesContext" = ""; "StorageContext" = ""; "AppSourceContext" = "abc" } | ConvertTo-Json -Compress
        @{"AppSourceContinuousDelivery" = $true} | ConvertTo-Json | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/AL-Go-Settings.json')

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["NuGet","AppSource"]'
    }

    # AppSource App with GitHubPackagesContext and AppSourceContext defined, with AppSourceContinuousDelivery set, should yield GitHubPackages and AppSource
    It 'Test calling action directly - AppSource App / GitHubPackages + CD - Custom' {
        $env:Settings = @{ "type" = "AppSource App" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = "xyz"; "GitHubPackagesContext" = ""; "StorageContext" = ""; "AppSourceContext" = "abc" } | ConvertTo-Json -Compress
        @{"AppSourceContinuousDelivery" = $true} | ConvertTo-Json | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/AL-Go-Settings.json')
        "test" | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE 'DeliverToCustom.ps1')

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["NuGet","AppSource"]'
    }

    It 'Test calling action directly -  AppSource App / NuGet + AppSource + Custom' {
        $env:Settings = @{ "type" = "AppSource App" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = "xyz"; "GitHubPackagesContext" = ""; "StorageContext" = ""; "AppSourceContext" = "abc"; "CustomContext" = "123" } | ConvertTo-Json -Compress
        @{"AppSourceContinuousDelivery" = $true} | ConvertTo-Json | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/AL-Go-Settings.json')
        "test" | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeliverToCustom.ps1')

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["NuGet","AppSource","Custom"]'
        $generatedOutPut | Should -Contain 'contextSecrets=NuGetContext,AppSourceContext,CustomContext'
    }

    It 'Test calling action directly - PTE / Storage + Custom' {
        $env:Settings = @{ "type" = "PTE" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = ""; "GitHubPackagesContext" = ""; "StorageContext" = "xyz"; "AppSourceContext" = "abc"; "CustomContext" = "123" } | ConvertTo-Json -Compress
        @{"AppSourceContinuousDelivery" = $true} | ConvertTo-Json | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/AL-Go-Settings.json')
        "test" | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeliverToCustom.ps1')

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["Storage","Custom"]'
        $generatedOutPut | Should -Contain 'ContextSecrets=StorageContext,CustomContext'
    }

    It 'Test calling action directly - PTE (branch) / Storage + Custom (and AppSourceContext) - yields no delivery targets' {
        $env:Settings = @{ "type" = "PTE" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = ""; "GitHubPackagesContext" = ""; "StorageContext" = "xyz"; "AppSourceContext" = "abc"; "CustomContext" = "123" } | ConvertTo-Json -Compress
        "test" | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeliverToCustom.ps1')
        $env:GITHUB_REF_NAME = 'branch'

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=[]'
        $generatedOutPut | Should -Contain 'ContextSecrets='
    }

    It 'Test calling action directly - PTE (branch) / Storage + Custom' {
        $env:Settings = @{ "type" = "PTE"; "DeliverToCustom" = @{"Branches" = @("main","branch")} } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = ""; "GitHubPackagesContext" = ""; "StorageContext" = "xyz"; "AppSourceContext" = "abc"; "CustomContext" = "123" } | ConvertTo-Json -Compress
        "test" | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeliverToCustom.ps1')
        $env:GITHUB_REF_NAME = "branch"

        . (Join-Path $scriptRoot $scriptName) -checkContextSecrets $true

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["Custom"]'
        $generatedOutPut | Should -Contain 'ContextSecrets=CustomContext'
    }

    It 'Test calling action directly - Do not check context secrets' {
        $env:Settings = @{ "type" = "PTE" } | ConvertTo-Json -Compress
        $env:Secrets = @{ "NuGetContext" = ""; "GitHubPackagesContext" = ""; "StorageContext" = "xyz"; "AppSourceContext" = "abc"; "CustomContext" = "123" } | ConvertTo-Json -Compress
        @{"AppSourceContinuousDelivery" = $true} | ConvertTo-Json | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/AL-Go-Settings.json')
        "test" | Set-Content -Path (Join-Path $env:GITHUB_WORKSPACE '.github/DeliverToCustom.ps1')

        . (Join-Path $scriptRoot $scriptName)  -checkContextSecrets $false

        $generatedOutPut = Get-Content $env:GITHUB_OUTPUT -Encoding UTF8
        $generatedOutPut | Should -Contain 'DeliveryTargetsJson=["GitHubPackages","NuGet","Storage","Custom"]'
        $generatedOutPut | Should -Contain 'ContextSecrets=GitHubPackagesContext,NuGetContext,StorageContext,CustomContext'
    }
}
