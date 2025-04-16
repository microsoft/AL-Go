function RunCreateRelease {
    Param(
        [string] $buildVersion,
        [string] $name,
        [string] $tag,
        [ValidateSet('Release','Draft','Prerelease')]
        [string] $releaseType = 'Release',
        [switch] $createReleaseBranch,
        [string] $updateVersionNumber = '',
        [switch] $skipUpdatingDependencies,
        [switch] $directCommit,
        [switch] $useGhTokenWorkflow,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Create release'
    $parameters = @{
        "buildVersion" = $buildVersion
        "name" = $name
        "tag" = $tag
        "releaseType" = $releaseType
        "createReleaseBranch" = @("true","false")[!$createReleaseBranch]
        "updateVersionNumber" = $updateVersionNumber
        "skipUpdatingDependencies" = @("true","false")[!$skipUpdatingDependencies]
        "directCommit" = @("true","false")[!$directCommit]
        "useGhTokenWorkflow" = @("true","false")[!$useGhTokenWorkflow]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}
