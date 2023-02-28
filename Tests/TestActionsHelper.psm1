Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

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
                $yaml.AppendLine("    required: $($required.ToString().ToLowerInvariant())") | Out-Null
                $envLines.AppendLine("        _$($name): `${{ inputs.$($name) }}")
                if ($type -eq "System.String" -or $type -eq "System.Int32") {
                    $parameterString += " -$($name) `$ENV:_$($name)"
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
    $yaml.AppendLine("      run: try { `${{ github.action_path }}/$actionName.ps1$parameterString } catch { Write-Host ""::Error::Unexpected error when running action (`$(`$_.Exception.Message.Replace(""*"",'').Replace(""*"",' ')))""; exit 1 }") | Out-Null
    $yaml.AppendLine("branding:") | Out-Null
    $yaml.AppendLine("  icon: terminal") | Out-Null
    $yaml.Append("  color: blue") | Out-Null
    
    $yamlLines = $yaml.ToString().Replace("`r","").Split("`n")
    $actualYaml = @(Get-Content -path (Join-Path $scriptRoot "action.yaml"))

    $i = 0
    while ($i -lt $yamlLines.Count -and $i -lt $actualYaml.count) {
        $actualYaml[$i] | Should -BeLike $yamlLines[$i]
        $i++
    }

    $yamlLines.Count | Should -be $actualYaml.Count
}

function TestActionsAreComingFromMicrosoftALGOActions {
    param(
        [Parameter(Mandatory)]
        [string]$YamlPath
    )

    $yaml = Get-Content -Path $YamlPath -Raw

    # Test all AL-GO Actions are coming from microsoft/AL-Go-Actions@<main|preview>
    $alGoActionsFromForksPattern = '\w*/AL-Go-Actions/\w*@\w*'
    $alGoActionsFromALGORepo = '\w*/AL-Go/Actions/\w*@\w*'

    $actions = [regex]::matches($yaml, "($alGoActionsFromForksPattern)|($alGoActionsFromALGORepo)")

    $mainAction = "microsoft/AL-Go-Actions/\w*@main"
    $previewAction = "microsoft/AL-Go-Actions/\w*@preview"

    $actions | ForEach-Object {
        $action = $_.Value
        $action | Should -Match "$mainAction|$previewAction"
    }
}

function TestAllWorkflowsInPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $workflows = Get-ChildItem -Path $Path -File -Recurse -Include ('*.yaml', '*.yml')
    $workflows | ForEach-Object {
        TestActionsAreComingFromMicrosoftALGOActions -YamlPath $_.FullName
    }
}

Export-ModuleMember -Function GetActionScript
Export-ModuleMember -Function YamlTest
Export-ModuleMember -Function TestAllWorkflowsInPath
