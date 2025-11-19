Param(
    [Parameter(HelpMessage = "Test type (test or upgrade)", Mandatory = $false)]
    [ValidateSet('test', 'upgrade')]
    [string] $testType = 'test',
    [Parameter(HelpMessage = "Private repository", Mandatory = $false)]
    [bool] $private = $false,
    [Parameter(HelpMessage = "GitHub owner", Mandatory = $true)]
    [string] $githubOwner,
    [Parameter(HelpMessage = "Repository name", Mandatory = $true)]
    [string] $repoName,
    [Parameter(HelpMessage = "E2E App ID", Mandatory = $true)]
    [string] $e2eAppId,
    [Parameter(HelpMessage = "E2E App Key", Mandatory = $true)]
    [string] $e2eAppKey,
    [Parameter(HelpMessage = "ALGO Auth App", Mandatory = $true)]
    [string] $algoAuthApp,
    [Parameter(HelpMessage = "Template", Mandatory = $true)]
    [string] $template,
    [Parameter(HelpMessage = "Admin center API credentials", Mandatory = $false)]
    [string] $adminCenterApiCredentials = '',
    [Parameter(HelpMessage = "Multi-project", Mandatory = $false)]
    [bool] $multiProject = $false,
    [Parameter(HelpMessage = "AppSource app", Mandatory = $false)]
    [bool] $appSource = $false,
    [Parameter(HelpMessage = "Linux", Mandatory = $false)]
    [bool] $linux = $false,
    [Parameter(HelpMessage = "Use compiler folder", Mandatory = $false)]
    [bool] $useCompilerFolder = $false,
    [Parameter(HelpMessage = "Release (for upgrade tests)", Mandatory = $false)]
    [string] $release = '',
    [Parameter(HelpMessage = "Content path (for upgrade tests)", Mandatory = $false)]
    [string] $contentPath = ''
)

try {
    if ($testType -eq 'upgrade') {
        $params = @{
            'github' = $true
            'githubOwner' = $githubOwner
            'repoName' = $repoName
            'e2eAppId' = $e2eAppId
            'e2eAppKey' = $e2eAppKey
            'algoauthapp' = $algoAuthApp
            'template' = $template
            'appSource' = $appSource
            'release' = $release
            'contentPath' = $contentPath
        }
        
        . (Join-Path "." "e2eTests/Test-AL-Go-Upgrade.ps1") @params
    }
    else {
        $params = @{
            'github' = $true
            'githubOwner' = $githubOwner
            'repoName' = $repoName
            'e2eAppId' = $e2eAppId
            'e2eAppKey' = $e2eAppKey
            'algoauthapp' = $algoAuthApp
            'template' = $template
            'adminCenterApiCredentials' = $adminCenterApiCredentials
            'multiProject' = $multiProject
            'appSource' = $appSource
            'linux' = $linux
            'useCompilerFolder' = $useCompilerFolder
        }
        
        if ($private) {
            $params['private'] = $true
        }
        
        . (Join-Path "." "e2eTests/Test-AL-Go.ps1") @params
    }
}
catch {
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    Write-Host "::Error::$($_.Exception.Message)"
    $host.SetShouldExit(1)
}
