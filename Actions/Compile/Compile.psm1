function New-BuildOutputFile {
    param(
        [string]$BuildArtifactFolder,
        [string]$BuildOutputPath,
        [switch]$DisplayInConsole,
        [string]$BasePath = $ENV:GITHUB_WORKSPACE
    )
    # Create the file path for the build output
    New-Item -Path $BuildOutputPath -ItemType File -Force | Out-Null

    # Collect the log files and append their content to the build output file
    $logFiles = Get-ChildItem -Path $BuildArtifactFolder -Recurse -Filter "*.log" | Select-Object -ExpandProperty FullName    
    foreach ($logFile in $logFiles) {
        $sanitizedLines = Get-Content -Path $logFile | ForEach-Object { $_ -replace '^\[OUT\]\s?', '' }
        Add-Content -Path $buildOutputPath -Value $sanitizedLines

        # Print build output to console (aggregated), preserving line formatting
        if ($DisplayInConsole) {
            Convert-AlcOutputToAzureDevOps -basePath $BasePath -AlcOutput $sanitizedLines -gitHubActions
        }
    }

    return $buildOutputPath
}

Export-ModuleMember -Function New-BuildOutputFile