$ALGoHelperPath = "$([System.IO.Path]::GetTempFileName()).ps1"
$webClient = New-Object System.Net.WebClient
$webClient.CachePolicy = New-Object System.Net.Cache.RequestCachePolicy -argumentList ([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore)
$webClient.Encoding = [System.Text.Encoding]::UTF8
$webClient.DownloadFile('https://raw.githubusercontent.com/microsoft/AL-Go-Actions/main/AL-Go-Helper.ps1', $ALGoHelperPath)
. $ALGoHelperPath -local

$environmentName = Enter-Value `
    -title "Environment name" `
    -question "Please enter the name of the environment to create" `
    -default "$($env:USERNAME)-sandbox"

$reuseExistingEnvironment = Select-Value `
    -title "What if the environment already exists?" `
    -options @{ "Yes" = "Reuse existing environment"; "No" = "Recreate environment" } `
    -question "Select behavior" `
    -default "No"

$baseFolder = (Get-Item -path (Join-Path $PSScriptRoot "..\..")).FullName
CreateDevEnv `
    -kind cloud `
    -caller local `
    -environmentName $environmentName `
    -reuseExistingEnvironment:($reuseExistingEnvironment -eq "Yes") `
    -baseFolder $baseFolder
