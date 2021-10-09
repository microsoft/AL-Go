$ALGoHelperPath = "$([System.IO.Path]::GetTempFileName()).ps1"
$webClient = New-Object System.Net.WebClient
$webClient.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy -argumentList ([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
$webClient.Encoding = [System.Text.Encoding]::UTF8
$webClient.DownloadFile('https://raw.githubusercontent.com/microsoft/AL-Go-Actions/main/AL-Go-Helper.ps1', $ALGoHelperPath)
. $ALGoHelperPath -local

$containerName = Enter-Value `
    -title "Container name" `
    -question "Please enter the name of the container to create" `
    -default "bcserver"

$auth = Select-Value `
    -title "Authentication mechanism for container" `
    -options @{ "Windows" = "Windows Authentication"; "UserPassword" = "Username/Password authentication" } `
    -question "Select authentication mechanism for container" `
    -default "UserPassword"

if ($auth -eq "Windows") {
    $credential = Get-Credential -Message "Please enter your Windows Credentials" -UserName $env:USERNAME
    $CurrentDomain = "LDAP://" + ([ADSI]"").distinguishedName
    $domain = New-Object System.DirectoryServices.DirectoryEntry($CurrentDomain,$credential.UserName,$credential.GetNetworkCredential().password)
    if ($null -eq $domain.name) {
        Write-Host -ForegroundColor Red "Unable to verify your Windows Credentials, you might not be able to authenticate to your container"
    }
}
else {
    $credential = Get-Credential -Message "Please enter username and password for your container" -UserName "admin"
}

$baseFolder = (Get-Item -path (Join-Path $PSScriptRoot "..\..")).FullName
CreateDevEnv `
    -kind local `
    -caller local `
    -containerName $containerName `
    -baseFolder $baseFolder `
    -auth $auth `
    -credential $credential