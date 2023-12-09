Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [PSCustomObject] $gitHubSecrets,
    [Parameter(HelpMessage = "Display the name (not the value) of secrets available to the repository", Mandatory = $true)]
    [bool] $displayNameOfSecrets
)

#
# Check GitHub Secrets for common mistakes
# If GitHub secrets are multi-line, then every line in any GitHub secret available to the workflow will be masked individually by GitHub
# This can cause problems if these values are used as elsewhere - f.ex. if a line contains a { or a } character, then no JSON string can be parsed from one job to another
# This function checks for multi-line secrets displays warnings if multi-line secrets with lines containing short strings
#

# minSecretSize determines the minimum length of a secret value before a warning is displayed
$minSecretSize = 8

function GetDisplaySecretName {
    Param(
        [string] $secretName,
        [bool] $displayNameOfSecrets
    )

    if ($displayNameOfSecrets) {
        return $secretName
    }
    else {
        return "<redacted>"
    }
}

function CheckSecretForCommonMistakes {
    Param (
        [string] $displayName,
        [string] $secretValue
    )

    $warning = $false
    $hasLineBreaks = $secretValue.contains("`n")
    try {
        $json = $secretValue | ConvertFrom-Json
        $isJson = $true
    }
    catch {
        $isJson = $false
    }
    if ($isJson) {
        # JSON Secrets should not contain line breaks
        if ($hasLineBreaks) {
            OutputWarning -Message "Secret $displayName contains line breaks. JSON formatted secrets available to AL-Go for GitHub should be compressed JSON (i.e. NOT contain any line breaks)."
            $warning = $true
        }
        # JSON Secrets properties should not contain values shorter then $minSecretSize characters
        foreach($keyName in $json.PSObject.Properties.Name) {
            if ((IsPropertySecret -propertyName $keyName) -and ($json."$keyName" -isnot [boolean])) {
                if ("$($json."$keyName")".Length -lt $minSecretSize) {
                    OutputWarning -Message "JSON Secret $displayName contains properties with very short values. These values will be masked, but the secret might be indirectly exposed and might also cause issues in AL-Go for GitHub."
                    $warning = $true
                }
            }
        }
    }
    else {
        if ($hasLineBreaks) {
            OutputWarning -Message "Secret $displayName contains line breaks. GitHub Secrets available to AL-Go for GitHub should not contain line breaks."
            $warning = $true
        }
        elseif ($secretValue.Length -lt $minSecretSize) {
            OutputWarning -Message "Secret $displayName has a very short value. This value will be masked, but the secret might be indirectly exposed and might also cause issues in AL-Go for GitHub."
            $warning = $true
        }
    }
    return $warning
}

$anyWarning = $false
foreach($secretName in $gitHubSecrets.PSObject.Properties.Name) {
    $secretValue = $gitHubSecrets."$secretName"
    $displayName = GetDisplaySecretName -secretName $secretName -displayNameOfSecrets $displayNameOfSecrets
    if ($displayNameOfSecrets) {
        Write-Host "Checking secret $secretName"
    }
    if (CheckSecretForCommonMistakes -displayName $displayName -secretValue $secretValue) {
        $anyWarning = $true
    }
}

if ($anyWarning) {
    OutputSuggestion -Message "Consider restricting access to secrets not needed by AL-Go for GitHub. See [documentation](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions#reviewing-access-to-organization-level-secrets)."
}
