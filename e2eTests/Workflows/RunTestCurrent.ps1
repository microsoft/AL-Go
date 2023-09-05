function RunTestCurrent {
    Param(
        [switch] $wait,
        [string] $repository,
        [string] $branch = "main"
    )

    $workflowName = 'Test Current'
    $parameters = @{
    }
    RunWorkflow -name $workflowName -parameters $parameters -wait:$wait -branch $branch -repository $repository
}