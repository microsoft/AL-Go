function DownloadTemplateRepository {
    Param(
        [hashtable] $headers,
        [ref] $templateUrl,
        [ref] $templateSha,
        [bool] $downloadLatest
    )

    # Construct API URL
    $apiUrl = $templateUrl.Value.Split('@')[0] -replace "https://github.com/", "$ENV:GITHUB_API_URL/repos/"
    $branch = $templateUrl.Value.Split('@')[1]

    Write-Host "TemplateUrl: $($templateUrl.Value)"
    Write-Host "TemplateSha: $($templateSha.Value)"
    Write-Host "DownloadLatest: $downloadLatest"

    if ($downloadLatest) {
        # Get Branches from template repository
        $response = InvokeWebRequest -Headers $headers -Uri "$apiUrl/branches" -retry
        $branchInfo = ($response.content | ConvertFrom-Json) | Where-Object { $_.Name -eq $branch }
        if (!$branchInfo) {
            throw "$($templateUrl.Value) doesn't exist"
        }
        $templateSha.Value = $branchInfo.commit.sha
        Write-Host "Latest SHA for $($templateUrl.Value): $($templateSha.Value)"
    }
    $archiveUrl = "$apiUrl/zipball/$($templateSha.Value)"
    Write-Host "Using ArchiveUrl: $archiveUrl"

    # Download template repository
    $tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    InvokeWebRequest -Headers $headers -Uri $archiveUrl -OutFile "$tempName.zip" -retry
    Expand-7zipArchive -Path "$tempName.zip" -DestinationPath $tempName
    Remove-Item -Path "$tempName.zip"
    $tempName
}
