function Test-Property {
    Param(
        [HashTable] $json,
        [string] $key,
        [switch] $must,
        [switch] $should,
        [switch] $maynot,
        [switch] $shouldnot
    )

    $exists = $json.ContainsKey($key)
    if ($exists) {
        if ($maynot) {
            Write-Host "::Error::Property '$key' may not exist in $settingsFile"
        }
        elseif ($shouldnot) {
            Write-Host "::Warning::Property '$key' should not exist in $settingsFile"
        }
    }
    else {
        if ($must) {
            Write-Host "::Error::Property '$key' must exist in $settingsFile"
        }
        elseif ($should) {
            Write-Host "::Warning::Property '$key' should exist in $settingsFile"
        }
    }
}

function Test-Json {
    Param(
        [string] $jsonFile,
        [string] $baseFolder,
        [switch] $repo
    )

    $settingsFile = $jsonFile.Substring($baseFolder.Length)
    if ($repo) {
        Write-Host "Checking AL-Go Repo Settings file $settingsFile"
    }
    else {
        Write-Host "Checking AL-Go Settings file $settingsFile"
    }

    try {
        $json = Get-Content -Path $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json | ConvertTo-HashTable
        if ($repo) {
            Test-Property -settingsFile $settingsFile -json $json -key 'templateUrl' -should
        }
        else {
            Test-Property -settingsFile $settingsFile -json $json -key 'templateUrl' -maynot
            'nextMajorSchedule','nextMinorSchedule','currentSchedule','githubRunner','runs-on' | ForEach-Object {
                Test-Property -settingsFile $settingsFile -json $json -key $_ -shouldnot
            }
        }
    }
    catch {
        Write-Host "::Error::$($_.Exception.Message)"
    }
}

function Test-ALGoRepository {
    Param(
        [string] $baseFolder
    )
    
    # Test .json files are formatted correctly
    Get-ChildItem -Path $baseFolder -Filter '*.json' -Recurse | ForEach-Object {
        if ($_.FullName -like '*\.AL-Go\Settings.json') {
            Test-Json -jsonFile $_.FullName -baseFolder $baseFolder
        }
        elseif ($_.FullName -like '*\.github\*Settings.json') {
            Test-Json -jsonFile $_.FullName -baseFolder $baseFolder -repo:($_.BaseName -eq "AL-Go-Settings")
        }
    }
}
