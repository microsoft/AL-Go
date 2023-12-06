Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [PSCustomObject] $gitHubSecrets
)

#
# Check GitHub Secrets for common mistakes
# If GitHub secrets are multi-line, then every line in any GitHub secret available to the workflow will be masked individually by GitHub
# This can cause problems if these values are used as elsewhere - f.ex. if a line contains a { or a } character, then no JSON string can be parsed from one job to another
# This function checks for multi-line secrets displays warnings if multi-line secrets with lines containing short strings
#

function CheckSecretForCommonMistakes {
    Param (
        [string] $secretName,
        [string] $secretValue
    )

    try {
        $json = $secretValue | ConvertFrom-Json
        $isJson = $true
    }
    catch {
        $isJson = $false
    }
    if ($isJson) {
        # JSON Secrets should not contain line breaks
        if ($secretValue.contains("`n")) {
            AddToSummary -type Warning -Message "Secret $secretName contains line breaks. JSON Secrets available to AL-Go for GitHub should be compressed JSON (i.e. NOT contain any line breaks)."
        }
        # JSON Secrets properties should not contain values 3 characters or less
        foreach($keyName in $json.PSObject.Properties.Name) {
            if (IsPropertySecret -propertyName $keyName) {
                if ($json."$keyName".Length -le 4) {
                    AddToSummary -type Warning -Message "JSON Secret $secretName contains properties with very short values. These values will be masked, but the secret might be indirectly exposed and might also cause issues in AL-Go for GitHub."
                }
            }
        }
    }
    else {
        if ($secretValue.contains("`n")) {
            AddToSummary -type Warning -Message "Secret $secretName contains line breaks. GitHub Secrets available to AL-Go for GitHub should not contain line breaks."
        }
        elseif ($secretValue.Length -le 4) {
            AddToSummary -type Warning -Message "Secret $secretName has a very short value. This value will be masked, but the secret might be indirectly exposed and might also cause issues in AL-Go for GitHub."
        }
    }
}

foreach($secretName in $gitHubSecrets.PSObject.Properties.Name) {
    $secretValue = $gitHubSecrets."$secretName"
    Write-Host "Checking secret $secretName"
    CheckSecretForCommonMistakes -secretName $secretName -secretValue $secretValue
}
