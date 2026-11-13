[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in Pester test scopes')]
param()

$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "AnalyzeCodeCoverage workflow wiring" {
    BeforeAll {
        $repositoryRoot = Join-Path $PSScriptRoot ".." -Resolve
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
        $content = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
        $jobMatch = [regex]::Match(
            $content,
            '(?ms)^  AnalyzeCodeCoverage:\r?\n(?<body>.*?)(?=^  [A-Za-z][A-Za-z0-9]+:\r?\n|\z)'
        )

        $jobMatch.Success | Should -BeTrue
        $job = $jobMatch.Value
        $job | Should -Match 'needs: \[ Initialization, Build \]'
        $job | Should -Not -Match 'needs: \[[^\]]*AnalyzeCodeCoverage'
        $job | Should -Match 'contains\(needs\.Initialization\.outputs\.buildOrderJson, ''"codeCoverageRepositorySummary":true''\)'
        $job | Should -Match "pattern: '\*-\*CodeCoverage-\*'"
        $job | Should -Match 'continue-on-error: true'
        $job | Should -Not -Match 'merge-multiple'
        $job | Should -Match 'shell: \$\{\{ inputs\.shell \}\}'
        $job | Should -Match 'scope: repository'
        $job | Should -Match 'buildOrderJson: \$\{\{ needs\.Initialization\.outputs\.buildOrderJson \}\}'

        $finalJobName = if ($Workflow -eq "PullRequestHandler.yaml") { "StatusCheck" } else { "PostProcess" }
        $finalJob = [regex]::Match(
            $content,
            "(?ms)^  $finalJobName`:\r?\n(?<body>.*?)(?=^  [A-Za-z][A-Za-z0-9]+:\r?\n|\z)"
        ).Value
        $finalJob | Should -Match 'needs: \[[^\]]*AnalyzeCodeCoverage[^\]]*\]'
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

            $runTestsStep.Success | Should -BeTrue
            $runTestsStep.Value | Should -Match 'shell: \$\{\{ inputs\.shell \}\}'
            $downloadDependenciesStep.Success | Should -BeTrue
            $downloadDependenciesStep.Value | Should -Match 'shell: \$\{\{ inputs\.shell \}\}'
            $content | Should -Match '(?ms)- name: Analyze Code Coverage.*?scope: project'
            $content | Should -Match '(?ms)- name: Analyze Code Coverage.*?shell: \$\{\{ inputs\.shell \}\}'
            $content | Should -Match "coveragePath: '\$\{\{ inputs\.project \}\}/\.buildartifacts/CodeCoverage/'"
            $content | Should -Match 'CodeCoverage/coverage-status\.json'
        }
    }

    It 'Preserves analyzer dependencies when build jobs are expanded' {
        $helperPath = Join-Path $repositoryRoot "Actions\CheckForUpdates\CheckForUpdates.HelperFunctions.ps1"
        $content = Get-Content -LiteralPath $helperPath -Raw -Encoding UTF8

        $content | Should -Match '\$analyzeCodeCoverage = \$yaml\.Get\(''jobs:/AnalyzeCodeCoverage:/''\)'
        $content | Should -Match '\$postProcessNeeds \+= @\(''AnalyzeCodeCoverage''\)'
        $content | Should -Match '\$statusCheck\.Replace\(''needs:'', .*postProcessNeeds'
    }
}
