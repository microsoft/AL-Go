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
            if ($start -eq 0) {
                $this.content = $yamlContent+$this.content[($start+$count)..($this.content.Count-1)]
            }
            elseif ($start+$count -eq $this.content.Count) {
                $this.content = $this.content[0..($start-1)]+$yamlContent
            }
            else {
                $this.content = $this.content[0..($start-1)]+$yamlContent+$this.content[($start+$count)..($this.content.Count-1)]
            }
        }
        else {
            Write-Host -ForegroundColor Red "cannot locate $line"
        }
    }

    # Replace all occurrences of $from with $to throughout the Yaml content
    [void] ReplaceAll([string] $from, [string] $to) {
        $this.content = $this.content | ForEach-Object { $_.replace($from, $to) }
    }
}
