function Test-Property {
    Param(
        [HashTable] $json,
        [string] $settingsDescription,
        [string] $key,
        [switch] $must,
        [switch] $should,
        [switch] $maynot,
        [switch] $shouldnot
    )

    $exists = $json.Keys -contains $key
    if ($exists) {
        if ($maynot) {
            throw "Property '$key' may not exist in $settingsDescription"
        }
        elseif ($shouldnot) {
            Write-Host "::Warning::Property '$key' should not exist in $settingsDescription"
        }
    }
    else {
        if ($must) {
            throw "Property '$key' must exist in $settingsDescription"
        }
        elseif ($should) {
            Write-Host "::Warning::Property '$key' should exist in $settingsDescription"
        }
    }
}

function Test-Shell {
    Param(
        [HashTable] $json,
        [string] $settingsDescription,
        [string] $property
    )

    if ($json.Keys -contains $property) {
        $shell = $json.$property
        if ($shell -ne 'powershell' -and $shell -ne 'pwsh') {
            throw "$property is '$shell', must be 'powershell' or 'pwsh' in $settingsDescription"
        }
    }
}

function Test-SettingsJson {
    Param(
        [hashtable] $json,
        [string] $settingsDescription,
        [ValidateSet('Repo','Project','Workflow','Variable')]
        [string] $type
    )

    Test-Shell -json $json -settingsDescription $settingsDescription -property 'shell'
    Test-Shell -json $json -settingsDescription $settingsDescription -property 'gitHubRunnerShell'

    if ($type -eq 'Repo') {
        # Test for things that should / should not exist in a repo settings file
        Test-Property -settingsDescription $settingsDescription -json $json -key 'templateUrl' -should
    }
    if ($type -eq 'Project') {
        # Test for things that should / should not exist in a project settings file
    }
    if ($type -eq 'Workflow') {
        # Test for things that should / should not exist in a workflow settings file
    }
    if ($type -eq 'Variable') {
        # Test for things that should / should not exist in a settings variable
    }
    if ($type -eq 'Project' -or $type -eq 'Workflow') {
        # templateUrl should not be in Project or Workflow settings
        Test-Property -settingsDescription $settingsDescription -json $json -key 'templateUrl' -maynot

        # schedules and runs-on should not be in Project or Workflow settings
        'nextMajorSchedule','nextMinorSchedule','currentSchedule','githubRunner','runs-on' | ForEach-Object {
            Test-Property -settingsDescription $settingsDescription -json $json -key $_ -shouldnot
        }
    }
}

function Test-JsonStr {
    Param(
        [string] $jsonStr,
        [string] $settingsDescription,
        [ValidateSet('Repo','Project','Workflow','Variable')]
        [string] $type
    )

    if ($jsonStr -notlike '{*') {
        throw "Settings in $settingsDescription is not recognized as JSON (does not start with '{'))"
    }

    try {
        $json = $jsonStr | ConvertFrom-Json | ConvertTo-HashTable
        Test-SettingsJson -json $json -settingsDescription $settingsDescription -type:$type
    }
    catch {
        throw "$($_.Exception.Message.Replace("`r",'').Replace("`n",' '))"
    }

}

function Test-JsonFile {
    Param(
        [string] $jsonFile,
        [string] $baseFolder,
        [ValidateSet('Repo','Project','Workflow')]
        [string] $type
    )

    $settingsFile = $jsonFile.Substring($baseFolder.Length+1)
    Write-Host "Checking AL-Go $type settings file in $settingsFile (type = $type)"

    Test-JsonStr -org -jsonStr (Get-Content -Path $jsonFile -Raw -Encoding UTF8) -settingsDescription $settingsFile -type $type
}

function Test-ALGoRepository {
    Param(
        [string] $baseFolder = $ENV:GITHUB_WORKSPACE
    )

    if ($ENV:ALGoOrgSettings) {
        Write-Host "Checking AL-Go Org Settings variable (ALGoOrgSettings)"
        Test-JsonStr -jsonStr "$ENV:ALGoOrgSettings" -settingsDescription 'ALGoOrgSettings variable' -type 'Variable'
    }
    if ($ENV:ALGoRepoSettings) {
        Write-Host "Checking AL-Go Repo Settings variable (ALGoRepoSettings)"
        Test-JsonStr -jsonStr "$ENV:ALGoRepoSettings" -settingsDescription 'ALGoRepoSettings variable' -type 'Variable'
    }

    Write-Host "BaseFolder: $baseFolder"

    # Test .json files are formatted correctly
    # Get-ChildItem needs -force to include folders starting with . (e.x. .github / .AL-Go) on Linux
    Get-ChildItem -Path $baseFolder -Filter '*.json' -Recurse -Force | ForEach-Object {
        if ($_.Directory.Name -eq '.AL-Go' -and $_.BaseName -eq 'settings') {
            Test-JsonFile -jsonFile $_.FullName -baseFolder $baseFolder -type 'Project'
        }
        elseif ($_.Directory.Name -eq '.github' -and $_.BaseName -like '*ettings') {
            if ($_.BaseName -eq 'AL-Go-Settings') {
                $type = 'Repo'
            }
            else {
                $type = 'Workflow'
            }
            Test-JsonFile -jsonFile $_.FullName -baseFolder $baseFolder -type $type
        }
    }
}

function Write-Big {
    Param(
        [string] $str
    )
    $chars = @{
        "0" = @(
            "  ___  "
            " / _ \ "
            "| | | |"
            "| | | |"
            "| |_| |"
            " \___/ "
        )
        "1" = @(
            " __ "
            "/_ |"
            " | |"
            " | |"
            " | |"
            " |_|"
        )
        "2" = @(
            " ___  "
            "|__ \ "
            "   ) |"
            "  / / "
            " / /_ "
            "|____|"
        )
        "3" = @(
            " ____  "
            "|___ \ "
            "  __) |"
            " |__ < "
            " ___) |"
            "|____/ "
        )
        "4" = @(
            " _  _   "
            "| || |  "
            "| || |_ "
            "|__   _|"
            "   | |  "
            "   |_|  "
        )
        "5" = @(
            " _____ "
            "| ____|"
            "| |__  "
            "|___ \ "
            " ___) |"
            "|____/ "
        )
        "6" = @(
            "   __  "
            "  / /  "
            " / /_  "
            "| '_ \ "
            "| (_) |"
            " \___/ "
        )
        "7" = @(
            " ______ "
            "|____  |"
            "    / / "
            "   / /  "
            "  / /   "
            " /_/    "
        )
        "8" = @(
            "  ___  "
            " / _ \ "
            "| (_) |"
            " > _ < "
            "| (_) |"
            " \___/ "
        )
        "9" = @(
            "  ___  "
            " / _ \ "
            "| (_) |"
            " \__, |"
            "   / / "
            "  /_/  "
        )
        "." = @(
            "   "
            "   "
            "   "
            "   "
            " _ "
            "(_)"
        )
        "v" = @(
            "       "
            "       "
            "__   __"
            "\ \ / /"
            " \ V / "
            "  \_(_)"
        )
        "p" = @(
            " _____                _               "
            "|  __ \              (_)              "
            "| |__) | __ _____   ___  _____      __"
            "|  ___/ '__/ _ \ \ / / |/ _ \ \ /\ / /"
            "| |   | | |  __/\ V /| |  __/\ V  V / "
            "|_|   |_|  \___| \_/ |_|\___| \_/\_/  "
        )
        "d" = @(
            " _____             "
            "|  __ \            "
            "| |  | | _____   __"
            "| |  | |/ _ \ \ / /"
            "| |__| |  __/\ V / "
            "|_____/ \___| \_(_)"
        )
        "a" = @(
            "          _           _____          __              _____ _ _   _    _       _       "
            "    /\   | |         / ____|        / _|            / ____(_) | | |  | |     | |      "
            "   /  \  | |  ______| |  __  ___   | |_ ___  _ __  | |  __ _| |_| |__| |_   _| |__    "
            "  / /\ \ | | |______| | |_ |/ _ \  |  _/ _ \| '__| | | |_ | | __|  __  | | | | '_ \   "
            " / ____ \| |____    | |__| | (_) | | || (_) | |    | |__| | | |_| |  | | |_| | |_) |  "
            "/_/    \_\______|    \_____|\___/  |_| \___/|_|     \_____|_|\__|_|  |_|\__,_|_.__/   "
        )
    }

    $lines = $chars."a".Count
    for ($line = 0; $line -lt $lines; $line++) {
        foreach ($ch in $str.ToCharArray()) {
            if ($chars.Keys -contains $ch) {
                $bigCh = $chars."$ch"
                Write-Host -noNewline $bigCh[$line]
            }
        }
        Write-Host
    }
}
