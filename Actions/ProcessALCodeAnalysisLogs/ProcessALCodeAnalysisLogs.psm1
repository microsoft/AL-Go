<#
    .SYNOPSIS
    Normalizes a file path by converting backslashes to forward slashes and removing leading drive letters.
    .DESCRIPTION
    This function takes a file path as input, converts all backslashes to forward slashes,
    and removes any leading drive letters (e.g., "C:") to standardize the path format.
    .PARAMETER Path
    The file path to normalize.
#>
function NormalizePath {
    param(
        [string] $Path
    )
    # Convert backslashes to forward slashes and remove leading drive letter
    return ($Path -replace '\\', '/') -replace '^[A-Za-z]:', ''
}

<#
    .SYNOPSIS
    Finds a file in the workspace based on its absolute path.
    .DESCRIPTION
    Given an absolute path, this function searches the workspace for a file with the same name and returns its relative path.
    If no file is found, it returns $null.
    .PARAMETER AbsolutePath
    The absolute path of the file to find.
    .PARAMETER WorkspacePath
    The workspace path to search in. Defaults to the GITHUB_WORKSPACE environment variable.
#>
function Get-FileFromAbsolutePath {
    param(
        [Parameter(HelpMessage = "The absolute path of the file to find.", Mandatory = $true)]
        [string] $AbsolutePath,
        [Parameter(HelpMessage = "The workspace path to search in.", Mandatory = $false)]
        [string] $WorkspacePath = $ENV:GITHUB_WORKSPACE
    )

    # Remove leading drive letter and convert backslashes to forward slashes to match unix-style paths
    $normalizedPath = NormalizePath -path $AbsolutePath

    if (Test-Path -Path $normalizedPath -PathType Leaf) {
        OutputDebug -message "File exists at absolute path: $AbsolutePath"
        # If the file exists at the absolute path, return the relative path from the workspace root
        return NormalizePath -Path ([System.IO.Path]::GetRelativePath($workspacePath, $normalizedPath))
    }

    # Extract the file name from the absolute path
    $fileName = [System.IO.Path]::GetFileName($normalizedPath)

    # Search the workspace path for a file with that name
    $matchingFiles = @(Get-ChildItem -Path $WorkspacePath -Filter $fileName -File -Recurse -ErrorAction SilentlyContinue)
    if($matchingFiles.Count -eq 1) {
        OutputDebug -message "Found one matching file for absolute path: $AbsolutePath"
        $foundFile = $matchingFiles | Select-Object -First 1
        $relativePath = NormalizePath -Path ([System.IO.Path]::GetRelativePath($workspacePath, $foundFile.FullName))
        return $relativePath
    }

    OutputDebug -message "Could not find file for absolute path: $AbsolutePath"
    return $null
}

<#
    .SYNOPSIS
    Extracts the most appropriate message from an issue object.
    .DESCRIPTION
    Given an issue object, this function checks for the presence of "shortMessage" and "fullMessage" properties
    and returns the most appropriate one based on their availability.
    If neither property is available, it returns $null.
    .PARAMETER issue
    The issue object to extract the message from.
#>
function Get-IssueMessage {
    param(
        [Parameter(HelpMessage = "The issue object to extract the message from.", Mandatory = $true)]
        [PSCustomObject] $issue
    )

    if ($issue.PSObject.Properties.Name -contains "shortMessage") {
        return $issue.shortMessage
    } elseif ($issue.PSObject.Properties.Name -contains "fullMessage") {
        return $issue.fullMessage
    } else {
        return $null
    }
}

Export-ModuleMember -Function Get-FileFromAbsolutePath, Get-IssueMessage
