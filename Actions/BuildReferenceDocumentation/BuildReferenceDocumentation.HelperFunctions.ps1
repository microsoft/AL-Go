function DownloadAlDoc {
    if ("$ENV:aldocPath" -eq "") {
        $ENV:aldocCommand = ''
        Write-Host "Locating aldoc"
        $artifactUrl = Get-BCArtifactUrl -type sandbox -country core -select Latest -accept_insiderEula
        Write-Host "Downloading aldoc"
        $folder = Download-Artifacts $artifactUrl
        $alLanguageVsix = Join-Path $folder '*.vsix' -Resolve
        $tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        Copy-Item -Path $alLanguageVsix -Destination "$($tempFolder).zip"
        New-Item -Path $tempFolder -ItemType Directory | Out-Null
        Write-Host "Extracting aldoc"
        Expand-Archive -Path "$($tempFolder).zip" -DestinationPath $tempFolder -Force
        Remove-Item -Path "$($tempFolder).zip" -Force
        if ($IsLinux) {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/linux/aldoc'
            if (Test-Path $ENV:aldocPath) {
                & /usr/bin/env sudo pwsh -command "& chmod +x $ENV:aldocPath"
            }
            else {
                # If the executable isn't found, use dotnet to run the dll
                $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/linux/aldoc.dll'
                $ENV:aldocCommand = 'dotnet'
            }
        }
        else {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/win32/aldoc.exe'
        }
        if (-not (Test-Path $ENV:aldocPath)) {
            throw "aldoc tool not found at $ENV:aldocPath"
        }
        if ($IsLinux) {
        }
        Write-Host "Installing/Updating docfx"
        CmdDo -command dotnet -arguments @("tool","update","--global docfx --version 2.75.3") -messageIfCmdNotFound "dotnet not found. Please install it from https://dotnet.microsoft.com/download"
    }
    return $ENV:aldocPath, $ENV:aldocCommand
}

function SanitizeFileName([string] $fileName) {
    $fileName.Replace('_','-').Replace('?','_').Replace('*','_').Replace(' ','-').Replace('\','-').Replace('/','-').Replace(':','-').Replace('<','-').Replace('>','-').Replace('|','-').Replace('%','pct')
}

function GetAppNameAndFolder {
    Param(
        [string] $appFile
    )

    $tmpFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    Extract-AppFileToFolder -appFilename $appFile -appFolder $tmpFolder -generateAppJson
    $appJson = Get-Content -Path (Join-Path $tmpFolder 'app.json') -Encoding utf8 | ConvertFrom-Json
    $appJson.name
    (SanitizeFileName -fileName $appJson.name).ToLower()
    Remove-Item -Path $tmpFolder -Recurse -Force
}

function GenerateTocYml {
    Param(
        [string] $version,
        [string[]] $allVersions,
        [hashtable] $allApps,
        [switch] $groupByProject
    )

    $prefix = ''
    if ($version) {
        # If $version is set, then we are generating reference documentation for a release
        # all releases will be in a subfolder called releases/$version
        # prefix is used to reference links in the root of the site relative to the site we are building now
        # We cannot use / as prefix, because that will not work when hosting the site on GitHub pages
        $prefix = "../../"
    }
    $tocYml = @(
        "items:"
        )
    if ($allVersions.Count -gt 0) {
        $tocYml += @(
            "  - name: Releases"
            "    items:"
            "    - name: main"
            "      href: $($prefix)index.html"
            )
        foreach($ver in $allVersions) {
            $tocYml += @(
                "    - name: $ver"
                "      href: $($prefix)releases/$ver/index.html"
                )
        }
    }
    $allApps | ConvertTo-Json -Depth 99 | Out-Host
    if ($allApps.Keys.Count -eq 1 -and ($allApps.Keys[0] -eq $repoName -or $allApps.Keys[0] -eq 'dummy')) {
        # Single project repo - do not use project names as folders
        $groupByProject = $false
    }
    $projects = @($allApps.Keys.GetEnumerator() | Sort-Object)
    foreach($project in $projects) {
        if ($groupByProject) {
            $tocYml += @(
                "  - name: $project"
                "    items:"
                )
            $indent = "    "
        }
        else {
            $indent = "  "
        }
        $theseApps = @{}
        # Get all apps for this project
        foreach($appFile in $allApps."$project") {
            $appName, $appFolder = GetAppNameAndFolder -appFile $appFile
            $theseApps."$appName" = $appFolder
        }
        # Add all apps sorted by name
        $theseApps.Keys.GetEnumerator() | Sort-Object | ForEach-Object {
            $tocYml += @(
                "$($indent)- name: $($_)"
                "$($indent)  href: reference/$($theseApps."$_")/toc.yml"
                )
        }
    }
    $tocYml
}


#
# Generate Reference documentation for a branch or a release.
# All Apps to use for the ref. doc. are downloaded from the release or latest build of the branch.
#
function GenerateDocsSite {
    Param(
        [string] $version,
        [string[]] $allVersions,
        [hashtable] $allApps,
        [string] $repoName,
        [string] $releaseNotes,
        [string] $header,
        [string] $footer,
        [string] $defaultIndexMD,
        [string] $defaultReleaseMD,
        [string] $docsPath,
        [string] $logLevel,
        [switch] $groupByProject,
        [switch] $hostIt
    )

    function ReplacePlaceHolders {
        Param(
            [string] $str,
            [string] $version = '',
            [string] $releaseNotes = '',
            [string] $indexTemplateRelativePath = ''
        )
        return $str.Replace('{REPOSITORY}',$ENV:GITHUB_REPOSITORY).Replace('{VERSION}',$version).Replace('{RELEASENOTES}',$releaseNotes).Replace('{INDEXTEMPLATERELATIVEPATH}',$indexTemplateRelativePath)
    }

    $indexTemplateRelativePath = '.aldoc/index.md'
    if ($version) {
        $thisTemplateRelativePath = '.aldoc/release.md'
        $thisDefaultMD = $defaultReleaseMD
    }
    else {
        $thisTemplateRelativePath = $indexTemplateRelativePath
        $thisDefaultMD = $defaultIndexMD
    }

    $indexTemplatePath = Join-Path $ENV:GITHUB_WORKSPACE $thisTemplateRelativePath
    if (-not (Test-Path $indexTemplatePath)) {
        $indexTemplatePath = Join-Path $ENV:GITHUB_WORKSPACE $indexTemplateRelativePath
    }
    if (Test-Path $indexTemplatePath) {
        $indexTemplate = Get-Content -Encoding utf8 -Path $indexTemplatePath -Raw
    }
    else {
        $indexTemplate = $thisDefaultMD
    }
    $indexContent = ReplacePlaceHolders -str $indexTemplate -version $version -releaseNotes $releaseNotes -indexTemplateRelativePath $thisTemplateRelativePath

    $aldocPath, $aldocCommand = DownloadAlDoc
    if ($aldocCommand) {
        $aldocArguments = @($aldocPath)
    }
    else {
        $aldocArguments = @()
        $aldocCommand = $aldocPath
    }

    $docfxPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -Path $docfxPath -ItemType Directory | Out-Null
    try {
        # Generate new toc.yml with releases and apps
        $newTocYml = GenerateTocYml -version $version -allVersions $allVersions -allApps $allApps -repoName $repoName -groupByProject $groupByProject

        # calculate apps for aldoc
        $apps = @()
        foreach($value in $allApps.Values) {
            $apps += @($value)
        }
        $apps = @($apps | Select-Object -Unique)

        $arguments = $aldocArguments + @(
            "init"
            "--output", """$docfxpath""",
            "--loglevel", $loglevel,
            "--targetpackages", "'$($apps -join "','")'"
            )
        Write-Host "invoke $aldocCommand $arguments"
        CmdDo -command $aldocCommand -arguments $arguments

        # Update docfx.json
        Write-Host "Update docfx.json"
        $docfxJsonFile = Join-Path $docfxPath 'docfx.json'
        $docfxJson = Get-Content -Encoding utf8 -Path $docfxJsonFile | ConvertFrom-Json
        $docfxJson.build.globalMetadata._appName = ReplacePlaceHolders -str $header -version $version -releaseNotes $releaseNotes
        $docfxJson.build.globalMetadata._appFooter = ReplacePlaceHolders -str $footer -version $version -releaseNotes $releaseNotes
        $docfxJson | ConvertTo-Json -Depth 99 | Set-Content -Path $docfxJsonFile -Encoding utf8

        Write-Host "docfx.json:"
        Get-Content $docfxJsonFile | Out-Host

        # Create new toc.yml
        Write-Host "Create new toc.yml"
        $tocYmlFile = Join-Path $docfxpath 'toc.yml'

        Write-Host "Original TOC (from aldoc)):"
        Get-Content $tocYmlFile | Out-Host

        Set-Content -Path $tocYmlFile -Value ($newTocYml -join "`n") -Encoding utf8

        Write-Host "TOC:"
        Get-Content $tocYmlFile | Out-Host

        $apps | ForEach-Object {
            $arguments = $aldocArguments + @(
                "build"
                "--output", """$docfxpath""",
                "--loglevel", $loglevel,
                "--source", $_
                )
            Write-Host "invoke $aldocCommand $arguments"
            CmdDo -command $aldocCommand -arguments $arguments
        }

        # Set release notes
        Write-Host "Update index.md"
        $indexMdFile = Join-Path $docfxpath 'index.md'
        Set-Content -path $indexMdFile -value $indexContent -encoding utf8

        Write-Host "index.md:"
        Get-Content $indexMdFile | Out-Host

        $arguments = @(
            "build"
            "--output", """$docsPath""",
            "--logLevel", $loglevel,
            """$docfxJsonFile"""
            )
        if ($hostIt) {
            $arguments += @("-s")
            Write-Host "Generate and host site"
        }
        Write-Host "invoke doxfx $arguments"
        CmdDo -command docfx -arguments $arguments
    }
    finally {
        Remove-Item -Path $docfxPath -Recurse -Force
    }
}

# Build a list of all projects (folders) and apps to use when building reference documentation
# return value is a hashtable for all apps and a hashtable for all dependencies
# Every hashtable has project name as key and an array of app files as value
# if groupByProject is false, all apps will be collected in one "project" called "dummy", which is never displayed
function CalculateProjectsAndApps {
    Param(
        [string] $tempFolder,
        [string[]] $includeProjects,
        [string[]] $excludeProjects,
        [switch] $groupByProject
    )

    if ($includeProjects.Count -eq 0) { $includeProjects = @("*") }
    $projectList = @($includeProjects | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    Write-Host "Include Project Patterns"
    $projectList | ForEach-Object { Write-Host "- $_" }
    $excludeProjectList = @($excludeProjects | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    Write-Host "Exclude Project Patterns"
    $excludeProjectList | ForEach-Object { Write-Host "- $_" }
    foreach($mask in 'Apps','Dependencies') {
        $allApps = @{}
        foreach($folder in (Get-ChildItem -Path $tempFolder | Where-Object { $_.PSIsContainer })) {
            if (($folder.Name -match "^(.*)-main-$mask-(\d*\.\d*\.\d*\.\d*)$") -or
                ($folder.Name -match "^(.*)-release.*-$mask-(\d*\.\d*\.\d*\.\d*)$")) {
                $project = $Matches[1]
                $includeIt = $null -ne ($projectList | Where-Object { $project -like $_ })
                if ($includeIt) {
                    $excludeIt = $null -ne ($excludeProjectList | Where-Object { $project -like $_ })
                    if (-not $excludeIt) {
                        if (-not $groupByProject) {
                            # use project name dummy for all apps when not using projects as folders
                            $project = 'dummy'
                        }
                        if (-not $allApps.ContainsKey("$project")) {
                            $allApps."$project" = @()
                        }
                        Get-ChildItem -Path $folder.FullName -Filter '*.app' | ForEach-Object {
                            $allApps."$project" += @($_.FullName)
                        }
                    }
                }
            }
        }
        $allApps
    }
}
