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

# Colors
$colorCodeMagenta = '35'

function Write-Debug-Base {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "`e[${colorCodeMagenta}m[AL-Go-Debug]`e[0m $Message"
}

# Debug logging that is only written when additional logging is enabled
function Write-Debug-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($debugLoggingEnabled) {
        Write-Debug-Base $Message
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
        Write-Debug-Base "Function '$functionName' called with parameters:"
        foreach ($param in $Parameters.Keys) {
            Write-Debug-Base "- $($param): $($Parameters[$param])"
        }
        if ($Parameters.Count -eq 0) {
            Write-Debug-Base "- None"
        }
    }
}

# Regular log that is always written
function Write-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host $Message
}