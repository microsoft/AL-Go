[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in Pester test scopes')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "AnalyzeCodeCoverage workflow wiring" {
    BeforeAll {
        $repositoryRoot = Join-Path $PSScriptRoot ".." -Resolve
        . (Join-Path $repositoryRoot "Actions\CheckForUpdates\yamlclass.ps1")
        . (Join-Path $repositoryRoot "Actions\CheckForUpdates\CheckForUpdates.HelperFunctions.ps1")
        $templateRoots = @(
            (Join-Path $repositoryRoot "Templates\AppSource App\.github\workflows"),
            (Join-Path $repositoryRoot "Templates\Per Tenant Extension\.github\workflows")
        )
    }

    It 'Adds a separated repository fan-in job to <Template>/<Workflow>' -TestCases @(
        foreach ($template in @("AppSource App", "Per Tenant Extension")) {
            foreach ($workflow in @("CICD.yaml", "PullRequestHandler.yaml", "Current.yaml", "NextMajor.yaml", "NextMinor.yaml")) {
                @{
                    Template = $template
                    Workflow = $workflow
                }
            }
        }
    ) {
        param($Template, $Workflow)

        $workflowPath = Join-Path $repositoryRoot "Templates\$Template\.github\workflows\$Workflow"
        $yaml = [Yaml]::Load($workflowPath)
        $job = $yaml.Get('jobs:/AnalyzeCodeCoverage:/')

        $job | Should -Not -BeNullOrEmpty
        $yaml.GetPropertyArray('jobs:/AnalyzeCodeCoverage:/needs:') |
            Should -Be @('Initialization', 'Build')
        $yaml.GetProperty('jobs:/Initialization:/outputs:/githubRunnerShell:') |
            Should -Be '${{ steps.ReadSettings.outputs.GitHubRunnerShell }}'
        $job.content | Should -Contain '    continue-on-error: true'
        $job.content | Should -Contain "      pattern: '*-*CodeCoverage-*'"
        $job.content | Should -Not -Match 'merge-multiple'
        $job.content | Should -Contain '      shell: ${{ needs.Initialization.outputs.githubRunnerShell }}'
        $job.content | Should -Contain '      scope: repository'
        $job.content | Should -Contain '      buildOrderJson: ${{ needs.Initialization.outputs.buildOrderJson }}'
        $yaml.GetProperty('jobs:/AnalyzeCodeCoverage:/if:') |
            Should -Be '(!cancelled()) && contains(needs.Initialization.outputs.buildOrderJson, ''"codeCoverageRepositorySummary":true'')'

        $finalJobName = if ($Workflow -eq "PullRequestHandler.yaml") { "StatusCheck" } else { "PostProcess" }
        $yaml.GetPropertyArray("jobs:/${finalJobName}:/needs:") |
            Should -Contain 'AnalyzeCodeCoverage'
    }

    It 'Adds project analysis to both reusable build workflows' {
        foreach ($templateRoot in $templateRoots) {
            $content = Get-Content -LiteralPath (Join-Path $templateRoot "_BuildALGoProject.yaml") `
                -Raw -Encoding UTF8
            $runTestsStep = [regex]::Match(
                $content,
                '(?ms)^      - name: Run Tests\r?\n(?<body>.*?)(?=^      - name: |\z)'
            )
            $downloadDependenciesStep = [regex]::Match(
                $content,
                '(?ms)^      - name: Download Project Dependencies\r?\n(?<body>.*?)(?=^      - name: |\z)'
            )
            $uploadArtifactReferences = @(
                [regex]::Matches(
                    $content,
                    'actions/upload-artifact@(?<pin>[0-9a-f]+) # (?<version>v[0-9.]+)'
                ) | ForEach-Object { "$($_.Groups['pin'].Value) $($_.Groups['version'].Value)" } |
                    Sort-Object -Unique
            )

            $runTestsStep.Success | Should -BeTrue
            $runTestsStep.Value | Should -Match 'shell: \$\{\{ inputs\.shell \}\}'
            $downloadDependenciesStep.Success | Should -BeTrue
            $downloadDependenciesStep.Value | Should -Match 'shell: \$\{\{ inputs\.shell \}\}'
            $uploadArtifactReferences | Should -Be @(
                'cf430e030ddbb5b0abf93d22962f4752f3646cd9 v7.0.2'
            )
            $content | Should -Match '(?ms)- name: Analyze Code Coverage.*?scope: project'
            $content | Should -Match '(?ms)- name: Analyze Code Coverage.*?shell: \$\{\{ inputs\.shell \}\}'
            $content | Should -Match "coveragePath: '\$\{\{ inputs\.project \}\}/\.buildartifacts/CodeCoverage/'"
            $content | Should -Match 'CodeCoverage/coverage-status\.json'
        }
    }

    It 'Preserves analyzer dependencies when <Workflow> build jobs are expanded' -TestCases @(
        @{ Workflow = 'CICD.yaml'; FinalJob = 'PostProcess' }
        @{ Workflow = 'PullRequestHandler.yaml'; FinalJob = 'StatusCheck' }
    ) {
        param($Workflow, $FinalJob)

        $workflowPath = Join-Path $repositoryRoot "Templates\AppSource App\.github\workflows\$Workflow"
        $yaml = [Yaml]::Load($workflowPath)

        ModifyBuildWorkflows -yaml $yaml -depth 3 -includeBuildPP $false

        $yaml.GetPropertyArray('jobs:/AnalyzeCodeCoverage:/needs:') |
            Should -Be @('Initialization', 'Build')
        $yaml.GetPropertyArray("jobs:/${FinalJob}:/needs:") |
            Should -Contain 'AnalyzeCodeCoverage'
        $yaml.GetPropertyArray("jobs:/${FinalJob}:/needs:") |
            Should -Contain 'Build'
        $yaml.GetPropertyArray("jobs:/${FinalJob}:/needs:") |
            Should -Contain 'Build1'
        $yaml.GetPropertyArray("jobs:/${FinalJob}:/needs:") |
            Should -Contain 'Build2'
        $yaml.GetProperty('jobs:/Initialization:/outputs:/githubRunnerShell:') |
            Should -Be '${{ steps.ReadSettings.outputs.GitHubRunnerShell }}'
        $yaml.Get('jobs:/AnalyzeCodeCoverage:/').content |
            Should -Contain '      shell: ${{ needs.Initialization.outputs.githubRunnerShell }}'
    }
}
