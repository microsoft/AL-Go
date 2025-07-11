
if ($env:GITHUB_ACTIONS -eq "true") {
    $runningLocal = $false
} else {
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

<#
    .SYNOPSIS
        Writes debug information about the function call and its parameters if extended debug logging is enabled.
    .DESCRIPTION
        Writes debug information about the function call and its parameters to the console if extended debug logging is enabled.
        Automatically retrieves the caller's name and arguments from the call stack.
#>
function OutputDebugFunctionCall {
    if ($debugLoggingEnabled -or $runningLocal) {
        try {
            $caller = (Get-PSCallStack)[1]
            $callerName = $caller.Command
            $argString = $caller.Arguments

            OutputDebug "Function '$callerName' called with parameters:"

            if ($argString -match '^\{(.*)\}$') {
                $inner = $matches[1]

                # Match key=value pairs, allowing for quoted strings with commas
                $pattern = '(?<key>\w+)\s*=\s*(?<value>(?:(?!,\s*\w+\s*=).)+)'
                $regexMatches = [regex]::Matches($inner, $pattern)

                if ($regexMatches.Count -eq 0) {
                    OutputDebug "None"
                }
                foreach ($match in $regexMatches) {
                    $key = $match.Groups['key'].Value
                    $val = $match.Groups['value'].Value
                    OutputDebug "-$($key): $val"
                }
            } else {
                OutputDebug "Unable to parse arguments."
            }
        } catch {
            OutputDebug "Unable to parse arguments."
        }

    }
}

<#
    .SYNOPSIS
        Starts a console log group.
    .DESCRIPTION
        Starts a console log group. All subsequent log messages will be grouped under this message until Write-GroupEnd is called.
    .PARAMETER Message
        Name/Title of the group.
#>
function OutputGroupStart {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($runningLocal) {
        Write-Host "==== Group start: $Message ===="
    } else {
        Write-Host "::group::$Message"
    }
}

<#
    .SYNOPSIS
        Ends a console log group.
    .DESCRIPTION
        Ends a console log group started with Write-GroupStart. All subsequent log messages will be outside of this group.
    .PARAMETER Message
        Name/Title of the group.
#>
function OutputGroupEnd {
    if ($runningLocal) {
        Write-Host "==== Group end ===="
    } else {
        Write-Host "::endgroup::"
    }
}

<#
    .SYNOPSIS
        Writes to console with optional color.
    .DESCRIPTION
        Writes a message to the console with an optional color. If no color is specified, the message is written in the default console color.
    .PARAMETER Message
        Message to be written to console.
    .PARAMETER Color
        Optional color for the message. Valid values are 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan'.
#>
function OutputColor {
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

<#
    .SYNOPSIS
        Write an error message to the console.
    .DESCRIPTION
        Writes an error message to the console. If running locally, it throws an exception with the message.
    .PARAMETER Message
        Message to be written to console.
#>
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

<#
    .SYNOPSIS
        Write a warning message to the console.
    .DESCRIPTION
        Writes a warning message to the console. If running locally, it writes the message in yellow.
    .PARAMETER Message
        Message to be written to console.
#>
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

<#
    .SYNOPSIS
        Write a notice message to the console.
    .DESCRIPTION
        Writes a notice message to the console. If running locally, it writes the message in blue.
    .PARAMETER Message
        Message to be written to console.
#>
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

<#
    .SYNOPSIS
        Mask a value in the log.
    .DESCRIPTION
        Masks a value in the log to prevent sensitive information from being displayed. If running locally, it writes the masked value to the console.
    .PARAMETER Value
        The value to be masked in the log.
#>
function MaskValueInLog {
    Param(
        [string] $value
    )

    if (!$runningLocal) {
        Write-Host "`r::add-mask::$value"
    }
}

<#
    .SYNOPSIS
        Write a debug message to the console.
    .DESCRIPTION
        Writes a debug message to the console. If running locally, it writes the message in magenta.
    .PARAMETER Message
        Message to be written to console.
#>
function OutputDebug {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Host $message
    }
    else {
        Write-Host "::Debug::[AL-Go]$message"
    }
}

Export-ModuleMember -Function OutputColor, OutputDebugFunctionCall, OutputGroupStart, OutputGroupEnd, OutputError, OutputWarning, OutputNotice, MaskValueInLog, OutputDebug
Export-ModuleMember -Variable debugLoggingEnabled
