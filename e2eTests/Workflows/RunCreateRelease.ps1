function RunCreateRelease {
    Param(
        [string] $appVersion,
        [string] $name,
        [string] $tag,
        [switch] $prerelease,
        [switch] $draft,
        [switch] $createReleaseBranch,
        [string] $updateVersionNumber = '',
        [switch] $directCommit,
        [switch] $useGhTokenWorkflow,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Create release'
    $parameters = @{
        "appVersion" = $appVersion
        "name" = $name
        "tag" = $tag
        "prerelease" = @("true","false")[!$prerelease]
        "draft" = @("true","false")[!$draft]
        "createReleaseBranch" = @("true","false")[!$createReleaseBranch]
        "updateVersionNumber" = $updateVersionNumber
        "directCommit" = @("true","false")[!$directCommit]
        "useGhTokenWorkflow" = @("true","false")[!$useGhTokenWorkflow]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}
