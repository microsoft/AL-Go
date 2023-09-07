function GetNavSipFromArtifacts
(
    [string] $NavSipDestination
)
{
    $artifactTempFolder = Join-Path $([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

    try {
        Download-Artifacts -artifactUrl (Get-BCArtifactUrl -type Sandbox -country core) -basePath $artifactTempFolder | Out-Null
        Write-Host "Downloaded artifacts to $artifactTempFolder"
        $navsip = Get-ChildItem -Path $artifactTempFolder -Filter "navsip.dll" -Recurse
        Write-Host "Found navsip at $($navsip.FullName)"
        Copy-Item -Path $navsip.FullName -Destination $NavSipDestination -Force | Out-Null
        Write-Host "Copied navsip to $NavSipDestination"
    }
    finally {
        Remove-Item -Path $artifactTempFolder -Recurse -Force
    }
}

<#
.SYNOPSIS
Register the navsip.dll in the system32 folder
#>
function Register-NavSip() {
    $navSipDestination = "C:\Windows\System32"
    $navSipDllPath = Join-Path $navSipDestination "navsip.dll"
    try {
        if (-not (Test-Path $navSipDllPath)) {
            GetNavSipFromArtifacts -NavSipDestination $navSipDllPath
        }

        Write-Host "Unregistering dll $navSipDllPath"
        RegSvr32 /u /s $navSipDllPath
        Write-Host "Registering dll $navSipDllPath"
        RegSvr32 /s $navSipDllPath
    }
    catch {
        Write-Host "Failed to copy navsip to $navSipDestination"
    }

}

Export-ModuleMember Register-NavSip
