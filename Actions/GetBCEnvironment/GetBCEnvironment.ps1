param (
    [Parameter(Mandatory = $true)]
    [string] $Provider,
    [Parameter(Mandatory = $true)]
    [string] $Project,
    [Parameter(Mandatory = $true)]
    [string] $BaseFolder
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$telemetryScope = $null
$bcContainerHelperPath = DownloadAndImportBcContainerHelper -baseFolder $ENV:GITHUB_WORKSPACE

# IMPORTANT: No code that can fail should be outside the try/catch

function Get-BCArtifactUrlBasedOnSettings($artifact) {
    # Taken from BC Container Helper

    $segments = "$artifact/////".Split('/')

    $storageAccount = $segments[0];
    $type = $segments[1]; if ($type -eq "") { $type = 'Sandbox' }
    $version = $segments[2]
    $country = $segments[3]; if ($country -eq "") { $country = "us" }
    $select = $segments[4]; if ($select -eq "") { $select = "latest" }
    $sasToken = $segments[5]

    Write-Host "Determining artifacts to use"
    $minsto = $storageAccount
    $minsel = $select
    $mintok = $sasToken

    $artifactUrl = Get-BCArtifactUrl -storageAccount $minsto -type $type -version $version -country $country -select $minsel -sasToken $mintok | Select-Object -First 1

    if (!($artifactUrl)) {
        throw "Unable to locate artifacts"
    }

    return $artifactUrl
}

try {
    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    function Get-BCDockerCredentials {
        $NewBcContainerScript = {
            Param(
            [Hashtable] $parameters
            )


            New-BcContainer @parameters
            Invoke-ScriptInBcContainer $parameters.ContainerName -scriptblock { $progressPreference = 'SilentlyContinue' }
        }

        $randomName = @((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char] $_ }) -join ''
        $randomUsername = @((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char] $_ }) -join ''
        $randomPassword = @((65..90) + (97..122) | Get-Random -Count 10 | ForEach-Object { [char] $_ }) -join ''
        $containerName = "bc-$randomName"

        $credentials = (New-Object pscredential $randomUsername, (ConvertTo-SecureString -String $randomPassword -AsPlainText -Force))

        Write-Host "Creaing docker container"

        $settings = ReadSettings -baseFolder $BaseFolder -project $Project
        $artifactUrl = Get-BCArtifactUrlBasedOnSettings $settings.artifact $settings.additionalCountries

        $Parameters = @{
            "accept_eula" = $true
            "containerName" = $containerName
            "artifact" = $artifactUrl
            "useGenericImage" = $useGenericImage
            "Credential" = $credential
            "auth" = 'UserPassword'
            "vsixFile" = $vsixFile
            "updateHosts" = $true
            "FilesOnly" = $false
        }

        Invoke-Command -ScriptBlock $NewBcContainerScript -ArgumentList $Parameters

        return $credentials
    }

    $credentials = @{}
    switch ($Provider) {
        'BCDockerContainer' { $credentials = Get-BCDockerCredentials }
        Default { throw "Provider $Provider not supported" }
    }


    $credentialsJSON = ConverTo-Json $credentials -Depth 99 -compress
    Add-Content -Path $env:GITHUB_OUTPUT -Value "CredentialsJSON=$credentialsJSON"
}
catch {
    OutputError -message "GetBCEnvironment action failed.$([environment]::Newline)Error: $($_.Exception.Message)$([environment]::Newline)Stacktrace: $($_.scriptStackTrace)"
    exit
}
finally {
    CleanupAfterBcContainerHelper -bcContainerHelperPath $bcContainerHelperPath
}