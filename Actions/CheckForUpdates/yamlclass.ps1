#requires -Version 5.0

# This class holds the content of a Yaml file
# The content is stored in an array of strings, where each string is a line of the Yaml file
# The class provides methods to find and replace lines in the Yaml file
class Yaml {

    [string[]] $content

    # Constructor based on an array of strings
    Yaml([string[]] $content) {
        $this.content = $content
    }

    # Static load function to load a Yaml file into a Yaml class
    static [Yaml] Load([string] $filename) {
        $fileContent = Get-Content -Path $filename -Encoding UTF8
        return [Yaml]::new($fileContent)
    }

    # Save the Yaml file with LF line endings using UTF8 encoding
    Save([string] $filename) {
        $this.content | Set-ContentLF -Path $filename
    }

    # Find the lines for the specified Yaml path, given by $line
    # If $line contains multiple segments separated by '/', then the segments are searched for recursively
    # The Yaml path is case insensitive
    # The Search mechanism finds only lines with the right indentation. When searching for a specific job, use jobs:/(job name)/
    # $start and $count are set to the start and count of the lines found
    # Returns $true if the line are found, otherwise $false
    # If $line ends with '/', then the lines for the section are returned only
    # If $line doesn't end with '/', then the line + the lines for the section are returned (and the lines for the section are indented)
    [bool] Find([string] $line, [ref] $start, [ref] $count) {
        if ($line.Contains('/')) {
            $idx = $line.IndexOf('/')
            $find = $line.Split('/')[0]
            $rest = $line.Substring($idx+1)
            $s1 = 0
            $c1 = 0
            if ($rest -eq '') {
                [Yaml] $yaml = $this.Get($find, [ref] $s1, [ref] $c1)
                if ($yaml) {
                   $start.value = $s1+1
                   $count.value = $c1-1
                   return $true
                }
            }
            else {
                [Yaml] $yaml = $this.Get("$find/", [ref] $s1, [ref] $c1)
                if ($yaml) {
                    $s2 = 0
                    $c2 = 0
                    if ($yaml.Find($rest, [ref] $s2, [ref] $c2)) {
                        $start.value = $s1+$s2
                        $count.value = $c2
                        return $true
                    }
                }
            }
            return $false
        }
        else {
            $start.value = -1
            $count.value = 0
            for($i=0; $i -lt $this.content.Count; $i++) {
                $s = "$($this.content[$i])  "
                if ($s -like "$($line)*") {
                    if ($s.TrimEnd() -eq $line) {
                        $start.value = $i
                    }
                    else {
                        $start.value = $i
                        $count.value = 1
                        return $true
                    }
                }
                elseif ($start.value -ne -1 -and $s -notlike "  *") {
                    if ($this.content[$i-1].Trim() -eq '') {
                        $count.value = ($i-$start.value-1)
                    }
                    else {
                        $count.value = ($i-$start.value)
                    }
                    return $true
                }
            }
            if ($start.value -ne -1) {
                $count.value = $this.content.Count-$start.value
                return $true
            }
            else {
                return $false
            }
        }
    }

    # Locate the lines for the specified Yaml path, given by $line and return lines as a Yaml object
    # $start and $count are set to the start and count of the lines found
    # Indentation of the first line returned is 0
    # Indentation of the other lines returned is the original indentation - the original indentation of the first line
    # Returns $null if the lines are not found
    # See Find for more details
    [Yaml] Get([string] $line, [ref] $start, [ref] $count) {
        $s = 0
        $c = 0
        if ($this.Find($line, [ref] $s, [ref] $c)) {
            $charCount = ($line.ToCharArray() | Where-Object {$_ -eq '/'} | Measure-Object).Count
            [string[]] $result = @($this.content | Select-Object -Skip $s -First $c | ForEach-Object {
                "$_$("  "*$charCount)".Substring(2*$charCount).TrimEnd()
            } )
            $start.value = $s
            $count.value = $c
            return [Yaml]::new($result)
        }
        else {
            return $null
        }
    }

    # Locate the lines for the specified Yaml path, given by $line and return lines as a Yaml object
    # Same function as Get, but $start and $count are not set
    [Yaml] Get([string] $line) {
        [int]$start = 0
        [int]$count = 0
        return $this.Get($line, [ref] $start, [ref] $count)
    }

    # Locate all lines in the next level of a yaml path
    # if $line is empty, you get all first level lines
    # Example:
    # GetNextLevel("jobs:/") returns @("Initialization:","CheckForUpdates:","Build:","Deploy:",...)
    [string[]] GetNextLevel([string] $line) {
        [int]$start = 0
        [int]$count = 0
        [Yaml] $yaml = $this
        if ($line) {
            $yaml = $this.Get($line, [ref] $start, [ref] $count)
        }
        return $yaml.content | Where-Object { $_ -and -not $_.StartsWith(' ') }
    }

    # Get the value of a property as a string
    # Example:
    # GetProperty("jobs:/Build:/needs:") returns "[ Initialization, Build1 ]"
    [string] GetProperty([string] $line) {
        [int]$start = 0
        [int]$count = 0
        [Yaml] $yaml = $this.Get($line, [ref] $start, [ref] $count)
        if ($yaml -and $yaml.content.Count -eq 1) {
            return $yaml.content[0].SubString($yaml.content[0].IndexOf(':')+1).Trim()
        }
        return $null
    }

    # Get the value of a property as a string array
    # Example:
    # GetPropertyArray("jobs:/Build:/needs:") returns @("Initialization", "Build")
    [string[]] GetPropertyArray([string] $line) {
        $prop = $this.GetProperty($line)
        if ($prop) {
            # "needs: [ Initialization, Build ]" becomes @("Initialization", "Build")
            return $prop.TrimStart('[').TrimEnd(']').Split(',').Trim()
        }
        return $null
    }

    # Replace the lines for the specified Yaml path, given by $line with the lines in $content
    # If $line ends with '/', then the lines for the section are replaced only
    # If $line doesn't end with '/', then the line + the lines for the section are replaced
    # See Find for more details
    [void] Replace([string] $line, [string[]] $content) {
        [int]$start = 0
        [int]$count = 0
        if ($this.Find($line, [ref] $start, [ref] $count)) {
            $charCount = ($line.ToCharArray() | Where-Object {$_ -eq '/'} | Measure-Object).Count
            if ($charCount) {
                $yamlContent = $content | ForEach-Object { "$("  "*$charCount)$_".TrimEnd() }
            }
            else {
                $yamlContent = $content
            }
            $this.Remove($start, $count)
            $this.Insert($start, $yamlContent)
        }
        else {
            Write-Host -ForegroundColor Red "cannot locate $line"
        }
    }

    # Replace all occurrences of $from with $to throughout the Yaml content
    [void] ReplaceAll([string] $from, [string] $to) {
        $this.content = $this.content | ForEach-Object { $_.replace($from, $to) }
    }

    # Remove lines in Yaml content
    [void] Remove([int] $start, [int] $count) {
        if ($count -eq 0) {
            return
        }
        if ($start -eq 0) {
            $this.content = $this.content[$count..($this.content.Count-1)]
        }
        elseif($start + $count -ge $this.content.Count) {
            $this.content = $this.content[0..($start-1)]
        }
        else {
            $this.content = $this.content[0..($start-1)] + $this.content[($start+$count)..($this.content.Count-1)]
        }
    }

    # Insert lines in Yaml content
    [void] Insert([int] $index, [string[]] $yamlContent) {
        if (!$yamlContent) {
            return
        }
        if ($index -eq 0) {
            $this.content = $yamlContent + $this.content
        }
        elseif ($index -eq $this.content.Count) {
            $this.content = $this.content + $yamlContent
        }
        else {
            $this.content = $this.content[0..($index-1)] + $yamlContent + $this.content[$index..($this.content.Count-1)]
        }
    }

    # Add lines to Yaml content
    [void] Add([string[]] $yamlContent) {
        if (!$yamlContent) {
            return
        }
        $this.Insert($this.content.Count, $yamlContent)
    }

    # Locate jobs in YAML based on a name pattern
    # Example:
    # GetCustomJobsFromYaml() returns @("CustomJob1", "CustomJob2")
    # GetCustomJobsFromYaml("Build*") returns @("Build1","Build2","Build")
    [hashtable[]] GetCustomJobsFromYaml([string] $name) {
        $result = @()
        $allJobs = $this.GetNextLevel('jobs:/').Trim(':')
        $customJobs = @($allJobs | Where-Object { $_ -like $name })
        if ($customJobs) {
            $nativeJobs = @($allJobs | Where-Object { $customJobs -notcontains $_ })
            Write-Host "Native Jobs:"
            foreach($nativeJob in $nativeJobs) {
                Write-Host "- $nativeJob"
            }
            Write-Host "Custom Jobs:"
            foreach($customJob in $customJobs) {
                Write-Host "- $customJob"
                $jobsWithDependency = $nativeJobs | Where-Object { $this.GetPropertyArray("jobs:/$($_):/needs:") | Where-Object { $_ -eq $customJob } }
                # If any Build Job has a dependency on this CustomJob, add will be added to all build jobs later
                if ($jobsWithDependency | Where-Object { $_ -like 'Build*' }) {
                    $jobsWithDependency = @($jobsWithDependency | Where-Object { $_ -notlike 'Build*' }) + @('Build')
                }
                if ($jobsWithDependency) {
                    Write-Host "  - Jobs with dependency: $($jobsWithDependency -join ', ')"
                    $result += @(@{ "Name" = $customJob; "Content" = @($this.Get("jobs:/$($customJob):").content); "NeedsThis" = @($jobsWithDependency) })
                }
            }
        }
        return $result
    }

    # Add jobs to Yaml and update Needs section from native jobs which needs this custom Job
    # $customJobs is an array of hashtables with Name, Content and NeedsThis
    # Example:
    # $customJobs = @(@{ "Name" = "CustomJob1"; "Content" = @("  - pwsh","  -File Build1"); "NeedsThis" = @("Initialization", "Build") })
    # AddCustomJobsToYaml($customJobs)
    # The function will add the job CustomJob1 to the Yaml file and update the Needs section of Initialization and Build
    # The function will not add the job CustomJob1 if it already exists
    [void] AddCustomJobsToYaml([hashtable[]] $customJobs) {
        $existingJobs = $this.GetNextLevel('jobs:/').Trim(':')
        Write-Host "Adding New Jobs"
        foreach($customJob in $customJobs) {
            if ($existingJobs -contains $customJob.Name) {
                Write-Host "Job $($customJob.Name) already exists"
                continue
            }
            Write-Host "$($customJob.Name) has dependencies from $($customJob.NeedsThis -join ',')"
            foreach($needsthis in $customJob.NeedsThis) {
                if ($needsthis -eq 'Build') {
                    $existingJobs | Where-Object { $_ -like 'Build*'} | ForEach-Object {
                        # Add dependency to all build jobs
                        $this.Replace("jobs:/$($_):/needs:","needs: [ $(@($this.GetPropertyArray("jobs:/$($_):/needs:"))+@($customJob.Name) -join ', ') ]")
                    }
                }
                elseif ($existingJobs -contains $needsthis) {
                    # Add dependency to job
                    $this.Replace("jobs:/$($needsthis):/needs:","needs: [ $(@($this.GetPropertyArray("jobs:/$($needsthis):/needs:"))+@($customJob.Name) -join ', ') ]")
                }
            }
            $this.content += @('') + @($customJob.content | ForEach-Object { "  $_" })
        }
    }

    [string[]] GetStepsFromJob([string] $job) {
        $steps = $this.GetNextLevel("Jobs:/$($job):/steps:/") | Where-Object { $_ -like '- name: *' } | ForEach-Object { $_.Substring(8).Trim() }
        if ($steps | Group-Object | Where-Object { $_.Count -gt 1 }) {
            Write-Host "Duplicate step names in job '$job'"
            return @()
        }
        return $steps
    }

    [hashtable[]] GetCustomStepsFromAnchor([string] $job, [string] $anchorStep, [bool] $before) {
        $steps = $this.GetStepsFromJob($job)
        $anchorIdx = $steps.IndexOf($anchorStep)
        if ($anchorIdx -lt 0) {
            Write-Host "Cannot find anchor step '$anchorStep' in job '$job'"
            return @()
        }
        $idx = $anchorIdx
        $customSteps = @()
        if ($before) {
            while ($idx -gt 0 -and $steps[$idx-1] -like 'CustomStep*') {
                $idx--
            }
            if ($idx -ne $anchorIdx) {
                $customSteps = @($steps[$idx..($anchorIdx-1)])
                # Reverse the order of the custom steps in order to apply in correct order from the anchor step
                [array]::Reverse($customSteps)
            }
        }
        else {
            while ($idx -lt $steps.Count-1 -and $steps[$idx+1] -like 'CustomStep*') {
                $idx++
            }
            if ($idx -ne $anchorIdx) {
                $customSteps = @($steps[($anchorIdx+1)..$idx])
            }
        }
        $result = @()
        foreach($customStep in $customSteps) {
            $stepContent = $this.Get("Jobs:/$($job):/steps:/- name: $($customStep)").content
            $result += @(@{"Name" = $customStep; "Content" =  $stepContent; "AnchorStep" = $anchorStep; "Before" = $before })
        }
        return $result
    }

    [hashtable[]] GetCustomStepsFromYaml([string] $job, [hashtable[]] $anchors) {
        $steps = $this.GetStepsFromJob($job)
        $result = @()
        foreach($anchor in $anchors) {
            $result += $this.GetCustomStepsFromAnchor($job, $anchor.Step, $anchor.Before)
        }
        foreach($step in $steps) {
            if ($step -like 'CustomStep*') {
                if (-not ($result | Where-Object { $_.Name -eq $step })) {
                    Write-Host "Custom step '$step' does not belong to a supported anchor"
                }
            }
        }
        return $result
    }

    [void] AddCustomStepsToAnchor([string] $job, [hashtable[]] $customSteps, [string] $anchorStep, [bool] $before) {
        $steps = $this.GetStepsFromJob($job)
        if (!$steps) {
            Write-Host "::Warning::Cannot find job '$job'"
            return
        }
        $anchorIdx = $steps.IndexOf($anchorStep)
        if ($anchorIdx -lt 0) {
            Write-Host "::Warning::Cannot find anchor step '$anchorStep' in job '$job'"
            return
        }
        foreach($customStep in $customSteps | Where-Object { $_.AnchorStep -eq $anchorStep -and $_.Before -eq $before }) {
            if ($steps -contains $customStep.Name) {
                Write-Host "Custom step '$($customStep.Name)' already exists in job '$job'"
            }
            else {
                $anchorStart = 0
                $anchorCount = 0
                if ($this.Find("Jobs:/$($job):/steps:/- name: $($anchorStep)", [ref] $anchorStart, [ref] $anchorCount)) {
                    if ($before) {
                        $this.Insert($anchorStart-1, @('') + @($customStep.Content | ForEach-Object { "      $_" }))
                    }
                    else {
                        $this.Insert($anchorStart+$anchorCount, @('') + @($customStep.Content | ForEach-Object { "      $_" }))
                    }
                }
            }
            # Use added step as anchor for next step
            $anchorStep = $customStep.Name
        }
    }

    [void] AddCustomStepsToYaml([string] $job, [hashtable[]] $customSteps, [hashtable[]] $anchors) {
        foreach($anchor in $anchors) {
            $this.AddCustomStepsToAnchor($job, $customSteps, $anchor.Step, $anchor.Before)
        }
    }

    static [PSCustomObject] GetPermissionsFromArray([string[]] $permissionsArray) {
        $permissions = [PSCustomObject]@{}
        $permissionsArray | ForEach-Object {
            $permissions | Add-Member -MemberType NoteProperty -Name $_.Split(':')[0].Trim() -Value $_.Split(':')[1].Trim()
        }
        return $permissions
    }

    static [string[]] GetPermissionsArray([PSCustomObject] $permissions) {
        $permissionsArray = @()
        $permissions.PSObject.Properties.Name | ForEach-Object {
            $permissionsArray += "$($_): $($permissions."$_")"
        }
        return $permissionsArray
    }

    static [PSCustomObject] MergePermissions([PSCustomObject] $permissions, [PSCustomObject] $permissions2) {
        $permissions2.PSObject.Properties.Name | ForEach-Object {
            if ($permissions.PSObject.Properties.Name -eq $_) {
                $permission = $permissions."$_"
                $permission2 = $permissions2."$_"
                if ($permission -eq 'write' -or $permission2 -eq 'write') {
                    $permissions."$_" = 'write'
                }
                elseif ($permission -eq 'read' -or $permission2 -eq 'read') {
                    $permissions."$_" = 'read'
                }
                else {
                    $permissions."$_" = 'none'
                }
            }
            else {
                $permissions | Add-Member -MemberType NoteProperty -Name $_ -Value $permissions2."$_"
            }
        }
        return $permissions
    }

    static [void] ApplyCustomizations([ref] $srcContent, [string] $yamlFile, [hashtable] $anchors) {
        $srcYaml = [Yaml]::new($srcContent.Value.Split("`n"))
        try {
            $yaml = [Yaml]::Load($yamlFile)
        }
        catch {
            return
        }
        # Merge permissions
        Write-host "Merge permissions"
        $srcPermissions = [Yaml]::GetPermissionsFromArray($srcYaml.Get('permissions:/').content)
        $yamlPermissions = [Yaml]::GetPermissionsFromArray($yaml.Get('permissions:/').content)
        $srcYaml.Replace('permissions:/', [Yaml]::GetPermissionsArray([Yaml]::MergePermissions($srcPermissions, $yamlPermissions)))

        # Apply cystom steps
        Write-Host "Apply custom steps"
        $filename = [System.IO.Path]::GetFileName($yamlFile)
        if ($anchors.ContainsKey($filename)) {
            $fileAnchors = $anchors."$filename"
            foreach($job in $fileAnchors.Keys) {
                # Locate custom steps in destination YAML
                $customSteps = $yaml.GetCustomStepsFromYaml($job, $fileAnchors."$job")
                if ($customSteps) {
                    $srcYaml.AddCustomStepsToYaml($job, $customSteps, $fileAnchors."$job")
                }
            }
        }
        # Locate custom jobs in destination YAML
        Write-Host "Apply custom jobs"
        $customJobs = @($yaml.GetCustomJobsFromYaml('CustomJob*'))
        if ($customJobs) {
            # Add custom jobs to template YAML
            $srcYaml.AddCustomJobsToYaml($customJobs)
        }
        $srcContent.Value = $srcYaml.content -join "`n"
    }
}
