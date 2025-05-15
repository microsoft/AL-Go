Param(
    [Parameter(HelpMessage = "Comma-separated list of Secrets to get.", Mandatory = $true)]
    [string] $getSecrets = "",
    [Parameter(HelpMessage = "Determines whether you want to use the GhTokenWorkflow secret for TokenForPush", Mandatory = $false)]
    [string] $useGhTokenWorkflowForPush = 'false'
)

. (Join-Path -Path $PSScriptRoot -ChildPath "..\AL-Go-Helper.ps1" -Resolve)

$settings = $env:Settings | ConvertFrom-Json | ConvertTo-HashTable

# Build an array of secrets to get (and the names of the secrets)
[System.Collections.ArrayList] $secretsCollection = @()
$secretNames = @{}

function AddSecret {
    Param(
        [string] $secret,
        [switch] $useMapping
    )

    if ($secret) {
        $secretName = $secret
        $secretNameProperty = "$($secretName)SecretName"
        if ($useMapping.IsPresent -and $settings.Keys -contains $secretNameProperty) {
            $secretName = $settings."$secretNameProperty"
        }
        # Secret is the AL-Go name of the secret
        # SecretName is the actual name of the secret to get from the KeyVault or GitHub environment
        if ($secretName -and ($script:secretsCollection -notcontains $secret)) {
            # Add secret to the collection of secrets to get
            $script:secretsCollection += $secret
            $script:secretNames += @{
                "$secret" = "$secretName"
            }
        }
    }
}

AddSecret -secret 'AZURE_CREDENTIALS' -useMapping
foreach($secret in ($getSecrets.Split(',') | Select-Object -Unique)) {
    switch ($secret) {
        'TokenForPush' {
            AddSecret -secret 'TokenForPush'
            if ($useGhTokenWorkflowForPush -eq 'true') {
                # If we are using the ghTokenWorkflow for commits, we need to get ghTokenWorkflow secret
                AddSecret -secret 'ghTokenWorkflow' -useMapping
            }
        }
        'GitSubmodulesToken' {
            # If we are getting the gitSubModules token, we might need to get the github token as well
            AddSecret -secret $secret -useMapping
            AddSecret -secret 'github_token'
        }
        'AppDependencySecrets' {
            # Loop through appDependencyProbingPaths and trustedNuGetFeeds and add secrets to the collection of secrets to get
            $settingsCollection = @()
            if ($settings.Keys -contains 'appDependencyProbingPaths') {
                $settingsCollection += $settings.appDependencyProbingPaths
            }
            if ($settings.Keys -contains 'trustedNuGetFeeds') {
                $settingsCollection += $settings.trustedNuGetFeeds
            }
            foreach($settingsItem in $settingsCollection) {
                if ($settingsItem.PsObject.Properties.name -eq "AuthTokenSecret") {
                    AddSecret -secret $settingsItem.authTokenSecret
                }
            }
            # Look through installApps and installTestApps for secrets and add them to the collection of secrets to get
            foreach($installSettingsKey in @('installApps','installTestApps')) {
                if ($settings.Keys -contains $installSettingsKey) {
                    $settings."$installSettingsKey" | ForEach-Object {
                        # If any of the installApps URLs contains '${{SECRETNAME}}' we need to get the secret
                        $pattern = '.*(\$\{\{\s*([^}]+?)\s*\}\}).*'
                        if ($_ -match $pattern) {
                            AddSecret -secret $matches[2]
                        }
                    }
                }
            }
        }
        default {
            AddSecret -secret $secret -useMapping
        }
    }
}

# Calculate output for secrets
# one output called FORMATSTR with the content: {{"secret1":{0},"secret2":{1},"secret3":{2}}}
# and one environment variable per secret called S0, S1, S2 with the name of the GitHub Secret (or Azure DevOps secret) to look for
if ($secretsCollection.Count -gt 32) {
    throw "Maximum number of secrets exceeded."
}

$cnt = 0
$formatArr = @()
foreach($secret in $secretsCollection) {
    $formatArr += @("""$Secret"":{$cnt}")
    Add-Content -Encoding UTF8 -Path $ENV:GITHUB_ENV -Value "S$cnt=$($secretNames[$secret])"
    Write-Host "S$cnt=$($secretNames[$secret])"
    $cnt++
}
Add-Content -Encoding UTF8 -Path $ENV:GITHUB_OUTPUT -Value "FORMATSTR={{$($formatArr -join ',')}}"
Write-Host "FORMATSTR={{$($formatArr -join ',')}}"
