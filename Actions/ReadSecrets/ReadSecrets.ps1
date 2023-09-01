Param(
    [Parameter(HelpMessage = "All GitHub Secrets in compressed JSON format", Mandatory = $true)]
    [string] $gitHubSecrets = "",
    [Parameter(HelpMessage = "Comma separated list of Secrets to get", Mandatory = $true)]
    [string] $getSecrets = "",
    [Parameter(HelpMessage = "Determines whether you want to use the GhTokenWorkflow secret for TokenForPush", Mandatory = $false)]
    [string] $useGhTokenWorkflowForPush = 'false'
)

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
    Import-Module (Join-Path $PSScriptRoot ".\ReadSecretsHelper.psm1") -ArgumentList $gitHubSecrets

    $outSecrets = [ordered]@{}
    $settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable
    $keyVaultName = ""
    if (IsKeyVaultSet -and $settings.ContainsKey('keyVaultName')) {
        $keyVaultName = $settings.keyVaultName
        if ([string]::IsNullOrEmpty($keyVaultName)) {
            $credentialsJson = Get-KeyVaultCredentials | ConvertTo-HashTable
            if ($credentialsJson.Keys -contains "keyVaultName") {
                $keyVaultName = $credentialsJson.keyVaultName
            }
        }
    }
    $getAppDependencyProbingPathsSecrets = $false
    $getTokenForPush = $false
    [System.Collections.ArrayList]$secretsCollection = @()
    foreach($secret in ($getSecrets.Split(',') | Select-Object -Unique)) {
        if ($secret -eq 'TokenForPush') {
            $getTokenForPush = $true
            if ($useGhTokenWorkflowForPush -ne 'true') { continue }
            # If we are using the ghTokenWorkflow for commits, we need to get ghTokenWorkflow secret
            $secret = 'ghTokenWorkflow'
        }
        $secretNameProperty = "$($secret)SecretName"
        if ($secret -eq 'AppDependencyProbingPathsSecrets') {
            $getAppDependencyProbingPathsSecrets = $true
        }
        else {
            if ($settings.Keys -contains $secretNameProperty) {
                $secret = "$($secret)=$($settings."$secretNameProperty")"
            }
            if ($secretsCollection -notcontains $secret) {
                $secretsCollection += $secret
            }
        }
    }

    # Loop through appDependencyProbingPaths and add secrets to the collection of secrets to get
    if ($getAppDependencyProbingPathsSecrets -and $settings.Keys -contains 'appDependencyProbingPaths') {
        foreach($appDependencyProbingPath in $settings.appDependencyProbingPaths) {
            if ($appDependencyProbingPath.PsObject.Properties.name -eq "AuthTokenSecret") {
                if ($secretsCollection -notcontains $appDependencyProbingPath.authTokenSecret) {
                    $secretsCollection += $appDependencyProbingPath.authTokenSecret
                }
            }
        }
    }

    # Loop through secrets (use @() to allow us to remove items from the collection while looping)
    foreach($secret in @($secretsCollection)) {
        $secretSplit = $secret.Split('=')
        $secretsProperty = $secretSplit[0]
        $secretName = $secretsProperty
        if ($secretSplit.Count -gt 1) {
            $secretName = $secretSplit[1]
        }

        if ($secretName) {
            $secretValue = GetSecret -secret $secretName -keyVaultName $keyVaultName
            if ($secretValue) {
                $json = @{}
                try {
                    $json = $secretValue | ConvertFrom-Json | ConvertTo-HashTable
                }
                catch {
                }
                if ($json.Keys.Count) {
                    if ($secretValue.contains("`n")) {
                        throw "JSON Secret $secretName contains line breaks. JSON Secrets should be compressed JSON (i.e. NOT contain any line breaks)."
                    }
                    foreach($keyName in $json.Keys) {
                        if (@("Scopes","TenantId","BlobName","ContainerName","StorageAccountName") -notcontains $keyName) {
                            # Mask individual values (but not Scopes, TenantId, BlobName, ContainerName and StorageAccountName)
                            MaskValue -key "$($secretName).$($keyName)" -value $json."$keyName"
                        }
                    }
                }
                $base64value = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($secretValue))
                $outSecrets += @{ "$secretsProperty" = $base64value }
                Write-Host "$secretsProperty successfully read from secret $secretName"
                $secretsCollection.Remove($secret)
            }
        }
    }

    if ($secretsCollection) {
        $unresolvedSecrets = ($secretsCollection | ForEach-Object {
            $secretSplit = @($_.Split('='))
            if ($secretSplit.Count -eq 1) {
                $secretSplit[0]
            }
            else {
                "$($secretSplit[0]) (Secret $($secretSplit[1]))"
            }
            $outSecrets += @{ "$($secretSplit[0])" = "" }
        }) -join ', '
        Write-Host "The following secrets was not found: $unresolvedSecrets"
    }

    #region Action: Output

    $outSecretsJson = $outSecrets | ConvertTo-Json -Compress
    Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "Secrets=$outSecretsJson"

    if ($getTokenForPush) {
        if ($useGhTokenWorkflowForPush -eq 'true' -and $outSecrets.ghTokenWorkflow) {
            Write-Host "Use ghTokenWorkflow for Push"
            $ghToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($outSecrets.ghTokenWorkflow))
        }
        else {
            Write-Host "Use github_token for Push"
            $ghToken = GetGithubSecret -SecretName 'github_token'
        }
        Add-Content -Encoding UTF8 -Path $env:GITHUB_OUTPUT -Value "TokenForPush=$ghToken"
    }

    #endregion
}
finally {
    $buildMutex.ReleaseMutex()
}
