function Convert-FromBase64 {
    Param(
        [string] $value
    )
    $decodedValue = [System.Text.Encoding]::Utf8.GetString([System.Convert]::FromBase64String($value))
    return $decodedValue
}