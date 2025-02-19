function BuildMarkdownTable {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Headers, #Format "label;location"
        [Parameter(Mandatory = $true)]
        [string[][]]$Rows
    )

    $headerRow = '|'
    $separatorRow = '|'
    $columnCount = $Headers.Length
    foreach ($header in $Headers) {
        $headerParts = $header -split ";"
        if ($headerParts.Length -ne 2) {
            throw "Header '$header' is not in the correct format. It should be 'label;location'"
        }
        $headerRow += "$($headerParts[0])|"
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
                throw "Header '$header' has an invalid location. It should be 'left', 'right' or 'center'"
            }
        }
    }

    $table = @($headerRow, $separatorRow)

    foreach ($row in $Rows) {
        if ($row.Length -ne $columnCount) {
            throw "Row '$row' does not have the same number of columns ($($row.Length)) as the headers ($columnCount)"
        }
        $rowString = $row -join " | "
        $rowString = "| $rowString |"
        $table += $rowString
    }

    return $table -join "`n"
}
