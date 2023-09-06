$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

$env:GITHUB_OUTPUT = [System.IO.Path]::GetTempFileName()

function iReplace {
    Param(
        [string] $string,
        [string] $source,
        [string] $replace
    )

    if ("$source" -eq "") {
        throw "source is empty"
    }
    do {
        $idx = $string.IndexOf($source, [System.StringComparison]::InvariantCultureIgnoreCase)
        if ($idx -ge 0) {
            $string = "$($string.SubString(0,$idx))$replace$($string.SubString($idx+$source.Length))"
        }
    } while ($idx -ge 0)
    $string
}

<#
.SYNOPSIS
Get the action script from a script file
#>
function GetActionScript {
    Param(
        [string] $scriptRoot,
        [string] $scriptName
    )

    $scriptPath = Join-Path $ScriptRoot $scriptName -Resolve
    $actionname = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)

    $actionScript = Get-Content -raw -path $scriptPath
    $actionScript = "function $actionName {`n$actionScript`n}"

    # resolve psscriptroot references
    $actionScript = iReplace -string $actionScript -source '$psscriptroot' -replace "'$scriptRoot'"
    $actionScript
}

<#
.SYNOPSIS
Test the yaml structure of an action
#>
function YamlTest {
    Param(
        [string] $scriptRoot,
        [string] $actionName,
        [string] $actionScript,
        $permissions = @{},
        $outputs = @{}
    )

    $emptyActionScript = "function emptyAction {`n[CmdletBinding()]`nParam()`n}`n"
    Invoke-Expression $emptyActionScript
    $emptyCmd = get-command emptyAction
    $systemParameters = @($emptyCmd.Parameters.Keys.GetEnumerator() | ForEach-Object { $_ })

    Invoke-Expression $actionScript

    $yaml = [System.Text.StringBuilder]::new()
    $yaml.AppendLine("name: *") | Out-Null
    $yaml.AppendLine("author: *") | Out-Null
    if ($permissions -and $permissions.Count -gt 0) {
        $yaml.AppendLine("permissions:") | Out-Null
        $permissions.Keys | ForEach-Object {
            $yaml.AppendLine("  $($_): $($permissions."$_")") | Out-Null
        }
    }
    $cmd = get-command $actionname
    $yaml.AppendLine("inputs:") | Out-Null
    $yaml.AppendLine("  shell:") | Out-Null
    $yaml.AppendLine("    description: Shell in which you want to run the action (powershell or pwsh)") | Out-Null
    $yaml.AppendLine("    required: false") | Out-Null
    $yaml.AppendLine("    default: powershell") | Out-Null
    $parameterString = ""
    $warningLines = @()
    $envLines = [System.Text.StringBuilder]::new()
    if ($cmd.Parameters.Count -gt 0) {
        $cmd.Parameters.GetEnumerator() | ForEach-Object {
            $name = $_.Key
            if ($name -notin $systemParameters) {
                $value = $_.Value
                $description = $value.ParameterSets.__allParameterSets.HelpMessage
                if (!($description)) { $description = "*" }
                $required = $value.ParameterSets.__allParameterSets.IsMandatory
                $type = $value.ParameterType.ToString()
                $yaml.AppendLine("  $($name):") | Out-Null
                $yaml.AppendLine("    description: $description") | Out-Null
                if ($name -ne 'GitHubSecrets') {
                    $envLines.AppendLine("        _$($name): `${{ inputs.$($name) }}")
                }
                $yaml.AppendLine("    required: $($required.ToString().ToLowerInvariant())") | Out-Null
                if ($type -eq "System.String" -or $type -eq "System.Int32") {
                    if ($name -eq 'GitHubSecrets') {
                        $parameterString += ' -gitHubSecrets ''${{ inputs.gitHubSecrets }}'''
                    }
                    else {
                        $parameterString += " -$($name) `$ENV:_$($name)"
                    }
                    if (!$required) {
                        $yaml.AppendLine("    default: *") | Out-Null
                    }
                }
                elseif ($type -eq "System.Boolean") {
                    $parameterString += " -$($name) (`$ENV:_$($name) -eq 'Y')"
                    if (!$required) {
                        $yaml.AppendLine("    default: 'N'") | Out-Null
                    }
                }
                else {
                    throw "Unknown parameter type: $type. Only String, Int and Bool allowed"
                }
            }
        }
    }
    if ($outputs -and $outputs.Count -gt 0) {
        $yaml.AppendLine("outputs:") | Out-Null
        $outputs.Keys | ForEach-Object {
            $yaml.AppendLine("  $($_):") | Out-Null
            $yaml.AppendLine("    description: $($outputs."$_")") | Out-Null
            $yaml.AppendLine("    value: `${{ steps.$($actionname.ToLowerInvariant()).outputs.$($_) }}") | Out-Null
        }
    }
    $yaml.AppendLine("runs:") | Out-Null
    $yaml.AppendLine("  using: composite") | Out-Null
    $yaml.AppendLine("  steps:") | Out-Null
    $yaml.AppendLine("    - name: run") | Out-Null
    $yaml.AppendLine('      shell: ${{ inputs.shell }}') | Out-Null
    if ($outputs -and $outputs.Count -gt 0) {
        $yaml.AppendLine("      id: $($actionname.ToLowerInvariant())") | Out-Null
    }
    if ($envLines.Length -gt 0) {
        $yaml.AppendLine("      env:") | Out-Null
        $yaml.Append($envLines.ToString())
    }
    if ($warningLines) {
        $yaml.AppendLine("      run: |") | Out-Null
        # Add the warning lines
        $warningLines | ForEach-Object {
            $yaml.AppendLine("        $_") | Out-Null
        }
    }
    else {
        $yaml.AppendLine("      run: |") | Out-Null
    }
    $yaml.AppendLine('        $errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0') | Out-Null
    $yaml.AppendLine("        try {") | Out-Null
    $yaml.AppendLine("          `${{ github.action_path }}/$actionName.ps1$parameterString") | Out-Null
    $yaml.AppendLine("        }") | Out-Null
    $yaml.AppendLine("        catch {") | Out-Null
    $yaml.AppendLine('          Write-Host "::ERROR::Unexpected error when running action. Error Message: $($_.Exception.Message.Replace("`r",'''').Replace("`n",'' '')), StackTrace: $($_.ScriptStackTrace.Replace("`r",'''').Replace("`n",'' <- ''))";') | Out-Null
    $yaml.AppendLine("          exit 1") | Out-Null
    $yaml.AppendLine("        }") | Out-Null
    $yaml.AppendLine("branding:") | Out-Null
    $yaml.AppendLine("  icon: terminal") | Out-Null
    $yaml.Append("  color: blue") | Out-Null

    $yamlLines = $yaml.ToString().Replace("`r","").Split("`n")
    $actualYaml = @(Get-Content -path (Join-Path $scriptRoot "action.yaml"))

    $i = 0
    while ($i -lt $yamlLines.Count -and $i -lt $actualYaml.count) {
        if ($yamlLines[$i] -ne $actualYaml[$i]) {
            $actualYaml[$i] | Should -BeLike $yamlLines[$i]
        }
        $i++
    }

    $yamlLines.Count | Should -be $actualYaml.Count
}

<#
.SYNOPSIS
Test that all actions are referenced from microsoft/AL-Go-Actions@<main|preview> or actions/ (by GitHub)
#>
function TestActionsReferences {
    param(
        [Parameter(Mandatory)]
        [string]$YamlPath
    )

    $yaml = Get-Content -Path $YamlPath -Raw

    # Test all referenced actions are coming from microsoft/AL-Go-Actions@<main|preview> or actions/ (by GitHub)
    $actionReferencePattern = 'uses:\s*(.*)@(.*)'

    $actionReferences = [regex]::matches($yaml, $actionReferencePattern)

    $alGoActionPattern = "^microsoft/AL-Go-Actions/*"
    $gitHubActionPattern = "^actions/*"

    $actionReferences | ForEach-Object {
        $origin = $_.Groups[1].Value
        $version = $_.Groups[2].Value

        $origin | Should -Match "($alGoActionPattern|$gitHubActionPattern)"

        if($origin -match $alGoActionPattern) {
            $version | Should -Match "main|preview"
        }
    }
}

<#
.SYNOPSIS
Test that all referenced workflows are coming from .github/workflows/
#>
function TestWorkflowReferences {
    param(
        [Parameter(Mandatory)]
        [string]$YamlPath
    )

    $yaml = Get-Content -Path $YamlPath -Raw

    # Test all referenced workflows are coming from .github/workflows/
    $alGoWorkflowReferencePatterns = 'uses:\s*(.*).(yaml|yml)'

    $workflowReferences = [regex]::matches($yaml, $alGoWorkflowReferencePatterns)

    $localWorkflowsPattern = '^./.github/workflows/*'

    $workflowReferences | ForEach-Object {
        $workflowPath = $_.Groups[1].Value
        $workflowPath | Should -Match "$localWorkflowsPattern"
    }
}

<#
.SYNOPSIS
Get all workflows in a path
#>
function GetWorkflowsInPath {
    param(
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [string]$Path
    )
    Process {
        return (Get-ChildItem -Path $Path -File -Recurse -Include ('*.yaml', '*.yml'))
    }
}

function PesterMatchHashtable($ActualValue, $ExpectedValue, [switch] $Negate) {
    $message = FindMismatchedHashtableValue -Prefix "" -ActualValue $ActualValue -ExpectedValue $ExpectedValue
    $success = $null -eq $message

    if ($success) {
        if ($Negate) {
            #expecting failure
            $success = $false
            $message = "Expected: '$ActualValue' to not match the expression '$ExpectedValue'"
        }
        # else - we can just return success
    }
    else {
        if ($Negate) {
            # expecting failure
            $success = $true
            $message = ""
        }
        # else - we can just return failure
    }
    return New-Object psobject -Property @{
        Succeeded      = $success
        FailureMessage = $message
    }
}

function FindMismatchedHashtableValue($Prefix, $ActualValue, $ExpectedValue) {
    foreach($expectedKey in $ExpectedValue.Keys) {
        if (-not($ActualValue.Keys -contains $expectedKey)){
            return "Expected key: '$Prefix$expectedKey', but missing in actual"
        }
        $expectedItem = $ExpectedValue[$expectedKey]
        $actualItem = $ActualValue[$expectedKey]
        if ($actualItem -is [array] -and $expectedItem -is [array]) {
            if ($actualItem.Count -ne $expectedItem.Count) {
                return "Value differs for array at key '$Prefix$expectedKey'. Expected count: $($expectedItem.Count), actual count: $($actualItem.Count)"
            }
            0..($actualItem.Count-1) | ForEach-Object {
                if ($actualItem[$_] -is [hashtable] -and $expectedItem[$_] -is [hashtable]) {
                    $message = FindMismatchedHashtableValue -Prefix "$($Prefix)$($expectedKey)[$_]." -ActualValue $actualItem[$_] -ExpectedValue $expectedItem[$_]
                    if ($message) {
                        return $message
                    }
                }
                elseif (-not ($actualItem[$_] -eq $expectedItem[$_])) {
                    return "Value differs for key '$($Prefix)$($expectedKey)[$_]'. Expected value: '$($expectedItem[$_])', actual value: '$($actualItem[$_])'"
                }
            }
        }
        elseif ($actualItem -is [hashtable] -and $expectedItem -is [hashtable]) {
            $message = FindMismatchedHashtableValue -Prefix "$($Prefix)$($expectedKey)." -ActualValue $actualItem -ExpectedValue $expectedItem
            if ($message) {
                return $message
            }
        }
        elseif (-not ($actualItem -eq $expectedItem)) {
            return "Value differs for key '$Prefix$expectedKey'. Expected value: '$expectedItem', actual value: '$actualItem'"
        }
    }

    foreach($actualKey in $ActualValue.Keys) {
        if (-not($ExpectedValue.Keys -contains $actualKey)){
            return "Actual key: '$prefix$actualKey', but missing in expected"
        }
    }
}

Add-AssertionOperator -Name MatchHashtable -Test $function:PesterMatchHashtable

Export-ModuleMember -Function GetActionScript
Export-ModuleMember -Function YamlTest
Export-ModuleMember -Function GetWorkflowsInPath
Export-ModuleMember -Function TestActionsReferences
Export-ModuleMember -Function TestWorkflowReferences
