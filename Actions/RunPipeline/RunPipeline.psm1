

<#
.SYNOPSIS
    Converts a list of test app files, unwrapping them if they are wrapped in parentheses.
.DESCRIPTION
    This function takes an array of test app file paths or URLs and checks each one to see
    if it is wrapped in parentheses. If it is, the function removes the parentheses.
    The test apps are passed to Run-AlPipeline. Here we only run tests in test apps that are not wrapped.
.PARAMETER TestApps
    An array of test app file paths or URLs to be processed.
.OUTPUTS
    An array of unwrapped test app file paths or URLs.
#>
function ConvertTo-UnwrappedTestApps() {
    param (
        [Parameter(Mandatory = $true)]
        [array]$TestApps
    )
    $unwrappedTestApps = @()
    foreach ($app in $TestApps) {
        # Check if the appfile is a URL or not wrapped in parentheses
        if (($app -like 'http*://*') -or ($app -notlike '(*)')) {
            $newAppFile = $app
        } else {
            Write-Host "Unwrapping test app file: $app"
            $newAppFile = $app.TrimStart("(").TrimEnd(")")
        }

        $unwrappedTestApps += $newAppFile
    }

    return $unwrappedTestApps
}

Export-ModuleMember -Function ConvertTo-UnwrappedTestApps
