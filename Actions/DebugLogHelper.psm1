$debugLoggingEnabled = $false
if ($env:DEBUGLOGGING -eq 'true') {
    $debugLoggingEnabled = $true
}

# Debug logging that is only written when additional logging is enabled
function Write-Debug-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($debugLoggingEnabled) {
        Write-Host -ForegroundColor Green "DEBUG: $Message"
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
        Write-Host -ForegroundColor Green "DEBUG: Function '$functionName' called with parameters:"
        foreach ($param in $Parameters.Keys) {
            Write-Host -ForegroundColor Green "  $($param): $($Parameters[$param])"
        }
    }
}

# Regular log that is always written
function Write-Info {

}