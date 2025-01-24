<#
 .SYNOPSIS
  This function will return the Access Token based on the gitHubAppClientId and privateKey
  This GitHub App must be installed in the repositories for which the access is requested
  The permissions of the GitHub App must include the permissions requested
 .PARAMETER gitHubAppClientId
  The GitHub App Client ID
 .Parameter privateKey
  The GitHub App Private Key
 .PARAMETER api_url
  The GitHub API URL
 .PARAMETER repository
  The Current GitHub repository
 .PARAMETER repositories
  The repositories to request access to
 .PARAMETER permissions
  The permissions to request for the Access Token
#>
function GetGitHubAppAuthToken {
    Param(
        [string] $gitHubAppClientId,
        [string] $privateKey,
        [string] $api_url = $ENV:GITHUB_API_URL,
        [string] $repository,
        [hashtable] $permissions = @{},
        [string[]] $repositories = @()
    )

    Write-Host "Using GitHub App with ClientId $gitHubAppClientId for authentication"
    $jwt = GenerateJwtForTokenRequest -gitHubAppClientId $gitHubAppClientId -privateKey $privateKey
    $headers = @{
        "Accept" = "application/vnd.github+json"
        "Authorization" = "Bearer $jwt"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    Write-Host "Get App Info $api_url/repos/$repository/installation"
    $appinfo = Invoke-RestMethod -Method GET -UseBasicParsing -Headers $headers -Uri "$api_url/repos/$repository/installation"
    $body = @{}
    # If repositories are provided, limit the requested repositories to those
    if ($repositories) {
        $body += @{ "repositories" = @($repositories | ForEach-Object { $_.SubString($_.LastIndexOf('/')+1) } ) }
    }
    # If permissions are provided, limit the requested permissions to those
    if ($permissions) {
        $body += @{ "permissions" = $permissions }
    }
    Write-Host "Get Token Response $($appInfo.access_tokens_url) with $($body | ConvertTo-Json -Compress)"
    $tokenResponse = Invoke-RestMethod -Method POST -UseBasicParsing -Headers $headers -Body ($body | ConvertTo-Json -Compress) -Uri $appInfo.access_tokens_url
    Write-Host "return token"
    return $tokenResponse.token, $tokenResponse.expires_in
}

# Generate JWT for token request
# As documented here: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app
function GenerateJwtForTokenRequest {
    Param(
        [string] $gitHubAppClientId,
        [string] $privateKey
    )

    $header = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
        alg = "RS256"
        typ = "JWT"
    }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{
        iat = [System.DateTimeOffset]::UtcNow.AddSeconds(-10).ToUnixTimeSeconds()
        exp = [System.DateTimeOffset]::UtcNow.AddMinutes(10).ToUnixTimeSeconds()
        iss = $gitHubAppClientId
    }))).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    $signature = pwsh -command {
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $privateKey = "$($args[1])"
        $rsa.ImportFromPem($privateKey)
        $signature = [Convert]::ToBase64String($rsa.SignData([System.Text.Encoding]::UTF8.GetBytes($args[0]), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        Write-OutPut $signature
    } -args "$header.$payload", $privateKey
    return "$header.$payload.$signature"
}

Export-ModuleMember -Function GetGitHubAppAuthToken, GenerateJwtForTokenRequest