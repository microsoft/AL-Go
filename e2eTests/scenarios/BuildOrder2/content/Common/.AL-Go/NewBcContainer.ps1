Param( [HashTable] $parameters )

New-BcContainer @parameters

1..1000 | % {
    Write-Host $_
    Invoke-ScriptInBcContainer -containerName $parameters.containerName -ScriptBlock {
        $winSdkSetupExe = "c:\run\winsdksetup.exe"
        $winSdkSetupUrl = "https://bcartifacts.azureedge.net/prerequisites/winsdksetup.exe"
        (New-Object System.Net.WebClient).DownloadFile($winSdkSetupUrl,$winSdkSetupExe)
    }
}
   