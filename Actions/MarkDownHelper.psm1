<#
    .SYNOPSIS
        Helper functions for creating markdown tables.

    .PARAMETER Headers
        An array of strings representing the headers of the table.
        Each header should be in the format "label;alignment", where alighment can be "left", "l", "right", "r", or "center", "c".

    .PARAMETER Rows
        An array of arrays representing the rows of the table. Each row should have the same number of elements as there are headers.

    .OUTPUTS
        A string representing the markdown table, with '\n' at the end of each line.

    .EXAMPLE
        $headers = @("Name;left", "Age;center", "Location;right")
        $rows = @(
            @("Alice", 30, "New York"),
            @("Bob", 25, "Los Angeles")
        )
        $markdownTable = BuildMarkdownTable -Headers $headers -Rows $rows
#>
function Build-MarkdownTable {
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $Headers,
        [Parameter(Mandatory = $true)]
        [string[][]] $Rows
    )

    $tableSb = [System.Text.StringBuilder]::new()
    $headerRow = '|'
    $separatorRow = '|'
    $columnCount = $Headers.Length
    foreach ($header in $Headers) {
        $headerParts = $header -split ";"
        $headerRow += "$($headerParts[0])|"
        if ($headerParts.Length -eq 2) {
            switch ($headerParts[1].ToLower()) {
                {$_ -in @('l','left')} {
                    $separatorRow += ":---|"
                }
                {$_ -in @('r','right')} {
                    $separatorRow += "---:|"
                }
                {$_ -in @('c','center')} {
                    $separatorRow += ":---:|"
                }
                default {
                    Write-Host "Invalid alignment: ($_), should be 'left', 'right' or 'center'. Defaulting to 'left'."
                    $separatorRow += ":---|"
                }
            }
        }
        else {
            Write-Host "Invalid header format: ($header), should be 'label;alignment'. Defaulting to 'left'."
            $separatorRow += ":---|"
        }

    }

    $tableSb.Append("$headerRow\n") | Out-Null
    $tableSb.Append("$separatorRow\n") | Out-Null

    foreach ($row in $Rows) {
        if ($row.Length -ne $columnCount) {
            throw "Row '$($row -join ';')' does not have the same number of columns ($($row.Length)) as the headers ($columnCount)"
        }
        $rowString = $row -join "|"
        $rowString = "|$rowString|"
        $tableSb.Append("$rowString\n") | Out-Null
    }
    $tableSb.Append("\n") | Out-Null

    return $tableSb.ToString()
}

Export-ModuleMember -Function *-*
