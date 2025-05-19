$debugLoggingEnabled = $false
try {
    Write-Host "RUNNER_DEBUG environment variable: $env:RUNNER_DEBUG"
    if ($env:RUNNER_DEBUG -eq 1) {
        $debugLoggingEnabled = $true
    }
} catch {
    Write-Host "Failed to parse RUNNER_DEBUG environment variable. Defaulting to false."
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