# TRASER ADO Work Item Auto-Close

Param(
    [Parameter(Mandatory)][string]$Organization,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$FromTag,
    [Parameter(Mandatory)][string]$ToTag,
    [string]$SourceState = 'Release Pending',
    [string]$TargetState = 'Done',
    [string]$ReleaseUrl = ''
)

$headers = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Token")); "Content-Type" = "application/json-patch+json" }
$baseUrl = "https://dev.azure.com/$Organization/$Project/_apis"

$commits = git log "$FromTag..$ToTag" --oneline 2>$null
if (-not $commits) { Write-Host "No commits between $FromTag and $ToTag"; return }

$ids = @()
foreach ($c in $commits) { [regex]::Matches($c, 'AB#(\d+)') | ForEach-Object { $ids += [int]$_.Groups[1].Value } }
$ids = $ids | Sort-Object -Unique
if ($ids.Count -eq 0) { Write-Host "No AB# references found"; return }

Write-Host "Found $($ids.Count) work items: $($ids -join ', ')"
$closed = 0; $skipped = 0; $failed = 0

foreach ($id in $ids) {
    try {
        $wi = Invoke-RestMethod -Uri "$baseUrl/wit/workItems/$id`?api-version=7.0" -Headers @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Token")) }
        if ($wi.fields.'System.State' -ne $SourceState) { $skipped++; continue }
        $body = @(@{ op = "add"; path = "/fields/System.State"; value = $TargetState }) | ConvertTo-Json -AsArray
        Invoke-RestMethod -Uri "$baseUrl/wit/workItems/$id`?api-version=7.0" -Method Patch -Headers $headers -Body $body | Out-Null
        $commentBody = @{ text = "Closed by GitHub Release <a href='$ReleaseUrl'>$ToTag</a>" } | ConvertTo-Json
        Invoke-RestMethod -Uri "$baseUrl/wit/workItems/$id/comments?api-version=7.0-preview.4" -Method Post -Headers @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Token")); "Content-Type" = "application/json" } -Body $commentBody | Out-Null
        $closed++
    } catch { Write-Warning "#$id failed: $_"; $failed++ }
}
Write-Host "Results: $closed closed, $skipped skipped, $failed failed"
