
if ($env:GITHUB_ACTIONS -eq "true") {
    $runningLocal = $false
} else {
    $runningLocal = $true
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
        Writes debug information about the function call and its parameters if extended debug logging is enabled or running locally.
    .DESCRIPTION
        Writes debug information about the function call and its parameters to the console if extended debug logging is enabled or running locally.
        Automatically retrieves the caller's name and arguments from the call stack.
#>
function OutputDebugFunctionCall {
    try {
        $caller = (Get-PSCallStack)[1]
        $callerName = $caller.Command
        $callerParameters = $caller.InvocationInfo.BoundParameters

        OutputDebug "Function '$callerName' called with parameters:"
        if ($callerParameters.Count -eq 0) {
            OutputDebug "None"
        }
        foreach ($key in $callerParameters.Keys) {
            $val = $callerParameters[$key]
            OutputDebug "-$($key): $val"
        }
    } catch {
        OutputDebug "Unable to retrieve function information from call stack."
    }
}

<#
    .SYNOPSIS
        Starts a console log group.
    .DESCRIPTION
        Starts a console log group. All subsequent log messages will be grouped under this message until OutputGroupEnd is called.
        If running locally, it writes a simple message to the console. If running in GitHub Actions, it uses the `::group::` command to create a collapsible group in the log.
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
        Ends a console log group started with OutputGroupStart. All subsequent log messages will be outside of this group.
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
        # char 27 is the escape character for ANSI codes which works in both PS 5 and 7.
        Write-Host "$([char] 27)[${colorCode}m$Message$([char] 27)[0m"
    } else {
        Write-Host $Message
    }
}

<#
    .SYNOPSIS
        Write an error message to the console.
    .DESCRIPTION
        Writes an error message to the console. Throws an exception if running locally, otherwise formats the message for GitHub Actions.
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
        Writes a warning message to the console. Uses Write-Warning if running locally, otherwise formats the message for GitHub Actions.
    .PARAMETER Message
        Message to be written to console.
#>
function OutputWarning {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Warning $message
    }
    else {
        Write-Host "::Warning::$message"
    }
}

<#
    .SYNOPSIS
        Write a notice message to the console.
    .DESCRIPTION
        Writes a notice message to the console. Uses regular Write-Host if running locally, otherwise formats the message for GitHub Actions.
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
        Writes a debug message to the console. Uses Write-Debug if running locally, otherwise formats the message for GitHub Actions.
    .PARAMETER Message
        Message to be written to console.
#>
function OutputDebug {
    Param(
        [string] $message
    )

    if ($runningLocal) {
        Write-Debug $message
    }
    else {
        Write-Host "::Debug::[AL-Go]$message"
    }
}

<#
    .SYNOPSIS
        Outputs each item in an array to the console with optional formatting.
    .DESCRIPTION
        Outputs each item in an array to the console. An optional formatter script block can be provided to customize the output format of each item.
        If a message is provided, it is output before the array items. If the array is empty or null, it outputs "- None".
    .PARAMETER Message
        An optional message to output before the array items.
    .PARAMETER Array
        The array of items to output.
    .PARAMETER Formatter
        An optional script block to format each item in the array.
    .PARAMETER Debug
        A switch indicating whether to output messages as debug messages.
#>
function OutputArray {
    Param(
        [string] $Message,
        [object[]] $Array,
        [scriptblock] $Formatter = { "- $_" },
        [switch] $Debug
    )

    function OutputMessage {
        Param(
            [string] $Message,
            [switch] $Debug
        )

        if ($Debug) {
            OutputDebug $Message
        }
        else {
            Write-Host $Message
        }
    }

    if($Message) {
        OutputMessage $Message -Debug:$Debug
    }
    if (!$Array) {
        OutputMessage "- None" -Debug:$Debug
    }
    else {
        $Array | ForEach-Object {
            OutputMessage "$(& $Formatter $_)" -Debug:$Debug
        }
    }
}

Export-ModuleMember -Function OutputColor, OutputDebugFunctionCall, OutputGroupStart, OutputGroupEnd, OutputError, OutputWarning, OutputNotice, MaskValueInLog, OutputDebug, OutputArray
Export-ModuleMember -Variable debugLoggingEnabled
