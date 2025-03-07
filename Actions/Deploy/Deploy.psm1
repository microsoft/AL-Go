<#
 .SYNOPSIS
  Get the head ref from a PR
 .PARAMETER repository
  Repository to search in
 .PARAMETER prId
  The PR Id
 .PARAMETER token
  Auth token
#>
function GetHeadRefFromPRId {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $repository,
        [Parameter(Mandatory = $true)]
        [string] $prId,
        [Parameter(Mandatory = $true)]
        [string] $token
    )

    $headers = GetHeaders -token $token

    $pullsURI = "https://api.github.com/repos/$repository/pulls/$prId"
    Write-Host "- $pullsURI"
    $pr = (InvokeWebRequest -Headers $headers -Uri $pullsURI).Content | ConvertFrom-Json

    return $pr.head.ref
}
