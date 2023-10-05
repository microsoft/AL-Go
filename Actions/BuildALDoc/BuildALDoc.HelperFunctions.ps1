function DownloadAlDoc {
    if ("$ENV:aldocPath" -eq "") {
        $artifactUrl = Get-BCArtifactUrl -storageAccount bcinsider -type sandbox -country core -select Latest -accept_insiderEula
        $folder = Download-Artifacts $artifactUrl
        $alLanguageVsix = Join-Path $folder '*.vsix' -Resolve
        $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        New-Item -Path $tempFolder -ItemType Directory | Out-Null
        Expand-Archive -Path $alLanguageVsix -DestinationPath $tempFolder -Force
        $isPsCore = $PSVersionTable.PSVersion -ge "6.0.0"
        if ($isPsCore -and $isLinux) {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/linux/aldoc'
            & /usr/bin/env sudo pwsh -command "& chmod +x $ENV:aldocPath"
        }
        else {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/win32/aldoc.exe'
        }

        CmdDo -command dotnet -arguments @('tool','update','-g docfx')
    }
    $ENV:aldocPath
}

function SanitizeFileName([string] $filename) {
    $filename.Replace('_','-').Replace('?','_').Replace('*','_').Replace(' ','-').Replace('\','-').Replace('/','-').Replace(':','-').Replace('<','-').Replace('>','-').Replace('|','-').Replace('%','pct')
}

function GetAppNameAndFolder {
    Param(
        [string] $appFile
    )

    $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    Extract-AppFileToFolder -appFilename $appFile -appFolder $tmpFolder -generateAppJson
    $appJson = Get-Content -Path (Join-Path $tmpFolder 'app.json') -Encoding utf8 | ConvertFrom-Json
    $appJson.name
    (SanitizeFileName -filename $appJson.name).ToLower()
    Remove-Item -Path $tmpFolder -Recurse -Force
}

function GenerateDocsSite {
    Param(
        [string] $version,
        [string[]] $allVersions,
        [hashtable] $allApps,
        [string] $releaseNotes,
        [string] $header = "Documentation",
        [string] $footer = "Made with <a href=""https://aka.ms/AL-Go"">AL-Go for GitHub</a>, <a href=""https://go.microsoft.com/fwlink/?linkid=2247728"">ALDoc</a> and <a href=""https://dotnet.github.io/docfx"">DocFx</a>",
        [string] $docsPath,
        [string] $logLevel,
        [switch] $hostIt
    )

    $alDocPath = DownloadAlDoc
    $docfxPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -path $docfxPath -ItemType Directory | Out-Null
    try {
        $apps = @()
        # Generate new toc.yml and calculate apps - releases and projects
        $newTocYml = @('items:','  - name: Releases','    items:','    - name: main','      href: /')
        foreach($ver in $allVersions) {
            $newTocYml += @("    - name: $ver","      href: releases/$ver")
        }
        if ($allApps.Keys.Count -eq 1 -and $allApps.Keys[0] -eq '.') {
            # Single prokect repo
            foreach($appFile in $allApps.".") {
                $apps += @($appFile)
                $appName, $appFolder = GetAppNameAndFolder -appFile $appFile
                $newTocYml += @("  - name: $appName","    href: reference/$appFolder/toc.yml")
            }
        }
        else {
            # Multi project repo add all apps
            foreach($project in $allApps.Keys) {
                $newTocYml += @("  - name: $project",'    items:')
                foreach($appFile in $allApps."$project") {
                    $apps += @($appFile)
                    $appName, $appFolder = GetAppNameAndFolder -appFile $appFile
                    $newTocYml += @("    - name: $appName","      href: reference/$appFolder/toc.yml")
                }
            }
        }

        CmdDo -command $aldocPath -arguments @("init","--output ""$docfxpath""","--loglevel $loglevel","--targetpackages ""$($apps -join '","')""")

        Write-Host "Back from aldoc init:"
        get-childitem -path "$docfxPath/*" -Recurse -File | % { Write-Host "$($_.Directory.Name)  [$($_.Name)]" }

        # Update docfx.json
        $docfxJsonFile = Join-Path $docfxPath 'docfx.json'
        $docfxJson = Get-Content -Encoding utf8 -Path $docfxJsonFile | ConvertFrom-Json
        $docfxJson.build.globalMetadata._appName = $header
        $docfxJson.build.globalMetadata._appFooter = $footer
        $docfxJson | ConvertTo-Json -Depth 99 | Set-Content -Path $docfxJsonFile -Encoding utf8

        Write-Host "-----------------------JSON-----------------------"
        Get-Content $docfxJsonFile -Encoding utf8 | Out-Host

        # Create new toc.yml
        $tocYmlFile = Join-Path $docfxpath 'toc.yml'
        Write-Host "-----------------------ORGTOC-----------------------"
        Get-Content $tocYmlFile -Encoding utf8 | Out-Host
        Set-Content -Path $tocYmlFile -Value ($newTocYml -join "`n") -Encoding utf8

        Write-Host "-----------------------NEWTOC-----------------------"
        Get-Content $tocYmlFile -Encoding utf8 | Out-Host

        $apps | ForEach-Object {
            Write-Host "Build $_  $(Test-Path $_))"
            CmdDo -command $aldocPath -arguments @("build","--output ""$docfxpath""","--loglevel $loglevel","--source ""$_""")

            Write-Host "Back from aldoc build:"
            get-childitem -path "$docfxPath/*" -Recurse -File | % { Write-Host "$($_.Directory.Name)  [$($_.Name)]" }
        }

        # Set release notes
        Set-Content -path (Join-Path $docfxpath 'index.md') -value $releaseNotes -encoding utf8

        Write-Host "CALL DOCFX with this:"
        get-childitem -path "$docfxPath/*" -Recurse -File | % { Write-Host "$($_.Directory.Name)  [$($_.Name)]" }

        $arguments = @("build", "--output ""$docsPath""", "--logLevel $loglevel", """$docfxJsonFile""")
        if ($hostIt) {
            $arguments += @('-s')
            Write-Host "Generate and host site"
        }
        CmdDo -command docfx -arguments $arguments
    }
    finally {
        Remove-Item -Path $docfxPath -Recurse -Force
    }
}

function CalculateProjectsAndApps {
    Param(
        [string] $tempFolder,
        [string] $projects,
        [string] $refname
    )

    if ($projects -eq "") { $projects = "*" }
    $projectList = @($projects.Split(',') | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    foreach($mask in 'Apps','Dependencies') {
        $allApps = @{}
        Get-ChildItem -Path $tempFolder -Directory | ForEach-Object {
            if ($_.Name -match "^(.*)-main-$mask-(\d*\.\d*\.\d*\.\d*)$") {
                $project = $Matches[1]
                if ($projectList | Where-Object { $project -like $_ }) {
                    $allApps."$project" = @()
                    Get-ChildItem -Path $_.FullName -Filter '*.app' -Recurse | ForEach-Object {
                        $allApps."$project" += @($_.FullName)
                    }
                }
            }
        }
        $allApps
    }
}