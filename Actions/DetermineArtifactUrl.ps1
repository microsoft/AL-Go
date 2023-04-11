function Determine-ArtifactUrl {
    Param(
        [hashtable] $projectSettings,
        [string] $insiderSasToken = "",
        [switch] $doNotIssueWarnings
    )

    $artifact = $projectSettings.artifact
    if ($artifact.Contains('{INSIDERSASTOKEN}')) {
        if ($insiderSasToken) {
            $artifact = $artifact.replace('{INSIDERSASTOKEN}', $insiderSasToken)
        }
        else {
            throw "Artifact definition $artifact requires you to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
        }
    }

    Write-Host "Checking artifact setting for project"
    if ($artifact -eq "" -and $projectSettings.updateDependencies) {
        $artifact = Get-BCArtifactUrl -country $projectSettings.country -select all | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$projectSettings.applicationDependency } | Select-Object -First 1
        if (-not $artifact) {
            if ($insiderSasToken) {
                $artifact = Get-BCArtifactUrl -storageAccount bcinsider -country $projectSettings.country -select all -sasToken $insiderSasToken | Where-Object { [Version]$_.Split("/")[4] -ge [Version]$projectSettings.applicationDependency } | Select-Object -First 1
                if (-not $artifact) {
                    throw "No artifacts found for application dependency $($projectSettings.applicationDependency)."
                }
            }
            else {
                throw "No artifacts found for application dependency $($projectSettings.applicationDependency). If you are targetting an insider version, you need to create a secret called InsiderSasToken, containing the Insider SAS Token from https://aka.ms/collaborate"
            }
        }
    }
    
    if ($artifact -like "https://*") {
        $artifactUrl = $artifact
        $storageAccount = ("$artifactUrl////".Split('/')[2]).Split('.')[0]
        $artifactType = ("$artifactUrl////".Split('/')[3])
        $version = ("$artifactUrl////".Split('/')[4])
        $country = ("$artifactUrl////".Split('?')[0].Split('/')[5])
        $sasToken = "$($artifactUrl)?".Split('?')[1]
    }
    else {
        $segments = "$artifact/////".Split('/')
        $storageAccount = $segments[0];
        $artifactType = $segments[1]; if ($artifactType -eq "") { $artifactType = 'Sandbox' }
        $version = $segments[2]
        $country = $segments[3]; if ($country -eq "") { $country = $projectSettings.country }
        $select = $segments[4]; if ($select -eq "") { $select = "latest" }
        $sasToken = $segments[5]
        $artifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $version -country $country -select $select -sasToken $sasToken | Select-Object -First 1
        if (-not $artifactUrl) {
            throw "No artifacts found for the artifact setting ($artifact) in $ALGoSettingsFile"
        }
        $version = $artifactUrl.Split('/')[4]
        $storageAccount = $artifactUrl.Split('/')[2]
    }

    if ($projectSettings.additionalCountries -or $country -ne $projectSettings.country) {
        if ($country -ne $projectSettings.country -and !$doNotIssueWarnings) {
            OutputWarning -message "artifact definition in $ALGoSettingsFile uses a different country ($country) than the country definition ($($projectSettings.country))"
        }
        Write-Host "Checking Country and additionalCountries"
        # AT is the latest published language - use this to determine available country codes (combined with mapping)
        $ver = [Version]$version
        Write-Host "https://$storageAccount/$artifactType/$version/$country"
        $atArtifactUrl = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -country at -version "$($ver.Major).$($ver.Minor)" -select Latest -sasToken $sasToken
        Write-Host "Latest AT artifacts $atArtifactUrl"
        $latestATversion = $atArtifactUrl.Split('/')[4]
        $countries = Get-BCArtifactUrl -storageAccount $storageAccount -type $artifactType -version $latestATversion -sasToken $sasToken -select All | ForEach-Object { 
            $countryArtifactUrl = $_.Split('?')[0] # remove sas token
            $countryArtifactUrl.Split('/')[5] # get country
        }
        Write-Host "Countries with artifacts $($countries -join ',')"
        $allowedCountries = $bcContainerHelperConfig.mapCountryCode.PSObject.Properties.Name + $countries | Select-Object -Unique
        Write-Host "Allowed Country codes $($allowedCountries -join ',')"
        if ($allowedCountries -notcontains $projectSettings.country) {
            throw "Country ($($projectSettings.country)), specified in $ALGoSettingsFile is not a valid country code."
        }
        $illegalCountries = $projectSettings.additionalCountries | Where-Object { $allowedCountries -notcontains $_ }
        if ($illegalCountries) {
            throw "additionalCountries contains one or more invalid country codes ($($illegalCountries -join ",")) in $ALGoSettingsFile."
        }
        $artifactUrl = $artifactUrl.Replace($artifactUrl.Split('/')[4],$atArtifactUrl.Split('/')[4])
    }
    return $artifactUrl
}
