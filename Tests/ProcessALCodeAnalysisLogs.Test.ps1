Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe 'ProcessALCodeAnalysisLogs Action Tests' {

    BeforeAll {
        $actionName = "ProcessALCodeAnalysisLogs"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName

        Mock Write-Host {}
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'alErrorLogSchema', Justification = 'False positive.')]
        $alErrorLogSchema = @{
            "version" = "0.2"
            "toolInfo" = @{
                "toolName" = "Microsoft (R) AL Compiler"
                "productVersion" = "14.3.26"
                "fileVersion" = "14.3.26"
            }
            "issues" = @()
        }
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'sampleIssue1', Justification = 'False positive.')]
        $sampleIssue1 = @{
            "ruleId"=  "AA001"
            "locations" = @(
                @{
                    "analysisTarget" = @(
                        @{
                            "uri" = "D:\\a\\repo\\repo\\TestArtifacts\\ALFileName.al"
                            "region" = @{
                                "startLine" = 1
                                "startColumn" = 1
                                "endLine" = 1
                                "endColumn" = 1
                            }
                        }
                    )
                }
            )
            "shortMessage" = "Issue short message"
            "fullMessage" = "Issue full message"
            "properties" = @{
                "severity" = "Warning"
                "warningLevel" = "1"
                "defaultSeverity" = "Warning"
                "title" = "title"
                "category" = "category"
                "helpLink" = "helplink"
                "isEnabledByDefault" = "True"
                "isSuppressedInSource" = "False"
            }
        }
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'sampleIssue2', Justification = 'False positive.')]
        $sampleIssue2 = @{
            "ruleId"=  "AA001"
            "locations" = @(
                @{
                    "analysisTarget" = @(
                        @{
                            "uri" = "D:\\a\\repo\\repo\\TestArtifacts\\ALFileName.al"
                            "region" = @{
                                "startLine" = 2
                                "startColumn" = 1
                                "endLine" = 2
                                "endColumn" = 1
                            }
                        }
                    )
                }
            )
            "shortMessage" = "Issue short message"
            "fullMessage" = "Issue full message"
            "properties" = @{
                "severity" = "Warning"
                "warningLevel" = "1"
                "defaultSeverity" = "Warning"
                "title" = "title"
                "category" = "category"
                "helpLink" = "helplink"
                "isEnabledByDefault" = "True"
                "isSuppressedInSource" = "False"
            }
        }
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'sampleIssue3', Justification = 'False positive.')]
        $sampleIssue3 = @{
            "ruleId"=  "AA002"
            "locations" = @(
                @{
                    "analysisTarget" = @(
                        @{
                            "uri" = "D:\\a\\repo\\repo\\TestArtifacts\\ALFileName.al"
                            "region" = @{
                                "startLine" = 3
                                "startColumn" = 1
                                "endLine" = 3
                                "endColumn" = 1
                            }
                        }
                    )
                }
            )
            "shortMessage" = "Issue short message"
            "fullMessage" = "Issue full message"
            "properties" = @{
                "severity" = "Warning"
                "warningLevel" = "1"
                "defaultSeverity" = "Warning"
                "title" = "title"
                "category" = "category"
                "helpLink" = "helplink"
                "isEnabledByDefault" = "True"
                "isSuppressedInSource" = "False"
            }
        }
        $ENV:GITHUB_WORKSPACE = [System.IO.Path]::GetTempPath()
        # Copy sample files to temp folder
        Copy-Item -Path "$PSScriptRoot\TestArtifacts\*" -Destination $ENV:GITHUB_WORKSPACE -Recurse -Force
        $errorLogsFolder = Join-Path $ENV:GITHUB_WORKSPACE "ErrorLogs"
        if (!(Test-Path $errorLogsFolder)) {
            New-Item -Path $errorLogsFolder -ItemType Directory -Force
        }
    }

    AfterEach {
        $errorLogsFolder = Join-Path $ENV:GITHUB_WORKSPACE "ErrorLogs"

        if (Test-Path $errorLogsFolder) {
            Remove-Item -Path "$errorLogsFolder\*" -Recurse -Force
        }
    }

    It 'SARIF file should be created' {
        # Create 1 error log file with 1 issue
        $errorLogFile = Join-Path $errorLogsFolder "sample.errorLog.json"
        $baseIssueContent = $alErrorLogSchema
        $baseIssueContent.issues += $sampleIssue1
        $baseIssueContent | ConvertTo-Json -Depth 10 | Set-Content -Path $errorLogFile

        & $scriptPath

        $sarifFile = Join-Path $errorLogsFolder "output.sarif.json"
        $sarifFile | Should -Exist
    }

    It 'All issues added from single error log file' {
        # Create 1 error log file with 2 issues
        $errorLogFile = Join-Path $errorLogsFolder "sample.errorLog.json"
        $baseIssueContent = $alErrorLogSchema
        $baseIssueContent.issues += $sampleIssue1
        $baseIssueContent.issues += $sampleIssue3
        $baseIssueContent | ConvertTo-Json -Depth 10 | Set-Content -Path $errorLogFile

        & $scriptPath

        $sarifFile = Join-Path $errorLogsFolder "output.sarif.json"
        $sarifContent = Get-Content -Path $sarifFile -Raw | ConvertFrom-Json
        $sarifContent.runs[0].results.Count | Should -Be 2
    }

    It 'All issues added from multiple error log files' {
        # Create 2 error log file with 2 issues
        $errorLogFile1 = Join-Path $errorLogsFolder "sample1.errorLog.json"
        $baseIssueContent1 = $alErrorLogSchema.clone()
        $baseIssueContent1.issues += $sampleIssue1
        $baseIssueContent1 | ConvertTo-Json -Depth 10 | Set-Content -Path $errorLogFile1

        $errorLogFile2 = Join-Path $errorLogsFolder "sample2.errorLog.json"
        $baseIssueContent2 = $alErrorLogSchema.clone()
        $baseIssueContent2.issues += $sampleIssue3
        $baseIssueContent2 | ConvertTo-Json -Depth 10 | Set-Content -Path $errorLogFile2

        & $scriptPath

        $sarifFile = Join-Path $errorLogsFolder "output.sarif.json"
        $sarifContent = Get-Content -Path $sarifFile -Raw | ConvertFrom-Json
        $sarifContent.runs[0].results.Count | Should -Be 2
    }

    It 'Multiple issues with same ruleId results in SARIF with single rule' {
        # Create 2 error log file with 2 issues
        $errorLogFile = Join-Path $errorLogsFolder "sample.errorLog.json"
        $baseIssueContent = $alErrorLogSchema
        $baseIssueContent.issues += $sampleIssue1 #Issue 1 and 2 share the same ruleId, hence the output should have 2 rules in total.
        $baseIssueContent.issues += $sampleIssue2
        $baseIssueContent.issues += $sampleIssue3
        $baseIssueContent | ConvertTo-Json -Depth 10 | Set-Content -Path $errorLogFile

        & $scriptPath

        $sarifFile = Join-Path $errorLogsFolder "output.sarif.json"
        $sarifContent = Get-Content -Path $sarifFile -Raw | ConvertFrom-Json
        $sarifContent.runs[0].tool.driver.rules.Count | Should -Be 2
    }

    It 'Duplicate issues are only included once' {
        # Create 1 error log file with 3 issues where 2 are duplicates
        $errorLogFile = Join-Path $errorLogsFolder "sample.errorLog.json"
        $baseIssueContent = $alErrorLogSchema
        $baseIssueContent.issues += $sampleIssue1
        $baseIssueContent.issues += $sampleIssue1
        $baseIssueContent.issues += $sampleIssue2
        $baseIssueContent | ConvertTo-Json -Depth 10 | Set-Content -Path $errorLogFile

        & $scriptPath

        $baseIssueContent.issues.Count | Should -Be 3
        $sarifFile = Join-Path $errorLogsFolder "output.sarif.json"
        $sarifContent = Get-Content -Path $sarifFile -Raw | ConvertFrom-Json
        $sarifContent.runs[0].tool.driver.rules.Count | Should -Be 1
        $sarifContent.runs[0].results.Count | Should -Be 2
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript
    }
}
