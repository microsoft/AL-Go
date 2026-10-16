[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments',
    '',
    Justification = 'The imported functions resolve these test fixtures through PowerShell dynamic scope.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseBOMForUnicodeEncodedFile',
    '',
    Justification = 'The test intentionally covers Unicode domain labels and rendered Unicode output.'
)]
param()

BeforeAll {
    $NormalizationSchemaPath = Join-Path $PSScriptRoot 'fixtures/findings-report-roles/bcquality-findings-report.b74967bc.schema.json'
    $scriptPath = Join-Path $PSScriptRoot '../../Actions/ReviewAgent/scripts/Invoke-CopilotPRReview.psm1' -Resolve
    $scriptRoot = Split-Path -Parent $scriptPath
    $script:ReviewScriptPaths = @($scriptPath) + @(
        Get-ChildItem -LiteralPath $scriptRoot -Filter '*.ps1' -File |
            Where-Object FullName -ne $scriptPath |
            Sort-Object Name |
            Select-Object -ExpandProperty FullName
    )
    $script:ReviewSourceText = @(
        $script:ReviewScriptPaths | ForEach-Object {
            Get-Content -LiteralPath $_ -Raw
        }
    ) -join [Environment]::NewLine
    $EngineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptPath)))
    $ReviewRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
    $script:ReviewFunctionAsts = @()
    foreach ($reviewScriptPath in $script:ReviewScriptPaths) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $reviewScriptPath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if ($parseErrors.Count -gt 0) {
            throw "$reviewScriptPath`n$($parseErrors | ForEach-Object Message | Out-String)"
        }
        $script:ReviewFunctionAsts += @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true))
    }
    $script:ReviewFunctionAsts | Where-Object Name -ne 'Invoke-CopilotPRReview' | ForEach-Object {
        $functionDefinition = [scriptblock]::Create($_.Extent.Text)
        . $functionDefinition
    }

    $DomainMap = @{
        'al-security-review'    = 'Security'
        'al-performance-review' = 'Performance'
        'agent'                 = 'Agent'
    }
    $SeverityOrder = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
    $BCQualitySeverityMap = @{ blocker = 'Critical'; major = 'High'; minor = 'Medium'; info = 'Low' }
    $MinimumSeverity = 'Low'
    $AgentMinimumSeverity = 'Low'
    $MaxFindings = 25
    $script:LastParsingErrors = [System.Collections.Generic.List[string]]::new()
    $script:IsGitHubActions = $false

    $AgentVersion = '1'
    $AgentLabel = 'copilot-pr-review'
    $ReviewIteration = 2
    $AgentCommentDocUrl = 'https://example.test/review'
    $BCQualityVersion = '1.7'
    $script:BCQualityWebRepoUrl = 'https://github.com/microsoft/BCQuality'
}

Describe 'Review engine module boundary' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../../Actions/ReviewAgent/scripts/Invoke-CopilotPRReview.psm1' -Resolve
        Import-Module $modulePath -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module Invoke-CopilotPRReview
    }

    It 'exports only the review entry point and does not run a review on import' {
        @(Get-Command -Module Invoke-CopilotPRReview).Name | Should -Be @('Invoke-CopilotPRReview')
    }

    It 'resolves per-run configuration in private module functions without leaking it to the caller' {
        $names = @('BCQUALITY_VERSION', 'REVIEW_PHASE', 'REVIEW_SOURCE', 'GITHUB_TOKEN')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
        try {
            $env:BCQUALITY_VERSION = '2.0'
            $env:REVIEW_PHASE = 'post'
            $env:REVIEW_SOURCE = 'pr'
            $env:GITHUB_TOKEN = ''
            $Repository = 'caller-value'

            { Invoke-CopilotPRReview } | Should -Throw '*GITHUB_TOKEN is required for posting*'

            $Repository | Should -Be 'caller-value'
        }
        finally {
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }
}

Describe 'Untrusted review logging' {
    BeforeEach {
        $script:IsGitHubActions = $true
        $script:CapturedLog = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host {
            param($Object)
            $script:CapturedLog.Add([string]$Object)
        }
    }

    AfterEach {
        $script:IsGitHubActions = $false
    }

    It 'suspends workflow commands across both output streams with a fresh token' {
        $stdout = '::add-mask::forged-mask'
        $stderr = "`r::error::forged-annotation"
        $transcript = [System.Text.StringBuilder]::new()

        Write-CopilotOutput -Stdout $stdout -Stderr $stderr -Transcript $transcript

        $script:CapturedLog.Count | Should -Be 4
        $script:CapturedLog[0] | Should -Match '^::stop-commands::[a-f0-9]{32}$'
        $token = $script:CapturedLog[0].Substring('::stop-commands::'.Length)
        $script:CapturedLog[1] | Should -Be $stdout
        $script:CapturedLog[2] | Should -Be "[copilot-err] $stderr"
        $script:CapturedLog[3] | Should -Be "::$($token)::"
        $transcript.ToString() | Should -Match ([regex]::Escape("out: $stdout"))
        $transcript.ToString() | Should -Match ([regex]::Escape("err: $stderr"))

        $script:CapturedLog.Clear()
        Write-CopilotOutput -Stdout $stdout -Transcript $transcript
        $script:CapturedLog[0] | Should -Not -Be "::stop-commands::$token"
    }

    It 'restores command parsing even when replay fails' {
        { Invoke-WithWorkflowCommandsSuspended { throw 'Replay failed' } } | Should -Throw '*Replay failed*'

        $script:CapturedLog.Count | Should -Be 2
        $token = $script:CapturedLog[0].Substring('::stop-commands::'.Length)
        $script:CapturedLog[1] | Should -Be "::$($token)::"
    }

    It 'also protects model-supplied phase details' {
        Write-LogPhaseDetail -Line "Reason: untrusted`r::add-mask::forged"

        $script:CapturedLog[0] | Should -Match '^::stop-commands::[a-f0-9]{32}$'
        $script:CapturedLog[1] | Should -Be "  Reason: untrusted`r::add-mask::forged"
        $token = $script:CapturedLog[0].Substring('::stop-commands::'.Length)
        $script:CapturedLog[2] | Should -Be "::$($token)::"
    }

    It 'escapes annotation control characters without decoding supplied escapes: <Name>' -ForEach @(
        @{ Name = 'bare CR and LF'; Text = "first`r::warning::forged`n%0A"; Expected = 'first%0D::warning::forged%0A%250A' }
        @{ Name = 'CRLF'; Text = "first`r`nsecond%0D"; Expected = 'first%0D%0Asecond%250D' }
    ) {
        Format-AnnotationMessage -Message $Text | Should -BeExactly $Expected
    }
}

Describe 'npm Copilot process launching' {
    It 'executes an npm loader without a command shell in the <Layout> layout' -ForEach @(
        @{ Layout = 'global' }, @{ Layout = 'local' }
    ) {
        $root = Join-Path $TestDrive "npm $Layout with spaces"
        $shimDirectory = if ($Layout -eq 'global') { $root } else { Join-Path $root 'node_modules/.bin' }
        $loaderDirectory = Join-Path $root 'node_modules/@github/copilot'
        New-Item -ItemType Directory -Path $shimDirectory, $loaderDirectory -Force | Out-Null
        $shim = Join-Path $shimDirectory 'copilot.cmd'
        Set-Content -LiteralPath $shim -Value '@exit /b 99' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $loaderDirectory 'npm-loader.js') -Encoding UTF8 -Value @'
if (process.argv.includes('--version')) {
    console.log('GitHub Copilot CLI 1.0.83.');
} else {
    process.stdout.write(JSON.stringify(process.argv.slice(2)));
}
'@

        Get-CopilotExecutableVersion -Executable $shim | Should -Be '1.0.83'

        $arguments = @('-p', 'spaces, "quotes" and trailing \', '--model=test-model')
        $startInfo = New-CopilotProcessStartInfo -Executable $shim -Arguments $arguments
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()

            $process.ExitCode | Should -Be 0
            $stderr.GetAwaiter().GetResult() | Should -BeNullOrEmpty
            @($stdout.GetAwaiter().GetResult() | ConvertFrom-Json) | Should -Be $arguments
        }
        finally {
            $process.Dispose()
        }
    }

    It 'fails explicitly when a command shim has no installed npm loader' {
        $shim = Join-Path $TestDrive 'missing-package/copilot.cmd'
        { New-CopilotProcessStartInfo -Executable $shim } | Should -Throw '*Cannot find the npm Copilot loader*'
    }
}

Describe 'Resolve-FindingLocation' {
    BeforeAll {
        $patch = @'
@@ -10,7 +10,7 @@
 context
 context
 context
-old line
+new line
 context
 context
 context
@@ -30,7 +30,7 @@
 context
 context
 context
-another old line
+another new line
 context
 context
 context
'@
        $lineMap = Build-LineMap -Patch $patch
    }

    It 'preserves an exact changed-line anchor' {
        $location = Resolve-FindingLocation -LineMap $lineMap -LineNumber 13

        $location.line | Should -Be 13
        $location.side | Should -Be 'RIGHT'
    }

    It 'marks an exact anchor as not inferred and stays StrictMode-safe' {
        # Regression: the exact-match branch used to return the raw Build-LineMap
        # entry, which has no 'inferred' key. Publish-Findings reads
        # [bool]($location.inferred ?? $false) with member syntax, and under
        # Set-StrictMode -Version Latest a missing property throws before ?? runs
        # (unlike hashtable indexing). Pester does not enable StrictMode, so assert
        # the exact behaviour of the posting call site explicitly.
        Set-StrictMode -Version Latest
        try {
            $location = Resolve-FindingLocation -LineMap $lineMap -LineNumber 13

            $location.inferred | Should -BeFalse
            { [bool]($location.inferred ?? $false) } | Should -Not -Throw
        }
        finally {
            Set-StrictMode -Off
        }
    }

    It 'uses the nearest changed line in the same hunk' {
        $location = Resolve-FindingLocation -LineMap $lineMap -LineNumber 12

        $location.line | Should -Be 13
        $location.side | Should -Be 'RIGHT'
        $location.inferred | Should -BeTrue
    }

    It 'uses the earlier changed line when distances are equal' {
        $tiePatch = @'
@@ -10,7 +10,7 @@
 context
-old before
+new before
 context
-old after
+new after
 context
 context
 context
'@
        $tieMap = Build-LineMap -Patch $tiePatch

        (Resolve-FindingLocation -LineMap $tieMap -LineNumber 12).line | Should -Be 11
    }

    It 'does not cross into an unrelated hunk' {
        Resolve-FindingLocation -LineMap $lineMap -LineNumber 22 | Should -BeNullOrEmpty
    }

    It 'does not treat a deleted old coordinate as an exact PR-head anchor' {
        $shiftedPatch = @'
@@ -20,4 +10,4 @@
 context
-old line
+new line
 context
 context
'@
        $shiftedMap = Build-LineMap -Patch $shiftedPatch

        Resolve-FindingLocation -LineMap $shiftedMap -LineNumber 21 | Should -BeNullOrEmpty
        (Resolve-FindingLocation -LineMap $shiftedMap -LineNumber 11).side | Should -Be 'RIGHT'
    }

    It 'prefers a same-hunk RIGHT anchor over a matching deleted old coordinate' {
        $shiftedPatch = @'
@@ -12,4 +10,4 @@
 context
-old line
+new line
 context
 context
'@
        $shiftedMap = Build-LineMap -Patch $shiftedPatch

        $location = Resolve-FindingLocation -LineMap $shiftedMap -LineNumber 13
        $location.line | Should -Be 11
        $location.side | Should -Be 'RIGHT'
        $location.inferred | Should -BeTrue
    }

    It 'infers the nearest LEFT anchor in a deletion-only hunk' {
        $deletionPatch = @'
@@ -10,7 +10,6 @@
 context
 context
 context
-deleted line
 context
 context
 context
'@
        $deletionMap = Build-LineMap -Patch $deletionPatch

        $location = Resolve-FindingLocation -LineMap $deletionMap -LineNumber 12

        $location.line | Should -Be 13
        $location.side | Should -Be 'LEFT'
        $location.inferred | Should -BeTrue
        (Resolve-FindingLocation -LineMap $deletionMap -LineNumber 13).side | Should -Be 'LEFT'
    }

    It 'maps nearby PR-head lines to the closest deletion in a deletion-only hunk' {
        $deletionPatch = @'
@@ -91,18 +91,14 @@
 context
 context
 context
-deleted first
 context
 context
 context
-deleted second
 context
 context
 context
 context
 context
-deleted third
-deleted fourth
 context
 context
 context
'@
        $deletionMap = Build-LineMap -Patch $deletionPatch

        (Resolve-FindingLocation -LineMap $deletionMap -LineNumber 97).line | Should -Be 98
        (Resolve-FindingLocation -LineMap $deletionMap -LineNumber 103).line | Should -Be 104
    }

    It 'does not infer a LEFT anchor across hunk boundaries' {
        $deletionPatch = @'
@@ -10,4 +10,3 @@
 context
-deleted line
 context
 context
@@ -30,4 +29,3 @@
 context
-another deleted line
 context
 context
'@
        $deletionMap = Build-LineMap -Patch $deletionPatch

        Resolve-FindingLocation -LineMap $deletionMap -LineNumber 20 | Should -BeNullOrEmpty
    }
}

Describe 'Inferred location deduplication' {
    It 'deduplicates by source line without reserving the shared anchor' {
        $domain = 'Style'
        $domainKey = ConvertTo-DomainMetadataKey -Domain $domain
        Mock Get-ReviewComments {
            @([pscustomobject]@{
                path = 'src/example.al'
                line = 13
                side = 'RIGHT'
                body = "<!-- agent_domain_key: $domainKey -->`n<!-- agent_source_line: 12 -->"
            })
        }

        $existing = Get-ExistingCommentKeys -Domain $domain

        $existing.SourceKeys.Contains('src/example.al:12') | Should -BeTrue
        $existing.Keys.Count | Should -Be 0
        $existing.Locations.Count | Should -Be 0
    }
}

Describe 'Resolve-FindingDomain' {
    It 'prefers the explicit lowercase domain over the legacy map' {
        $finding = [pscustomobject]@{
            domain = 'Breaking Changes'
            'from-sub-skill' = 'al-security-review'
        }
        Resolve-FindingDomain -Finding $finding | Should -Be 'Breaking Changes'
    }

    It 'accepts the capitalized Domain property' {
        Resolve-FindingDomain -Finding ([pscustomobject]@{ Domain = 'Web Services' }) |
            Should -Be 'Web Services'
    }

    It 'uses from-sub-skill and from_sub_skill legacy fallbacks' {
        Resolve-FindingDomain -Finding ([pscustomobject]@{ 'from-sub-skill' = 'al-security-review' }) |
            Should -Be 'Security'
        Resolve-FindingDomain -Finding ([pscustomobject]@{ from_sub_skill = 'al-performance-review' }) |
            Should -Be 'Performance'
    }

    It 'uses the legacy map when an explicit label is whitespace' {
        $finding = [pscustomobject]@{
            domain = "`t "
            'from-sub-skill' = 'al-security-review'
        }
        Resolve-FindingDomain -Finding $finding | Should -Be 'Security'
    }

    It 'falls back safely for missing and unusable labels' -ForEach @(
        @{ Explicit = $null }
        @{ Explicit = '' }
        @{ Explicit = '   ' }
    ) {
        $finding = [pscustomobject]@{ domain = $Explicit; 'from-sub-skill' = 'unknown-review' }
        Resolve-FindingDomain -Finding $finding | Should -Be 'Other'
    }
}

Describe 'Resolve-SuggestionPlacement' {
    It 'suppresses an edited single-line suggestion from a comment anchor' {
        $lines = @(
            'begin',
            '    // Calculate the quantity to release.',
            '    ReleaseQtyBase := Abs(QtyBase) - CalcQtyToPickOnLotBase(ItemLedgerEntry);',
            'end;'
        )
        $suggestion = @(
            '    ReleaseQtyBase := Abs(QtyBase) - this.CalcQtyToPickOnLotBase(ItemLedgerEntry);'
        )

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 2 -SuggestedLines $suggestion

        $placement | Should -BeNullOrEmpty
    }

    It 'does not match code suggestions to similar comment text' {
        $lines = @(
            '    // ReleaseQtyBase := Abs(QtyBase) - this.CalcQtyToPickOnLotBase(ItemLedgerEntry);',
            '    ReleaseQtyBase := Abs(QtyBase) - CalcQtyToPickOnLotBase(ItemLedgerEntry);'
        )
        $suggestion = @(
            '    ReleaseQtyBase := Abs(QtyBase) - this.CalcQtyToPickOnLotBase(ItemLedgerEntry);'
        )

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 1 -SuggestedLines $suggestion

        $placement | Should -BeNullOrEmpty
    }

    It 'suppresses an unrelated single-line rewrite instead of trusting the anchor' {
        $placement = Resolve-SuggestionPlacement `
            -FileLines @('begin', '    DoWork();', 'end;') `
            -AnchorLine 2 `
            -SuggestedLines @('    CompletelyDifferentOperation(Value);')

        $placement | Should -BeNullOrEmpty
    }

    It 'suppresses an ambiguous single-line target' {
        $lines = @(
            '    Customer.SetRange(Blocked, Customer.Blocked::All);',
            '    Vendor.SetRange(Blocked, Vendor.Blocked::All);'
        )

        $placement = Resolve-SuggestionPlacement `
            -FileLines $lines `
            -AnchorLine 1 `
            -SuggestedLines @('    Record.SetRange(Blocked, Record.Blocked::All);')

        $placement | Should -BeNullOrEmpty
    }

    It 'does not move from one code line to a more similar unrelated code line' {
        $lines = @(
            'OldResult := OldProvider.Calculate(Source);',
            'OtherResult := NewProvider.Calculate(Target);'
        )

        $placement = Resolve-SuggestionPlacement `
            -FileLines $lines `
            -AnchorLine 1 `
            -SuggestedLines @('Result := NewProvider.Calculate(Target);')

        $placement | Should -BeNullOrEmpty
    }

    It 'does not guess between plausible lines from a comment anchor' {
        $lines = @(
            '// Update the result.',
            'Result := Calculate(Source);',
            'begin',
            'end;',
            'Result := this.Provider.Calculate(Target);'
        )

        $placement = Resolve-SuggestionPlacement `
            -FileLines $lines `
            -AnchorLine 1 `
            -SuggestedLines @('Result := this.Provider.Calculate(Source);')

        $placement | Should -BeNullOrEmpty
    }

    It 'keeps an exact single-line suggestion on its anchor' {
        $placement = Resolve-SuggestionPlacement `
            -FileLines @('begin', '    DoWork();', 'end;') `
            -AnchorLine 2 `
            -SuggestedLines @(' DoWork(); ')

        $placement.startLine | Should -Be 2
        $placement.endLine | Should -Be 2
    }

    It 'suppresses a changed target when an out-of-range anchor clamps to code' {
        $placement = Resolve-SuggestionPlacement `
            -FileLines @('DoWork();', 'exit(Result);') `
            -AnchorLine 99 `
            -SuggestedLines @('exit(this.Result);')

        $placement | Should -BeNullOrEmpty
    }

    It 'suppresses empty input and blank single-line suggestions' {
        Resolve-SuggestionPlacement -FileLines @() -AnchorLine 1 -SuggestedLines @('x') |
            Should -BeNullOrEmpty
        Resolve-SuggestionPlacement -FileLines @('x') -AnchorLine 1 -SuggestedLines @('   ') |
            Should -BeNullOrEmpty
    }

    It 'preserves additive multi-line placement' {
        $lines = @('begin', '    DoFirst();', '    DoLast();', 'end;')
        $suggestion = @('    DoFirst();', '    DoMiddle();', '    DoLast();')

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 2 -SuggestedLines $suggestion

        $placement.startLine | Should -Be 2
        $placement.endLine | Should -Be 3
    }

    It 'places pure reorderings over the complete source span' {
        $lines = @('using Microsoft.Sales;', 'using Microsoft.Foundation;', 'using System;')
        $suggestion = @('using System;', 'using Microsoft.Foundation;', 'using Microsoft.Sales;')

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 2 -SuggestedLines $suggestion

        $placement.startLine | Should -Be 1
        $placement.endLine | Should -Be 3
    }

    It 'does not let an additive subsequence truncate a reordered source span' {
        $lines = @('using Microsoft.Sales;', 'using Microsoft.Foundation;', 'using System;')
        $suggestion = @('using Microsoft.Foundation;', 'using Microsoft.Sales;', 'using System;')

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 1 -SuggestedLines $suggestion

        $placement.startLine | Should -Be 1
        $placement.endLine | Should -Be 3
    }

    It 'suppresses a suggestion that both reorders and inserts' {
        $lines = @('using Microsoft.Sales;', 'using Microsoft.Foundation;', 'using System;')
        $suggestion = @(
            'using Microsoft.Foundation;',
            'using Microsoft.Sales;',
            'using Microsoft.Inventory;',
            'using System;'
        )
        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 1 -SuggestedLines $suggestion
        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 1 -SuggestedLines $suggestion

        $placement | Should -BeNullOrEmpty
    }

    It 'does not let reorder-plus-insert masquerade as a truncated additive span' {
        $lines = @('using Microsoft.Sales;', 'using Microsoft.Foundation;', 'using System;')
        $suggestion = @(
            'using Microsoft.Foundation;',
            'using Microsoft.Sales;',
            'using Microsoft.Inventory;',
            'using System;'
        )

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 2 -SuggestedLines $suggestion

        $placement | Should -BeNullOrEmpty
    }

    It 'prefers the repeated additive block that contains the anchor' {
        $lines = @('Reset();', 'Run();', 'Reset();', 'Run();')
        $suggestion = @('Reset();', 'Configure();', 'Run();')

        $placement = Resolve-SuggestionPlacement -FileLines $lines -AnchorLine 3 -SuggestedLines $suggestion

        $placement.startLine | Should -Be 3
        $placement.endLine | Should -Be 4
    }

    It 'suppresses equally ranked repeated reorder spans' {
        $placement = Resolve-SuggestionPlacement `
            -FileLines @('DoWork();', 'DoWork();', 'DoWork();') `
            -AnchorLine 2 `
            -SuggestedLines @('DoWork();', 'DoWork();')

        $placement | Should -BeNullOrEmpty
    }

    It 'does not treat a changed line set as a pure reordering' {
        $placement = Resolve-SuggestionPlacement `
            -FileLines @('using Microsoft.Sales;', 'using Microsoft.Foundation;') `
            -AnchorLine 1 `
            -SuggestedLines @('using Microsoft.Foundation;', 'using System;')

        $placement | Should -BeNullOrEmpty
    }

    It 'does not move a multi-line replacement away from a code anchor' {
        $placement = Resolve-SuggestionPlacement `
            -FileLines @('A();', 'B();', 'C();') `
            -AnchorLine 1 `
            -SuggestedLines @('B();', 'X();', 'C();')

        $placement | Should -BeNullOrEmpty
    }

    It 'counts duplicate lines when validating a multiset equality' {
        Test-LooseMultisetEqual `
            -A @('DoWork();', 'DoWork();', 'Finish();') `
            -B @('Finish();', 'DoWork();', 'DoWork();') |
            Should -BeTrue
        Test-LooseMultisetEqual `
            -A @('DoWork();', 'DoWork();', 'Finish();') `
            -B @('Finish();', 'Finish();', 'DoWork();') |
            Should -BeFalse
    }
}

Describe 'Agent domain normalization' {
    It 'preserves an explicit leaf domain for an agent finding' {
        $json = @{
            outcome = 'completed'
            findings = @(@{
                id = 'agent:security'
                domain = 'Security'
                'from-sub-skill' = 'al-security-review'
                severity = 'major'
                message = 'Issue'
                location = @{ file = 'src/a.al'; line = 1 }
                references = @()
            })
        } | ConvertTo-Json -Depth 8

        $finding = (ConvertFrom-BCQualityReport -Output $json).Findings[0]
        $finding.isAgentFinding | Should -BeTrue
        $finding.domain | Should -Be 'Security'
    }

    It 'uses Agent only for an unlabeled legacy agent finding without a mapped domain' {
        $json = @{
            outcome = 'completed'
            findings = @(@{
                id = 'legacy'
                knowledge_backed = $false
                severity = 'major'
                message = 'Issue'
                location = @{ file = 'src/a.al'; line = 1 }
                references = @()
            })
        } | ConvertTo-Json -Depth 8

        (ConvertFrom-BCQualityReport -Output $json).Findings[0].domain | Should -Be 'Agent'
    }

    It 'preserves the exact Agent label on a cross-cutting producer finding' {
        $json = @{
            outcome = 'completed'
            findings = @(@{
                id = 'agent:cross-cutting'
                domain = 'Agent'
                'from-sub-skill' = 'agent'
                severity = 'major'
                message = 'Issue'
                location = @{ file = 'src/a.al'; line = 1 }
                references = @()
            })
        } | ConvertTo-Json -Depth 8

        $finding = (ConvertFrom-BCQualityReport -Output $json).Findings[0]
        $finding.isAgentFinding | Should -BeTrue
        $finding.domain | Should -BeExactly 'Agent'
    }
}

Describe 'Domain metadata' {
    It 'round-trips a multi-word domain through collision-safe metadata' {
        $metadata = Get-AgentDomainMetadata -Domain 'Breaking Changes'
        $parsed = Get-CommentDomainMetadataKey -Body $metadata

        $parsed.Kind | Should -BeExactly 'Exact'
        $parsed.Key | Should -BeExactly (ConvertTo-DomainMetadataKey -Domain 'Breaking Changes')
    }

    It 'reads legacy single-token metadata' {
        $parsed = Get-CommentDomainMetadataKey -Body '<!-- agent_domain: security -->'

        $parsed.Kind | Should -BeExactly 'Legacy'
        $parsed.Key | Should -BeExactly 'security'
    }

    It 'encodes exact trimmed UTF-8 labels without lossy transformations' {
        $precomposed = [string][char]0x00E9
        $decomposed = "e$([char]0x0301)"
        $labels = @(
            'API', 'api', $precomposed, $decomposed, 'A B', 'A  B',
            'C#', 'C++', '!!!', '???', 'A-B', 'A_B', 'Æ', 'AE'
        )
        $keys = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )

        foreach ($label in $labels) {
            $keys.Add((ConvertTo-DomainMetadataKey -Domain $label)) | Should -BeTrue
        }
        $keys.Count | Should -Be $labels.Count
        ConvertTo-DomainMetadataKey -Domain '  API  ' |
            Should -BeExactly (ConvertTo-DomainMetadataKey -Domain 'API')
        ConvertTo-DomainMetadataKey -Domain 'A B' |
            Should -Not -BeExactly (ConvertTo-DomainMetadataKey -Domain 'A  B')
    }

    It 'deduplicates exact metadata by case, Unicode representation, whitespace, and punctuation' {
        $precomposed = [string][char]0x00E9
        $decomposed = "e$([char]0x0301)"
        $cases = @(
            @{ Label = 'API'; Path = 'src/1.al' }
            @{ Label = 'api'; Path = 'src/2.al' }
            @{ Label = $precomposed; Path = 'src/3.al' }
            @{ Label = $decomposed; Path = 'src/4.al' }
            @{ Label = 'A B'; Path = 'src/5.al' }
            @{ Label = 'A  B'; Path = 'src/6.al' }
            @{ Label = 'C#'; Path = 'src/7.al' }
            @{ Label = 'C++'; Path = 'src/8.al' }
            @{ Label = '!!!'; Path = 'src/9.al' }
            @{ Label = '???'; Path = 'src/10.al' }
        )
        $script:DomainComments = @($cases | ForEach-Object {
            [pscustomobject]@{
                body = Get-AgentDomainMetadata -Domain $_.Label
                path = $_.Path
                line = 10
                side = 'RIGHT'
            }
        })
        Mock Get-ReviewComments {
            $script:DomainComments
        }

        foreach ($case in $cases) {
            $existing = Get-ExistingCommentKeys -Domain $case.Label
            $existing.Keys.Count | Should -Be 1
            $existing.Keys.Contains("$($case.Path):10:RIGHT") | Should -BeTrue
        }
    }

    It 'keeps legacy lowercase matching separate from new exact matching' {
        $script:DomainComments = @(
            [pscustomobject]@{
                body = '<!-- agent_domain: security -->'
                path = 'src/legacy.al'; line = 1; side = 'RIGHT'
            },
            [pscustomobject]@{
                body = Get-AgentDomainMetadata -Domain 'security'
                path = 'src/exact.al'; line = 2; side = 'RIGHT'
            }
        )
        Mock Get-ReviewComments { $script:DomainComments }

        $capitalized = Get-ExistingCommentKeys -Domain 'Security'
        $capitalized.Keys.Count | Should -Be 1
        $capitalized.Keys.Contains('src/legacy.al:1:RIGHT') | Should -BeTrue
        $capitalized.Keys.Contains('src/exact.al:2:RIGHT') | Should -BeFalse

        (Get-ExistingCommentKeys -Domain 'security').Keys.Count | Should -Be 2
    }

    It 'does not match a new lowercase exact key to a capitalized target' {
        $script:DomainComments = @(
            [pscustomobject]@{
                body = Get-AgentDomainMetadata -Domain 'security'
                path = 'src/exact.al'; line = 2; side = 'RIGHT'
            }
        )
        Mock Get-ReviewComments { $script:DomainComments }

        (Get-ExistingCommentKeys -Domain 'security').Keys.Count | Should -Be 1
        (Get-ExistingCommentKeys -Domain 'Security').Keys.Count | Should -Be 0

        $script:DomainComments = @(
            [pscustomobject]@{
                body = Get-AgentDomainMetadata -Domain 'Security'
                path = 'src/exact-case.al'; line = 3; side = 'RIGHT'
            }
        )
        (Get-ExistingCommentKeys -Domain 'Security').Keys.Contains('src/exact-case.al:3:RIGHT') |
            Should -BeTrue
    }

    It 'reads both legacy single-token heading formats' {
        $script:DomainComments = @(
            [pscustomobject]@{
                body = '### High Security - issue'
                path = 'src/new-heading.al'; line = 1; side = 'RIGHT'
            },
            [pscustomobject]@{
                body = '### Security - High Severity'
                path = 'src/old-heading.al'; line = 2; side = 'RIGHT'
            }
        )
        Mock Get-ReviewComments { $script:DomainComments }

        (Get-ExistingCommentKeys -Domain 'Security').Keys.Count | Should -Be 2
    }
}

Describe 'Domain grouping and caps' {
    It 'caps exact domain labels independently' {
        $MaxFindings = 1
        try {
            $precomposed = [string][char]0x00E9
            $decomposed = "e$([char]0x0301)"
            $labels = @('API', 'api', $precomposed, $decomposed, 'A B', 'A  B', 'C#', 'C++')
            $rawFindings = [System.Collections.Generic.List[object]]::new()
            $line = 0
            foreach ($label in $labels) {
                $line++
                $rawFindings.Add(@{
                    id = "high-$line"; domain = $label; severity = 'major'; message = 'First'
                    location = @{ file = 'src/a.al'; line = $line }; references = @()
                }) | Out-Null
                $line++
                $rawFindings.Add(@{
                    id = "medium-$line"; domain = $label; severity = 'minor'; message = 'Second'
                    location = @{ file = 'src/a.al'; line = $line }; references = @()
                }) | Out-Null
            }
            $json = @{
                outcome = 'completed'
                findings = @($rawFindings)
            } | ConvertTo-Json -Depth 8

            $findings = (ConvertFrom-BCQualityReport -Output $json).Findings
            $findings.Count | Should -Be $labels.Count
            foreach ($label in $labels) {
                $domainFindings = @($findings | Where-Object {
                    [System.StringComparer]::Ordinal.Equals($_.domain, $label)
                })
                $domainFindings.Count | Should -Be 1
                $domainFindings[0].severity | Should -BeExactly 'High'
            }
        }
        finally {
            $MaxFindings = 25
        }
    }

    It 'keeps exact labels distinct through posting collections and summaries' {
        $precomposed = [string][char]0x00E9
        $decomposed = "e$([char]0x0301)"
        $labels = @('API', 'api', $precomposed, $decomposed, 'A B', 'A  B', 'C#', 'C++')
        $findings = @($labels | ForEach-Object {
            [pscustomobject]@{ domain = $_; isAgentFinding = $false }
        })
        Mock Publish-Findings {
            [pscustomobject]@{ inline = $Findings.Count; fallback = 0 }
        }

        $summary = Publish-FindingsByDomain -Findings $findings -LineMaps @{} -ChangedFileSet @{}
        $summary.Count | Should -Be $labels.Count
        foreach ($label in $labels) {
            $summary.ContainsKey($label) | Should -BeTrue
            $summary[$label].findings | Should -Be 1
            Should -Invoke Publish-Findings -Times 1 -ParameterFilter {
                [System.StringComparer]::Ordinal.Equals($Domain, $label)
            }
        }

        $body = Build-SummaryBody -Outcome completed -OutcomeReason '' -DomainSummary $summary `
            -Suppressed @() -SkippedSubSkills @() -FilterReport $null
        foreach ($label in $labels) {
            $safeLabel = ConvertTo-MarkdownTableCell -Value $label
            $body.Contains("| $safeLabel | 1 | 1 | 0 | 1 | 0 |") |
                Should -BeTrue -Because "the summary must contain the exact '$label' label"
        }
    }

    It 'keeps consumed-skill fallback domains distinct' {
        $report = [pscustomobject]@{
            SubResults = @()
            Findings = @(
                [pscustomobject]@{ domain = 'API'; references = @() },
                [pscustomobject]@{ domain = 'api'; references = @() }
            )
        }
        Mock Write-Host {}

        Write-ConsumedBCQualityLog -Report $report

        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq 'Sub-skills executed (2):' }
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq '  - API (findings=1)' }
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -eq '  - api (findings=1)' }
    }
}

Describe 'Domain rendering safety' {
    It 'preserves domain case in fallback text' {
        $finding = [pscustomobject]@{
            domain = 'API'
            severity = 'High'
            issue = ''
            recommendation = ''
            suggestedCode = ''
            references = @()
            isAgentFinding = $false
        }

        Build-CommentBody -Finding $finding | Should -Match 'High API finding'
    }

    It 'renders Markdown-active domain punctuation literally' {
        $finding = [pscustomobject]@{
            domain = '$@[API](//example): ~~C#~~!$'
            severity = 'High'
            issue = ''
            recommendation = ''
            suggestedCode = ''
            references = @()
            isAgentFinding = $false
        }

        Build-CommentBody -Finding $finding |
            Should -Match 'High &#36;&#64;\\\[API\\\]\\\(//example\\\)&#58; \\\~\\\~C\\#\\\~\\\~\\\!&#36; finding'
    }

    It 'shows agent provenance for an exact lowercase agent label' {
        $finding = [pscustomobject]@{
            domain = 'agent'
            severity = 'High'
            issue = 'Review judgement.'
            recommendation = ''
            suggestedCode = ''
            references = @()
            isAgentFinding = $true
        }

        Build-CommentBody -Finding $finding |
            Should -Match 'Agent judgement — not directly backed'
    }

    It 'preserves Unicode numeric entities while escaping Markdown' {
        ConvertTo-MarkdownTableCell -Value ([string][char]0x00E9) |
            Should -BeExactly '&#233;'
        ConvertTo-MarkdownTableCell -Value "e$([char]0x0301)" |
            Should -BeExactly "e$([char]0x0301)"
    }

    It 'escapes domain labels in LaTeX comment preheaders' {
        $finding = [pscustomobject]@{
            domain = 'API | 100%_safe & C#'
            severity = 'High'
            issue = 'Use the safe API.'
            recommendation = ''
            suggestedCode = ''
            references = @()
            isAgentFinding = $false
        }
        $body = Build-CommentBody -Finding $finding

        $body | Should -Match '100\\%\\_safe'
        $body | Should -Match '\\&'
        $body | Should -Match 'C\\#'
        $body | Should -Not -Match '<!-- agent_domain:'
    }

    It 'escapes markdown table separators, formatting, and HTML' {
        $summary = @{
            'API | 100%_safe & <test> $math$ @team :smile:' = @{
                findings = 1; knowledgeBacked = 1; agentFindings = 0; inline = 1; fallback = 0
            }
        }
        $body = Build-SummaryBody -Outcome completed -OutcomeReason '' -DomainSummary $summary `
            -Suppressed @() -SkippedSubSkills @() -FilterReport $null

        $body | Should -Match 'API \\\| 100%\\_safe &amp; &lt;test&gt; &#36;math&#36; &#64;team &#58;smile&#58;'
    }

    It 'renders failed sub-skills separately from intentionally skipped sub-skills' {
        $body = Build-SummaryBody -Outcome partial -OutcomeReason 'One review domain failed.' `
            -DomainSummary @{} -Suppressed @() `
            -SkippedSubSkills @([pscustomobject]@{ id = 'al-testing-review'; reason = 'configuration' }) `
            -FailedSubSkills @([pscustomobject]@{
                id = 'al-error-handling-review'
                reason = 'Leaf report failed schema validation.'
            }) `
            -FilterReport $null

        $body | Should -Match '### Sub-skills skipped'
        $body | Should -Match 'al-testing-review — configuration'
        $body | Should -Match '### Sub-skills failed — review coverage is incomplete'
        $body | Should -Match '\| al-error-handling-review \| Leaf report failed schema validation\. \|'
    }

    It 'uses a bounded fallback when a failed sub-skill has no report explanation' {
        $body = Build-SummaryBody -Outcome partial -OutcomeReason '' -DomainSummary @{} `
            -Suppressed @() -SkippedSubSkills @() `
            -FailedSubSkills @([pscustomobject]@{ id = 'al-query-review'; reason = '' }) `
            -FilterReport $null

        $body | Should -Match 'al-query-review'
        $body | Should -Match 'Failed without a report-provided explanation; see the run manifest'
    }

    It 'omits the failed sub-skills section when no sub-result failed' {
        $body = Build-SummaryBody -Outcome completed -OutcomeReason '' -DomainSummary @{} `
            -Suppressed @([pscustomobject]@{ path = 'microsoft/knowledge/a.md'; reason = 'configuration' }) `
            -SkippedSubSkills @([pscustomobject]@{ id = 'al-testing-review'; reason = 'not-applicable' }) `
            -FailedSubSkills @() -FilterReport $null

        $body | Should -Match 'Knowledge files suppressed'
        $body | Should -Match '### Sub-skills skipped'
        $body | Should -Not -Match 'Sub-skills failed'
    }
}

Describe 'Deterministic leaf orchestration contract' {
    BeforeEach {
        $BCQualityRoot = Join-Path $TestDrive 'deterministic-bcquality'
        $ReviewOutputDir = Join-Path $TestDrive 'review-output'
        $ReviewStartedAt = [DateTime]::UtcNow.AddSeconds(-5)
        $CopilotCliVersion = '1.0.83'
        $CopilotModel = 'claude-sonnet-5'
        $LeafModel = 'gpt-5.4'
        $CopilotLogLevel = 'info'
        $GitHubServerUrl = 'https://github.com'
        $script:CopilotExecutable = 'C:\tools\copilot.exe'
        $LeafExecution = 'serial'
        $MaxLeafConcurrency = 4
        $CopilotCliTimeoutMinutes = 30
        $MinimumSeverity = 'Low'
        $AgentMinimumSeverity = 'Low'
        $ReviewSource = 'local'
        $BCQualityVersion = '1.7'
        $AgentVersion = '1.0.0'
        $ReportFileName = '_review-report.json'
        $AgentWorkDir = $BCQualityRoot
        $AnalysisWorkspace = Join-Path $TestDrive 'source-snapshot'
        New-Item -ItemType Directory -Path $AnalysisWorkspace -Force | Out-Null
        $DiffRange = 'origin/main...HEAD'
        $script:AgentTranscript = ''
        $script:CopilotOtelRecords = @()
        $script:CopilotOtelMalformedRecords = 0
        $script:FailedLeafReviews = @()
        $script:ReviewProcessTelemetry = [System.Collections.Generic.List[object]]::new()
        $script:ReviewRunCompletedAt = $null
        $script:ObservedCopilotCliVersion = '1.0.83'
        New-Item -ItemType Directory -Path (Join-Path $BCQualityRoot 'microsoft/skills/review') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $BCQualityRoot 'skills') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $BCQualityRoot 'schemas') -Force | Out-Null
        @'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["skill", "findings", "suppressed"],
  "properties": {
    "skill": {
      "type": "object",
      "required": ["id"],
      "properties": { "id": { "type": "string" } }
    },
    "outcome": { "type": "string" },
    "outcome-reason": { "type": "string" },
    "summary": { "type": "object" },
    "findings": { "type": "array", "items": { "$ref": "#/definitions/finding" } },
    "references": { "type": "array" },
    "suppressed": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["reference"],
        "properties": { "reference": { "type": "object" } }
      }
    },
    "sub-results": { "type": "array", "items": { "$ref": "#" } },
    "skipped-sub-skills": { "type": "array" }
  },
  "definitions": {
    "finding": { "type": "object", "properties": { "location": { "$ref": "#/definitions/location" } } },
    "location": {
      "type": "object",
      "required": ["file", "line"],
      "properties": {
        "file": { "type": "string" },
        "line": { "type": "integer", "minimum": 1 },
        "range": {
          "type": "object",
          "required": ["start-line", "end-line"],
          "properties": {
            "start-line": { "type": "integer", "minimum": 1 },
            "end-line": { "type": "integer", "minimum": 1 }
          }
        }
      }
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $BCQualityRoot 'schemas/findings-report.schema.json')
        $LeafReportSchemaFileName = '_review-findings-report.leaf.schema.json'
        $RootReportSchemaFileName = '_review-findings-report.root.schema.json'
        Initialize-FindingsConsumerContext -SourcePaths @()
        Initialize-FindingsReportRoleSchemas
        Set-Content -LiteralPath (Join-Path $BCQualityRoot 'microsoft/skills/review/al-security-review.md') -Value '# security'
        Set-Content -LiteralPath (Join-Path $BCQualityRoot 'microsoft/skills/review/al-style-review.md') -Value '# style'

        @{
            version = 1
            skills = @(
                @{
                    id = 'al-code-review'
                    path = 'microsoft/skills/review/al-code-review.md'
                    version = 1
                    outputs = @('findings-report')
                    subSkills = @(
                        'microsoft/skills/review/al-security-review.md',
                        'microsoft/skills/review/al-style-review.md'
                    )
                },
                @{
                    id = 'al-security-review'
                    path = 'microsoft/skills/review/al-security-review.md'
                    version = 1
                    outputs = @('findings-report')
                    subSkills = @()
                },
                @{
                    id = 'al-style-review'
                    path = 'microsoft/skills/review/al-style-review.md'
                    version = 1
                    outputs = @('findings-report')
                    subSkills = @()
                }
            )
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $BCQualityRoot '_skill-index.json')

        $script:BCQualitySettingsCache = @{
            enabledLayers = @('microsoft')
            disabledSkills = @()
        }
        $script:TestLeafReports = @{}
        $script:TestLeafMetrics = [pscustomobject]@{
            models = @('gpt-5.4')
            usage_complete = $true
            malformed_records = 0
            cli_version = '1.0.83'
            total_tokens = 12
        }

        Mock Save-CopilotRunMetrics { $script:TestLeafMetrics }
        Mock Start-LeafCopilotProcess {
            param($Leaf, $WorkDir)

            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
            $script:TestLeafReports[$Leaf.id] |
                ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath (Join-Path $WorkDir $ReportFileName)
            $process = [pscustomobject]@{
                HasExited = $true
                ExitCode = 0
            }
            $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
            return [pscustomobject]@{
                Leaf = $Leaf
                WorkDir = $WorkDir
                OtelPath = Join-Path $WorkDir 'missing-otel.jsonl'
                Process = $process
                StdoutTask = [System.Threading.Tasks.Task]::FromResult([string]'')
                StderrTask = [System.Threading.Tasks.Task]::FromResult([string]'')
                StartedAt = [DateTime]::UtcNow.AddSeconds(-1)
            }
        }
    }

    It 'resolves leaves in the exact order declared by BCQuality' {
        $plan = @(Get-ReviewLeafPlan)

        $plan.id | Should -Be @('al-security-review', 'al-style-review')
        $plan.ordinal | Should -Be @(1, 2)
    }

    It 'removes configured disabled leaves without reordering the remainder' {
        $script:BCQualitySettingsCache.disabledSkills = @(
            'microsoft/skills/review/al-security-review.md'
        )

        $plan = @(Get-ReviewLeafPlan)

        $plan.id | Should -Be @('al-style-review')
        $plan.ordinal | Should -Be 2
    }

    It 'pins a leaf process to one skill and forbids child-agent delegation' {
        $AnalysisWorkspace = 'C:\review-target'
        $DiffRange = 'origin/main...HEAD'
        $ReviewPathSpec = ''
        $LeafModel = 'gpt-5.6-luna'
        $ReportFileName = '_review-report.json'
        $leaf = (Get-ReviewLeafPlan)[0]

        $prompt = New-LeafReviewPrompt -Leaf $leaf -WorkDir $TestDrive

        $prompt | Should -Match "Review only the domain defined by BCQuality leaf skill 'al-security-review'"
        $prompt | Should -Match "pinned mechanically to model 'gpt-5\.6-luna'"
        $prompt | Should -Match 'Do not invoke child agents or other review skills'
        $prompt | Should -Match ([regex]::Escape('./_review-findings-report.leaf.schema.json'))
        $prompt | Should -Match ([regex]::Escape('./_review-source-bounds.json'))
        $prompt | Should -Match 'final source file, NOT\s+patch/diff lines'
        $prompt | Should -Match 'Findings without location remain permitted'
        $prompt | Should -Match 'sub-results and skipped-sub-skills are super-skill-only fields and MUST NOT\s+appear, not even as empty arrays'
        $prompt | Should -Not -Match ([regex]::Escape('schemas/findings-report.schema.json'))
    }

    It 'writes engine-derived role schemas as run artifacts and copies the leaf contract to each leaf' {
        $leafPath = Join-Path $AgentWorkDir '_review-findings-report.leaf.schema.json'
        $rootPath = Join-Path $AgentWorkDir '_review-findings-report.root.schema.json'

        (Get-Content -LiteralPath $leafPath -Raw).TrimEnd() | Should -Be (Get-FindingsReportRoleSchema -Role leaf)
        (Get-Content -LiteralPath $rootPath -Raw).TrimEnd() | Should -Be (Get-FindingsReportRoleSchema -Role root)
        (Get-Content -LiteralPath $leafPath -Raw | ConvertFrom-Json).properties.PSObject.Properties.Name |
            Should -Not -Contain 'sub-results'

        $startCommand = Get-Command Start-LeafCopilotProcess -CommandType Function
        $startCommand.ScriptBlock.Ast.Extent.Text | Should -Match '\$LeafReportSchemaFileName'
        $startCommand.ScriptBlock.Ast.Extent.Text | Should -Match '_review-source-bounds.json'
    }

    It 'validates against the engine-held contract rather than the model-writable schema file' {
        Set-Content -LiteralPath (Join-Path $AgentWorkDir '_review-findings-report.leaf.schema.json') -Value '{}'
        $plan = @(Get-ReviewLeafPlan)
        $script:TestLeafReports['al-security-review'] = @{
            skill = @{ id = 'al-security-review' }
            findings = @()
            suppressed = @()
            unexpected = $true
        }

        $results = @(Invoke-DeterministicLeafReviews -Plan @($plan[0]))

        $results.Count | Should -Be 0
        $script:FailedLeafReviews[0].Reason | Should -Match 'false schema at ''/unexpected'''
    }

    It 'refuses to validate before role-specific schemas are initialized' {
        $script:FindingsReportRoleSchemas = $null

        { Get-FindingsReportRoleSchema -Role leaf } |
            Should -Throw '*schemas were not initialized*'
    }

    It 'repairs an omitted suppressed array without inventing suppressed items' {
        $report = [pscustomobject]@{
            skill = [pscustomobject]@{ id = 'al-security-review' }
            findings = @()
        }

        Repair-MissingSuppressedProperty -ReportObject $report | Should -BeTrue
        $report.PSObject.Properties.Match('suppressed').Count | Should -Be 1
        @($report.suppressed).Count | Should -Be 0

        $malformedSuppressed = [pscustomobject]@{
            skill = [pscustomobject]@{ id = 'al-security-review' }
            suppressed = @([pscustomobject]@{})
        }
        Repair-MissingSuppressedProperty -ReportObject $malformedSuppressed | Should -BeFalse
        $malformedSuppressed.suppressed[0].PSObject.Properties.Match('reference').Count | Should -Be 0
    }

    It 'rejects super-skill-only fields in an otherwise schema-valid leaf report' {
        $report = [pscustomobject]@{
            skill = [pscustomobject]@{ id = 'al-security-review' }
            findings = @()
            suppressed = @()
            'sub-results' = @()
            'skipped-sub-skills' = @()
        }

        { Assert-LeafReportRole -ReportObject $report } |
            Should -Throw '*super-skill-only field(s): sub-results, skipped-sub-skills*'
    }

    It 'marks a schema-valid leaf with super-skill fields failed during orchestration' {
        $plan = @(Get-ReviewLeafPlan)
        $script:TestLeafReports['al-security-review'] = @{
            skill = @{ id = 'al-security-review' }
            findings = @()
            suppressed = @()
            'sub-results' = @()
            'skipped-sub-skills' = @()
        }

        $results = @(Invoke-DeterministicLeafReviews -Plan @($plan[0]))

        $results.Count | Should -Be 0
        $script:FailedLeafReviews[0].Leaf.id | Should -Be 'al-security-review'
        $script:FailedLeafReviews[0].Reason |
            Should -Match 'super-skill-only field'
    }

    It 'marks a completed leaf with only <Field> failed during orchestration' -ForEach @(
        @{ Field = 'sub-results' },
        @{ Field = 'skipped-sub-skills' }
    ) {
        $plan = @(Get-ReviewLeafPlan)
        $script:TestLeafReports['al-security-review'] = @{
            skill = @{ id = 'al-security-review' }
            outcome = 'completed'
            findings = @(@{ id = 'agent:x' })
            suppressed = @()
            $Field = @()
        }

        $results = @(Invoke-DeterministicLeafReviews -Plan @($plan[0]))

        $results.Count | Should -Be 0
        $script:FailedLeafReviews[0].Reason |
            Should -Match "super-skill-only field\(s\): $Field\."
    }

    It 'rejects a consolidated report whose sub-result carries <Field>' -ForEach @(
        @{ Field = 'sub-results' },
        @{ Field = 'skipped-sub-skills' }
    ) {
        $plan = @(Get-ReviewLeafPlan)
        $nested = @{ skill = @{ id = 'al-security-review'; version = 1 }; outcome = 'not-applicable'; findings = @(); suppressed = @() }
        $nested[$Field] = @()
        $report = @{
            skill = @{ id = 'al-code-review'; version = 1 }
            outcome = 'completed'
            findings = @()
            suppressed = @()
            'sub-results' = @(
                $nested,
                @{ skill = @{ id = 'al-style-review'; version = 1 }; outcome = 'completed'; findings = @(); suppressed = @() }
            )
            'skipped-sub-skills' = @()
        } | ConvertTo-Json -Depth 10

        $rejection = { Assert-ConsolidatedReport -ReportText $report -Plan $plan } | Should -Throw -PassThru
        # Test-Json versions either throw the schema diagnostic or return false.
        $rejection.Exception.Message |
            Should -Match "(Root consolidation output does not conform to the root findings-report schema|false schema at '/sub-results/0/$Field')"
    }

    It 'rejects a consolidated report without sub-results' {
        $report = @{
            skill = @{ id = 'al-code-review'; version = 1 }
            outcome = 'completed'
            findings = @()
            suppressed = @()
        } | ConvertTo-Json -Depth 10

        { Assert-ConsolidatedReport -ReportText $report -Plan @(Get-ReviewLeafPlan) } |
            Should -Throw '*Required properties `["sub-results"`] are not present*'
    }

    It 'points root consolidation at the root role schema' {
        $AnalysisWorkspace = 'C:\review-target'
        $DiffRange = 'origin/main...HEAD'
        $leafResults = @([pscustomobject]@{ ReportPath = 'C:\out\01-security\_review-report.json' })

        $prompt = Build-ConsolidationPrompt -LeafResults $leafResults

        $prompt | Should -Match ([regex]::Escape('./_review-findings-report.root.schema.json'))
        $prompt | Should -Match 'every\s+sub-result is a leaf report that MUST NOT contain sub-results or\s+skipped-sub-skills'
    }

    It 'accepts a normal leaf report without super-skill fields' {
        $report = [pscustomobject]@{
            skill = [pscustomobject]@{ id = 'al-security-review' }
            findings = @()
            suppressed = @()
        }

        { Assert-LeafReportRole -ReportObject $report } | Should -Not -Throw
    }

    It 'reconciles final status from leaf coverage and the validated root report' {
        $plan = @(Get-ReviewLeafPlan)
        $complete = [pscustomobject]@{
            outcome = 'completed'
            'sub-results' = @(
                [pscustomobject]@{ outcome = 'completed' },
                [pscustomobject]@{ outcome = 'not-applicable' }
            )
        }
        $partialRoot = [pscustomobject]@{
            outcome = 'completed'
            'sub-results' = @(
                [pscustomobject]@{ outcome = 'completed' },
                [pscustomobject]@{ outcome = 'failed' }
            )
        }
        $failedRoot = [pscustomobject]@{
            outcome = 'failed'
            'sub-results' = @(
                [pscustomobject]@{ outcome = 'failed' },
                [pscustomobject]@{ outcome = 'failed' }
            )
        }
        $allLeaves = @([pscustomobject]@{ Leaf = $plan[0] }, [pscustomobject]@{ Leaf = $plan[1] })
        $oneLeaf = @([pscustomobject]@{ Leaf = $plan[0] })

        Get-ConsolidatedReviewStatus -Plan $plan -LeafResults $allLeaves -Report $complete |
            Should -Be 'completed'
        Get-ConsolidatedReviewStatus -Plan $plan -LeafResults $oneLeaf -Report $complete |
            Should -Be 'partial'
        Get-ConsolidatedReviewStatus -Plan $plan -LeafResults $allLeaves -Report $partialRoot |
            Should -Be 'partial'
        Get-ConsolidatedReviewStatus -Plan $plan -LeafResults $allLeaves -Report $failedRoot |
            Should -Be 'failed'
    }

    It 'harvests OTel before recovering a nonzero leaf exit' {
        $workDir = Join-Path $TestDrive 'nonzero-leaf'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        $otel = @(
            '{"type":"span","attributes":{"gen_ai.operation.name":"invoke_agent","gen_ai.agent.version":"1.0.83"}}',
            '{"type":"span","status":{"code":2},"attributes":{"gen_ai.operation.name":"chat","gen_ai.request.model":"gpt-5.4","gen_ai.usage.input_tokens":90,"gen_ai.usage.output_tokens":10}}'
        )
        Set-Content -LiteralPath (Join-Path $workDir 'otel.jsonl') -Value $otel
        $process = [pscustomobject]@{ HasExited = $true; ExitCode = 7 }
        $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        Mock Save-CopilotRunMetrics {
            param($Records, $WallTimeSeconds, $MalformedRecords)
            Get-CopilotRunMetrics -Records $Records -WallTimeSeconds $WallTimeSeconds -MalformedRecords $MalformedRecords
        }
        $leaf = @(Get-ReviewLeafPlan)[0]
        $state = [pscustomobject]@{
            Leaf = $leaf
            WorkDir = $workDir
            OtelPath = Join-Path $workDir 'otel.jsonl'
            Process = $process
            StdoutTask = [System.Threading.Tasks.Task]::FromResult([string]'')
            StderrTask = [System.Threading.Tasks.Task]::FromResult([string]'')
            StartedAt = [DateTime]::UtcNow.AddSeconds(-1)
        }

        $result = Receive-LeafCopilotProcess -State $state

        $result | Should -BeNullOrEmpty
        $script:CopilotOtelRecords.Count | Should -Be 2
        $failed = @($script:ReviewProcessTelemetry | Where-Object status -eq 'failed')
        $failed[0].metrics.total_tokens | Should -Be 100
        $failed[0].failure_reason | Should -Match 'exited with code 7'
    }

    It 'harvests OTel before recovering a timed-out leaf' {
        $workDir = Join-Path $TestDrive 'timeout-leaf'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        @(
            '{"type":"span","attributes":{"gen_ai.operation.name":"invoke_agent","gen_ai.agent.version":"1.0.83"}}',
            '{"type":"span","status":{"code":2},"attributes":{"gen_ai.operation.name":"chat","gen_ai.request.model":"gpt-5.4","gen_ai.usage.input_tokens":40,"gen_ai.usage.output_tokens":6}}'
        ) | Set-Content -LiteralPath (Join-Path $workDir 'otel.jsonl')
        $process = [pscustomobject]@{ HasExited = $true; ExitCode = 0 }
        $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        Mock Save-CopilotRunMetrics {
            param($Records, $WallTimeSeconds, $MalformedRecords)
            Get-CopilotRunMetrics -Records $Records -WallTimeSeconds $WallTimeSeconds -MalformedRecords $MalformedRecords
        }
        $leaf = @(Get-ReviewLeafPlan)[0]
        $oldTimeout = $CopilotCliTimeoutMinutes
        $CopilotCliTimeoutMinutes = 1
        try {
            $state = [pscustomobject]@{
                Leaf = $leaf
                WorkDir = $workDir
                OtelPath = Join-Path $workDir 'otel.jsonl'
                Process = $process
                StdoutTask = [System.Threading.Tasks.Task]::FromResult([string]'')
                StderrTask = [System.Threading.Tasks.Task]::FromResult([string]'')
                StartedAt = [DateTime]::UtcNow.AddMinutes(-2)
            }

            $result = Receive-LeafCopilotProcess -State $state

            $result | Should -BeNullOrEmpty
            $script:CopilotOtelRecords.Count | Should -Be 2
            $failed = @($script:ReviewProcessTelemetry | Where-Object status -eq 'failed')
            $failed[0].metrics.total_tokens | Should -Be 46
            $failed[0].failure_reason | Should -Match 'timed out'
        }
        finally {
            $CopilotCliTimeoutMinutes = $oldTimeout
        }
    }

    It 'records an uncontrolled timed-out leaf before refusing to drain output' {
        $workDir = Join-Path $TestDrive 'uncontrolled-timeout-leaf'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        $process = [pscustomobject]@{ HasExited = $false; ExitCode = $null }
        $process | Add-Member -MemberType ScriptMethod -Name Kill -Value {
            param($EntireProcessTree)
            $EntireProcessTree | Should -BeTrue
        }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
            param($Milliseconds)
            $Milliseconds | Should -BeGreaterThan 0
            return $false
        }
        $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        $script:OutputDrainAttempted = $false
        $stdoutTask = [pscustomobject]@{}
        $stdoutTask | Add-Member -MemberType ScriptMethod -Name GetAwaiter -Value {
            $script:OutputDrainAttempted = $true
            throw 'stdout drain must not be attempted'
        }
        $stderrTask = [pscustomobject]@{}
        $stderrTask | Add-Member -MemberType ScriptMethod -Name GetAwaiter -Value {
            $script:OutputDrainAttempted = $true
            throw 'stderr drain must not be attempted'
        }
        Mock Add-ReviewProcessTelemetry {}
        Mock Save-ReviewRunManifest {}
        $leaf = @(Get-ReviewLeafPlan)[0]
        $oldTimeout = $CopilotCliTimeoutMinutes
        $CopilotCliTimeoutMinutes = 1
        try {
            $state = [pscustomobject]@{
                Leaf = $leaf
                WorkDir = $workDir
                OtelPath = Join-Path $workDir 'otel.jsonl'
                Process = $process
                StdoutTask = $stdoutTask
                StderrTask = $stderrTask
                StartedAt = [DateTime]::UtcNow.AddMinutes(-2)
            }

            { Receive-LeafCopilotProcess -State $state } |
                Should -Throw "*remained running after timeout kill*"
            $script:OutputDrainAttempted | Should -BeFalse
            Should -Invoke Add-ReviewProcessTelemetry -Times 1 -Exactly -ParameterFilter {
                $Status -eq 'failed' -and
                $FailureReason -match 'remained running after timeout kill'
            }
            Should -Invoke Save-ReviewRunManifest -Times 1 -Exactly -ParameterFilter {
                $Status -eq 'failed' -and
                $FailureReason -match 'remained running after timeout kill'
            }
        }
        finally {
            $CopilotCliTimeoutMinutes = $oldTimeout
        }
    }

    It 'hard-fails a nonzero leaf when harvested OTel has the wrong model' {
        $workDir = Join-Path $TestDrive 'nonzero-wrong-model'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        @(
            '{"type":"span","attributes":{"gen_ai.operation.name":"invoke_agent","gen_ai.agent.version":"1.0.83"}}',
            '{"type":"span","status":{"code":2},"attributes":{"gen_ai.operation.name":"chat","gen_ai.request.model":"gemini-3.6-flash","gen_ai.usage.input_tokens":90,"gen_ai.usage.output_tokens":10}}'
        ) | Set-Content -LiteralPath (Join-Path $workDir 'otel.jsonl')
        $process = [pscustomobject]@{ HasExited = $true; ExitCode = 7 }
        $process | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        Mock Save-CopilotRunMetrics {
            param($Records, $WallTimeSeconds, $MalformedRecords)
            Get-CopilotRunMetrics -Records $Records -WallTimeSeconds $WallTimeSeconds -MalformedRecords $MalformedRecords
        }
        $leaf = @(Get-ReviewLeafPlan)[0]
        $state = [pscustomobject]@{
            Leaf = $leaf
            WorkDir = $workDir
            OtelPath = Join-Path $workDir 'otel.jsonl'
            Process = $process
            StdoutTask = [System.Threading.Tasks.Task]::FromResult([string]'')
            StderrTask = [System.Threading.Tasks.Task]::FromResult([string]'')
            StartedAt = [DateTime]::UtcNow.AddSeconds(-1)
        }

        { Receive-LeafCopilotProcess -State $state } |
            Should -Throw "*required model 'gpt-5.4'*"
        $script:CopilotOtelRecords.Count | Should -Be 2
    }

    It 'consolidates only after ordered leaf reports exist and forbids leaf retries' {
        $AnalysisWorkspace = 'C:\review-target'
        $DiffRange = 'origin/main...HEAD'
        $ReportFileName = '_review-report.json'
        $AgentWorkDir = $TestDrive
        $leafResults = @(
            [pscustomobject]@{ ReportPath = 'C:\out\01-security\_review-report.json' },
            [pscustomobject]@{ ReportPath = 'C:\out\02-style\_review-report.json' }
        )

        $prompt = Build-ConsolidationPrompt -LeafResults $leafResults

        $prompt.IndexOf('01-security') | Should -BeLessThan $prompt.IndexOf('02-style')
        $prompt | Should -Match 'Do not invoke child agents, Task tools, or leaf skills'
        $prompt | Should -Match 'Do not omit, retry, or replace any leaf report'
    }

    It 'surfaces failed leaves to root consolidation as failed rather than skipped' {
        $AnalysisWorkspace = 'C:\review-target'
        $DiffRange = 'origin/main...HEAD'
        $ReportFileName = '_review-report.json'
        $AgentWorkDir = $TestDrive
        $leafResults = @(
            [pscustomobject]@{ ReportPath = 'C:\out\01-security\_review-report.json' }
        )
        $failedLeaves = @(
            [pscustomobject]@{
                Leaf = [pscustomobject]@{ id = 'al-style-review' }
                Reason = 'report does not conform to the findings-report schema'
            }
        )

        $prompt = Build-ConsolidationPrompt -LeafResults $leafResults -FailedLeaves $failedLeaves

        $prompt | Should -Match 'al-style-review: failed before a usable findings-report was available'
        $prompt | Should -Match "outcome 'failed'"
        $prompt | Should -Match 'Failed leaves are distinct from\s+skipped'
    }

    It 'parses failed sub-results and their schema-defined outcome reasons' {
        $report = @{
            skill = @{ id = 'al-code-review'; version = 1 }
            outcome = 'partial'
            'outcome-reason' = 'One leaf failed.'
            summary = @{
                counts = @{ blocker = 0; major = 0; minor = 0; info = 0 }
                coverage = @{ 'worklist-size' = 2; 'items-evaluated' = 1 }
            }
            findings = @()
            suppressed = @()
            'sub-results' = @(
                @{
                    skill = @{ id = 'al-security-review'; version = 1 }
                    outcome = 'completed'
                    summary = @{
                        counts = @{ blocker = 0; major = 0; minor = 0; info = 0 }
                        coverage = @{ 'worklist-size' = 1; 'items-evaluated' = 1 }
                    }
                    findings = @()
                    suppressed = @()
                },
                @{
                    skill = @{ id = 'al-style-review'; version = 1 }
                    outcome = 'failed'
                    'outcome-reason' = 'Schema-invalid leaf report.'
                    summary = @{
                        counts = @{ blocker = 0; major = 0; minor = 0; info = 0 }
                        coverage = @{ 'worklist-size' = 1; 'items-evaluated' = 0 }
                    }
                    findings = @()
                    suppressed = @()
                }
            )
            'skipped-sub-skills' = @()
        } | ConvertTo-Json -Depth 20

        $parsed = ConvertFrom-BCQualityReport -Output $report

        $parsed.FailedSubSkills.Count | Should -Be 1
        $parsed.FailedSubSkills[0].id | Should -Be 'al-style-review'
        $parsed.FailedSubSkills[0].reason | Should -Be 'Schema-invalid leaf report.'
        $parsed.SkippedSubSkills.Count | Should -Be 0
    }

    It 'continues after a schema-invalid leaf and records partial coverage' {
        $plan = @(Get-ReviewLeafPlan)
        $script:TestLeafReports['al-security-review'] = @{
            skill = @{ id = 'al-security-review' }
            findings = @()
        }
        $script:TestLeafReports['al-style-review'] = @{
            skill = @{ id = 'al-style-review' }
            findings = @()
            suppressed = @(@{ reason = 'missing reference' })
        }

        $results = @(Invoke-DeterministicLeafReviews -Plan $plan)
        $status = Assert-UsableLeafReviewCoverage -Plan $plan -LeafResults $results
        $prompt = Build-ConsolidationPrompt -LeafResults $results -FailedLeaves $script:FailedLeafReviews
        Save-ReviewRunManifest -Status $status

        $results.Count | Should -Be 1
        $results[0].Leaf.id | Should -Be 'al-security-review'
        $status | Should -Be 'partial'
        $prompt | Should -Match 'al-style-review: failed before a usable findings-report was available'
        $repaired = Get-Content -LiteralPath $results[0].ReportPath -Raw | ConvertFrom-Json
        $repaired.PSObject.Properties.Match('suppressed').Count | Should -Be 1
        @($repaired.suppressed).Count | Should -Be 0
        $original = Get-Content (Join-Path (Split-Path $results[0].ReportPath) '_review-report.raw.json') -Raw | ConvertFrom-Json
        $original.PSObject.Properties.Match('suppressed').Count | Should -Be 0
        $script:TestLeafReports['al-style-review'].suppressed[0].ContainsKey('reference') | Should -BeFalse

        $manifest = Get-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw |
            ConvertFrom-Json
        $manifest.status | Should -Be 'partial'
        @($manifest.processes | Where-Object status -eq 'completed').Count | Should -Be 1
        @($manifest.processes | Where-Object status -eq 'failed').Count | Should -Be 1
        ($manifest.processes | Where-Object status -eq 'failed').skill_id | Should -Be 'al-style-review'
        ($manifest.processes | Where-Object status -eq 'failed').failure_reason |
            Should -Match '(Leaf report does not conform to the leaf findings-report schema|Required properties.*reference)'
    }

    It 'fails before root consolidation when every leaf report is unusable' {
        $plan = @(Get-ReviewLeafPlan)
        foreach ($leaf in $plan) {
            $script:TestLeafReports[$leaf.id] = @{
                skill = @{ id = $leaf.id }
                findings = @()
                suppressed = @(@{ reason = 'missing reference' })
            }
        }

        $results = @(Invoke-DeterministicLeafReviews -Plan $plan)

        $results.Count | Should -Be 0
        { Assert-UsableLeafReviewCoverage -Plan $plan -LeafResults $results } |
            Should -Throw '*All 2 deterministic review leaves failed*root consolidation was not run*'
        $manifest = Get-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw |
            ConvertFrom-Json
        $manifest.status | Should -Be 'failed'
        @($manifest.processes | Where-Object status -eq 'completed').Count | Should -Be 0
        @($manifest.processes | Where-Object status -eq 'failed').Count | Should -Be 2
        @($manifest.processes | Where-Object status -eq 'failed').skill_id |
            Should -Be @('al-security-review', 'al-style-review')
    }

    It 'rejects a consumer-invalid leaf before consolidation without salvaging findings or changing raw bytes' {
        $plan = @(Get-ReviewLeafPlan)
        $script:TestLeafReports['al-security-review'] = @{
            skill = @{ id = 'al-security-review' }
            findings = @(
                @{ id = 'agent:valid'; references = @(); confidence = 'medium'; severity = 'minor' },
                @{ id = 'agent:invalid'; references = @(); confidence = 'high'; severity = 'minor' }
            )
            # Deliberately omit suppressed: failed candidates must not be rewritten.
        }
        $script:TestLeafReports['al-style-review'] = @{
            skill = @{ id = 'al-style-review' }; findings = @(); suppressed = @()
        }
        $expectedBytes = [Text.Encoding]::UTF8.GetBytes(
            ($script:TestLeafReports['al-security-review'] | ConvertTo-Json -Depth 20) + [Environment]::NewLine
        )

        $results = @(Invoke-DeterministicLeafReviews -Plan $plan)
        $results.Count | Should -Be 1
        $results[0].Leaf.id | Should -Be 'al-style-review'
        $script:FailedLeafReviews.Count | Should -Be 1
        $script:FailedLeafReviews[0].Reason | Should -Match 'findings\[1\]\.confidence.*medium'
        $failedPath = Join-Path $ReviewOutputDir 'leaf-results/01-al-security-review'
        foreach ($name in @('_review-report.json', '_review-report.raw.json')) {
            [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $failedPath $name))) |
                Should -Be ([Convert]::ToBase64String($expectedBytes))
        }
        $prompt = Build-ConsolidationPrompt -LeafResults $results -FailedLeaves $script:FailedLeafReviews
        $prompt | Should -Match 'al-security-review: failed before a usable findings-report was available'
        $prompt | Should -Not -Match '01-al-security-review/_review-report.json'
        (Assert-UsableLeafReviewCoverage -Plan $plan -LeafResults $results) | Should -Be 'partial'
        $manifest = Get-Content (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw | ConvertFrom-Json
        $manifest.processes[0].status | Should -Be 'failed'
        $manifest.processes[0].failure_reason | Should -Match 'findings\[1\]\.confidence'
        Should -Invoke Start-LeafCopilotProcess -Times 2 -Exactly
    }

    It 'retains raw BOM/CRLF bytes and records only fully accepted normalization: <Valid>' -ForEach @(
        @{ Valid = $true }, @{ Valid = $false }
    ) {
        $fixture = Join-Path $PSScriptRoot 'fixtures/findings-consumer/privacy-015-normalization.json'
        $report = Get-Content $fixture -Raw | ConvertFrom-Json
        if (-not $Valid) { $report.findings[3].location.range.'end-line' = 58 }
        $script:FindingsReportRoleSchemas = New-FindingsReportRoleSchemas -SharedSchemaJson (
            Get-Content -LiteralPath $NormalizationSchemaPath -Raw
        )
        $sourceCounts = @(34, 29, 42, 57)
        for ($index = 0; $index -lt 4; $index++) {
            $script:FindingsConsumerContext.SourceFiles[$report.findings[$index].location.file] = @{
                exists = $true; line_count = $sourceCounts[$index]
            }
            $null = $script:FindingsConsumerContext.KnowledgePaths.Add($report.findings[$index].references[0].path)
        }
        $leaf = [pscustomobject]@{ id = 'al-privacy-review'; version = 1; ordinal = 1 }
        $script:ReviewPlanIds = @($leaf.id)
        $state = Start-LeafCopilotProcess -Leaf $leaf -WorkDir (Join-Path $ReviewOutputDir 'leaf-results/03-al-privacy-review') -Prompt 'unused'
        $path = Join-Path $state.WorkDir $ReportFileName
        $text = ($report | ConvertTo-Json -Depth 40) -replace '\r?\n', "`r`n"
        $bytes = [byte[]](@(0xef, 0xbb, 0xbf) + [Text.Encoding]::UTF8.GetBytes(" `r`n$text`r`n`t"))
        [IO.File]::WriteAllBytes($path, $bytes)
        $rawHash = (Get-FileHash $path).Hash

        $result = Receive-LeafCopilotProcess -State $state

        ($null -ne $result) | Should -Be $Valid
        $rawPath = Join-Path $state.WorkDir '_review-report.raw.json'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($rawPath)) |
            Should -Be ([Convert]::ToBase64String($bytes))
        $manifest = Get-Content (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw | ConvertFrom-Json
        $manifest.schema_version | Should -Be 1
        $manifest.processes.Count | Should -Be 1
        $manifest.processes[0].requested_model | Should -Be $LeafModel
        $manifest.processes[0].metrics.total_tokens | Should -Be 12
        $manifest.processes[0].report_path | Should -Be 'leaf-results/03-al-privacy-review/_review-report.json'
        if ($Valid) {
            $manifest.processes[0].status | Should -Be 'completed'
            $manifest.processes[0].normalization.raw_report_path | Should -Be 'leaf-results/03-al-privacy-review/_review-report.raw.json'
            $manifest.processes[0].normalization.raw_report_sha256 | Should -BeExactly $rawHash.ToLowerInvariant()
            $manifest.processes[0].normalization.changes.Count | Should -Be 8
            $acceptedText = Get-Content $result.ReportPath -Raw
            ($acceptedText | ConvertFrom-Json | ConvertTo-Json -Depth 40) | Should -Be ($result.Report | ConvertTo-Json -Depth 40)
            $result.Report.findings[3].id | Should -Be $report.findings[3].references[0].path
            $result.Report.findings[3].location.PSObject.Properties.Match('range').Count | Should -Be 0
            $prompt = Build-ConsolidationPrompt -LeafResults @($result)
            $prompt | Should -Match ([regex]::Escape(($result.ReportPath -replace '\\', '/')))
            $prompt | Should -Not -Match '_review-report.raw.json'
            $manifest.processes[0].normalization.changes = @()
            ($manifest | ConvertTo-Json -Depth 40 | Test-Json -SchemaFile (Join-Path $ReviewRoot 'schemas/review-run-diagnostics.schema.json') -ErrorAction SilentlyContinue) | Should -BeFalse
        } else {
            $manifest.processes[0].status | Should -Be 'failed'
            $manifest.processes[0].failure_reason | Should -Match 'findings\[3\]\.location.range.end-line'
            $manifest.processes[0].PSObject.Properties.Match('normalization').Count | Should -Be 0
            (Get-FileHash $path).Hash | Should -Be $rawHash
        }
    }

    It 'preserves exact raw bytes through <Stage> validation' -ForEach @(
        @{ Stage = 'JSON'; Payload = "{`r`ninvalid"; Valid = $false },
        @{ Stage = 'role'; Payload = '{"skill":{"id":"al-security-review"},"findings":[],"suppressed":[],"sub-results":[]}'; Valid = $false },
        @{ Stage = 'schema'; Payload = '{"skill":{"id":"al-security-review"},"findings":[],"suppressed":[{}]}'; Valid = $false },
        @{ Stage = 'source bounds'; Payload = '{"skill":{"id":"al-security-review"},"findings":[{"id":"agent:test","references":[],"confidence":"medium","severity":"minor","location":{"file":"src/Unknown.al","line":58}}],"suppressed":[]}'; Valid = $false },
        @{ Stage = 'consumer'; Payload = '{"skill":{"id":"al-security-review"},"findings":[{"id":"agent:test","references":[],"confidence":"high","severity":"minor"}],"suppressed":[]}'; Valid = $false },
        @{ Stage = 'accepted'; Payload = '{"skill":{"id":"al-security-review"},"findings":[],"suppressed":[]}'; Valid = $true }
    ) {
        $leaf = @(Get-ReviewLeafPlan)[0]
        $state = Start-LeafCopilotProcess -Leaf $leaf -WorkDir (Join-Path $TestDrive 'raw-leaf') -Prompt 'unused'
        $path = Join-Path $state.WorkDir $ReportFileName
        $bytes = [byte[]](@(0xef, 0xbb, 0xbf) + [Text.Encoding]::UTF8.GetBytes(" `r`n$Payload`r`n`t"))
        [IO.File]::WriteAllBytes($path, $bytes)

        $result = Receive-LeafCopilotProcess -State $state

        ($null -ne $result) | Should -Be $Valid
        foreach ($name in @($ReportFileName, '_review-report.raw.json')) {
            [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $state.WorkDir $name))) |
                Should -Be ([Convert]::ToBase64String($bytes))
        }
    }

    It 'stops the orchestration immediately on <Name> integrity failure' -ForEach @(
        @{
            Name = 'wrong-model'
            Metrics = [pscustomobject]@{
                models = @('gemini-3.6-flash')
                usage_complete = $true
                malformed_records = 0
                cli_version = '1.0.83'
                total_tokens = 12
            }
            ErrorPattern = "*required model 'gpt-5.4'*"
        },
        @{
            Name = 'incomplete-usage'
            Metrics = [pscustomobject]@{
                models = @('gpt-5.4')
                usage_complete = $false
                malformed_records = 0
                cli_version = '1.0.83'
                total_tokens = 12
            }
            ErrorPattern = '*incomplete Copilot usage telemetry*'
        },
        @{
            Name = 'malformed-telemetry'
            Metrics = [pscustomobject]@{
                models = @('gpt-5.4')
                usage_complete = $true
                malformed_records = 1
                cli_version = '1.0.83'
                total_tokens = 12
            }
            ErrorPattern = '*malformed Copilot telemetry record*'
        },
        @{
            Name = 'wrong-CLI'
            Metrics = [pscustomobject]@{
                models = @('gpt-5.4')
                usage_complete = $true
                malformed_records = 0
                cli_version = '1.0.82'
                total_tokens = 12
            }
            ErrorPattern = "*expected startup-probed Copilot CLI '1.0.83'*"
        }
    ) {
        $plan = @(Get-ReviewLeafPlan)
        foreach ($leaf in $plan) {
            $script:TestLeafReports[$leaf.id] = @{
                skill = @{ id = $leaf.id }
                findings = @()
                suppressed = @()
            }
        }
        $script:TestLeafMetrics = $Metrics

        { Invoke-DeterministicLeafReviews -Plan $plan } |
            Should -Throw $ErrorPattern
        Should -Invoke Start-LeafCopilotProcess -Times 1 -Exactly
        $manifest = Get-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw |
            ConvertFrom-Json
        $manifest.status | Should -Be 'failed'
        @($manifest.processes | Where-Object status -eq 'failed').Count | Should -Be 1
        @($manifest.processes).Count | Should -Be 1
    }

    It 'rejects a consolidated report that changes the declared leaf order' {
        $plan = @(Get-ReviewLeafPlan)
        $report = @{
            skill = @{ id = 'al-code-review'; version = 1 }
            outcome = 'completed'
            summary = @{ knowledge = 0; agent = 0; suppressed = 0; total = 0 }
            findings = @()
            references = @()
            suppressed = @()
            'sub-results' = @(
                @{ skill = @{ id = 'al-style-review'; version = 1 }; outcome = 'completed'; summary = @{}; findings = @(); suppressed = @() },
                @{ skill = @{ id = 'al-security-review'; version = 1 }; outcome = 'completed'; summary = @{}; findings = @(); suppressed = @() }
            )
            'skipped-sub-skills' = @()
        } | ConvertTo-Json -Depth 10

        { Assert-ConsolidatedReport -ReportText $report -Plan $plan } |
            Should -Throw "*was 'al-style-review'; expected 'al-security-review'*"
    }

    It 'fails closed on model, usage, malformed-record, and CLI-version telemetry mismatches' {
        $valid = [pscustomobject]@{
            models = @('gpt-5.4')
            usage_complete = $true
            malformed_records = 0
            cli_version = '1.0.83'
        }
        { Assert-CopilotInvocationMetrics -Metrics $valid -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Not -Throw

        $wrongModel = $valid.PSObject.Copy()
        $wrongModel.models = @('gemini-3.6-flash')
        { Assert-CopilotInvocationMetrics -Metrics $wrongModel -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Throw "*required model 'gpt-5.4'*"

        $incomplete = $valid.PSObject.Copy()
        $incomplete.usage_complete = $false
        { Assert-CopilotInvocationMetrics -Metrics $incomplete -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Throw '*incomplete Copilot usage telemetry*'

        $malformed = $valid.PSObject.Copy()
        $malformed.malformed_records = 1
        { Assert-CopilotInvocationMetrics -Metrics $malformed -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Throw '*1 malformed Copilot telemetry record*'

        $wrongCli = $valid.PSObject.Copy()
        $wrongCli.cli_version = '1.0.82'
        { Assert-CopilotInvocationMetrics -Metrics $wrongCli -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Throw "*expected startup-probed Copilot CLI '1.0.83'*"
    }

    It 'accepts absent OTel CLI version after the executable pin is verified at startup' {
        $metrics = [pscustomobject]@{
            models = @('gpt-5.4')
            usage_complete = $true
            malformed_records = 0
            cli_version = $null
        }

        { Assert-CopilotInvocationMetrics -Metrics $metrics -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Not -Throw
    }

    It 'accepts a matching OTel CLI version when telemetry reports one' {
        $script:ObservedCopilotCliVersion = '1.0.88'
        $metrics = [pscustomobject]@{
            models = @('gpt-5.4')
            usage_complete = $true
            malformed_records = 0
            cli_version = '1.0.88'
        }

        { Assert-CopilotInvocationMetrics -Metrics $metrics -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Not -Throw
    }

    It 'rejects a mismatched OTel CLI version when telemetry reports one' {
        $script:ObservedCopilotCliVersion = '1.0.88'
        $metrics = [pscustomobject]@{
            models = @('gpt-5.4')
            usage_complete = $true
            malformed_records = 0
            cli_version = '1.0.83'
        }

        { Assert-CopilotInvocationMetrics -Metrics $metrics -RequestedModel 'gpt-5.4' -InvocationLabel 'leaf' } |
            Should -Throw "*expected startup-probed Copilot CLI '1.0.88'; telemetry reported '1.0.83'*"
    }

    It 'writes a resolved run manifest with ordered per-process telemetry' {
        $script:ReviewPlanIds = @('al-security-review')
        $script:ReviewPlanSourceSnapshot = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $metrics = [pscustomobject]@{
            models = @('gpt-5.4')
            usage_complete = $true
            malformed_records = 0
            cli_version = '1.0.83'
            total_tokens = 12
        }
        $started = [DateTime]::UtcNow.AddSeconds(-2)
        Add-ReviewProcessTelemetry -Role leaf -Ordinal 1 -SkillId 'al-security-review' `
            -RequestedModel 'gpt-5.4' -Status completed -StartedAt $started `
            -CompletedAt ([DateTime]::UtcNow) -Metrics $metrics -ExitCode 0 `
            -ReportPath (Join-Path $ReviewOutputDir 'leaf-results/01-security/_review-report.json')

        Save-ReviewRunManifest -Status completed

        $manifest = Get-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw |
            ConvertFrom-Json
        $manifest.schema_version | Should -Be 1
        $manifest.status | Should -Be 'completed'
        $manifest.configuration.copilot_cli_version | Should -Be '1.0.83'
        $manifest.configuration.PSObject.Properties.Name | Should -Be @(
            'copilot_cli_version',
            'root_model',
            'leaf_model',
            'leaf_execution',
            'max_leaf_concurrency',
            'cli_timeout_minutes',
            'minimum_severity',
            'agent_minimum_severity',
            'review_source'
        )
        $manifest.configuration.PSObject.Properties.Match('requested_copilot_cli_version').Count |
            Should -Be 0
        $manifest.configuration.root_model | Should -Be 'claude-sonnet-5'
        $manifest.configuration.leaf_execution | Should -Be 'serial'
        $manifest.engine.repository | Should -BeNullOrEmpty
        $manifest.bcquality.version | Should -Be $BCQualityVersion
        $manifest.plan.leaf_ids | Should -Be @('al-security-review')
        $manifest.processes[0].requested_model | Should -Be 'gpt-5.4'
        $manifest.processes[0].report_path | Should -Be 'leaf-results/01-security/_review-report.json'
    }

    It 'records the repository and commit that supplied the review action' {
        $script:ReviewPlanIds = @('al-security-review')
        $ReviewSource = 'pr'
        $originalEngineRepository = $env:COPILOT_REVIEW_ENGINE_REPOSITORY
        $originalEngineCommit = $env:COPILOT_REVIEW_ENGINE_COMMIT
        try {
            $env:COPILOT_REVIEW_ENGINE_REPOSITORY = 'contoso/AL-Go'
            $env:COPILOT_REVIEW_ENGINE_COMMIT = '0123456789abcdef0123456789abcdef01234567'

            Save-ReviewRunManifest -Status completed

            $manifest = Get-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw |
                ConvertFrom-Json
            $manifest.engine.repository | Should -Be 'contoso/AL-Go'
            $manifest.engine.commit | Should -Be '0123456789abcdef0123456789abcdef01234567'
        }
        finally {
            $env:COPILOT_REVIEW_ENGINE_REPOSITORY = $originalEngineRepository
            $env:COPILOT_REVIEW_ENGINE_COMMIT = $originalEngineCommit
        }
    }

    It 'records action reference <Ref> without mistaking a mutable ref for a commit' -ForEach @(
        @{ Ref = 'main'; Commit = $null }
        @{ Ref = 'v10.0'; Commit = $null }
        @{ Ref = '0123456789abcdef0123456789abcdef01234567'; Commit = '0123456789abcdef0123456789abcdef01234567' }
    ) {
        $script:ReviewPlanIds = @('al-security-review')
        $ReviewSource = 'pr'
        $originalRepository = $env:COPILOT_REVIEW_ENGINE_REPOSITORY
        $originalRef = $env:COPILOT_REVIEW_ENGINE_REF
        $originalCommit = $env:COPILOT_REVIEW_ENGINE_COMMIT
        try {
            $env:COPILOT_REVIEW_ENGINE_REPOSITORY = 'contoso/AL-Go-Actions'
            $env:COPILOT_REVIEW_ENGINE_REF = $Ref
            $env:COPILOT_REVIEW_ENGINE_COMMIT = $null

            Save-ReviewRunManifest -Status completed

            $manifest = Get-Content -LiteralPath (Join-Path $ReviewOutputDir '_run-manifest.json') -Raw -Encoding UTF8 |
                ConvertFrom-Json
            $manifest.engine.ref | Should -Be $Ref
            $manifest.engine.commit | Should -Be $Commit
        }
        finally {
            $env:COPILOT_REVIEW_ENGINE_REPOSITORY = $originalRepository
            $env:COPILOT_REVIEW_ENGINE_REF = $originalRef
            $env:COPILOT_REVIEW_ENGINE_COMMIT = $originalCommit
        }
    }

    It 'requires the action repository for pull request reviews' {
        $script:ReviewPlanIds = @('al-security-review')
        $ReviewSource = 'pr'
        $originalActionRepository = $env:GITHUB_ACTION_REPOSITORY
        try {
            $env:GITHUB_ACTION_REPOSITORY = $null

            { Save-ReviewRunManifest -Status completed } |
                Should -Throw '*GITHUB_ACTION_REPOSITORY is required for pull request reviews*'
        }
        finally {
            $env:GITHUB_ACTION_REPOSITORY = $originalActionRepository
        }
    }
}

Describe 'Copilot sub-agent delegation guard' {
    It 'applies the guard to every leaf and root Copilot invocation' {
        $functions = @($script:ReviewFunctionAsts)

        foreach ($name in @('Get-LeafCopilotArguments', 'Invoke-CopilotCli')) {
            $function = $functions | Where-Object Name -eq $name
            $function | Should -Not -BeNullOrEmpty
            $function.Body.Extent.Text | Should -Match 'Get-CopilotSecurityArguments'
            $function.Body.Extent.Text | Should -Not -Match '--allow-all-tools'
            $function.Body.Extent.Text | Should -Not -Match '--excluded-tools'
        }
        $securityFunction = $functions | Where-Object Name -eq 'Get-CopilotSecurityArguments'
        $securityFunction | Should -Not -BeNullOrEmpty
        $securityFunction.Body.Extent.Text | Should -Match "'--available-tools', 'view', 'glob', 'rg', 'apply_patch'"
        $securityFunction.Body.Extent.Text | Should -Not -Match '\btask\b'
        ($functions | Where-Object Name -eq 'Start-LeafCopilotProcess').Body.Extent.Text |
            Should -Match 'Get-LeafCopilotArguments -Prompt \$Prompt'
    }

    It 'keeps delegated sub-agent chat spans without usage fail-closed' {
        $records = @(
            '{"type":"span","attributes":{"gen_ai.operation.name":"chat","gen_ai.request.model":"gpt-5.6-luna","gen_ai.usage.input_tokens":17551,"gen_ai.usage.output_tokens":151,"github.copilot.nano_aiu":125956000.0,"github.copilot.cost":1.0}}',
            '{"type":"span","attributes":{"gen_ai.operation.name":"execute_tool","gen_ai.tool.name":"task"}}',
            '{"type":"span","attributes":{"gen_ai.operation.name":"chat","gen_ai.request.model":"gpt-5.6-luna","github.copilot.interaction_id":"sub-agent"}}',
            '{"type":"span","attributes":{"gen_ai.operation.name":"invoke_agent","gen_ai.agent.name":"security-review"}}'
        ) | ForEach-Object { $_ | ConvertFrom-Json }

        $metrics = Get-CopilotRunMetrics -Records $records

        $metrics.api_calls | Should -Be 2
        $metrics.usage_api_calls | Should -Be 1
        $metrics.usage_complete | Should -BeFalse
        $metrics.ai_credits | Should -BeNullOrEmpty
        { Assert-CopilotInvocationMetrics -Metrics $metrics -RequestedModel 'gpt-5.6-luna' -InvocationLabel "Leaf 'al-security-review'" } |
            Should -Throw "*Leaf 'al-security-review' produced incomplete Copilot usage telemetry*"
    }
}

Describe 'BCQuality version ownership' {
    It 'uses the configured major.minor version in every phase' {
        Resolve-BCQualityVersion -Version '1.7' | Should -Be '1.7'
        Resolve-BCQualityVersion -Version ' 2.0 ' | Should -Be '2.0'
    }

    It 'rejects missing or invalid versions' -ForEach @('', 'v1.7', '1.7.0', 'main') {
        { Resolve-BCQualityVersion -Version $_ } |
            Should -Throw '*BCQUALITY_VERSION must use major.minor format*'
    }
}

Describe 'PR head SHA binding' {
    BeforeEach {
        $gitContext = [pscustomobject]@{
            TrustedWorkspace = 'C:\trusted-workspace'
        }
    }

    It 'accepts the fetched PR head only when it matches the validated event SHA' {
        $expected = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        Mock Invoke-GitCommand { @($expected.ToUpperInvariant()) } -ParameterFilter {
            $Arguments -join ' ' -eq '-C C:\trusted-workspace rev-parse --verify refs/remotes/origin/pr/42^{commit}'
        }

        Get-ValidatedPrHeadCommit `
            -Context $gitContext `
            -RemoteRef 'refs/remotes/origin/pr/42' `
            -ExpectedHeadSha $expected |
            Should -BeExactly $expected

        Should -Invoke Invoke-GitCommand -Times 1 -Exactly
    }

    It 'fails closed when the pull request head changed after intake' {
        $expected = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $fetched = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        Mock Invoke-GitCommand { @($fetched) }

        {
            Get-ValidatedPrHeadCommit `
                -Context $gitContext `
                -RemoteRef 'refs/remotes/origin/pr/42' `
                -ExpectedHeadSha $expected
        } | Should -Throw "*does not match validated PR_HEAD_SHA '$expected'*"
    }

    It 'rejects a non-commit result from the fetched PR ref' {
        Mock Invoke-GitCommand { @('refs/remotes/origin/pr/42') }

        {
            Get-ValidatedPrHeadCommit `
                -Context $gitContext `
                -RemoteRef 'refs/remotes/origin/pr/42' `
                -ExpectedHeadSha 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        } | Should -Throw "*did not resolve to a full commit SHA*"
    }
}

Describe 'BCQuality settings ownership' {
    BeforeEach {
        $env:BCQUALITY_SETTINGS_JSON = @{
            marketplaceRepo = 'https://github.com/microsoft/BCQuality'
            version = '1.7'
            enabledLayers = @('microsoft')
            disabledSkills = @('microsoft/skills/review/al-style-review.md')
            knowledge = @{ allow = @('microsoft/knowledge/**'); deny = @() }
        } | ConvertTo-Json -Compress -Depth 10
        $script:BCQualitySettingsCache = $null
    }

    AfterEach {
        Remove-Item Env:BCQUALITY_SETTINGS_JSON -ErrorAction SilentlyContinue
        $script:BCQualitySettingsCache = $null
    }

    It 'builds task context with internal AL defaults' {
        $context = Build-TaskContext

        $context['enabled-layers'] | Should -Be @('microsoft')
        $context['disabled-skills'] | Should -Be @('microsoft/skills/review/al-style-review.md')
        $context.technologies | Should -Be @('al')
        $context.countries | Should -Be @('w1')
        $context['application-area'] | Should -Be @('all')
        $context.Contains('bc-version') | Should -BeFalse
    }
}

Describe 'BCQuality reference links' {
    BeforeEach {
        $env:BCQUALITY_REPO = 'https://github.com/example/PrivateQuality.git/'
        $BCQualityVersion = '2.3'
        $script:BCQualityWebRepoUrl = $null
    }

    AfterEach {
        Remove-Item Env:BCQUALITY_REPO -ErrorAction SilentlyContinue
        $script:BCQualityWebRepoUrl = 'https://github.com/microsoft/BCQuality'
    }

    It 'uses the configured marketplace repository and content version' {
        Build-ReferenceLink -Reference ([pscustomobject]@{ path = 'knowledge/article.md' }) |
            Should -Be '[knowledge/article.md](https://github.com/example/PrivateQuality/blob/v2.3/knowledge/article.md)'
    }
}

Describe 'AL-Go review engine version' {
    It 'combines the nearest AL-Go release with the BCQuality content minor' {
        $root = Join-Path $TestDrive 'versioned-engine'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        & git -C $root init -q
        & git -C $root config user.email 'test@example.com'
        & git -C $root config user.name 'Test'
        Set-Content -LiteralPath (Join-Path $root 'engine.txt') -Value 'release'
        & git -C $root add engine.txt
        & git -C $root commit -q -m 'release'
        & git -C $root tag v3.2
        Set-Content -LiteralPath (Join-Path $root 'engine.txt') -Value 'main'
        & git -C $root commit -q -am 'main'

        $AgentSemVerRaw = ''
        $AgentDateRaw = ''
        $AgentVersionRaw = ''
        $BCQualityVersion = '1.9'

        Resolve-AgentVersion -EngineRoot $root | Should -Be '3.2.9'
    }
}

Describe 'Local review authentication' {
    BeforeAll {
        $script:AuthWorkspace = Join-Path $TestDrive 'workspace'
        $script:AuthBCQuality = Join-Path $TestDrive 'bcquality'
        $script:AuthOutput = Join-Path $TestDrive 'review-output'
        New-Item -ItemType Directory -Path $script:AuthWorkspace -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:AuthBCQuality 'skills') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:AuthBCQuality 'schemas') -Force | Out-Null
        Set-Content -Path (Join-Path $script:AuthBCQuality 'skills/entry.md') -Value '# entry'
        Set-Content -Path (Join-Path $script:AuthBCQuality 'schemas/findings-report.schema.json') -Value '{}'
        & git -C $script:AuthWorkspace init -q
    }

    BeforeEach {
        $ReviewPhase = 'generate'
        $ReviewSource = 'local'
        $GithubToken = $null
        $CopilotToken = $null
        $BaseRef = 'HEAD'
        $AnalysisWorkspace = $script:AuthWorkspace
        $TrustedWorkspace = $script:AuthWorkspace
        $ReviewOutputDir = $script:AuthOutput
        $BCQualityRoot = $script:AuthBCQuality
        $BaseBranch = 'main'
        $PrNumber = 0
        $PrHeadSha = $null
        $MinimumSeverity = 'Low'
        $AgentMinimumSeverity = 'Low'
        $CopilotCliTimeoutMinutes = 30
        $CopilotModel = 'claude-sonnet-5'
        $CopilotCliVersion = '1.0.83'
        $LeafModel = 'gpt-5.4'
        $script:CopilotExecutable = $null
        $script:ObservedCopilotCliVersion = $null

        Mock Get-Command {
            [pscustomobject]@{ Name = 'Test-Json' }
        } -ParameterFilter { $Name -eq 'Test-Json' }
        Mock Resolve-CopilotExecutable { 'C:\tools\copilot.exe' }
        Mock Invoke-CopilotVersionProbe {
            @(
                'GitHub Copilot CLI 1.0.83.',
                "Run 'copilot update' to check for updates."
            )
        }
    }

    It 'allows local generation without GH_TOKEN' {
        { Assert-Config } | Should -Not -Throw
    }

    It 'accepts valid branch names containing apostrophes' {
        $BaseBranch = "release/o'clock"
        { Assert-Config } | Should -Not -Throw
    }

    It 'rejects invalid branch names: <_>' -ForEach @('bad..branch', 'branch.lock', 'bad branch', 'bad~branch', '-option') {
        $BaseBranch = $_
        { Assert-Config } | Should -Throw '*BASE_BRANCH is not a valid git branch name*'
    }

    It 'probes the exact child executable and applies the requested pin at startup' {
        { Assert-Config } | Should -Not -Throw

        $script:CopilotExecutable | Should -Be 'C:\tools\copilot.exe'
        $script:ObservedCopilotCliVersion | Should -Be '1.0.83'
        Should -Invoke Resolve-CopilotExecutable -Times 1 -Exactly
        Should -Invoke Invoke-CopilotVersionProbe -Times 1 -Exactly -ParameterFilter {
            $Executable -eq 'C:\tools\copilot.exe'
        }
    }

    It 'accepts a numeric CLI prerelease from the verified multi-line banner' {
        Mock Invoke-CopilotVersionProbe {
            @(
                'GitHub Copilot CLI 1.0.89-1.',
                "Run 'copilot update' to check for updates."
            )
        }

        Get-CopilotExecutableVersion -Executable 'C:\tools\copilot.exe' | Should -Be '1.0.89-1'
    }

    It 'accepts a different exact CLI pin when the runner installs that version' {
        $CopilotCliVersion = '1.0.89'
        Mock Invoke-CopilotVersionProbe {
            @(
                'GitHub Copilot CLI 1.0.89.',
                "Run 'copilot update' to check for updates."
            )
        }

        { Assert-Config } | Should -Not -Throw
        $script:ObservedCopilotCliVersion | Should -Be '1.0.89'
    }

    It 'fails early when the requested CLI pin differs from the startup probe' {
        Mock Invoke-CopilotVersionProbe {
            @(
                'GitHub Copilot CLI 1.0.88.',
                "Run 'copilot update' to check for updates."
            )
        }

        { Assert-Config } |
            Should -Throw "*COPILOT_REVIEW_CLI_VERSION '1.0.83' does not match startup-probed Copilot CLI version '1.0.88'*"
    }

    It 'fails early when the executable version output is unparseable' {
        Mock Invoke-CopilotVersionProbe {
            @(
                'GitHub Copilot CLI 1.0.83',
                "Run 'copilot update' to check for updates."
            )
        }

        { Assert-Config } |
            Should -Throw "*must return exactly one 'GitHub Copilot CLI <semantic-version>.' banner*"
    }

    It 'fails early when the executable version output has competing CLI banners' {
        Mock Invoke-CopilotVersionProbe {
            @(
                'GitHub Copilot CLI 1.0.83.',
                'GitHub Copilot CLI 1.0.88.'
            )
        }

        { Get-CopilotExecutableVersion -Executable 'C:\tools\copilot.exe' } |
            Should -Throw "*must return exactly one 'GitHub Copilot CLI <semantic-version>.' banner*"
    }

    It 'still requires GH_TOKEN for PR generation' {
        $ReviewSource = 'pr'
        $PrNumber = 1
        $PrHeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

        { Assert-Config } | Should -Throw '*GH_TOKEN is required*'
    }

    It 'requires a full commit SHA for PR reviews' {
        $ReviewSource = 'pr'
        $CopilotToken = 'generate-token'
        $PrNumber = 1
        $PrHeadSha = 'abc123'

        { Assert-Config } | Should -Throw "*PR_HEAD_SHA must be a full 40-character commit SHA*"
    }

    It 'rejects a model working directory inside the repository under review' {
        $ReviewOutputDir = Join-Path $script:AuthWorkspace '.bc-review'

        { Assert-Config } | Should -Throw '*must be disjoint*'
    }

    It 'allows post validation with generated provenance and no BCQuality checkout' {
        $ReviewPhase = 'post'
        $ReviewSource = 'pr'
        $GithubToken = 'post-token'
        $PrNumber = 1
        $PrHeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $BCQualityRoot = $null
        $BCQualityVersion = Resolve-BCQualityVersion -Version '1.7'

        { Assert-Config } | Should -Not -Throw
        $BCQualityVersion | Should -Be '1.7'
    }

    It 'publishes generated findings after post validation without a BCQuality checkout' {
        $ReviewPhase = 'post'
        $ReviewSource = 'pr'
        $GithubToken = 'post-token'
        $PrNumber = 1
        $PrHeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $BCQualityRoot = $null
        $BCQualityVersion = Resolve-BCQualityVersion -Version '1.7'
        Mock Publish-Findings {
            [pscustomobject]@{ inline = $Findings.Count; fallback = 0 }
        }

        { Assert-Config } | Should -Not -Throw
        $summary = Publish-FindingsByDomain `
            -Findings @([pscustomobject]@{ domain = 'Style'; isAgentFinding = $false }) `
            -LineMaps @{} `
            -ChangedFileSet @{}

        $summary['Style'].inline | Should -Be 1
        Should -Invoke Publish-Findings -Times 1 -Exactly
    }

    It 'continues requiring BCQUALITY_ROOT for all and generate' -ForEach @('all', 'generate') {
        $ReviewPhase = $_
        $BCQualityRoot = $null

        { Assert-Config } | Should -Throw '*BCQUALITY_ROOT is required*'

        $BCQualityRoot = Join-Path $TestDrive 'missing-bcquality'
        { Assert-Config } | Should -Throw '*BCQUALITY_ROOT does not exist*'
    }

    It 'launches the child Copilot process without a visible console window' {
        foreach ($name in @('Invoke-CopilotCli', 'Start-LeafCopilotProcess')) {
            $source = ($script:ReviewFunctionAsts | Where-Object Name -eq $name).Body.Extent.Text
            $source | Should -Match '\$startInfo\.CreateNoWindow\s*=\s*\$true'
            $source | Should -Match 'New-CopilotProcessStartInfo -Executable \$script:CopilotExecutable'
        }
    }

    It 'does not forward inherited tokens to a local non-CI child process' {
        $environment = New-CopilotChildEnvironment `
            -ReviewSource 'local' `
            -CopilotToken 'inherited-gh-token' `
            -CopilotGithubToken 'inherited-copilot-token' `
            -CiValue $null

        $environment.ContainsKey('GH_TOKEN') | Should -BeFalse
        $environment.ContainsKey('COPILOT_GITHUB_TOKEN') | Should -BeFalse
        $environment.ContainsKey('GITHUB_TOKEN') | Should -BeFalse
    }

    It 'forwards only COPILOT_GITHUB_TOKEN to a local CI child process' {
        $environment = New-CopilotChildEnvironment `
            -ReviewSource 'local' `
            -CopilotToken 'inherited-gh-token' `
            -CopilotGithubToken 'ci-copilot-token' `
            -CiValue 'true'

        $environment['COPILOT_GITHUB_TOKEN'] | Should -Be 'ci-copilot-token'
        $environment.ContainsKey('GH_TOKEN') | Should -BeFalse
    }

    It 'forwards the PR credential only through the Copilot-specific variable' {
        $environment = New-CopilotChildEnvironment `
            -ReviewSource 'pr' `
            -CopilotToken 'pr-copilot-token' `
            -CopilotGithubToken 'inherited-copilot-token' `
            -CiValue 'true'

        $environment['COPILOT_GITHUB_TOKEN'] | Should -Be 'pr-copilot-token'
        $environment.ContainsKey('GH_TOKEN') | Should -BeFalse
    }

    It 'does not set COPILOT_GH_HOST for github.com' {
        $environment = New-CopilotChildEnvironment `
            -ReviewSource 'pr' `
            -CopilotToken 'pr-copilot-token' `
            -CopilotGithubToken $null `
            -CiValue 'true' `
            -GitHubServerUrl 'https://github.com'

        $environment.ContainsKey('COPILOT_GH_HOST') | Should -BeFalse
    }

    It 'sets COPILOT_GH_HOST for a GitHub Enterprise host' {
        $environment = New-CopilotChildEnvironment `
            -ReviewSource 'pr' `
            -CopilotToken 'pr-copilot-token' `
            -CopilotGithubToken $null `
            -CiValue 'true' `
            -GitHubServerUrl 'https://contoso.ghe.com'

        $environment['COPILOT_GH_HOST'] | Should -Be 'https://contoso.ghe.com'
        $environment['COPILOT_GITHUB_TOKEN'] | Should -Be 'pr-copilot-token'
    }

    It 'constrains reviewer tools and token propagation for every platform' {
        $arguments = @(Get-CopilotSecurityArguments -WritablePath 'C:\review-output\leaf\_review-report.json')
        $joined = $arguments -join ' '

        $joined | Should -Match '--available-tools view glob rg apply_patch'
        $joined | Should -Match '--disallow-temp-dir'
        $joined | Should -Match '--allow-tool write\(C:/review-output/leaf/_review-report\.json\)'
        $joined | Should -Match '--deny-tool shell'
        $joined | Should -Match '--deny-tool url'
        $joined | Should -Match '--secret-env-vars GH_TOKEN,GITHUB_TOKEN,COPILOT_GITHUB_TOKEN'
        $joined | Should -Not -Match '/\*\*'
        $joined | Should -Not -Match 'allow-all-paths'
        $joined | Should -Not -Match 'allow-all-tools'
    }
}

Describe 'Test-GitHubEnterpriseHost' {
    It 'treats github.com as the default host' {
        Test-GitHubEnterpriseHost -ServerUrl 'https://github.com' | Should -BeFalse
        Test-GitHubEnterpriseHost -ServerUrl 'https://github.com/' | Should -BeFalse
        Test-GitHubEnterpriseHost -ServerUrl '' | Should -BeFalse
        Test-GitHubEnterpriseHost -ServerUrl $null | Should -BeFalse
    }

    It 'recognises GitHub Enterprise Cloud and Server hosts' {
        Test-GitHubEnterpriseHost -ServerUrl 'https://contoso.ghe.com' | Should -BeTrue
        Test-GitHubEnterpriseHost -ServerUrl 'https://github.contoso.local/' | Should -BeTrue
    }

    It 'derives the API base and git credential host from the Actions server variables' {
        $source = $script:ReviewSourceText
        $source | Should -Not -Match 'https://api\.github\.com/repos'
        $source | Should -Not -Match "http\.https://github\.com/\.extraheader"
        $source | Should -Match '\$BaseUrl\s*=\s*"\$GitHubApiUrl/repos/\$Repository"'
        $source | Should -Match '\$env:GIT_CONFIG_KEY_0 = "http\.\$GitHubServerUrl/\.extraheader"'
    }
}

Describe 'Sanitized review data projection' {
    BeforeEach {
        $AnalysisWorkspace = Join-Path $TestDrive 'untrusted-repository'
        $ReviewDataRoot = Join-Path $TestDrive 'review-data'
        $gitContext = [pscustomobject]@{
            AnalysisWorkspace = $AnalysisWorkspace
            ReviewDataRoot = $ReviewDataRoot
        }
        New-Item -ItemType Directory -Path (Join-Path $AnalysisWorkspace '.github/skills/hostile') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $AnalysisWorkspace '.agents/skills/hostile') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $AnalysisWorkspace 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace '.github/skills/hostile/SKILL.md') -Value 'hostile'
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace '.agents/skills/hostile/SKILL.md') -Value 'hostile'
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace 'AGENTS.md') -Value 'hostile'
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace 'src/code.al') -Value 'codeunit 1 Test {}'
        & git -C $AnalysisWorkspace init -q
        & git -C $AnalysisWorkspace config user.email 'test@example.invalid'
        & git -C $AnalysisWorkspace config user.name 'Test'
        & git -C $AnalysisWorkspace add .
        & git -C $AnalysisWorkspace commit -qm 'fixture'
    }

    It 'exports reviewable code without loading repository-owned trusted configuration' {
        New-ReviewDataProjection -Context $gitContext

        Test-Path -LiteralPath (Join-Path $ReviewDataRoot 'src/code.al') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $ReviewDataRoot '.github/skills') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $ReviewDataRoot '.agents/skills') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $ReviewDataRoot 'AGENTS.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $AnalysisWorkspace '.github/skills/hostile/SKILL.md') | Should -BeTrue
    }

    It 'does not let export-ignore omit reviewed files' {
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace '.gitattributes') `
            -Value 'src/code.al export-ignore'
        & git -C $AnalysisWorkspace add .gitattributes
        & git -C $AnalysisWorkspace commit -qm 'add hostile export-ignore'

        New-ReviewDataProjection -Context $gitContext

        $committedContent = [Text.Encoding]::UTF8.GetString(
            (Invoke-GitCommandBytes -Arguments @(
                '-C', $AnalysisWorkspace, 'cat-file', 'blob', 'HEAD:src/code.al'
            ))
        )
        Get-Content -LiteralPath (Join-Path $ReviewDataRoot 'src/code.al') -Raw |
            Should -BeExactly $committedContent
    }

    It 'does not let export-subst mutate reviewed files' {
        $substitutionMarker = '$Format:%H$'
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace 'src/substituted.txt') `
            -Value $substitutionMarker -NoNewline
        Set-Content -LiteralPath (Join-Path $AnalysisWorkspace '.gitattributes') `
            -Value 'src/substituted.txt export-subst'
        & git -C $AnalysisWorkspace add .gitattributes src/substituted.txt
        & git -C $AnalysisWorkspace commit -qm 'add hostile export-subst'

        New-ReviewDataProjection -Context $gitContext

        Get-Content -LiteralPath (Join-Path $ReviewDataRoot 'src/substituted.txt') -Raw |
            Should -BeExactly $substitutionMarker
    }
}

Describe 'Review output path isolation' {
    It 'canonicalizes REVIEW_OUTPUT_DIR before deriving the Copilot working directory' {
        $source = $script:ReviewSourceText

        $source | Should -Match '\$ReviewOutputDir\s*=\s*\[IO\.Path\]::GetFullPath\(\$ReviewOutputDirRaw\)'
        $source.IndexOf('$ReviewOutputDir  = [IO.Path]::GetFullPath($ReviewOutputDirRaw)') |
            Should -BeLessThan $source.IndexOf('$AgentWorkDir = $ReviewOutputDir')
    }
}

Describe 'Repair-ShellEscapedQuotes' {
    # Mirrors the real bug: a suggested-code field whose AL Label content is
    # emitted through a single-quoted shell argument leaves the POSIX
    # close/escape/reopen idiom '\'' in _review-report.json. That 4-char
    # sequence is invalid JSON and is rejected by strict parsers (Python's
    # json.loads in BC-Bench; .NET System.Text.Json here), even though
    # PowerShell's own ConvertFrom-Json happens to tolerate it.
    It 'collapses the POSIX shell single-quote escape so a strict parser accepts the report' {
        $corrupt = '{"suggested-code":"BearerTok: Label ' + "'\''" + '******' + "'\''" + ', Locked = true;"}'
        { [System.Text.Json.JsonDocument]::Parse($corrupt) } | Should -Throw

        $repaired = Repair-ShellEscapedQuotes -Text $corrupt
        $repaired.Contains("'\''") | Should -BeFalse
        $doc = [System.Text.Json.JsonDocument]::Parse($repaired)
        $doc.RootElement.GetProperty('suggested-code').GetString() |
            Should -Be "BearerTok: Label '******', Locked = true;"
    }

    It 'preserves valid JSON string escapes (backslash-quote and backslash-n)' {
        $json = '{"message":"He said \"hi\"\nnext line"}'
        Repair-ShellEscapedQuotes -Text $json | Should -Be $json
    }

    It 'leaves clean text unchanged and is idempotent' {
        $clean = '{"a":"no shell quotes here"}'
        $once = Repair-ShellEscapedQuotes -Text $clean
        $once | Should -Be $clean
        Repair-ShellEscapedQuotes -Text $once | Should -Be $clean
    }

    It 'passes empty and null input through unchanged' {
        Repair-ShellEscapedQuotes -Text '' | Should -Be ''
        Repair-ShellEscapedQuotes -Text $null | Should -BeNullOrEmpty
    }
}

Describe 'Get-RegionalPathInfo' {
    It 'parses an src/Apps regional path' {
        $info = Get-RegionalPathInfo -FilePath 'src/Apps/US/Sales/Foo.Codeunit.al'
        $info.Tree | Should -Be 'apps'
        $info.Region | Should -Be 'us'
        $info.Relative | Should -Be 'Sales/Foo.Codeunit.al'
    }

    It 'parses an src/Layers regional path and normalizes backslashes/case' {
        $info = Get-RegionalPathInfo -FilePath '\src\Layers\W1\Bar.al'
        $info.Tree | Should -Be 'layers'
        $info.Region | Should -Be 'w1'
        $info.Path | Should -Be 'src/Layers/W1/Bar.al'
    }

    It 'returns null for a non-regional path' {
        Get-RegionalPathInfo -FilePath 'src/System Application/Foo.al' | Should -BeNullOrEmpty
    }
}

Describe 'Get-FindingOtherRegions' {
    It 'returns an empty array when the property is absent (StrictMode-safe)' {
        (Get-FindingOtherRegions -Finding ([pscustomobject]@{ filePath = 'x' })).Count | Should -Be 0
    }
}

Describe 'Group-RegionalFindings' {
    BeforeAll {
        function New-RegionalFinding {
            param([string] $Path, [int] $Line = 10, [string] $Issue = 'Avoid N+1 query', [string] $Rec = 'Use SetLoadFields')
            [pscustomobject]@{
                filePath = $Path; lineNumber = $Line; severity = 'Medium'
                domain = 'Performance'; issue = $Issue; recommendation = $Rec
            }
        }
    }

    It 'collapses an identical finding across regions and prefers W1 as primary' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/US/Foo.al' -Line 42
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al' -Line 42
            New-RegionalFinding -Path 'src/Apps/DE/Foo.al' -Line 42
        )
        $result = @(Group-RegionalFindings -Findings $findings)
        $result.Count | Should -Be 1
        $result[0].filePath | Should -Be 'src/Apps/W1/Foo.al'
        $others = Get-FindingOtherRegions -Finding $result[0]
        $others.Count | Should -Be 2
        ($others | ForEach-Object { $_.region }) | Should -Be @('DE', 'US')
        $others[0].line | Should -Be 42
    }

    It 'picks a deterministic primary when no W1 copy is present' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/US/Foo.al' -Line 42
            New-RegionalFinding -Path 'src/Apps/DE/Foo.al' -Line 42
        )
        $result = @(Group-RegionalFindings -Findings $findings)
        $result.Count | Should -Be 1
        $result[0].filePath | Should -Be 'src/Apps/DE/Foo.al'
        (Get-FindingOtherRegions -Finding $result[0]).region | Should -Be 'US'
    }

    It 'preserves regional findings when equivalent defects cannot be established' {
        $findings = @(
            New-RegionalFinding -Path 'src/Layers/W1/AlCosting/Foo.Codeunit.al' -Line 7 -Issue 'Missing SetLoadFields before Get' -Rec 'Add SetLoadFields'
            New-RegionalFinding -Path 'src/Layers/BE/AlCosting/Foo.Codeunit.al' -Line 7 -Issue 'Same issue as the W1 copy: no SetLoadFields' -Rec 'Add a SetLoadFields call'
        )
        $result = @(Group-RegionalFindings -Findings $findings)
        $result.Count | Should -Be 2
    }

    It 'preserves two distinct defects on the same line across regions' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al' -Issue 'N+1 query' -Rec 'Load fields'
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al' -Issue 'Repeated lookup' -Rec 'Cache result'
            New-RegionalFinding -Path 'src/Apps/US/Foo.al' -Issue 'N+1 query' -Rec 'Load fields'
            New-RegionalFinding -Path 'src/Apps/US/Foo.al' -Issue 'Repeated lookup' -Rec 'Cache result'
        )
        $result = @(Group-RegionalFindings -Findings $findings)
        $result.Count | Should -Be 2
        $result.issue | Should -Contain 'N+1 query'
        $result.issue | Should -Contain 'Repeated lookup'
        foreach ($finding in $result) {
            @(Get-FindingOtherRegions -Finding $finding).Count | Should -Be 1
        }
    }

    It 'preserves differing severity and suggested fixes at the same regional location' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al'
            New-RegionalFinding -Path 'src/Apps/US/Foo.al'
            New-RegionalFinding -Path 'src/Apps/DE/Foo.al'
        )
        $findings[1].severity = 'High'
        $findings[2] | Add-Member -NotePropertyName suggestedCode -NotePropertyValue 'Use a different fix'
        @(Group-RegionalFindings -Findings $findings).Count | Should -Be 3
    }

    It 'preserves different rule identities even when their messages match' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al'
            New-RegionalFinding -Path 'src/Apps/US/Foo.al'
        )
        $findings[0] | Add-Member -NotePropertyName rawId -NotePropertyValue 'rule-a'
        $findings[1] | Add-Member -NotePropertyName rawId -NotePropertyValue 'rule-b'
        @(Group-RegionalFindings -Findings $findings).Count | Should -Be 2
    }

    It 'does not merge Apps and Layers trees at the same relative path and line' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al'
            New-RegionalFinding -Path 'src/Layers/US/Foo.al'
        )
        @(Group-RegionalFindings -Findings $findings).Count | Should -Be 2
    }

    It 'does not collapse findings at different lines of the same file across regions' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/US/Foo.al' -Line 10
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al' -Line 20
        )
        (Group-RegionalFindings -Findings $findings).Count | Should -Be 2
    }

    It 'does not collapse identical findings that stay within one region' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/US/Foo.al' -Line 10
            New-RegionalFinding -Path 'src/Apps/US/Bar.al' -Line 99
        )
        $result = @(Group-RegionalFindings -Findings $findings)
        $result.Count | Should -Be 2
        (Get-FindingOtherRegions -Finding $result[0]).Count | Should -Be 0
    }

    It 'leaves a non-regional finding untouched even if it shares a signature' {
        $findings = @(
            New-RegionalFinding -Path 'src/Apps/US/Foo.al'
            New-RegionalFinding -Path 'src/Apps/W1/Foo.al'
            New-RegionalFinding -Path 'src/System Application/Foo.al'
        )
        $result = @(Group-RegionalFindings -Findings $findings)
        $result.Count | Should -Be 2
        ($result | Where-Object { $_.filePath -eq 'src/System Application/Foo.al' }).Count | Should -Be 1
    }
}

Describe 'Format-OtherRegionsNotice' {
    It 'renders a bullet list of the other regional copies' {
        $finding = [pscustomobject]@{ otherRegions = @(
            [pscustomobject]@{ path = 'src/Apps/US/Foo.al'; line = 42; region = 'US' }
        ) }
        $notice = Format-OtherRegionsNotice -Finding $finding
        $notice | Should -Match 'regional copies'
        $notice | Should -Match 'src/Apps/US/Foo.al:42`'
        $notice | Should -Match '\(US\)'
    }

    It 'returns an empty string when there are no other regions (under StrictMode)' {
        # Regression guard: Get-FindingOtherRegions returns @() when the property is
        # absent, but a function's empty-array return unrolls to $null on assignment,
        # so a naive $others.Count throws under Set-StrictMode -Version Latest (the mode
        # the orchestrator runs under). Pester does not enable StrictMode, so assert it
        # explicitly here on the common non-collapsed-finding path.
        & {
            Set-StrictMode -Version Latest
            Format-OtherRegionsNotice -Finding ([pscustomobject]@{ filePath = 'x' })
        } | Should -Be ''
    }
}

Describe 'Save-ReviewArtifacts' {
    It 'persists sub-results used for knowledge and sub-skill diagnostics' {
        $ReviewOutputDir = Join-Path $TestDrive 'review-output'
        $Repository = 'microsoft/BCApps'
        $PrNumber = 1
        $BaseBranch = 'main'
        $PrHeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $report = [pscustomobject]@{
            Outcome = 'completed'
            OutcomeReason = ''
            Findings = @()
            Suppressed = @()
            SubResults = @(
                [pscustomobject]@{
                    id = 'al-performance-review'
                    outcome = 'completed'
                    references = @([pscustomobject]@{ path = 'microsoft/knowledge/performance/article.md' })
                }
            )
            SkippedSubSkills = @()
        }

        Save-ReviewArtifacts -RawOutput '{}' -Report $report -ParseErrors @() -TaskContext @{} -Transcript ''

        $saved = Get-Content -LiteralPath (Join-Path $ReviewOutputDir 'al-code-review-findings.json') -Raw | ConvertFrom-Json
        $saved.subResults.Count | Should -Be 1
        $saved.subResults[0].id | Should -Be 'al-performance-review'
        $saved.subResults[0].references[0].path | Should -Be 'microsoft/knowledge/performance/article.md'
    }
}

Describe 'Deterministic findings consumer acceptance' {
    BeforeAll {
        # Minimal source-faithful fixtures from BC-Bench run 37293252219:
        # privacy-008 / al-privacy-review, privacy-015 / al-performance-review,
        # http-consumed-false-01 / al-error-handling-review. Only prose and
        # optional suggestions were removed; all failing fields are unchanged.
        # Original report SHA256s, respectively:
        # dd43b71d5f4cc80eacbabfcbfb88462edee926e128102cab6eaf23b9e133ce78
        # cabc94d1352c8d4e62218aa3f4949f404014dd2db7e4b6c0efe6200b858b9e1e
        # b71268431d53548bad0cd1677c5ea7e4be02b329e8d96beb2c0ae1d92cf613c4
        $consumerFixtures = Join-Path $PSScriptRoot 'fixtures/findings-consumer'
        $sharedSchema = Get-Content (Join-Path $PSScriptRoot 'fixtures/findings-report-roles/bcquality-findings-report.b74967bc.schema.json') -Raw
        $consumerLeafSchema = (New-FindingsReportRoleSchemas -SharedSchemaJson $sharedSchema).Leaf
    }

    BeforeEach {
        $AnalysisWorkspace = Join-Path $TestDrive 'consumer-source'
        $BCQualityRoot = Join-Path $TestDrive 'consumer-knowledge'
        $AgentWorkDir = $BCQualityRoot
        New-Item -ItemType Directory -Path (Join-Path $AnalysisWorkspace 'src'), $BCQualityRoot -Force | Out-Null
        $reports = @{}
        foreach ($fixtureName in @('privacy-008', 'privacy-015', 'http-consumed-false-01')) {
            $reports[$fixtureName] = Get-Content (Join-Path $consumerFixtures "$fixtureName.json") -Raw | ConvertFrom-Json
            foreach ($reference in $reports[$fixtureName].findings.references) {
                if (-not $reference) { continue }
                $fullPath = Join-Path $BCQualityRoot $reference.path
                New-Item -ItemType Directory -Path (Split-Path $fullPath) -Force | Out-Null
                Set-Content -LiteralPath $fullPath -Value '# Synthetic knowledge inventory entry'
            }
        }
        # The privacy evidence has exactly 22 final-source lines. Other files
        # are synthetic bounds-only stubs, not copies of the benchmark source.
        $sourceCounts = [ordered]@{
            'src/CustomerSyncDispatcher.Codeunit.al' = 22
            'src/ExternalCRMSync.Codeunit.al' = 40
            'src/OutboxEmailDispatcher.Codeunit.al' = 40
            'src/BCBHttpDelivery.Codeunit.al' = 16
            'src/Empty.al' = 0
        }
        foreach ($entry in $sourceCounts.GetEnumerator()) {
            [IO.File]::WriteAllText((Join-Path $AnalysisWorkspace $entry.Key), ("source line`n" * $entry.Value))
        }
        $sourcePaths = @($sourceCounts.Keys) + 'src/Deleted.al'
        $context = New-FindingsConsumerContext -SourceRoot $AnalysisWorkspace -SourcePaths $sourcePaths -KnowledgeRoot $BCQualityRoot
        $valid = $reports['privacy-008']
        $valid.findings[0].location.line = 22
        $valid.findings[0].location.range.'start-line' = 22
        $valid.findings[0].location.range.'end-line' = 22
        $primary = $valid.findings[0].references[0].path
    }

    It 'rejects the schema-valid original <Name> failure deterministically' -ForEach @(
        @{ Name = 'privacy-008'; Failure = '*line 44*22 final-source lines*' },
        @{ Name = 'privacy-015'; Failure = '*.id*must exactly equal primary reference*' },
        @{ Name = 'http-consumed-false-01'; Failure = '*.confidence*medium*' }
    ) {
        $path = Join-Path $consumerFixtures "$Name.json"
        $before = (Get-FileHash $path).Hash
        $raw = Get-Content $path -Raw
        ($raw | Test-Json -Schema $consumerLeafSchema -ErrorAction Stop) | Should -BeTrue
        $report = $raw | ConvertFrom-Json
        { Assert-LeafConsumerAcceptance -ReportObject $report -Context $context } | Should -Throw $Failure
        (Get-FileHash $path).Hash | Should -Be $before
        ($report | ConvertTo-Json -Depth 20) | Should -Be (($raw | ConvertFrom-Json) | ConvertTo-Json -Depth 20)
    }

    It 'accepts citation-backed final-line and inclusive-range findings without changing them' {
        $valid.findings[0].location.line = 1
        $valid.findings[0].location.range.'start-line' = 1
        $valid.findings[0].references[0] | Add-Member -NotePropertyName sha -NotePropertyValue ('a' * 40)
        $before = $valid | ConvertTo-Json -Depth 20
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } | Should -Not -Throw
        ($valid | ConvertTo-Json -Depth 20) | Should -Be $before
    }

    It 'permits findings without location and locations without range under StrictMode' {
        $valid.findings[0].location.PSObject.Properties.Remove('range')
        & {
            Set-StrictMode -Version Latest
            Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context
            $valid.findings[0].PSObject.Properties.Remove('location')
            Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context
            $valid.findings[0].references = @()
            $valid.findings[0].id = 'agent:repository-wide'
            $valid.findings[0].confidence = 'medium'
            $valid.findings[0].severity = 'minor'
            $valid.summary.counts.major = 0
            $valid.summary.counts.minor = 1
            Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context
        }
    }

    It 'does not impose findings citation existence on configuration-suppressed references' {
        $valid.suppressed = @([pscustomobject]@{
            reference = [pscustomobject]@{ path = 'community/knowledge/disabled/article.md' }
            reason = 'configuration'
        })
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } | Should -Not -Throw
    }

    It 'rejects unsafe knowledge reference <_>' -ForEach @(
        '../outside.md', '/absolute.md', 'C:/outside.md', 'C:relative.md', '\\server\share\article.md',
        'microsoft\knowledge\privacy\article.md', 'microsoft/knowledge/../outside.md',
        'microsoft/knowledge/privacy/./article.md', 'microsoft//knowledge/privacy/article.md',
        'microsoft/knowledge/privacy/article.md:stream', 'https://example.test/article.md',
        'microsoft/knowledge/privacy/article.md#fragment', 'microsoft/knowledge/privacy/article.md ',
        'microsoft/knowledge/privacy/../privacy/article.md'
    ) {
        $valid.findings[0].id = $_
        $valid.findings[0].references[0].path = $_
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } |
            Should -Throw '*not a safe repo-relative knowledge path*'
    }

    It 'rejects unknown or differently cased knowledge paths including secondary references' -ForEach @(
        'microsoft/knowledge/privacy/unknown.md',
        'microsoft/knowledge/Privacy/privacy-notice-consent-for-external-data-transfer.md'
    ) {
        $valid.findings[0].references += [pscustomobject]@{ path = $_ }
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } |
            Should -Throw '*references[[]1[]].path*does not exist*'
    }

    It 'requires ordinal exact citation equality for <Suffix>' -ForEach @(
        @{ Suffix = '#location' }, @{ Suffix = ' ' }, @{ Suffix = 'case' }
    ) {
        $valid.findings[0].id = if ($Suffix -eq 'case') { $primary.ToUpperInvariant() } else { "$primary$Suffix" }
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } |
            Should -Throw '*must exactly equal primary reference*'
    }

    It 'allows the same citation ID at distinct valid source locations' {
        $second = $valid.findings[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $second.location.file = 'src/OutboxEmailDispatcher.Codeunit.al'
        $valid.findings += $second
        $valid.summary.counts.major = 2
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } | Should -Not -Throw
    }

    It 'rejects locations outside the exact changed-file scope: <_>' -ForEach @(
        'src/Unchanged.al', 'src/customersyncdispatcher.Codeunit.al',
        'src\CustomerSyncDispatcher.Codeunit.al', '/src/CustomerSyncDispatcher.Codeunit.al',
        '../src/CustomerSyncDispatcher.Codeunit.al', 'src/./CustomerSyncDispatcher.Codeunit.al'
    ) {
        Set-Content (Join-Path $AnalysisWorkspace 'src/Unchanged.al') -Value 'exists but not changed'
        $valid.findings[0].location.file = $_
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } |
            Should -Throw '*not an exact in-scope source path*'
    }

    It 'rejects missing/deleted in-scope files and empty-file line anchors' -ForEach @(
        @{ Path = 'src/Deleted.al'; Failure = '*not an existing regular file*' },
        @{ Path = 'src/Empty.al'; Failure = '*0 final-source lines*' }
    ) {
        $valid.findings[0].location.file = $Path
        $valid.findings[0].location.line = 1
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } | Should -Throw $Failure
    }

    It 'rejects invalid final-source bounds: <Label>' -ForEach @(
        @{ Label = 'zero line'; Line = 0; Start = 1; End = 1; Failure = '*.location.line*' },
        @{ Label = 'past EOF'; Line = 23; Start = 23; End = 23; Failure = '*.location.line*' },
        @{ Label = 'mismatched start'; Line = 20; Start = 19; End = 22; Failure = '*.range.start-line*' },
        @{ Label = 'reversed range'; Line = 20; Start = 20; End = 19; Failure = '*.range.end-line*' },
        @{ Label = 'end past EOF'; Line = 20; Start = 20; End = 23; Failure = '*.range.end-line*' }
    ) {
        $valid.findings[0].location.line = $Line
        $valid.findings[0].location.range.'start-line' = $Start
        $valid.findings[0].location.range.'end-line' = $End
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } | Should -Throw $Failure
    }

    It 'rejects uncited <_> severity without downgrading it' -ForEach @('major', 'blocker') {
        $valid.findings[0].references = @()
        $valid.findings[0].id = 'agent:test'
        $valid.findings[0].confidence = 'medium'
        $valid.findings[0].severity = $_
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $context } |
            Should -Throw '*uncited findings cannot exceed minor severity*'
        $valid.findings[0].severity | Should -Be $_
    }

    It 'uses the pre-model snapshot rather than tampered bounds, knowledge or source files' {
        Initialize-FindingsConsumerContext -SourcePaths $sourcePaths
        Set-Content (Join-Path $AgentWorkDir '_review-source-bounds.json') -Value '{"files":[]}'
        [IO.File]::AppendAllText((Join-Path $AnalysisWorkspace 'src/CustomerSyncDispatcher.Codeunit.al'), ("new line`n" * 50))
        Set-Content (Join-Path $BCQualityRoot 'microsoft/knowledge/privacy/invented.md') -Value '# Invented after capture'
        $badLine = Get-Content (Join-Path $consumerFixtures 'privacy-008.json') -Raw | ConvertFrom-Json
        { Assert-LeafConsumerAcceptance -ReportObject $badLine -Context $script:FindingsConsumerContext } |
            Should -Throw '*line 44*22 final-source lines*'
        $valid.findings[0].references += [pscustomobject]@{ path = 'microsoft/knowledge/privacy/invented.md' }
        { Assert-LeafConsumerAcceptance -ReportObject $valid -Context $script:FindingsConsumerContext } |
            Should -Throw '*does not exist in the pinned filtered BCQuality snapshot*'
    }

    It 'writes deterministic bounds and clears them with the existing lifecycle in <_> mode' -ForEach @('cwd', 'plugin') {
        if ($_ -eq 'plugin') {
            $AgentWorkDir = Join-Path $TestDrive 'plugin-output'
            New-Item -ItemType Directory -Path $AgentWorkDir -Force | Out-Null
        }
        Initialize-FindingsConsumerContext -SourcePaths $sourcePaths
        $path = Join-Path $AgentWorkDir '_review-source-bounds.json'
        $before = Get-Content $path -Raw
        $bounds = $before | ConvertFrom-Json
        ($bounds.files | Where-Object path -eq 'src/CustomerSyncDispatcher.Codeunit.al').line_count | Should -Be 22
        ($bounds.files | Where-Object path -eq 'src/Empty.al').line_count | Should -Be 0
        ($bounds.files | Where-Object path -eq 'src/Deleted.al').exists | Should -BeFalse
        ($bounds.files | Where-Object path -eq 'src/Deleted.al').line_count | Should -BeNullOrEmpty
        [array]::Reverse($sourcePaths)
        Initialize-FindingsConsumerContext -SourcePaths $sourcePaths
        (Get-Content $path -Raw) | Should -Be $before
        Clear-BCQualityRunArtifacts
        Test-Path $path | Should -BeFalse
    }

    It 'counts real final lines with LF, CRLF, BOM and no trailing newline' -ForEach @(
        @{ Content = "first`nsecond`n"; Bom = $false },
        @{ Content = "first`r`nsecond"; Bom = $true },
        @{ Content = "first`nsecond"; Bom = $false }
    ) {
        [IO.File]::WriteAllText((Join-Path $AnalysisWorkspace 'src/Empty.al'), $Content, [Text.UTF8Encoding]::new($Bom))
        $captured = New-FindingsConsumerContext -SourceRoot $AnalysisWorkspace -SourcePaths @('src/Empty.al') -KnowledgeRoot $BCQualityRoot
        $captured.SourceFiles['src/Empty.al'].line_count | Should -Be 2
    }

    It 'rejects unsafe scope before reading source files' {
        { New-FindingsConsumerContext -SourceRoot $AnalysisWorkspace -SourcePaths @('../outside.al') -KnowledgeRoot $BCQualityRoot } |
            Should -Throw '*unsafe source path*'
    }

    It 'excludes linked directories from source and knowledge snapshots' {
        $outside = Join-Path $TestDrive 'outside-snapshot'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content (Join-Path $outside 'article.md') -Value '# Outside snapshot'
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path (Join-Path $AnalysisWorkspace 'linked') -Target $outside | Out-Null
        New-Item -ItemType $linkType -Path (Join-Path $BCQualityRoot 'microsoft/knowledge/linked') -Target $outside | Out-Null
        $captured = New-FindingsConsumerContext -SourceRoot $AnalysisWorkspace -SourcePaths @('linked/article.md') -KnowledgeRoot $BCQualityRoot
        $captured.SourceFiles['linked/article.md'].exists | Should -BeFalse
        $captured.KnowledgePaths.Contains('microsoft/knowledge/linked/article.md') | Should -BeFalse
    }

    It 'discovers exact unquoted git paths before capturing bounds' {
        $ReviewPathSpec = 'src'
        $DiffRange = '--cached'
        $null = Invoke-GitCommand -Arguments @('-C', $AnalysisWorkspace, 'init', '--quiet')
        $paths = @('src/Bracket[1].al', "src/Caf$([char]0xe9).al", 'src/With space.al')
        foreach ($path in $paths) {
            Set-Content -LiteralPath (Join-Path $AnalysisWorkspace $path) -Value 'final line'
        }
        $null = Invoke-GitCommand -Arguments (@('-C', $AnalysisWorkspace, 'add', '--') + $paths)
        $changed = @(Get-GitChangedFiles -Context ([pscustomobject]@{
            AnalysisWorkspace = $AnalysisWorkspace
            DiffRange = $DiffRange
            ReviewPathSpec = $ReviewPathSpec
        }))
        $changed | Should -Be $paths
        $captured = New-FindingsConsumerContext -SourceRoot $AnalysisWorkspace -SourcePaths $changed -KnowledgeRoot $BCQualityRoot
        foreach ($path in $paths) {
            $captured.SourceFiles[$path].exists | Should -BeTrue
            $captured.SourceFiles[$path].line_count | Should -Be 1
        }
    }

    It 'copies authoritative run inputs into an isolated leaf before launching in <_> mode' -ForEach @('cwd', 'plugin') {
        if ($_ -eq 'plugin') {
            $AgentWorkDir = Join-Path $TestDrive 'copy-plugin-output'
            New-Item -ItemType Directory -Path $AgentWorkDir -Force | Out-Null
        }
        $LeafReportSchemaFileName = '_review-findings-report.leaf.schema.json'
        $inputNames = @('_task-context.json', '_review-changed-files.txt', '_review-object-index.txt', $LeafReportSchemaFileName)
        foreach ($inputName in $inputNames) {
            Set-Content -LiteralPath (Join-Path $AgentWorkDir $inputName) -Value '{}'
        }
        Initialize-FindingsConsumerContext -SourcePaths $sourcePaths
        $workDir = Join-Path $TestDrive 'copied-leaf'
        $CopilotLogLevel = 'info'
        $LeafModel = 'test-model'
        $GitHubServerUrl = 'https://github.com'
        $ReviewSource = 'local'
        $CopilotToken = ''
        $CopilotGithubToken = ''
        Mock New-CopilotChildEnvironment { throw 'Stopped before any model process could launch' }

        { Start-LeafCopilotProcess -Leaf ([pscustomobject]@{ id = 'test-leaf' }) -WorkDir $workDir -Prompt 'test' } |
            Should -Throw '*Stopped before any model process could launch*'

        foreach ($inputName in @($inputNames) + '_review-source-bounds.json') {
            (Get-FileHash (Join-Path $workDir $inputName)).Hash |
                Should -Be (Get-FileHash (Join-Path $AgentWorkDir $inputName)).Hash
        }
        Set-Content (Join-Path $workDir '_review-source-bounds.json') -Value '{"files":[{"path":"src/CustomerSyncDispatcher.Codeunit.al","exists":true,"line_count":999}]}'
        $bad = Get-Content (Join-Path $consumerFixtures 'privacy-008.json') -Raw | ConvertFrom-Json
        { Assert-LeafConsumerAcceptance -ReportObject $bad -Context $script:FindingsConsumerContext } |
            Should -Throw '*line 44*22 final-source lines*'
    }
}

Describe 'Bounded leaf accepted-copy normalization' {
    BeforeAll {
        # Four findings from privacy-015/al-privacy-review in run 37310924454.
        # IDs, references, source locations, ranges and counts are unchanged.
        # Original SHA256: 26aead0958e6ffe60c947f740b95ecf016783116a88d1254e87cea5c54c10107.
        $normalizationFixture = Join-Path $PSScriptRoot 'fixtures/findings-consumer/privacy-015-normalization.json'
        $normalizationRaw = Get-Content -LiteralPath $normalizationFixture -Raw
        $normalizationSchema = (New-FindingsReportRoleSchemas -SharedSchemaJson (
            Get-Content -LiteralPath $NormalizationSchemaPath -Raw
        )).Leaf
        $normalizationSources = Get-OrdinalDictionary
        foreach ($pair in @(
            @('src/AIContextBuilder.Codeunit.al', 34),
            @('src/CustomerDataExporter.Codeunit.al', 29),
            @('src/ExternalCRMSync.Codeunit.al', 42),
            @('src/OutboxEmailDispatcher.Codeunit.al', 57)
        )) {
            $normalizationSources[$pair[0]] = @{ exists = $true; line_count = $pair[1] }
        }
        $normalizationKnowledge = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $normalizationPrimary = 'microsoft/knowledge/privacy/privacy-notice-consent-for-external-data-transfer.md'
        $null = $normalizationKnowledge.Add($normalizationPrimary)
        $normalizationContext = [pscustomobject]@{
            SourceFiles = $normalizationSources
            KnowledgePaths = $normalizationKnowledge
        }
    }

    BeforeEach {
        $normalizationReport = $normalizationRaw | ConvertFrom-Json
    }

    It 'normalizes all four IDs and ranges in one private candidate without changing any other value' {
        $before = (Get-FileHash $normalizationFixture).Hash
        $accepted = New-AcceptedLeafReport -ReportText $normalizationRaw -Schema $normalizationSchema -Context $normalizationContext
        $accepted.Changes.Count | Should -Be 8
        @($accepted.Report.findings).Count | Should -Be 4
        $accepted.Report.findings.id | Should -Be (@($normalizationPrimary) * 4)
        for ($index = 0; $index -lt 4; $index++) {
            $accepted.Report.findings[$index].location.PSObject.Properties.Match('range').Count | Should -Be 0
            $idChange = $accepted.Changes[$index]
            $idChange.kind | Should -Be 'finding-id'
            $idChange.finding_index | Should -Be $index
            $idChange.original_id | Should -Be $normalizationReport.findings[$index].id
            $idChange.canonical_id | Should -Be $normalizationPrimary
            $rangeChange = $accepted.Changes[$index + 4]
            $rangeChange.kind | Should -Be 'location-range'
            $rangeChange.finding_index | Should -Be $index
            $rangeChange.line | Should -Be $normalizationReport.findings[$index].location.line
            ($rangeChange.original_range | ConvertTo-Json) |
                Should -Be ($normalizationReport.findings[$index].location.range | ConvertTo-Json)
            $normalizationReport.findings[$index].id = $normalizationPrimary
            $normalizationReport.findings[$index].location.PSObject.Properties.Remove('range')
        }
        ($accepted.Report | ConvertTo-Json -Depth 40) | Should -Be ($normalizationReport | ConvertTo-Json -Depth 40)
        ($accepted.Text | Test-Json -Schema $normalizationSchema) | Should -BeTrue
        (Get-FileHash $normalizationFixture).Hash | Should -Be $before
    }

    It 'leaves canonical reports and telemetry unchanged on repeated acceptance' {
        $accepted = New-AcceptedLeafReport -ReportText $normalizationRaw -Schema $normalizationSchema -Context $normalizationContext
        $canonical = " `r`n$($accepted.Text)`r`n`t"
        $again = New-AcceptedLeafReport -ReportText $canonical -Schema $normalizationSchema -Context $normalizationContext
        $again.Text | Should -BeExactly $canonical
        $again.Changes.Count | Should -Be 0
        ($again.Report | ConvertTo-Json -Depth 40) | Should -Be ($accepted.Report | ConvertTo-Json -Depth 40)
    }

    It 'preserves untouched timestamp-shaped strings instead of applying PowerShell date conversion' {
        $text = $normalizationRaw.Replace('Synthetic AI request privacy finding.', '2026-10-05T13:00:00+05:30')
        $accepted = New-AcceptedLeafReport -ReportText $text -Schema $normalizationSchema -Context $normalizationContext
        $accepted.Text | Should -Match ([regex]::Escape('"2026-10-05T13:00:00+05:30"'))
        $accepted.Changes.Count | Should -Be 8
    }

    It 'canonicalizes cited IDs without requiring a location or removing a valid range' {
        $normalizationReport.findings[0].PSObject.Properties.Remove('location')
        $normalizationReport.findings[1].location.range.'start-line' = $normalizationReport.findings[1].location.line
        $normalizationReport.findings[1] | Add-Member -NotePropertyName 'suggested-code' -NotePropertyValue 'SafeReplacement();'
        $accepted = New-AcceptedLeafReport -ReportText ($normalizationReport | ConvertTo-Json -Depth 40) -Schema $normalizationSchema -Context $normalizationContext
        $accepted.Changes.Count | Should -Be 6
        $accepted.Report.findings[0].PSObject.Properties.Match('location').Count | Should -Be 0
        $accepted.Report.findings[1].location.range.'start-line' | Should -Be 24
        $accepted.Report.findings[1].'suggested-code' | Should -Be 'SafeReplacement();'
    }

    It 'permits existing range-only normalization for valid uncited agent findings without changing their IDs' {
        foreach ($finding in $normalizationReport.findings) {
            $finding.references = @()
            $finding.id = 'agent:valid-concern'
            $finding.severity = 'minor'
            $finding.confidence = 'medium'
        }
        $normalizationReport.summary.counts.major = 0
        $normalizationReport.summary.counts.minor = 4
        $accepted = New-AcceptedLeafReport -ReportText ($normalizationReport | ConvertTo-Json -Depth 40) -Schema $normalizationSchema -Context $normalizationContext
        $accepted.Changes.Count | Should -Be 4
        @($accepted.Changes | Where-Object kind -eq 'finding-id').Count | Should -Be 0
        $accepted.Report.findings.id | Should -Be (@('agent:valid-concern') * 4)
        $accepted.Report.findings.confidence | Should -Be (@('medium') * 4)
    }

    It 'rejects the whole candidate for an unrelated defect: <Name>' -ForEach @(
        @{ Name = 'unsafe reference'; Mutate = { $normalizationReport.findings[3].references[0].path = '../outside.md' } },
        @{ Name = 'unknown reference'; Mutate = { $normalizationReport.findings[3].references[0].path = 'microsoft/knowledge/privacy/unknown.md' } },
        @{ Name = 'unknown supporting reference'; Mutate = { $normalizationReport.findings[3].references += [pscustomobject]@{ path = 'microsoft/knowledge/privacy/unknown.md' } } },
        @{ Name = 'wrong reference case'; Mutate = { $normalizationReport.findings[3].references[0].path = $normalizationPrimary.ToUpperInvariant() } },
        @{ Name = 'malformed reference object'; Mutate = { $normalizationReport.findings[3].references[0] | Add-Member -NotePropertyName extra -NotePropertyValue $true } },
        @{ Name = 'cited agent ID'; Mutate = { $normalizationReport.findings[3].id = 'agent:cited' } },
        @{ Name = 'qualified cited agent ID'; Mutate = { $normalizationReport.findings[3].id = 'al-privacy-review:agent:cited' } },
        @{ Name = 'leaf producer'; Mutate = { $normalizationReport.findings[3] | Add-Member -NotePropertyName 'from-sub-skill' -NotePropertyValue 'agent' } },
        @{ Name = 'uncited nonagent ID'; Mutate = { $normalizationReport.findings[3].references = @() } },
        @{ Name = 'high confidence agent'; Mutate = { $normalizationReport.findings[3].references = @(); $normalizationReport.findings[3].id = 'agent:uncited' } },
        @{ Name = 'high severity agent'; Mutate = { $normalizationReport.findings[3].references = @(); $normalizationReport.findings[3].id = 'agent:uncited'; $normalizationReport.findings[3].confidence = 'medium' } },
        @{ Name = 'blank ID'; Mutate = { $normalizationReport.findings[3].id = '' } },
        @{ Name = 'null ID'; Mutate = { $normalizationReport.findings[3].id = $null } },
        @{ Name = 'integer ID'; Mutate = { $normalizationReport.findings[3].id = 1 } },
        @{ Name = 'missing ID'; Mutate = { $normalizationReport.findings[3].PSObject.Properties.Remove('id') } },
        @{ Name = 'zero start'; Mutate = { $normalizationReport.findings[3].location.range.'start-line' = 0 } },
        @{ Name = 'string start'; Mutate = { $normalizationReport.findings[3].location.range.'start-line' = '18' } },
        @{ Name = 'fractional start'; Mutate = { $normalizationReport.findings[3].location.range.'start-line' = 18.5 } },
        @{ Name = 'extra range property'; Mutate = { $normalizationReport.findings[3].location.range | Add-Member -NotePropertyName extra -NotePropertyValue $true } },
        @{ Name = 'anchor outside range'; Mutate = { $normalizationReport.findings[3].location.range.'end-line' = 22 } },
        @{ Name = 'start after anchor'; Mutate = { $normalizationReport.findings[3].location.range.'start-line' = 24; $normalizationReport.findings[3].location.range.'end-line' = 25 } },
        @{ Name = 'reversed range'; Mutate = { $normalizationReport.findings[3].location.range.'end-line' = 17 } },
        @{ Name = 'out of bounds end'; Mutate = { $normalizationReport.findings[3].location.range.'end-line' = 58 } },
        @{ Name = 'out of bounds line'; Mutate = { $normalizationReport.findings[3].location.line = 58; $normalizationReport.findings[3].location.range.'end-line' = 58 } },
        @{ Name = 'out of scope source'; Mutate = { $normalizationReport.findings[3].location.file = 'src/unknown.al' } },
        @{ Name = 'suggested-code range'; Mutate = { $normalizationReport.findings[3] | Add-Member -NotePropertyName 'suggested-code' -NotePropertyValue 'Replacement();' } },
        @{ Name = 'empty suggested-code'; Mutate = { $normalizationReport.findings[3] | Add-Member -NotePropertyName 'suggested-code' -NotePropertyValue '' } },
        @{ Name = 'null suggested-code'; Mutate = { $normalizationReport.findings[3] | Add-Member -NotePropertyName 'suggested-code' -NotePropertyValue $null } },
        @{ Name = 'incorrect counts'; Mutate = { $normalizationReport.summary.counts.major = 3 } },
        @{ Name = 'incomplete completed coverage'; Mutate = { $normalizationReport.summary.coverage.'items-evaluated' = 1 } },
        @{ Name = 'leaf role'; Mutate = { $normalizationReport | Add-Member -NotePropertyName 'sub-results' -NotePropertyValue @() } }
    ) {
        & $Mutate
        $raw = $normalizationReport | ConvertTo-Json -Depth 40
        $acceptedOutput = [Collections.Generic.List[object]]::new()
        {
            New-AcceptedLeafReport -ReportText $raw -Schema $normalizationSchema -Context $normalizationContext |
                ForEach-Object { $acceptedOutput.Add($_) }
        } | Should -Throw
        $acceptedOutput.Count | Should -Be 0
        ($normalizationReport | ConvertTo-Json -Depth 40) | Should -BeExactly $raw
    }

    It 'rejects non-JSON output instead of normalizing it' {
        { New-AcceptedLeafReport -ReportText "prefix $normalizationRaw" -Schema $normalizationSchema -Context $normalizationContext } |
            Should -Throw
    }

    It 'rejects URI and wildcard metacharacters even in inventoried reference paths: <_>' -ForEach @(
        'microsoft/knowledge/privacy/encoded%20article.md',
        'microsoft/knowledge/privacy/article#fragment.md',
        'microsoft/knowledge/privacy/article?query.md',
        'microsoft/knowledge/privacy/wildcard*.md',
        "microsoft/knowledge/privacy/control$([char]0x7f).md"
    ) {
        $path = $_
        $null = $normalizationContext.KnowledgePaths.Add($path)
        try {
            $normalizationReport.findings[3].references[0].path = $path
            { New-AcceptedLeafReport -ReportText ($normalizationReport | ConvertTo-Json -Depth 40) -Schema $normalizationSchema -Context $normalizationContext } |
                Should -Throw '*not a safe repo-relative knowledge path*'
        }
        finally {
            $null = $normalizationContext.KnowledgePaths.Remove($path)
        }
    }
}

Describe 'Runtime leaf source-bound schemas and prompt' {
    BeforeAll {
        $boundedShared = Get-Content -LiteralPath $NormalizationSchemaPath -Raw
        $cumulativeFixture = Join-Path $PSScriptRoot 'fixtures/findings-consumer/privacy-015-cumulative-lines.json'
        $cumulativeRaw = Get-Content -LiteralPath $cumulativeFixture -Raw
        # V4 run 37586436198, privacy-015/al-error-handling-review:
        # original SHA256 e91576b806136b17aa7ef02a30a0b827973506cb49757ac1e1226e53e2eec06d.
        # stdout records one `nl -ba` invocation with these four files in order.
        $v4Counts = [ordered]@{
            'src/AIContextBuilder.Codeunit.al' = 34
            'src/CustomerDataExporter.Codeunit.al' = 29
            'src/ExternalCRMSync.Codeunit.al' = 42
            'src/OutboxEmailDispatcher.Codeunit.al' = 57
        }
    }
    BeforeEach {
        $boundedSources = Get-OrdinalDictionary
        foreach ($entry in $v4Counts.GetEnumerator()) {
            $boundedSources[$entry.Key] = @{ path = $entry.Key; exists = $true; line_count = $entry.Value }
        }
        $boundedSchemas = New-FindingsReportRoleSchemas -SharedSchemaJson $boundedShared -SourceFiles $boundedSources
        $boundedReport = $cumulativeRaw | ConvertFrom-Json -AsHashtable
        $boundedReport.findings[0].location.line = 24
        $boundedReport.findings[1].location.line = 35
        $boundedReport.findings[1].location.range.'start-line' = 35
        $boundedReport.findings[1].location.range.'end-line' = 36
        $script:FindingsConsumerContext = [pscustomobject]@{ SourceFiles = $boundedSources }
        $script:CopilotExecutable = 'C:\tools\copilot.exe'
        $AnalysisWorkspace = 'C:\review-target'
        $BCQualityRoot = 'C:\bcquality'
        $DiffRange = 'origin/main...HEAD'
        $ReviewPathSpec = ''
        $ReviewSource = 'local'
        $GitHubServerUrl = 'https://github.com'
        $LeafModel = 'gpt-5.6-luna'
        $CopilotLogLevel = 'info'
        $LeafReportSchemaFileName = '_review-findings-report.leaf.schema.json'
        $ReportFileName = '_review-report.json'
        $promptLeaf = [pscustomobject]@{ id = 'al-error-handling-review'; version = 1; path = 'microsoft/skills/review/al-error-handling-review.md' }
    }

    It 'rejects the exact V4 coordinates that unbounded role schemas admitted' {
        $base = New-FindingsReportRoleSchemas -SharedSchemaJson $boundedShared
        ($cumulativeRaw | Test-Json -Schema $base.Leaf) | Should -BeTrue
        ($cumulativeRaw | Test-Json -Schema $boundedSchemas.Leaf -ErrorAction SilentlyContinue) | Should -BeFalse
        $location = ($boundedSchemas.Leaf | ConvertFrom-Json -AsHashtable).definitions.location
        $exporter = @($location.allOf | Where-Object { $_.Contains('if') -and $_.if.properties.file.const -ceq 'src/CustomerDataExporter.Codeunit.al' })[0]
        $exporter.then.properties.line.maximum | Should -Be 29
        $crm = @($location.allOf | Where-Object { $_.Contains('if') -and $_.if.properties.file.const -ceq 'src/ExternalCRMSync.Codeunit.al' })[0]
        $crm.then.properties.line.maximum | Should -Be 42
        $crm.then.properties.range.properties.'start-line'.maximum | Should -Be 42
        $crm.then.properties.range.properties.'end-line'.maximum | Should -Be 42
    }

    It 'explains every V4 bad coordinate by multi-file nl accumulation rather than patch offsets' {
        $original = $cumulativeRaw | ConvertFrom-Json
        $original.findings[0].location.line | Should -Be (34 + 24)
        $original.findings[1].location.line | Should -Be (34 + 29 + 35)
        $original.findings[1].location.range.'start-line' | Should -Be (34 + 29 + 24)
        $original.findings[1].location.range.'end-line' | Should -Be (34 + 29 + 36)
        # Native git diff positions reconstructed from the same new-file source.
        $original.findings[0].location.line | Should -Not -Be 70
        $original.findings[1].location.line | Should -Not -Be 116
    }

    It 'enforces structural source bounds for <Name>' -ForEach @(
        @{ Name = 'first line'; Valid = $true; Mutate = { $boundedReport.findings[0].location.line = 1 } },
        @{ Name = 'last line'; Valid = $true; Mutate = { $boundedReport.findings[0].location.line = 29 } },
        @{ Name = 'no locations'; Valid = $true; Mutate = { foreach ($finding in $boundedReport.findings) { $finding.Remove('location') } } },
        @{ Name = 'no range'; Valid = $true; Mutate = { $boundedReport.findings[1].location.Remove('range') } },
        @{ Name = 'exporter overflow'; Valid = $false; Mutate = { $boundedReport.findings[0].location.line = 58 } },
        @{ Name = 'CRM overflow'; Valid = $false; Mutate = { $boundedReport.findings[1].location.line = 98 } },
        @{ Name = 'range start overflow'; Valid = $false; Mutate = { $boundedReport.findings[1].location.range.'start-line' = 87 } },
        @{ Name = 'range end overflow'; Valid = $false; Mutate = { $boundedReport.findings[1].location.range.'end-line' = 99 } },
        @{ Name = 'unknown path'; Valid = $false; Mutate = { $boundedReport.findings[0].location.file = 'src/Unknown.al' } },
        @{ Name = 'path case'; Valid = $false; Mutate = { $boundedReport.findings[0].location.file = 'src/customerdataexporter.Codeunit.al' } },
        @{ Name = 'absolute path'; Valid = $false; Mutate = { $boundedReport.findings[0].location.file = '/src/CustomerDataExporter.Codeunit.al' } },
        @{ Name = 'backslash path'; Valid = $false; Mutate = { $boundedReport.findings[0].location.file = 'src\CustomerDataExporter.Codeunit.al' } },
        @{ Name = 'null location'; Valid = $false; Mutate = { $boundedReport.findings[0].location = $null } },
        @{ Name = 'zero line'; Valid = $false; Mutate = { $boundedReport.findings[0].location.line = 0 } },
        @{ Name = 'fractional line'; Valid = $false; Mutate = { $boundedReport.findings[0].location.line = 24.5 } },
        @{ Name = 'string line'; Valid = $false; Mutate = { $boundedReport.findings[0].location.line = '24' } },
        @{ Name = 'missing line'; Valid = $false; Mutate = { $boundedReport.findings[0].location.Remove('line') } },
        @{ Name = 'extra field'; Valid = $false; Mutate = { $boundedReport.findings[0].location['extra'] = $true } },
        @{ Name = 'range relation stays semantic'; Valid = $true; Mutate = { $boundedReport.findings[1].location.range.'start-line' = 24 } }
    ) {
        & $Mutate
        [bool](($boundedReport | ConvertTo-Json -Depth 40) | Test-Json -Schema $boundedSchemas.Leaf -ErrorAction SilentlyContinue) |
            Should -Be $Valid
    }

    It 'rejects any present location with only empty or deleted source files while keeping omission valid' {
        $none = Get-OrdinalDictionary
        $none['src/Empty.al'] = @{ exists = $true; line_count = 0 }
        $none['src/Deleted.al'] = @{ exists = $false; line_count = $null }
        foreach ($scope in @($none, (Get-OrdinalDictionary))) {
            $schemas = New-FindingsReportRoleSchemas -SharedSchemaJson $boundedShared -SourceFiles $scope
            (($boundedReport | ConvertTo-Json -Depth 40) | Test-Json -Schema $schemas.Leaf -ErrorAction SilentlyContinue) | Should -BeFalse
            $without = $boundedReport | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
            foreach ($finding in $without.findings) { $finding.Remove('location') }
            (($without | ConvertTo-Json -Depth 40) | Test-Json -Schema $schemas.Leaf) | Should -BeTrue
        }
    }

    It 'appends source constraints without replacing existing location restrictions' {
        $shared = $boundedShared | ConvertFrom-Json -AsHashtable
        $shared.definitions.location['allOf'] = @(@{ properties = @{ line = @{ maximum = 10 } } })
        $schemas = New-FindingsReportRoleSchemas -SharedSchemaJson ($shared | ConvertTo-Json -Depth 100) -SourceFiles $boundedSources
        ($schemas.Leaf | ConvertFrom-Json -AsHashtable).definitions.location.allOf[0].properties.line.maximum | Should -Be 10
        (($boundedReport | ConvertTo-Json -Depth 40) | Test-Json -Schema $schemas.Leaf -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'keeps schema output identical under reordered source input' {
        $reversed = Get-OrdinalDictionary
        $keys = @($v4Counts.Keys)
        [array]::Reverse($keys)
        foreach ($key in $keys) { $reversed[$key] = $boundedSources[$key] }
        $schemas = New-FindingsReportRoleSchemas -SharedSchemaJson $boundedShared -SourceFiles $reversed
        $schemas.Leaf | Should -BeExactly $boundedSchemas.Leaf
        $schemas.Root | Should -BeExactly $boundedSchemas.Root
    }

    It 'constrains nested leaves without changing root self-review locations or PR79 roles' {
        $root = $boundedReport | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
        $root.skill.id = 'al-code-review'
        $root['sub-results'] = @($boundedReport)
        $root.findings[0].location.line = 58
        (($root | ConvertTo-Json -Depth 40) | Test-Json -Schema $boundedSchemas.Root) | Should -BeTrue
        $root.'sub-results'[0].findings[0].location.line = 58
        (($root | ConvertTo-Json -Depth 40) | Test-Json -Schema $boundedSchemas.Root -ErrorAction SilentlyContinue) | Should -BeFalse
        $root.'sub-results'[0].findings[0].location.line = 24
        $root.'sub-results'[0]['sub-results'] = @()
        (($root | ConvertTo-Json -Depth 40) | Test-Json -Schema $boundedSchemas.Root -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'fails closed when the pinned location definition can no longer be safely intersected' {
        $shared = $boundedShared | ConvertFrom-Json -AsHashtable
        $shared.definitions.finding.properties.location.'$ref' = '#/definitions/newLocation'
        { New-FindingsReportRoleSchemas -SharedSchemaJson ($shared | ConvertTo-Json -Depth 100) -SourceFiles $boundedSources } |
            Should -Throw '*location/finding definition shape*'
    }

    It 'uses the captured snapshot despite tampered bounds, schema and expanded source files' {
        $AnalysisWorkspace = Join-Path $TestDrive 'bounded-target'
        $BCQualityRoot = Join-Path $TestDrive 'bounded-knowledge'
        $AgentWorkDir = $BCQualityRoot
        $RootReportSchemaFileName = '_review-findings-report.root.schema.json'
        New-Item -ItemType Directory -Path (Join-Path $AnalysisWorkspace 'src'), (Join-Path $BCQualityRoot 'schemas') -Force | Out-Null
        Set-Content (Join-Path $BCQualityRoot 'schemas/findings-report.schema.json') -Value $boundedShared
        foreach ($entry in $v4Counts.GetEnumerator()) {
            [IO.File]::WriteAllText((Join-Path $AnalysisWorkspace $entry.Key), ("source`n" * $entry.Value))
        }
        Initialize-FindingsConsumerContext -SourcePaths @($v4Counts.Keys)
        $before = $script:FindingsConsumerContext.SourceFiles | ConvertTo-Json -Depth 10
        Set-Content (Join-Path $AgentWorkDir '_review-source-bounds.json') -Value '{"files":[]}'
        [IO.File]::AppendAllText((Join-Path $AnalysisWorkspace 'src/CustomerDataExporter.Codeunit.al'), ("new`n" * 100))
        Initialize-FindingsReportRoleSchemas
        (Get-Content (Join-Path $AgentWorkDir $LeafReportSchemaFileName) -Raw).TrimEnd() | Should -BeExactly (Get-FindingsReportRoleSchema -Role leaf)
        Set-Content (Join-Path $AgentWorkDir $LeafReportSchemaFileName) -Value '{}'
        Set-Content (Join-Path $AgentWorkDir $RootReportSchemaFileName) -Value '{}'
        ($cumulativeRaw | Test-Json -Schema (Get-FindingsReportRoleSchema -Role leaf) -ErrorAction SilentlyContinue) | Should -BeFalse
        ($script:FindingsConsumerContext.SourceFiles | ConvertTo-Json -Depth 10) | Should -BeExactly $before
    }

    It 'requires source capture before runtime schema initialization' {
        $BCQualityRoot = Join-Path $TestDrive 'uncaptured-bcquality'
        $script:FindingsConsumerContext = $null
        { Initialize-FindingsReportRoleSchemas } | Should -Throw '*Source snapshot must be captured*'
    }

    It 'inlines the complete small scope with file-local viewing and self-validation instructions' {
        $prompt = New-LeafReviewPrompt -Leaf $promptLeaf -WorkDir $TestDrive
        foreach ($entry in $v4Counts.GetEnumerator()) {
            $prompt | Should -Match ([regex]::Escape(('"{0}": 1..{1}' -f $entry.Key, $entry.Value)))
        }
        $prompt | Should -Match 'Line numbering restarts at 1 for every file'
        $prompt | Should -Match 'Never use multi-operand nl -ba'
        $prompt | Should -Match 'separate per-file line viewer'
        $prompt | Should -Match 'Self-validate the complete final JSON against the supplied leaf'
        $prompt | Should -Not -Match 'No truncated inline list'
        (Get-CommandLineCharacterUpperBound -Arguments (@($script:CopilotExecutable) + (Get-LeafCopilotArguments -Prompt $prompt -WorkDir $TestDrive))) |
            Should -BeLessOrEqual 24576
    }

    It 'JSON-quotes paths and describes every empty or deleted file in a small scope' {
        $boundedSources['src/A "quoted".al'] = @{ exists = $true; line_count = 2 }
        $boundedSources['src/Empty.al'] = @{ exists = $true; line_count = 0 }
        $boundedSources['src/Deleted.al'] = @{ exists = $false; line_count = $null }
        $prompt = New-LeafReviewPrompt -Leaf $promptLeaf -WorkDir $TestDrive
        $prompt | Should -Match ([regex]::Escape('"src/A \"quoted\".al": 1..2'))
        $prompt | Should -Match ([regex]::Escape('"src/Empty.al": no valid final-source lines'))
        $prompt | Should -Match ([regex]::Escape('"src/Deleted.al": no valid final-source lines'))
    }

    It 'omits the entire inline list for a large scope without weakening the complete schema' {
        foreach ($i in 1..150) { $boundedSources["src/AdditionalLongRepresentativeFile$i.Codeunit.al"] = @{ exists = $true; line_count = 100 } }
        $prompt = New-LeafReviewPrompt -Leaf $promptLeaf -WorkDir $TestDrive
        $prompt | Should -Match 'complete 154-entry line-limit list'
        $prompt | Should -Match 'read it in full. No truncated inline list'
        $prompt | Should -Not -Match 'Complete final-source line limits'
        $prompt | Should -Not -Match '"src/.*": 1\.\.'
        $schema = (New-FindingsReportRoleSchemas -SharedSchemaJson $boundedShared -SourceFiles $boundedSources).Leaf | ConvertFrom-Json -AsHashtable
        $schema.definitions.location.allOf[0].properties.file.enum.Count | Should -Be 154
        (Get-CommandLineCharacterUpperBound -Arguments (@($script:CopilotExecutable) + (Get-LeafCopilotArguments -Prompt $prompt -WorkDir $TestDrive))) |
            Should -BeLessOrEqual 24576
    }

    It 'accounts for executable and non-prompt arguments before admitting a small inline list' {
        $inline = New-LeafReviewPrompt -Leaf $promptLeaf -WorkDir $TestDrive
        $initialBound = Get-CommandLineCharacterUpperBound -Arguments (@($script:CopilotExecutable) + (Get-LeafCopilotArguments -Prompt $inline -WorkDir $TestDrive))
        $extraCharacters = [int][Math]::Ceiling((24576 + 50 - $initialBound) / 2)
        $script:CopilotExecutable += 'x' * $extraCharacters
        $prompt = New-LeafReviewPrompt -Leaf $promptLeaf -WorkDir $TestDrive
        $prompt | Should -Match 'No truncated inline list'
        (Get-CommandLineCharacterUpperBound -Arguments (@($script:CopilotExecutable) + (Get-LeafCopilotArguments -Prompt $prompt -WorkDir $TestDrive))) |
            Should -BeLessOrEqual 24576
        (Get-CommandLineCharacterUpperBound -Arguments @('', 'a"b\', 'path with space', ([string][char]0x4e2d))) |
            Should -Be (1 + 3 + (2 * 4 + 3) + (2 * 15 + 3) + 5)
    }
}

Describe 'Findings-report role contracts derived from the pinned BCQuality schema' {
    BeforeAll {
        # The fixture is BCQuality schemas/findings-report.schema.json at the
        # pinned ref b74967bc (identical at 130d5de6). The leaf-*.json fixtures
        # are unmodified leaf reports from BC-Bench run 36852068369.
        $fixtureRoot = Join-Path $PSScriptRoot 'fixtures/findings-report-roles'
        $sharedSchema = Get-Content -LiteralPath (Join-Path $fixtureRoot 'bcquality-findings-report.b74967bc.schema.json') -Raw
        $roleSchemas = New-FindingsReportRoleSchemas -SharedSchemaJson $sharedSchema
        $script:FindingsReportRoleSchemas = $roleSchemas

        function Test-RoleContract {
            param([string] $Json, [string] $Schema)
            return [bool]($Json | Test-Json -Schema $Schema -ErrorAction SilentlyContinue)
        }
        function New-LeafReport {
            param([string] $Id, [string] $Outcome = 'not-applicable', [hashtable] $Extra = @{})
            $report = [ordered]@{
                skill = [ordered]@{ id = $Id; version = 1 }
                outcome = $Outcome
                summary = [ordered]@{
                    counts = [ordered]@{ blocker = 0; major = 0; minor = 0; info = 0 }
                    coverage = [ordered]@{ 'worklist-size' = 0; 'items-evaluated' = 0 }
                }
                findings = @()
                suppressed = @()
            }
            foreach ($key in $Extra.Keys) { $report[$key] = $Extra[$key] }
            return $report
        }
        function New-RootReport {
            param([object[]] $SubResults, [hashtable] $Extra = @{})
            $report = New-LeafReport -Id 'al-code-review' -Outcome 'completed'
            $report['sub-results'] = $SubResults
            foreach ($key in $Extra.Keys) { $report[$key] = $Extra[$key] }
            return $report
        }
        $completedLeafJson = Get-Content -LiteralPath (Join-Path $fixtureRoot 'leaf-completed.security-clean-02.al-error-handling-review.json') -Raw
    }

    It 'rejects the observed malformed leaf <Name> while the shared schema accepts it' -ForEach @(
        @{ Name = 'privacy-015.al-query-review' },
        @{ Name = 'http-consumed-false-01.al-finance-review' },
        @{ Name = 'privacy-015-attempt2.al-finance-review' }
    ) {
        $json = Get-Content -LiteralPath (Join-Path $fixtureRoot "leaf-not-applicable-root-fields.$Name.json") -Raw
        $report = $json | ConvertFrom-Json

        $report.outcome | Should -Be 'not-applicable'
        Test-RoleContract -Json $json -Schema $sharedSchema | Should -BeTrue
        Test-RoleContract -Json $json -Schema $roleSchemas.Leaf | Should -BeFalse
        { Assert-LeafReportRole -ReportObject $report } |
            Should -Throw '*super-skill-only field(s): sub-results, skipped-sub-skills*'
    }

    It 'rejects <Field> in a <Outcome> leaf even when empty' -ForEach @(
        @{ Field = 'sub-results'; Outcome = 'not-applicable' },
        @{ Field = 'skipped-sub-skills'; Outcome = 'not-applicable' },
        @{ Field = 'sub-results'; Outcome = 'completed' },
        @{ Field = 'skipped-sub-skills'; Outcome = 'completed' }
    ) {
        $json = New-LeafReport -Id 'al-query-review' -Outcome $Outcome -Extra @{ $Field = @() } |
            ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $sharedSchema | Should -BeTrue
        Test-RoleContract -Json $json -Schema $roleSchemas.Leaf | Should -BeFalse
    }

    It 'keeps valid real and synthetic leaf reports valid' {
        Test-RoleContract -Json $completedLeafJson -Schema $roleSchemas.Leaf | Should -BeTrue
        $notApplicable = New-LeafReport -Id 'al-query-review' -Extra @{ 'outcome-reason' = 'No query objects changed.' } |
            ConvertTo-Json -Depth 20
        Test-RoleContract -Json $notApplicable -Schema $roleSchemas.Leaf | Should -BeTrue
    }

    It 'preserves shared constraints in the leaf contract' {
        $failedWithoutReason = New-LeafReport -Id 'al-query-review' -Outcome 'failed' | ConvertTo-Json -Depth 20
        $notApplicableWithFinding = ($completedLeafJson | ConvertFrom-Json -AsHashtable)
        $notApplicableWithFinding['outcome'] = 'not-applicable'
        $unknownField = New-LeafReport -Id 'al-query-review' -Extra @{ provenance = 'x' } | ConvertTo-Json -Depth 20

        Test-RoleContract -Json $failedWithoutReason -Schema $roleSchemas.Leaf | Should -BeFalse
        Test-RoleContract -Json ($notApplicableWithFinding | ConvertTo-Json -Depth 20) -Schema $roleSchemas.Leaf | Should -BeFalse
        Test-RoleContract -Json $unknownField -Schema $roleSchemas.Leaf | Should -BeFalse
    }

    It 'accepts root-only fields at the root with valid leaf sub-results' {
        $root = New-RootReport -SubResults @(
            ($completedLeafJson | ConvertFrom-Json -AsHashtable),
            (New-LeafReport -Id 'al-query-review'),
            (New-LeafReport -Id 'al-finance-review' -Outcome 'failed' -Extra @{ 'outcome-reason' = 'Leaf report was unusable.' })
        ) -Extra @{ 'skipped-sub-skills' = @(@{ skill = @{ id = 'al-testing-review'; version = 1 }; reason = 'configuration' }) }
        $json = $root | ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $roleSchemas.Root | Should -BeTrue
    }

    It 'does not require root-only fields in nested leaves' {
        $json = New-RootReport -SubResults @(New-LeafReport -Id 'al-query-review') | ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $roleSchemas.Root | Should -BeTrue
    }

    It 'requires sub-results at the root' {
        $json = New-LeafReport -Id 'al-code-review' -Outcome 'completed' | ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $sharedSchema | Should -BeTrue
        Test-RoleContract -Json $json -Schema $roleSchemas.Root | Should -BeFalse
    }

    It 'rejects an observed malformed leaf nested in a root report' {
        $nested = Get-Content -LiteralPath (Join-Path $fixtureRoot 'leaf-not-applicable-root-fields.privacy-015.al-query-review.json') -Raw |
            ConvertFrom-Json -AsHashtable
        $json = New-RootReport -SubResults @($nested) | ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $sharedSchema | Should -BeTrue
        Test-RoleContract -Json $json -Schema $roleSchemas.Root | Should -BeFalse
    }

    It 'still validates nested leaf content against shared definitions' {
        $badLeaf = New-LeafReport -Id 'al-query-review' -Outcome 'failed'
        $json = New-RootReport -SubResults @($badLeaf) | ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $roleSchemas.Root | Should -BeFalse
    }

    It 'accepts the local not-applicable root shape written without leaf execution' {
        $json = New-RootReport -SubResults @() -Extra @{ outcome = 'not-applicable'; 'skipped-sub-skills' = @() } |
            ConvertTo-Json -Depth 20

        Test-RoleContract -Json $json -Schema $roleSchemas.Root | Should -BeTrue
    }

    It 'derives the leaf contract by removal only and identifies its source' {
        $shared = $sharedSchema | ConvertFrom-Json -AsHashtable
        $leaf = $roleSchemas.Leaf | ConvertFrom-Json -AsHashtable
        $root = $roleSchemas.Root | ConvertFrom-Json -AsHashtable

        $leaf.properties.Keys | Sort-Object |
            Should -Be (@($shared.properties.Keys | Where-Object { $_ -notin 'sub-results', 'skipped-sub-skills' }) | Sort-Object)
        $leaf.required | Should -Be $shared.required
        $leaf.additionalProperties | Should -BeFalse
        $leaf['$comment'] | Should -Match ([regex]::Escape([string]$shared['$id']))
        $root.required | Should -Contain 'sub-results'
        $root.properties['sub-results'].items['$ref'] | Should -Be '#/definitions/leafReport'
        $root.definitions.leafReport.properties.Keys | Sort-Object | Should -Be ($leaf.properties.Keys | Sort-Object)
    }

    It 'fails closed when the shared schema <Name>' -ForEach @(
        @{ Name = 'allows additional properties'; Mutate = { param($s) $s.Remove('additionalProperties') } },
        @{ Name = 'drops sub-results'; Mutate = { param($s) $s.properties.Remove('sub-results') } },
        @{ Name = 'drops skipped-sub-skills'; Mutate = { param($s) $s.properties.Remove('skipped-sub-skills') } },
        @{ Name = 'stops recursing sub-results'; Mutate = { param($s) $s.properties['sub-results'].items = @{ '$ref' = '#/definitions/finding' } } },
        @{ Name = 'requires sub-results'; Mutate = { param($s) $s.required = @($s.required) + 'sub-results' } },
        @{ Name = 'already defines leafReport'; Mutate = { param($s) $s.definitions['leafReport'] = @{} } },
        @{ Name = 'references a root-only field elsewhere'; Mutate = { param($s) $s.definitions.finding.properties['sub-results'] = @{ type = 'array' } } }
    ) {
        $shared = $sharedSchema | ConvertFrom-Json -AsHashtable
        & $Mutate $shared

        { New-FindingsReportRoleSchemas -SharedSchemaJson ($shared | ConvertTo-Json -Depth 100) } |
            Should -Throw '*Cannot derive role-specific findings-report schemas*'
    }
}
