function RunIncrementVersionNumber {
    Param(
        [string] $project,
        [string] $versionNumber,
        [switch] $directCommit,
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Increment Version Number'
    $parameters = @{
        "project" = $project
        "versionNumber" = $versionNumber
        "directCommit" = @("Y","N")[!$directCommit]
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}