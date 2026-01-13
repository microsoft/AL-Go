function New-BuildOutputFile {
    param(
        [string]$BuildArtifactFolder,
        [string]$BuildOutputPath,
        [switch]$DisplayInConsole
    )
    # Create the file path for the build output
    New-Item -Path $BuildOutputPath -ItemType File -Force | Out-Null

    # Collect the log files and append their content to the build output file
    $logFiles = Get-ChildItem -Path $BuildArtifactFolder -Recurse -Filter "*.log" | Select-Object -ExpandProperty FullName    
    foreach ($logFile in $logFiles) {
        Add-Content -Path $buildOutputPath -Value (Get-Content -Path $logFile -Raw)
    }

    # Print build output to console
    if ($DisplayInConsole) {
        Get-Content -Path $buildOutputPath | Write-Host
    }
    return $buildOutputPath
}

Export-ModuleMember -Function New-BuildOutputFile