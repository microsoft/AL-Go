. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
DownloadAndImportBcContainerHelper

Assert-DockerIsRunning
$genericImageName = Get-BestGenericImageName
Write-Host "Pulling Docker image '$genericImageName' in the background"

$process = Start-Process -FilePath "docker" -ArgumentList "pull", "--quiet", $genericImageName -NoNewWindow -PassThru
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "dockerPullPid=$($process.Id)"
Add-Content -Encoding UTF8 -Path $env:GITHUB_ENV -Value "dockerPullImage=$genericImageName"
Write-Host "Started background Docker pull with PID $($process.Id)"
