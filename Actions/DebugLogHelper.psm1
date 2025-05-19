$debugLoggingEnabled = $false
try {
    if ($env:RUNNER_DEBUG -eq 1) {
        $debugLoggingEnabled = $true
        Write-Host "AL-Go extended debugging is enabled."
    } else {
        Write-Host "AL-Go extended debug logging is disabled."
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
        Write-Host -ForegroundColor Yellow "[AL-Go-Debug] $Message"
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
        Write-Host -ForegroundColor Green "[AL-Go-Debug] Function '$functionName' called with parameters:"
        foreach ($param in $Parameters.Keys) {
            Write-Host -ForegroundColor Green "[AL-Go-Debug]  - $($param): $($Parameters[$param])"
        }
        if ($Parameters.Count -eq 0) {
            Write-Host -ForegroundColor Green "[AL-Go-Debug]  - None"
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