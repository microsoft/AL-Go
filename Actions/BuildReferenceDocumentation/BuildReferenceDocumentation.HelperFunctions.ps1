function DownloadAlDoc {
    if ("$ENV:aldocPath" -eq "") {
        Write-Host "Locating aldoc"
        $artifactUrl = Get-BCArtifactUrl -storageAccount bcinsider -type sandbox -country core -select Latest -accept_insiderEula
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
            & /usr/bin/env sudo pwsh -command "& chmod +x $ENV:aldocPath"
        }
        else {
            $ENV:aldocPath = Join-Path $tempFolder 'extension/bin/win32/aldoc.exe'
        }

        Write-Host "Installing/Updating docfx"
        CmdDo -command dotnet -arguments @("tool","update","-g docfx")
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
        [switch] $useProjectsAsFolders,
        [switch] $hostIt
    )

    function ReplacePlaceHolders {
        Param(
            [string] $str,
            [string] $version,
            [string] $releaseNotes
        )
        return $str.Replace('{REPOSITORY}',$ENV:GITHUB_REPOSITORY).Replace('{VERSION}',$version).Replace('{RELEASENOTES}',$releaseNotes)
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
    $indexContent = ReplacePlaceHolders -str $indexTemplate.Replace('{INDEXTEMPLATERELATIVEPATH}',$thisTemplateRelativePath) -version $version -releaseNotes $releaseNotes

    $alDocPath = DownloadAlDoc
    $docfxPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -path $docfxPath -ItemType Directory | Out-Null
    try {
        $apps = @()
        # Generate new toc.yml and calculate apps - releases and projects
        $prefix = ''
        if ($version) {
            # If $version is set, then we are generating reference documentation for a release
            $prefix = "../../"
        }
        $newTocYml = @(
            "items:"
            )
        if ($allVersions.Count -gt 0) {
            $newTocYml += @(
                "  - name: Releases"
                "    items:"
                "    - name: main"
                "      href: $($prefix)index.html"
                )
            foreach($ver in $allVersions) {
                $newTocYml += @(
                    "    - name: $ver"
                    "      href: $($prefix)releases/$ver/index.html"
                    )
            }
        }
        $allApps | ConvertTo-Json -Depth 99 | Out-Host
        if ($allApps.Keys.Count -eq 1 -and $allApps.Keys[0] -eq $repoName) {
            # Single project repo - do not use project names as folders
            $useProjectsAsFolders = $false
        }
        $projects = @($allApps.Keys.GetEnumerator() | Sort-Object)
        foreach($project in $projects) {
            if ($useProjectsAsFolders) {
                $newTocYml += @(
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
                $apps += @($appFile)
                $appName, $appFolder = GetAppNameAndFolder -appFile $appFile
                $theseApps."$appName" = $appFolder
            }
            # Add all apps sorted by name
            $theseApps.Keys.GetEnumerator() | Sort-Object | ForEach-Object {
                $newTocYml += @(
                    "$($indent)- name: $($_)"
                    "$($indent)  href: reference/$($theseApps."$_")/toc.yml"
                    )
            }
        }

        $arguments = @(
            "init"
            "--output ""$docfxpath"""
            "--loglevel $loglevel"
            "--targetpackages ""$($apps -join '","')"""
            )
        Write-Host "invoke aldoc $arguments"
        CmdDo -command $aldocPath -arguments $arguments

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
            $arguments = @(
                "build"
                "--output ""$docfxpath"""
                "--loglevel $loglevel"
                "--source ""$_"""
                )
            Write-Host "invoke aldoc $arguments"
            CmdDo -command $aldocPath -arguments $arguments
        }

        # Set release notes
        Write-Host "Update index.md"
        $indexMdFile = Join-Path $docfxpath 'index.md'
        Set-Content -path $indexMdFile -value $indexContent -encoding utf8

        Write-Host "index.md:"
        Get-Content $indexMdFile | Out-Host

        $arguments = @(
            "build"
            "--output ""$docsPath"""
            "--logLevel $loglevel"
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

function CalculateProjectsAndApps {
    Param(
        [string] $tempFolder,
        [string[]] $projects,
        [string[]] $excludeProjects,
        [switch] $useProjectsAsFolders
    )

    if ($projects.Count -eq 0) { $projects = @("*") }
    $projectList = @($projects | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    Write-Host "Include Project Patterns"
    $projectList | ForEach-Object { Write-Host "- $_" }
    $excludeProjectList = @($excludeProjects | ForEach-Object { $_.Replace('\','_').Replace('/','_') })
    Write-Host "Exclude Project Patterns"
    $excludeProjectList | ForEach-Object { Write-Host "- $_" }
    foreach($mask in 'Apps','Dependencies') {
        $allApps = @{}
        Get-ChildItem -Path $tempFolder -Directory | ForEach-Object {
            if ($_.Name -match "^(.*)-main-$mask-(\d*\.\d*\.\d*\.\d*)$") {
                $project = $Matches[1]
                Write-Host "Project: $project"
                if ($projectList | Where-Object { $project -like $_ }) {
                    if (-not ($excludeProjectList | Where-Object { $project -like $_ })) {
                        if (-not $useProjectsAsFolders) {
                            $project = 'dummy'
                        }
                        if (-not $allApps.ContainsKey("$project")) {
                            $allApps."$project" = @()
                        }
                        Get-ChildItem -Path $_.FullName -Filter '*.app' | ForEach-Object {
                            $allApps."$project" += @($_.FullName)
                        }
                    }
                }
            }
        }
        $allApps
    }
}