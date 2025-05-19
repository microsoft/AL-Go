$debugLoggingEnabled = $false
try {
    Write-Host "_DEBUGLOGGING environment variable: $env:_DEBUGLOGGING"#RUNNER_DEBUG
    Write-Host "RUNNER_DEBUG environment variable: $env:RUNNER_DEBUG"
    if ($env:_DEBUGLOGGING -eq 1 -or $env:_DEBUGLOGGING -eq "true") {
        $debugLoggingEnabled = $true
    }
} catch {
    Write-Host "Failed to parse DEBUGLOGGING environment variable. Defaulting to false."
}


# Debug logging that is only written when additional logging is enabled
function Write-Debug-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($debugLoggingEnabled) {
        Write-Host -ForegroundColor Green "[Debug] $Message"
    }
}

# Function to write debug information about function calls
function Write-Debug-FunctionCallInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string] $FunctionName,
        [Parameter(Mandatory = $true)]
        [System.Object] $Parameters
    )

    if ($debugLoggingEnabled) {
        Write-Host -ForegroundColor Green "[Debug] Function '$functionName' called with parameters:"
        foreach ($param in $Parameters.Keys) {
            Write-Host -ForegroundColor Green "  $($param): $($Parameters[$param])"
        }
    }
}

# Regular log that is always written
function Write-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "$Message"
}