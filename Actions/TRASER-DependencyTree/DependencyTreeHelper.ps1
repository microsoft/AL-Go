# TRASER Dependency Tree Helper - extracted from TraserBCHelper

function New-MutableAppObject {
    param([PSCustomObject]$SourceObject, [int]$ProcessOrder)
    $obj = [PSCustomObject]@{}
    foreach ($prop in $SourceObject.PSObject.Properties.Name) {
        $obj | Add-Member -MemberType NoteProperty -Name $prop -Value $SourceObject.$prop
    }
    $obj | Add-Member -MemberType NoteProperty -Name "ProcessOrder" -Value $ProcessOrder -Force
    return $obj
}

function Add-ToDependencyTree {
    param([PSCustomObject]$AppObject, [PSObject[]]$DependencyArray = @(), [PSObject[]]$AppCollection)
    if ($null -ne $DependencyArray -and $DependencyArray.Count -gt 0) {
        if ($DependencyArray | Where-Object { $_.Id -eq $AppObject.Id } | Select-Object -First 1) { return $DependencyArray }
    }
    if ($AppObject.PSObject.Properties.Name -notcontains 'Dependencies' -or $AppObject.Dependencies.Count -eq 0) {
        return $DependencyArray + @(New-MutableAppObject -SourceObject $AppObject -ProcessOrder 0)
    }
    foreach ($dep in $AppObject.Dependencies) {
        $match = $AppCollection | Where-Object { $_.Id -eq $dep.Id } | Select-Object -First 1
        if ($match) { $DependencyArray = Add-ToDependencyTree -AppObject $match -DependencyArray $DependencyArray -AppCollection $AppCollection }
    }
    [int]$order = 0
    foreach ($dep in $AppObject.Dependencies) {
        $match = $DependencyArray | Where-Object { $_.Id -eq $dep.Id } | Select-Object -First 1
        if ($match -and ($match.ProcessOrder + 1) -gt $order) { $order = $match.ProcessOrder + 1 }
    }
    return $DependencyArray + @(New-MutableAppObject -SourceObject $AppObject -ProcessOrder $order)
}

function Get-AppDependencyTree {
    param([Parameter(Mandatory)][string]$Path)
    $allApps = @()
    Get-ChildItem -Path $Path -Filter "*.app" -Recurse | ForEach-Object {
        $app = Get-AppJsonFromAppFile -appFile $_.FullName
        $allApps += [PSCustomObject]@{ Id = $app.id; Version = [Version]$app.Version; Name = $app.Name; Publisher = $app.Publisher; ProcessOrder = 0; Dependencies = $app.Dependencies; Path = $_.FullName }
    }
    $result = @()
    $allApps | ForEach-Object { $result = Add-ToDependencyTree -AppObject $_ -DependencyArray $result -AppCollection $allApps }
    return $result | Sort-Object ProcessOrder
}
