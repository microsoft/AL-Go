Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../Actions/Github-Helper.psm1') -Force

Describe "DetermineDeploymentEnvironments Action Test" {
    BeforeAll {
        $actionName = "DetermineDeploymentEnvironments"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        function PassGeneratedOutput() {
            Get-Content $env:GITHUB_OUTPUT -Encoding UTF8 | ForEach-Object {
                Set-Variable -Scope Script -Name $_.Split('=')[0] -Value $_.SubString($_.IndexOf('=')+1)
            }
        }
    }

    BeforeEach {
        $env:GITHUB_REF_NAME = "main"
        $ENV:GITHUB_API_URL = ''
        $ENV:GITHUB_REPOSITORY = ''
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
        $outputs = [ordered]@{
            "EnvironmentsMatrixJson" = "The Environment matrix to use for the Deploy step in compressed JSON format"
            "DeploymentEnvironmentsJson" = "Deployment Environments with settings in compressed JSON format"
            "EnvironmentCount" = "Number of Deployment Environments"
            "UnknownEnvironment" = "Flag determining whether the environment is unknown"
            "GenerateALDocArtifact" = "Flag determining whether to generate the ALDoc artifact"
            "DeployALDocArtifact" = "Flag determining whether to deploy the ALDoc artifact to GitHub Pages"
        }
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs
    }

    Context 'Paginated GitHub environments' {
        BeforeEach {
            $script:apiEnvironments = @(1..101 | ForEach-Object {
                @{ "name" = "ENV-{0:D3}" -f $_; "protection_rules" = @() }
            })
            Mock InvokeWebRequest -MockWith { throw "Unexpected request: $uri" }
            Mock InvokeWebRequest -ParameterFilter { $uri -match '/environments\?per_page=100&page=\d+$' } -MockWith {
                $pageNumber = [int]($uri -replace '.*&page=', '')
                if ($pageNumber -gt 4) {
                    throw "Too many environment pages requested"
                }
                $pageItems = @($script:apiEnvironments | Select-Object -Skip (($pageNumber - 1) * 100) -First 100)
                return @{ "Content" = (@{ "total_count" = $script:apiEnvironments.Count; "environments" = $pageItems } | ConvertTo-Json -Depth 99 -Compress) }
            }
            $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @(); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } } | ConvertTo-Json -Compress
        }

        It 'Discovers all <count> environments for CD using <requests> requests' -TestCases @(
            @{ count = 0; requests = 1 }
            @{ count = 1; requests = 1 }
            @{ count = 30; requests = 1 }
            @{ count = 31; requests = 1 }
            @{ count = 100; requests = 2 }
            @{ count = 101; requests = 2 }
            @{ count = 200; requests = 3 }
            @{ count = 201; requests = 3 }
        ) {
            param($count, $requests)
            $script:apiEnvironments = @(for ($i = 1; $i -le $count; $i++) {
                @{ "name" = "ENV-{0:D3}" -f $i; "protection_rules" = @() }
            })

            . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
            PassGeneratedOutput

            $EnvironmentCount | Should -Be $count
            $deployEnvs = $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
            $deployEnvs.Count | Should -Be $count
            foreach ($apiEnvironment in $script:apiEnvironments) {
                $deployEnvs.ContainsKey($apiEnvironment.name) | Should -Be $true
            }
            $matrix = $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
            @($matrix.matrix.include).Count | Should -Be $count
            Assert-MockCalled InvokeWebRequest -Times $requests -Exactly -Scope It
        }

        It 'Publishes to an environment on the second page without creating it' {
            . (Join-Path $scriptRoot $scriptName) -getEnvironments 'ENV-101' -type 'Publish'
            PassGeneratedOutput

            $EnvironmentCount | Should -Be 1
            $UnknownEnvironment | Should -Be 0
            ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Be 'ENV-101'
            Assert-MockCalled InvokeWebRequest -Times 1 -Exactly -Scope It -ParameterFilter { $uri -like '*&page=2' }
        }

        It 'Applies branch policies from the second page for <deploymentType>' -TestCases @(
            @{ deploymentType = 'CD' }
            @{ deploymentType = 'Publish' }
        ) {
            param($deploymentType)
            $script:apiEnvironments[100].protection_rules = @(@{ "type" = "branch_policy" })
            $script:apiEnvironments[100].deployment_branch_policy = @{ "protected_branches" = $false; "custom_branch_policies" = $true }
            Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments/ENV-101/deployment-branch-policies' } -MockWith {
                return @{ "Content" = (@{ "branch_policies" = @(@{ "name" = "release/*" }) } | ConvertTo-Json -Depth 99 -Compress) }
            }

            . (Join-Path $scriptRoot $scriptName) -getEnvironments 'ENV-101' -type $deploymentType
            PassGeneratedOutput
            $EnvironmentCount | Should -Be 0

            $env:GITHUB_REF_NAME = 'release/1.0'
            . (Join-Path $scriptRoot $scriptName) -getEnvironments 'ENV-101' -type $deploymentType
            PassGeneratedOutput
            $EnvironmentCount | Should -Be 1
            ($DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).'ENV-101'.BranchesFromPolicy | Should -Be 'release/*'
            Assert-MockCalled InvokeWebRequest -Times 2 -Exactly -Scope It -ParameterFilter { $uri -like '*/deployment-branch-policies' }
        }

        It 'Fails rather than selecting from an incomplete list when a later page fails' {
            Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=2' } -MockWith {
                throw 'Environment page request failed'
            }

            { . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD' } | Should -Throw '*Environment page request failed*'
            Get-Content $env:GITHUB_OUTPUT -Encoding UTF8 | Where-Object { $_ -like 'EnvironmentsMatrixJson=*' } | Should -BeNullOrEmpty
        }
    }

    # 2 environments defined in GitHub - no branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - no branch policy' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }, @{ "name" = "another"; "protection_rules" = @() } ) })}
        }

        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } } | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]";"shell"="pwsh";"buildMode"="Default"};@{"environment"="test";"os"="[""ubuntu-latest""]";"shell"="pwsh";"buildMode"="Default"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"test"=@{"EnvironmentType"="SaaS";"EnvironmentName"="test";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"DependencyInstallMode"="install";"Scope"=$null;"syncMode"=$null;"buildMode"=$null;"continuousDeployment"=$null;"runs-on"=@("ubuntu-latest");"shell"="pwsh";"ppEnvironmentUrl"="";"companyId"="";"includeTestAppsInSandboxEnvironment"=$false;"excludeAppIds"=@();"unpublishOldVersions"=$false};"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"DependencyInstallMode"="install";"Scope"=$null;"syncMode"=$null;"buildMode"=$null;"continuousDeployment"=$null;"runs-on"=@("ubuntu-latest");"shell"="pwsh";"ppEnvironmentUrl"="";"companyId"="";"includeTestAppsInSandboxEnvironment"=$false;"excludeAppIds"=@();"unpublishOldVersions"=$false}}
        $EnvironmentCount | Should -Be 2

        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="test";"os"="[""ubuntu-latest""]";"shell"="pwsh";"buildMode"="Default"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"test"=@{"EnvironmentType"="SaaS";"EnvironmentName"="test";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"DependencyInstallMode"="install";"Scope"=$null;"syncMode"=$null;"buildMode"=$null;"continuousDeployment"=$null;"runs-on"=@("ubuntu-latest");"shell"="pwsh";"ppEnvironmentUrl"="";"companyId"="";"includeTestAppsInSandboxEnvironment"=$false;"excludeAppIds"=@();"unpublishOldVersions"=$false}}
        $EnvironmentCount | Should -Be 1
    }

    # 2 environments defined in GitHub - one with branch policy = protected branches
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy = protected branches' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $true; "custom_branch_policies" = $false } }, @{ "name" = "another"; "protection_rules" = @() } ) })}
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/branches' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } ))}
        }

        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } } | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]";"shell"="pwsh";"buildMode"="Default"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"DependencyInstallMode"="install";"Scope"=$null;"syncMode"=$null;"buildMode"=$null;"continuousDeployment"=$null;"runs-on"=@("ubuntu-latest");"shell"="pwsh";"ppEnvironmentUrl"="";"companyId"="";"includeTestAppsInSandboxEnvironment"=$false;"excludeAppIds"=@();"unpublishOldVersions"=$false}}
        $EnvironmentCount | Should -Be 1

        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
    }

    # 2 environments defined in GitHub - one with branch policy = branch. the other with no branch policy
    It 'Test calling action directly - 2 environments defined in GitHub - one with branch policy = main' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @( @{ "type" = "branch_policy"}); "deployment_branch_policy" = @{ "protected_branches" = $false; "custom_branch_policies" = $true } }, @{ "name" = "another"; "protection_rules" = @() } ) })}
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/branches' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @( @{ "name" = "branch"; "protected" = $true }, @{ "name" = "main"; "protected" = $false } ))}
        }
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/deployment-branch-policies' } -MockWith {
            return @{"Content" = (@{ "branch_policies" = @( @{ "name" = "branch" }, @{ "name" = "branch2" } ) } | ConvertTo-Json -Depth 99 -Compress)}
        }

        $env:Settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } } | ConvertTo-Json -Compress
        # Only another environment should be included when deploying from main
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"matrix"=@{"include"=@(@{"environment"="another";"os"="[""ubuntu-latest""]";"shell"="pwsh";"buildMode"="Default"})};"fail-fast"=$false}
        $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse | Should -MatchHashtable @{"another"=@{"EnvironmentType"="SaaS";"EnvironmentName"="another";"Branches"=@();"BranchesFromPolicy"=@();"Projects"="*";"DependencyInstallMode"="install";"Scope"=$null;"syncMode"=$null;"buildMode"=$null;"continuousDeployment"=$null;"runs-on"=@("ubuntu-latest");"shell"="pwsh";"ppEnvironmentUrl"="";"companyId"="";"includeTestAppsInSandboxEnvironment"=$false;"excludeAppIds"=@();"unpublishOldVersions"=$false}}
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "another"

        # Change branch to branch - now only test environment should be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"

        # Change branch to branch2 - test environment should still be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch2'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"

        # Add Branch policy to settings to only allow branch to deploy to test environment - now no environments should be included
        $settings += @{
            "DeployToTest" = @{
                "Branches" = @("branch")
            }
        }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 0

        # Change branch to branch - test environment should still be included (due to branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"
    }

    # 2 environments defined in GitHub, 1 in settings - exclude another environment
    It 'Test calling action directly - 2 environments defined in GitHub, one in settings' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() }; @{ "name" = "another"; "protection_rules" = @() } ) })}
        }

        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @("settingsenv"); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 3

        # Exclude another environment
        $settings.excludeEnvironments += @('another')
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 2
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Not -Contain "another"

        # Add Branch policy to settings to only allow branch to deploy to test environment
        $settings += @{
            "DeployToTest" = @{
                "Branches" = @("branch")
            }
        }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "settingsenv"

        # Changing branch to branch - now only test environment should be included (due to settings branch policy)
        $env:GITHUB_REF_NAME = 'branch'
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test"
    }

    # 2 environments defined in Settings - one PROD and one non-PROD (name based)
    It 'Test calling action directly - 2 environments defined in Settings - one PROD and one non-PROD (name based)' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            throw "Not supported"
        }

        # One PROD environment and one non-PROD environment - only non-PROD environment is selected for CD
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @("test (PROD)","another"); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "another"

        # Publish to test environment - test is included
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'Publish'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test (PROD)"
    }

    # 2 environments defined in Settings - one PROD and one non-PROD (settings based)
    It 'Test calling action directly - 2 environments defined in Settings - one PROD and one non-PROD (settings based)' {
        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @("test (PROD)","another"); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }

        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            throw "Not supported"
        }

        $settings += @{
            "DeployToTest" = @{
                "continuousDeployment" = $false
            }
            "DeployToAnother" = @{
                "continuousDeployment" = $true
            }
        }

        # One PROD environment and one non-PROD environment - only non-PROD environment is selected for CD
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "another"

        # Publish to test environment - test is included
        $env:Settings = $settings | ConvertTo-Json -Compress
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test' -type 'Publish'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "test (PROD)"
    }

    # Test that buildMode from DeployTo settings is correctly included in the matrix
    It 'Test calling action directly - Custom buildMode from DeployTo settings is included in matrix' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "test"; "protection_rules" = @() } ) })}
        }

        $settings = @{
            "type" = "PTE"
            "runs-on" = "ubuntu-latest"
            "shell" = "pwsh"
            "environments" = @()
            "excludeEnvironments" = @( 'github-pages' )
            "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false }
            "DeployToTest" = @{
                "buildMode" = "CustomBuildMode"
            }
        }

        $env:Settings = $settings | ConvertTo-Json -Compress -Depth 5
        . (Join-Path $scriptRoot $scriptName) -getEnvironments '*' -type 'CD'
        PassGeneratedOutput

        # Verify buildMode is correctly set to CustomBuildMode in the matrix
        $matrix = $EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
        $matrix.matrix.include[0].buildMode | Should -Be "CustomBuildMode"
        $EnvironmentCount | Should -Be 1

        # Verify buildMode is correctly set in DeploymentEnvironmentsJson
        $deployEnvs = $DeploymentEnvironmentsJson | ConvertFrom-Json | ConvertTo-HashTable -recurse
        $deployEnvs.test.buildMode | Should -Be "CustomBuildMode"
    }

    # Unknown environment - createEnvIfNotExists = false (default) - should throw error
    It 'Test calling action directly - Unknown environment without createEnvIfNotExists should throw' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @() })}
        }

        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }
        $env:Settings = $settings | ConvertTo-Json -Compress

        # Environment doesn't exist and createEnvIfNotExists is false (default) - should throw
        { . (Join-Path $scriptRoot $scriptName) -getEnvironments 'nonexistent' -type 'Publish' } | Should -Throw "*does not exist*"
    }

    # Unknown environment - createEnvIfNotExists = true - should create unknown environment
    It 'Test calling action directly - Unknown environment with createEnvIfNotExists should succeed' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @() })}
        }

        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }
        $env:Settings = $settings | ConvertTo-Json -Compress

        # Environment doesn't exist but createEnvIfNotExists is true - should succeed
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'newenv' -type 'Publish' -createEnvIfNotExists $true
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 1
        $UnknownEnvironment | Should -Be 1
        ($EnvironmentsMatrixJson | ConvertFrom-Json | ConvertTo-HashTable -recurse).matrix.include.environment | Should -Contain "newenv"
    }

    # Wildcard pattern with no matches - should not throw, just return 0 environments
    It 'Test calling action directly - Wildcard pattern with no matches should not throw' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @( @{ "name" = "prod"; "protection_rules" = @() } ) })}
        }

        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }
        $env:Settings = $settings | ConvertTo-Json -Compress

        # Pattern with wildcard that doesn't match any environment - should not throw, just return 0 environments
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'test*' -type 'Publish'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 0
    }

    # Environment name containing wildcard characters should throw (not be treated as unknown environment)
    It 'Test calling action directly - Environment name with wildcard should not create unknown environment' {
        Mock InvokeWebRequest -ParameterFilter { $uri -like '*/environments?per_page=100&page=1' } -MockWith {
            return @{"Content" = (ConvertTo-Json -Compress -Depth 99 -InputObject @{ "environments" = @() })}
        }

        $settings = @{ "type" = "PTE"; "runs-on" = "ubuntu-latest"; "shell" = "pwsh"; "environments" = @(); "excludeEnvironments" = @( 'github-pages' ); "alDoc" = @{ "continuousDeployment" = $false; "deployToGitHubPages" = $false } }
        $env:Settings = $settings | ConvertTo-Json -Compress

        # Environment name containing wildcard - should not create unknown environment, should return 0 environments
        . (Join-Path $scriptRoot $scriptName) -getEnvironments 'FAT*' -type 'Publish'
        PassGeneratedOutput
        $EnvironmentCount | Should -Be 0
        $UnknownEnvironment | Should -Be 0
    }
}
