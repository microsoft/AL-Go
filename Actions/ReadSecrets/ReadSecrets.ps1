Param(
    [Parameter(HelpMessage = "A JSON structure with all secrets needed. The structure already contains the existing GitHub secrets", Mandatory = $true)]
    [string] $gitHubSecrets = "",
    [Parameter(HelpMessage = "Determines whether you want to use the GhTokenWorkflow secret for TokenForPush", Mandatory = $false)]
    [string] $useGhTokenWorkflowForPush = 'false'
)

$UnEncodedSecrets = @('gitSubmodulesToken')

$buildMutexName = "AL-Go-ReadSecrets"
$buildMutex = New-Object System.Threading.Mutex($false, $buildMutexName)
try {
    try {
        if (!$buildMutex.WaitOne(1000)) {
            Write-Host "Waiting for other process executing ReadSecrets"
            $buildMutex.WaitOne() | Out-Null
            Write-Host "Other process completed ReadSecrets"
        }
    }
    catch [System.Threading.AbandonedMutexException] {
       Write-Host "Other process terminated abnormally"
    }

    . (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)
    Import-Module (Join-Path $PSScriptRoot "ReadSecretsHelper.psm1")

    $ghSecrets = $gitHubSecrets | ConvertFrom-Json

    $outSecrets = [ordered]@{}
    $keyVaultCredentials = GetKeyVaultCredentials -jsonStr $ghSecrets.AZURE_CREDENTIALS
    $getTokenForPush = $false
    $secrets = @($ghSecrets.PSObject.Properties.Name)
    for ($sno = 0; $sno -lt $secrets.Count; $sno++) {
        $secret = $secrets[$sno]
        $secretName = (get-item "ENV:S$sno").value
        if ($secret -eq 'TokenForPush') {
            $getTokenForPush = $true
        }
        if ($ghSecrets."$secret") {
            Write-Host "Secret $secret was found in GitHub secrets with the name $secretName."
        }
        elseif ($keyVaultCredentials) {
            # Missing secret - read from KeyVault
            $secretValue = GetKeyVaultSecret -secretName $secretName -keyVaultCredentials $keyVaultCredentials
            if ($secretValue) {
                Write-Host "Secret $secret was retrieved from the Key Vault $($keyVaultCredentials.keyVaultName) with the name $secretName."
                $ghSecrets."$secret" = $secretValue
                MaskValue -key $secret -value $secretValue
            }
            else {
                Write-Host "Secret $secret ($secretName), was not found in GitHub secrets or Key Vault $($keyVaultCredentials.keyVaultName)."
            }
        }
        else {
            Write-Host "Secret $secret ($secretName), was not found in GitHub secrets."
        }
    }

    # Loop through secrets and build outsecrets
    $unresolvedSecrets = @()
    foreach($secret in $secrets) {
        $secretValue = $ghSecrets."$secret"
        $base64encoded = $UnEncodedSecrets -notcontains $secret
        if ($secretValue) {
            try {
                $json = $secretValue | ConvertFrom-Json | ConvertTo-HashTable
            }
            catch {
                $json = @{}
            }
            if ($json.Keys.Count) {
                # If secret is a JSON object, mask the individual values
                foreach($keyName in $json.Keys) {
                    if ((IsPropertySecret -propertyName $keyName) -and ($json."$keyName" -isnot [boolean])) {
                        # Mask individual values if property is secret
                        MaskValue -key "$($secret).$($keyName)" -value "$($json."$keyName")"
                    }
                }
                # If secret is a JSON object for a federated token, query the ID_TOKEN and mask
                if ($json.ContainsKey('clientID') -and !($json.ContainsKey('clientSecret') -or $json.ContainsKey('refreshToken'))) {
                    try {
                        Write-Host "Query federated token"
                        $result = Invoke-RestMethod -Method GET -UseBasicParsing -Headers @{ "Authorization" = "bearer $ENV:ACTIONS_ID_TOKEN_REQUEST_TOKEN"; "Accept" = "application/vnd.github+json" } -Uri "$ENV:ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
                        $json += @{ "clientAssertion" = $result.value }
                        $secretValue = $json | ConvertTo-Json -Compress
                        MaskValue -key "$secret with federated token" -value $secretValue
                    }
                    catch {
                        throw "$Secret doesn't contain any ClientSecret and AL-Go is unable to acquire an ID_TOKEN. Error was $($_.Exception.Message)"
                    }
                }
            }

            if ($base64encoded) {
                $secretValue = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($secretValue.Trim()))
            }
            $outSecrets += @{ "$secret" = $secretValue }
        }
        elseif ($secret -eq 'gitSubmodulesToken') {
            # If the gitSubmodulesToken secret was not found, use the github_token
            Write-Host "Using github_token for gitSubmodulesToken"
            $outSecrets += @{ "$secret" = $ghSecret.'github_token' }
        }
        else {
            $outSecrets += @{ "$secret" = "" }
            $unresolvedSecrets += $secret
        }
    }

    if ($unresolvedSecrets.Count -gt 0) {
        Write-Host "The following secrets was not found: $unresolvedSecrets"
    }

    #region Action: Output

    $outSecretsJson = $outSecrets | ConvertTo-Json -Compress
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Secrets=$outSecretsJson"

    if ($getTokenForPush) {
        if ($useGhTokenWorkflowForPush -eq 'true' -and $ghSecrets.ghTokenWorkflow) {
            Write-Host "Use ghTokenWorkflow for Push"
            $ghToken = GetAccessToken -token $ghSecrets.ghTokenWorkflow -permissions @{"actions"="read";"contents"="write";"pull_requests"="write";"metadata"="read";"workflows"="write"}
        }
        else {
            Write-Host "Use github_token for Push"
            $ghToken = $ghSecrets.'github_token'
        }
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "TokenForPush=$ghToken"
    }

    #endregion
}
finally {
    $buildMutex.ReleaseMutex()
}
