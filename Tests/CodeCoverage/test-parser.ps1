. (Join-Path $PSScriptRoot "..\..\Actions\AL-Go-Helper.ps1")
Import-Module (Join-Path $PSScriptRoot "..\..\Actions\.Modules\TestRunner\CoverageProcessor\BCCoverageParser.psm1") -Force

$csvFile = Join-Path $PSScriptRoot "TestData\CoverageFiles\sample-coverage.dat"
Write-Host "Testing file: $csvFile"
Write-Host "File exists: $(Test-Path $csvFile)"

# Check raw content
$content = Get-Content -Path $csvFile
Write-Host "Lines in file: $($content.Count)"
Write-Host "First line: $($content[0])"
Write-Host "Second line: $($content[1])"

# Try parsing
try {
    $result = Read-BCCoverageCsvFile -Path $csvFile -ErrorAction Stop
    Write-Host "Result count: $($result.Count)"
    
    if ($result.Count -gt 0) {
        Write-Host "`nFirst entry:"
        $result[0] | Format-List
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
}
