
if ($env:GITHUB_ACTIONS -eq "true") {
    Write-Host "Running in GitHub Actions"
    $runningLocal = $false
} else {
    Write-Host "Running locally"
    $runningLocal = $true
}

$debugLoggingEnabled = $false
try {
    if ($env:RUNNER_DEBUG -eq 1) {
        $debugLoggingEnabled = $true
        Write-Host "AL-Go extended debug logging is enabled."
    } else {
        Write-Host "AL-Go extended debug logging is disabled."
    }
} catch {
    Write-Host "Failed to parse RUNNER_DEBUG environment variable. Defaulting to false."
}

# Colors
$colorCodeRed = '31'
$colorCodeGreen = '32'
$colorCodeYellow = '33'
$colorCodeBlue = '34'
$colorCodeMagenta = '35'
$colorCodeCyan = '36'

function Write-Debug-Base {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "$([char] 27)[${colorCodeMagenta}m[AL-Go-Debug]$([char] 27)[0m $Message"
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
# The $parameters param should always be called with $MyInvocation.BoundParameters if the given function got parameters.
function Write-Debug-FunctionCallInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string] $FunctionName,
        [Parameter(Mandatory = $false)]
        [System.Object] $Parameters = @{}
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

# Helper functions to wrap logs in groups for better overview in GitHub actions
function Write-GroupStart {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "::group::$Message"
}

function Write-GroupEnd {
    Write-Host "::endgroup::"
}

# Regular log that is always written and supports color coding
function Write-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan')]
        [string] $Color
    )

    if ($Color) {
        $colorCode = 0
        switch ($Color) {
            'Red' { $colorCode = $colorCodeRed }
            'Green' { $colorCode = $colorCodeGreen }
            'Yellow' { $colorCode = $colorCodeYellow }
            'Blue' { $colorCode = $colorCodeBlue }
            'Magenta' { $colorCode = $colorCodeMagenta }
            'Cyan' { $colorCode = $colorCodeCyan }
        }
        Write-Host "$([char] 27)[${colorCode}m$Message$([char] 27)[0m"
    } else {
        Write-Host $Message
    }
}

function OutputError {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        throw $message
    }
    else {
        Write-Host "::Error::$($message.Replace("`r",'').Replace("`n",' '))"
        $host.SetShouldExit(1)
    }
}

function OutputWarning {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host -ForegroundColor Yellow "WARNING: $message"
    }
    else {
        Write-Host "::Warning::$message"
    }
}

function OutputNotice {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host $message
    }
    else {
        Write-Host "::Notice::$message"
    }
}

function MaskValueInLog {
    Param(
        [string] $value
    )

    if (!$runningLocal) {
        Write-Host "`r::add-mask::$value"
    }
}

function OutputDebug {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host $message
    }
    else {
        Write-Host "::Debug::$message"
    }
}

Export-ModuleMember -Function Write-Debug-Info, Write-Debug-FunctionCallInfo, Write-GroupStart, Write-GroupEnd, Write-Info, OutputError, OutputWarning, OutputNotice, MaskValueInLog, OutputDebug
Export-ModuleMember -Variable debugLoggingEnabled