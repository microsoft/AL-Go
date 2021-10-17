function TestYaml([string] $scriptPath, $permissions) {

    $filename = [System.IO.Path]::GetFileName($scriptPath)
    $actionname = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
    Write-Host -ForegroundColor Green $filename

    $yamlPath = Join-Path ([System.IO.Path]::GetDirectoryName($scriptPath)) "action.yaml"
    
    $actionScript = "function myAction {`n[CmdletBinding()]`nParam()`n}`n"
    Invoke-Expression $actionScript
    $emptyCmd = get-command myAction
    $systemParameters = @($emptyCmd.Parameters.Keys.GetEnumerator() | ForEach-Object { $_ })
    
    $actionScript = Get-Content -raw -path $scriptPath
    $actionScript = "function $actionName {`n$actionScript`n}"
    Write-Host "Compiling script"
    Invoke-Expression $actionScript
    
    Write-Host "Building expected action.yaml"
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
    $addInputs = $true
    $parameterString = ""
    if ($cmd.Parameters.Count -gt 0) {
        $cmd.Parameters.GetEnumerator() | ForEach-Object {
            $name = $_.Key
            if ($name -notin $systemParameters) {
                $value = $_.Value
                $description = $value.ParameterSets.__allParameterSets.HelpMessage
                if (!($description)) { $description = "*" }
                $required = $value.ParameterSets.__allParameterSets.IsMandatory
                $type = $value.ParameterType.ToString()

                if ($addInputs) {
                    $yaml.AppendLine("inputs:") | Out-Null
                    $addInputs = $false
                }    
                $yaml.AppendLine("  $($name):") | Out-Null
                $yaml.AppendLine("    description: $description") | Out-Null
                $yaml.AppendLine("    required: $($required.ToString().ToLowerInvariant())") | Out-Null
                if ($type -eq "System.String" -or $type -eq "System.Int32") {
                    $parameterString += " -$($name) '`${{ inputs.$($name) }}'"
                    if (!$required) {
                        $yaml.AppendLine("    default: *") | Out-Null
                    }
                }
                elseif ($type -eq "System.Boolean") {
                    $parameterString += " -$($name) ('`${{ inputs.$($name) }}' -eq 'Y')"
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
    $yaml.AppendLine("runs:") | Out-Null
    $yaml.AppendLine("  using: composite") | Out-Null
    $yaml.AppendLine("  steps:") | Out-Null
    $yaml.AppendLine("    - run: `${{ github.action_path }}/$([System.IO.Path]::GetFileName($scriptPath))$parameterString") | Out-Null
    $yaml.AppendLine("      shell: PowerShell") | Out-Null
    $yaml.AppendLine("branding:") | Out-Null
    $yaml.AppendLine("  icon: terminal") | Out-Null
    $yaml.Append("  color: blue") | Out-Null
    
    $yamlLines = $yaml.ToString().Replace("`r","").Split("`n")
    $actualYaml = @(Get-Content -path $yamlPath)

    Write-Host "Comparing with action.yaml"
    if ($yamlLines.Count -ne $actualYaml.Count) {
        Write-Host "Count Mismatch $($yamlLines.Count)<>$($actualYaml.Count)"
    }
    $i = 0
    while ($i -lt $yamlLines.Count -and $i -lt $actualYaml.count) {
        if ($actualYaml[$i] -notlike $yamlLines[$i]) {
            Write-Host "Line #$($i+1)"
            Write-Host -ForegroundColor Green "Expected: '$($yamlLines[$i])'"
            Write-Host -ForegroundColor red   "Actual:   '$($actualYaml[$i])'"
        }
        $i++
    }

    $actionScript
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$permissions = [ordered]@{
    "contents" = "write"
    "pull-requests" = "write"
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\AddExistingApp\AddExistingApp.ps1" -permissions $permissions
Invoke-Expression $actionScript

$permissions = [ordered]@{
    "contents" = "write"
    "pull-requests" = "write"
    "workflows" = "write"
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\CheckForUpdates\CheckForUpdates.ps1" -permissions $permissions
Invoke-Expression $actionScript

$permissions = [ordered]@{
    "contents" = "write"
    "pull-requests" = "write"
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\CreateApp\CreateApp.ps1" -permissions $permissions
Invoke-Expression $actionScript

$permissions = [ordered]@{
    "contents" = "write"
    "pull-requests" = "write"
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\CreateDevelopmentEnvironment\CreateDevelopmentEnvironment.ps1" -permissions $permissions
Invoke-Expression $actionScript

$permissions = [ordered]@{
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\Deploy\Deploy.ps1" -permissions $permissions
Invoke-Expression $actionScript

$permissions = [ordered]@{
    "contents" = "write"
    "pull-requests" = "write"
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\IncrementVersionNumber\IncrementVersionNumber.ps1" -permissions $permissions
Invoke-Expression $actionScript

$permissions = [ordered]@{
}
$actionScript = TestYaml -scriptPath "C:\Users\freddyk\Documents\Freddydk-AL-Go\Actions\PipelineCleanup\PipelineCleanup.ps1" -permissions $permissions
Invoke-Expression $actionScript
